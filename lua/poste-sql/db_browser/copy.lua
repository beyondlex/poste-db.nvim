local state = require("poste.state")
local cli = require("poste.cli")
local util = require("poste.util")
local dialog = require("poste.dialog")

local M = {}

local function quote(name, dialect)
  if dialect == "mysql" then
    return "`" .. name:gsub("`", "``") .. "`"
  else
    return '"' .. name:gsub('"', '""') .. '"'
  end
end

local function dialect_table_exists_sql(dialect)
  if dialect == "mysql" then
    return "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '%s'"
  elseif dialect == "postgres" then
    return "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '%s')"
  else
    return "SELECT name FROM sqlite_master WHERE type='table' AND name='%s'"
  end
end

local function find_search_dir()
  local buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(buf)
  if buf_name and buf_name ~= "" then
    return vim.fn.fnamemodify(buf_name, ":p:h")
  end
  return vim.fn.getcwd()
end

local function run_sql_on_conn(conn_name, database, sql, on_result, on_error)
  local binary = cli.binary()
  if not binary then
    if on_error then on_error("Poste binary not found") end
    return
  end

  local search_dir = find_search_dir()
  local file = search_dir .. "/copy.sql"
  local cmd = string.format("%s run %s --line 1 --env %s --json --stdin",
    vim.fn.shellescape(binary),
    vim.fn.shellescape(file),
    vim.fn.shellescape(state.current_env or "dev")
  )
  if database and database ~= "" then
    cmd = cmd .. " --database " .. vim.fn.shellescape(database)
  end

  local content = "-- @connection " .. conn_name .. "\n" .. sql

  local stderr_buf = {}
  local job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then return end
      data = util.ensure_job_data(data)
      if #data == 0 then return end
      local output = table.concat(data, "\n")
      vim.schedule(function()
        if on_result then on_result(output) end
      end)
    end,
    on_stderr = function(_, data)
      if not data then return end
      for _, l in ipairs(data) do
        if l ~= "" then table.insert(stderr_buf, l) end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 and on_error then
        vim.schedule(function()
          local msg = table.concat(stderr_buf, "\n")
          if msg == "" then msg = "Exit code: " .. code end
          on_error(msg)
        end)
      end
    end,
  })

  if job_id > 0 then
    vim.fn.chansend(job_id, content)
    vim.fn.chanclose(job_id, "stdin")
  elseif on_error then
    on_error("Failed to start job")
  end
end

local function introspect_ddl(conn_name, db_name, table_name, on_result, on_error)
  local binary = cli.binary()
  if not binary then
    if on_error then on_error("Poste binary not found") end
    return
  end

  local search_dir = find_search_dir()
  local args = {
    binary,
    "introspect", conn_name,
    "--type", "ddl",
    "--table", table_name,
    "--database", db_name,
    "--env", state.current_env or "dev",
    "--path", search_dir,
  }

  local stderr_buf = {}
  vim.fn.jobstart(args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then return end
      data = util.ensure_job_data(data)
      if #data == 0 then return end
      local output = table.concat(data, "\n")
      vim.schedule(function()
        if on_result then on_result(output) end
      end)
    end,
    on_stderr = function(_, data)
      if not data then return end
      for _, l in ipairs(data) do
        if l ~= "" then table.insert(stderr_buf, l) end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 and on_error then
        vim.schedule(function()
          local msg = table.concat(stderr_buf, "\n")
          if msg == "" then msg = "DDL introspection failed with code " .. code end
          on_error(msg)
        end)
      end
    end,
  })
end

local function check_table_exists(conn_name, database, dialect, name, on_result, on_error)
  local sql = dialect_table_exists_sql(dialect):format(name)
  run_sql_on_conn(conn_name, database, sql, function(output)
    local ok, parsed = pcall(vim.json.decode, output)
    if not ok or not parsed then
      if on_error then on_error("Failed to parse table existence check") end
      return
    end
    local exists = false
    local body = parsed.body
    if body then
      local ok_body, decoded = pcall(vim.json.decode, body)
      if ok_body and decoded and decoded.results and decoded.results[1] then
        local r = decoded.results[1]
        if r.rows and #r.rows > 0 and r.rows[1] and #r.rows[1] > 0 then
          local val = r.rows[1][1]
          exists = (type(val) == "boolean" and val) or (type(val) == "string" and val ~= "")
        end
      end
    end
    on_result(exists)
  end, on_error)
end

local function resolve_table_name(conn_name, database, dialect, base_name, on_result, on_error)
  check_table_exists(conn_name, database, dialect, base_name, function(exists)
    if not exists then
      on_result(base_name)
      return
    end

    local function try_suffix(suffix)
      local candidate = base_name .. "_copy" .. (suffix > 1 and suffix or "")
      check_table_exists(conn_name, database, dialect, candidate, function(exists2)
        if not exists2 then
          on_result(candidate)
        else
          try_suffix(suffix + 1)
        end
      end, on_error)
    end

    try_suffix(1)
  end, on_error)
