local state = require("poste.state")
local cli = require("poste.cli")
local util = require("poste.util")
local dialog = require("poste.dialog")

local M = {}

local function setup_highlights()
  vim.api.nvim_set_hl(0, "PosteDbCopySuccess", { fg = "#9ece6a" })
  vim.api.nvim_set_hl(0, "PosteDbCopyError", { fg = "#f7768e" })
  vim.api.nvim_set_hl(0, "PosteDbCopyProgress", { fg = "#565f89" })
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = setup_highlights })

local function quote(name, dialect)
  if dialect == "mysql" then
    return "`" .. name:gsub("`", "``") .. "`"
  else
    return '"' .. name:gsub('"', '""') .. '"'
  end
end

local function has_value(v)
  return v ~= nil and v ~= vim.NIL
end

local function quote_value(val)
  if not has_value(val) then
    return "NULL"
  end
  local t = type(val)
  if t == "number" then
    return tostring(val)
  elseif t == "boolean" then
    return val and "TRUE" or "FALSE"
  elseif t == "string" then
    return "'" .. val:gsub("'", "''") .. "'"
  elseif t == "table" then
    local ok, json_str = pcall(vim.json.encode, val)
    if ok then
      return "'" .. json_str:gsub("'", "''") .. "'"
    end
    return "NULL"
  end
  return "'" .. tostring(val):gsub("'", "''") .. "'"
end

local function extract_row_count(r)
  if has_value(r.affected_rows) then return tostring(r.affected_rows) end
  if has_value(r.row_count) then return tostring(r.row_count) end
  return "?"
end

local function extract_elapsed(r)
  if has_value(r.execution_time_ms) then return tostring(r.execution_time_ms) .. "ms" end
  return "?"
end

local function check_result_error(decoded)
  if decoded and decoded.results and decoded.results[1] then
    local r = decoded.results[1]
    if has_value(r.error) then return r.error end
    if has_value(r.message) then return r.message end
  end
  return nil
end

local function extract_schema_from_ddl(ddl, table_name, dialect)
  if dialect == "mysql" then
    return nil
  end
  local quoted = '"' .. table_name .. '"'
  local pattern = '^CREATE TABLE "([^"]+)"%.' .. quoted
  local schema = ddl:match(pattern)
  if schema then return schema end
  return nil
end

local function extract_sequences_from_ddl(ddl, schema)
  local sequences = {}
  local seen = {}
  for seq_name in ddl:gmatch("nextval%('([^']+)'%:%:regclass%)") do
    if not seen[seq_name] then
      seen[seq_name] = true
      table.insert(sequences, seq_name)
    end
  end
  return sequences
end

local function column_type_for_seq(ddl, seq_name)
  local seq_ref = "nextval('" .. seq_name .. "'::regclass)"
  local seq_pos = ddl:find(seq_ref, 1, true)
  if not seq_pos then return "integer" end
  local before = ddl:sub(1, seq_pos - 1)
  local col_type = before:match('"[^"]+"%s+(%w+)%s+[^,]-%s+DEFAULT%s*$')
  if not col_type then
    col_type = before:match('"[^"]+"%s+(%w+)%s+DEFAULT%s*$')
  end
  if col_type == "bigint" then return "bigint" end
  if col_type == "smallint" then return "smallint" end
  return "integer"
end

local function rename_seq_reference(ddl, seq_name, new_seq_name)
  local old = "nextval('" .. seq_name .. "'::regclass)"
  local new = "nextval('" .. new_seq_name .. "'::regclass)"
  return ddl:gsub(old, new, 1)
end

local function prepare_table_ddl(ddl, target_table_name, table_name, schema, dialect)
  local modified = ddl:gsub("`" .. table_name .. "`", "`" .. target_table_name .. "`")
  modified = modified:gsub('"' .. table_name .. '"', '"' .. target_table_name .. '"')

  if dialect ~= "postgres" then
    return modified
  end

  local sequences = extract_sequences_from_ddl(modified, schema)
  if #sequences == 0 then
    return modified
  end

  local q = function(n) return quote(n, dialect) end
  local seq_stmts = {}
  for _, seq_name in ipairs(sequences) do
    local new_seq_name = seq_name:gsub(table_name, target_table_name)
    local seq_type = column_type_for_seq(ddl, seq_name)
    local qualified
    if schema then
      qualified = q(schema) .. "." .. q(new_seq_name)
    else
      qualified = q(new_seq_name)
    end
    table.insert(seq_stmts, "CREATE SEQUENCE IF NOT EXISTS " .. qualified .. " AS " .. seq_type .. ";")
    modified = rename_seq_reference(modified, seq_name, new_seq_name)
  end

  table.insert(seq_stmts, modified)
  return table.concat(seq_stmts, "\n")
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
  local browser = require("poste-sql.db_browser")
  return browser.get_search_dir()