end

local function copy_one_table(source, target, table_name, target_table_name, on_done, on_error)
  local q = function(n) return quote(n, source.dialect) end
  local same_server = source.conn == target.conn

  introspect_ddl(source.conn, source.db, table_name, function(ddl_output)
    local ok, parsed = pcall(vim.json.decode, ddl_output)
    if not ok or not parsed then
      on_error("Failed to parse DDL for " .. table_name)
      return
    end

    local items = parsed.items
    if not items or #items == 0 or not items[1].ddl then
      on_error("No DDL found for " .. table_name)
      return
    end

    local ddl = items[1].ddl
    local ddl_modified = ddl:gsub("`" .. table_name .. "`", "`" .. target_table_name .. "`")
    ddl_modified = ddl_modified:gsub('"' .. table_name .. '"', '"' .. target_table_name .. '"')

    run_sql_on_conn(target.conn, target.db, ddl_modified, function()
      local insert_sql
      if same_server then
        local quoted_src = q(source.db) .. "." .. q(table_name)
        local quoted_tgt = q(target.db) .. "." .. q(target_table_name)
        insert_sql = "INSERT INTO " .. quoted_tgt .. " SELECT * FROM " .. quoted_src .. ";"
      else
        on_error("Cross-server copy not yet supported")
        return
      end

      run_sql_on_conn(target.conn, target.db, insert_sql, function(insert_output)
        local ok2, parsed2 = pcall(vim.json.decode, insert_output)
        local row_count = "?"
        local elapsed = "?"
        if ok2 and parsed2 and parsed2.body then
          local ok_body, decoded = pcall(vim.json.decode, parsed2.body)
          if ok_body and decoded and decoded.results and decoded.results[1] then
            local r = decoded.results[1]
            if r.row_count then row_count = tostring(r.row_count) end
            if r.execution_time_ms then elapsed = tostring(r.execution_time_ms) .. "ms" end
            if r.affected_rows then row_count = tostring(r.affected_rows) end
          end
        end
        on_done(row_count, elapsed)
      end, function(err)
        on_error(err)
      end)
    end, function(err)
      on_error(err)
    end)
  end, function(err)
    on_error(err)
  end)
end

local function popup_options()
  local cfg = state.config.db_browser or {}
  local pos = cfg.split_position or "right"
  local width = 60
  local height = 12
  return { width = width, height = height, dir = pos }
end

local function show_confirm_dialog(source, target, table_names, on_confirm, on_cancel)
  local popts = popup_options()
  local height = math.max(12, 6 + math.min(#table_names, 5))
  height = math.min(height, 20)

  local opts = {
    title = "Copy Tables",
    width = popts.width,
    height = height,
    border = "rounded",
    backdrop = true,
  }

  local dlg = dialog.open(opts)

  local src_dialect_tag = " (" .. source.dialect .. ")"
  local tgt_dialect_tag = " (" .. target.dialect .. ")"
  local same_dialect = source.dialect == target.dialect
  local same_server = source.conn == target.conn
  local can_copy = same_dialect and same_server

  local status_text
  if not same_dialect then
    status_text = "  MISMATCH - dialect differs"
  elseif not same_server then
    status_text = "  Cross-server copy not yet supported"
  else
    status_text = "  Ready"
  end

  local lines = {
    "  Source:  " .. source.conn .. "." .. source.db .. src_dialect_tag,
    "  Target:  " .. target.conn .. "." .. target.db .. tgt_dialect_tag,
    "  Status:  " .. status_text,
    "",
  }

  local km = { buffer = dlg.buf, noremap = true, silent = true, nowait = true }
  if can_copy then
    local display_names = {}
    for i, name in ipairs(table_names) do
      if i <= 5 then
        table.insert(display_names, "    " .. name)
      else
        table.insert(display_names, "    ... and " .. (#table_names - 5) .. " more")
        break
      end
    end
    table.insert(lines, "  Selected tables (" .. #table_names .. "):")
    for _, l in ipairs(display_names) do
      table.insert(lines, l)
    end
    table.insert(lines, "")
    table.insert(lines, "  [y] Confirm  [n] Cancel")

    vim.keymap.set("n", "y", function()
      dlg:close()
      if on_confirm then on_confirm() end
    end, km)
    vim.keymap.set("n", "n", function()
      dlg:close()
      if on_cancel then on_cancel() end
    end, km)
  else
    table.insert(lines, "  Press [q] to close")
  end

  dlg:update(lines)
end

local function show_progress_dialog(source, target, table_names, on_close)
  local popts = popup_options()
  local height = math.max(14, 8 + #table_names)
  height = math.min(height, 24)

  local opts = {
    title = "Copying Tables",
    width = popts.width,
    height = height,
    border = "rounded",
    backdrop = true,
    on_close = on_close,
  }

  local dlg = dialog.open(opts)
  local results = {}
  local total = #table_names
  local completed = 0
  local failed = 0
  local errors = {}
  local cancelled = false

  for _, name in ipairs(table_names) do
    results[name] = { status = "pending", row_count = "", elapsed = "" }
  end

  local function render()
    local lines = {}
    local done = completed + failed
    local pct = total > 0 and math.floor(done / total * 100) or 0
    local bar_len = 20
    local filled = math.floor(done / total * bar_len)
    local bar = string.rep("█", filled) .. string.rep("░", bar_len - filled)
    table.insert(lines, "  " .. bar .. "  " .. done .. "/" .. total .. " (" .. pct .. "%)")
    table.insert(lines, "")
    table.insert(lines, "  Source: " .. source.conn .. "." .. source.db)
    table.insert(lines, "  Target: " .. target.conn .. "." .. target.db)
    table.insert(lines, "")

    for _, name in ipairs(table_names) do
      local r = results[name]
      if r.status == "done" then
        table.insert(lines, "  ✓ " .. name .. "  (" .. r.row_count .. " rows, " .. r.elapsed .. ")")
      elseif r.status == "copying" then
        table.insert(lines, "  ⟳ " .. name .. "  (copying...)")
      elseif r.status == "error" then
        table.insert(lines, "  ✘ " .. name)
      else
        table.insert(lines, "  ◻ " .. name .. "  (pending)")
      end
    end

    if done == total then
      table.insert(lines, "")
      table.insert(lines, "  Done. " .. completed .. " succeeded, " .. failed .. " failed.")
      if failed > 0 then
        table.insert(lines, "  Press [q] to see errors")
      end
    end

    dlg:update(lines)
  end

  render()

  local function advance(name, status, row_count, elapsed, err_msg)
    if cancelled then return end
    results[name] = { status = status, row_count = row_count or "", elapsed = elapsed or "" }
    if status == "done" then
      completed = completed + 1
    elseif status == "error" then
      failed = failed + 1
      errors[name] = err_msg or "Unknown error"
    end
    render()

    if completed + failed == total then
      if failed > 0 then
        vim.defer_fn(function()
          show_summary_dialog(completed, failed, errors)
        end, 500)
      end
    end
  end

  local function start_copy()
    local idx = 0
    local function process_next()
      if cancelled then return end
      idx = idx + 1
      if idx > total then return end
      local name = table_names[idx]

      results[name] = { status = "copying", row_count = "", elapsed = "" }
      render()

      resolve_table_name(target.conn, target.db, target.dialect, name, function(resolved_name)
        copy_one_table(source, target, name, resolved_name, function(row_count, elapsed)
          advance(name, "done", row_count, elapsed, nil)
          process_next()
        end, function(err)
          advance(name, "error", nil, nil, err)
          process_next()
        end)
      end, function(err)
        advance(name, "error", nil, nil, err)
        process_next()
      end)
    end

    process_next()
  end

  return dlg, start_copy, function()
    cancelled = true
    dlg:close()
  end
end

local function show_summary_dialog(completed, failed, errors)
  local lines = {
    "  Succeeded: " .. completed .. "  |  Failed: " .. failed,
    "",
  }
  if failed > 0 then
    for name, err in pairs(errors) do
      table.insert(lines, "  ✘ " .. name)
      local line_len = 50
      local pos = 1
      while pos <= #err do
        local chunk = err:sub(pos, pos + line_len - 1)
        table.insert(lines, "      " .. chunk)
        pos = pos + line_len
      end
    end
  end

  local height = math.max(6, 4 + #lines)
  height = math.min(height, 24)

  local dlg = dialog.open({
    title = "Copy Complete",
    width = 60,
    height = height,
    border = "rounded",
    backdrop = false,
  })
  dlg:update(lines)
end

function M.copy_tables(source, target, table_names, on_complete)
  local same_dialect = source.dialect == target.dialect
  local same_server = source.conn == target.conn

  if not same_dialect or not same_server then
    show_confirm_dialog(source, target, table_names, nil, nil)
    return
  end

  show_confirm_dialog(source, target, table_names, function()
    local _, start_copy_fn = show_progress_dialog(source, target, table_names, function()
      if on_complete then on_complete() end
    end)
    start_copy_fn()
  end, function()
    if on_complete then on_complete() end
  end)
end

return M