end

local function run_sql_on_conn(conn_name, database, sql, on_result, on_error)
  local binary = cli.binary()
  if not binary then
    if on_error then on_error("Poste binary not found") end
    return
  end

  local connections = require("poste-sql.connections")
  local url, err = connections.resolve_connection_url(conn_name)
  if not url then
    if on_error then on_error(err or "unknown error") end
    return
  end

  local search_dir = find_search_dir()
  local file = search_dir .. "/copy.sql"
  local cmd = string.format("%s run %s --line 1 --env %s --json --stdin --connection-url %s",
    vim.fn.shellescape(binary),
    vim.fn.shellescape(file),
    vim.fn.shellescape(state.current_env or "dev"),
    vim.fn.shellescape(url)
  )
  if database and database ~= "" then
    cmd = cmd .. " --database " .. vim.fn.shellescape(database)
  end

  local content = "-- @connection " .. url .. "\n" .. sql

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

  local connections = require("poste-sql.connections")
  local url, err = connections.resolve_connection_url(conn_name)
  if not url then
    if on_error then on_error(err or "unknown error") end
    return
  end

  local args = {
    binary,
    "introspect",
    "--connection-url", url,
    "--type", "ddl",
    "--table", table_name,
    "--database", db_name,
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

local function copy_data_same_server(source, target, schema, table_name, target_table_name, on_done, on_error)
  local q = function(n) return quote(n, source.dialect) end
  local function tbl(name)
    if schema and source.dialect ~= "sqlite" then
      return q(schema) .. "." .. q(name)
    end
    return q(name)
  end
  local insert_sql = "INSERT INTO " .. tbl(target_table_name) .. " SELECT * FROM " .. tbl(table_name) .. ";"

  run_sql_on_conn(target.conn, target.db, insert_sql, function(insert_output)
    local ok, parsed = pcall(vim.json.decode, insert_output)
    if not ok or not parsed then
      on_error("Failed to parse INSERT result for " .. table_name)
      return
    end
    local err = parsed.error
    if has_value(err) then
      on_error(tostring(err))
      return
    end
    if not parsed.body then
      on_error("No body in INSERT result for " .. table_name)
      return
    end
    local ok_body, decoded = pcall(vim.json.decode, parsed.body)
    if not ok_body or not decoded then
      on_error("Failed to decode INSERT result for " .. table_name)
      return
    end
    local r_err = check_result_error(decoded)
    if r_err then
      on_error(tostring(r_err))
      return
    end
    local r = decoded.results and decoded.results[1]
    if not r then
      on_error("No result in INSERT response for " .. table_name)
      return
    end
    on_done(extract_row_count(r), extract_elapsed(r))
  end, on_error)
end

local function check_response(output, label, on_error)
  local ok, parsed = pcall(vim.json.decode, output)
  if not ok or not parsed then
    on_error("Failed to parse " .. label .. " response")
    return false
  end
  local err = parsed.error
  if has_value(err) then
    on_error(tostring(err))
    return false
  end
  local body = parsed.body
  if not body then
    on_error("No body in " .. label .. " response")
    return false
  end
  local ok_body, decoded = pcall(vim.json.decode, body)
  if not ok_body or not decoded then
    on_error("Failed to decode " .. label .. " body")
    return false
  end
  local r_err = check_result_error(decoded)
  if r_err then
    on_error(tostring(r_err))
    return false
  end
  return true, decoded
end

local function copy_data_cross_server(source, target, schema, table_name, target_table_name, on_done, on_error)
  local q = function(n) return quote(n, source.dialect) end
  local function tbl(name)
    if schema and source.dialect ~= "sqlite" then
      return q(schema) .. "." .. q(name)
    end
    return q(name)
  end
  local select_sql = "SELECT * FROM " .. tbl(table_name) .. ";"

  run_sql_on_conn(source.conn, source.db, select_sql, function(select_output)
    local ok, decoded = check_response(select_output, "SELECT", on_error)
    if not ok then return end

    local r = decoded.results and decoded.results[1]
    if not r then
      on_error("No result in SELECT response for " .. table_name)
      return
    end
    local columns = r.columns
    local rows = r.rows
    if not columns or not rows then
      on_error("No columns or rows in SELECT result for " .. table_name)
      return
    end
    if #rows == 0 then
      on_done("0", "0ms")
      return
    end

    local col_names = {}
    for _, col in ipairs(columns) do
      table.insert(col_names, q(col.name))
    end
    local col_list = table.concat(col_names, ", ")

    local total_rows = 0
    local total_elapsed = "?"
    local batch_size = 500
    local function insert_batch(start_idx)
      if start_idx > #rows then
        on_done(tostring(total_rows), total_elapsed)
        return
      end

      local end_idx = math.min(start_idx + batch_size - 1, #rows)
      local value_groups = {}
      for i = start_idx, end_idx do
        local row = rows[i]
        local vals = {}
        for j = 1, #row do
          table.insert(vals, quote_value(row[j]))
        end
        table.insert(value_groups, "(" .. table.concat(vals, ", ") .. ")")
      end

      local insert_sql = "INSERT INTO " .. tbl(target_table_name)
        .. " (" .. col_list .. ") VALUES\n"
        .. table.concat(value_groups, ",\n")
        .. ";"

      run_sql_on_conn(target.conn, target.db, insert_sql, function(insert_output)
        local ok_insert, decoded = check_response(insert_output, "INSERT", on_error)
        if not ok_insert then return end
        local r = decoded.results and decoded.results[1]
        if r then
          total_elapsed = extract_elapsed(r)
        end
        total_rows = total_rows + (end_idx - start_idx + 1)
        insert_batch(end_idx + 1)
      end, on_error)
    end

    insert_batch(1)
  end, on_error)
end

local function copy_one_table(source, target, table_name, target_table_name, on_done, on_error)
  local same_server = source.conn == target.conn
  local same_db = source.db == target.db

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
    local schema = extract_schema_from_ddl(ddl, table_name, source.dialect)
    local ddl_prepared = prepare_table_ddl(ddl, target_table_name, table_name, schema, source.dialect)

    run_sql_on_conn(target.conn, target.db, ddl_prepared, function(ddl_output)
      local ok = check_response(ddl_output, "DDL", on_error)
      if not ok then return end
      if same_server and same_db then
        copy_data_same_server(source, target, schema, table_name, target_table_name, on_done, on_error)
      else
        copy_data_cross_server(source, target, schema, table_name, target_table_name, on_done, on_error)
      end
    end, on_error)
  end, on_error)
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
  local can_copy = same_dialect

  local status_text
  if not same_dialect then
    status_text = "  MISMATCH - dialect differs"
  elseif not same_server then
    status_text = "  Cross-server (SELECT+INSERT)"
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

local function show_summary_dialog(completed, failed, errors)
  local lines = {
    "  Succeeded: " .. completed .. "  |  Failed: " .. failed,
    "",
  }
  if failed > 0 then
    for name, err in pairs(errors) do
      table.insert(lines, "  ✘ " .. name)
      local clean = err:gsub("\n", " "):gsub("\r", "")
      local line_len = 50
      local pos = 1
      while pos <= #clean do
        local chunk = clean:sub(pos, pos + line_len - 1)
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
    local highlights = {}
    local done = completed + failed
    local pct = total > 0 and math.floor(done / total * 100) or 0
    local bar_len = 20
    local filled = math.floor(done / total * bar_len)
    local bar = string.rep("█", filled) .. string.rep("░", bar_len - filled)
    table.insert(lines, "  Source: " .. source.conn .. "." .. source.db)
    table.insert(lines, "  Target: " .. target.conn .. "." .. target.db)
    table.insert(lines, "")
    local bar_line = "  " .. bar .. "  " .. done .. "/" .. total .. " (" .. pct .. "%)"
    table.insert(lines, bar_line)
    table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #bar_line, hl_group = "PosteDbCopyProgress" })
    table.insert(lines, "")

    for _, name in ipairs(table_names) do
      local r = results[name]
      if r.status == "done" then
        local line = "  ✓ " .. name .. "  (" .. r.row_count .. " rows, " .. r.elapsed .. ")"
        table.insert(lines, line)
        table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #line, hl_group = "PosteDbCopySuccess" })
      elseif r.status == "copying" then
        table.insert(lines, "  ⟳ " .. name .. "  (copying...)")
      elseif r.status == "error" then
        local line = "  ✘ " .. name
        table.insert(lines, line)
        table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #line, hl_group = "PosteDbCopyError" })
      else
        table.insert(lines, "  ◻ " .. name .. "  (pending)")
      end
    end

    if done == total then
      table.insert(lines, "")
      local done_line = "  Done. " .. completed .. " succeeded, " .. failed .. " failed."
      table.insert(lines, done_line)
      local succeeded_str = tostring(completed) .. " succeeded"
      local succeeded_start = done_line:find(succeeded_str, 1, true) - 1
      if succeeded_start and completed > 0 then
        table.insert(highlights, { line = #lines - 1, col_start = succeeded_start, col_end = succeeded_start + #succeeded_str, hl_group = "PosteDbCopySuccess" })
      end
      if failed > 0 then
        table.insert(lines, "  Press [q] to see errors")
      end
    end

    dlg:update(lines, highlights)
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

function M.copy_tables(source, target, table_names, on_complete)
  if source.dialect ~= target.dialect then
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