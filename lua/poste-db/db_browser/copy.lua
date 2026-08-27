local state = require("poste.state")
local config = require("poste-db.config")
local cli = require("poste.cli")
local util = require("poste.util")
local dialog = require("poste.dialog")
local sql_conn = require("poste-db.db_browser.sql_conn")
local catalog = require("poste-db.db_browser.catalog")

local M = {}

local function setup_highlights()
  vim.api.nvim_set_hl(0, "PosteDbCopySuccess", { fg = "#9ece6a" })
  vim.api.nvim_set_hl(0, "PosteDbCopyError", { fg = "#f7768e" })
  vim.api.nvim_set_hl(0, "PosteDbCopyProgress", { fg = "#565f89" })
  state.apply_highlight_overrides({
    "PosteDbCopySuccess", "PosteDbCopyError", "PosteDbCopyProgress",
  })
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = setup_highlights })

local function quote(name, dialect)
  if dialect == "mysql" or dialect == "mariadb" then
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
  if dialect == "mysql" or dialect == "mariadb" then
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

local function dialect_table_exists_sql(dialect, schema)
  if dialect == "mysql" or dialect == "mariadb" then
    -- information_schema (not SHOW TABLES) so views collide correctly too.
    return "SELECT TABLE_NAME FROM information_schema.TABLES"
      .. " WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '%s'"
  elseif dialect == "postgres" then
    return "SELECT EXISTS (SELECT FROM information_schema.tables"
      .. " WHERE table_schema = '" .. (schema or "public") .. "'"
      .. " AND table_name = '%s')"
  else
    return "SELECT name FROM sqlite_master"
      .. " WHERE type IN ('table','view') AND name='%s'"
  end
end

--- Run `sql` on conn/database; on_result receives the raw JSON envelope.
local function run_sql_on_conn(conn_name, database, sql, on_result, on_error)
  sql_conn.run(conn_name, database, sql, on_result, on_error)
end

local function introspect_ddl(conn_name, db_name, table_name, on_result, on_error)
  local binary = cli.binary()
  if not binary then
    if on_error then on_error("Poste binary not found") end
    return
  end

  local connections = require("poste-db.connections")
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

local function check_table_exists(conn_name, database, dialect, name, on_result, on_error, schema)
  local sql = dialect_table_exists_sql(dialect, schema):format(name)
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

-- --------------------------------------------------------- conflict naming

local function make_default_input()
  ---@param prompt string
  ---@param default string
  ---@param cb function(string|nil)
  return function(prompt, default, cb)
    vim.ui.input({ prompt = prompt, default = default }, function(text)
      if text ~= nil and text == "" then text = nil end
      cb(text)
    end)
  end
end

--- Resolve target names for pasted items when originals already exist there.
---
--- - free name                → kept as-is
--- - colliding name           → dialog prefilled with <name>_copy (auto-bumped
---                              to _copy2… while occupied); user may type any
---                              name, which is itself re-checked and bumped
---                              automatically if taken
--- - cancelling the dialog    → aborts the whole paste (on_cancel)
---
---@param target table {conn, db, dialect}
---@param items table[] {name=..., schema=?}
---@param on_resolved function(names string[]) parallel to items
---@param on_cancel function()
---@param opts table|nil {skip_dialogs=bool}
function M.resolve_conflict_names(target, items, on_resolved, on_cancel, opts)
  opts = opts or {}
  local hooks = _G.poste_db_copy_test_hooks or {}
  local exists_fn = hooks.exists
    or function(t, name, schema, cb)
      check_table_exists(t.conn, t.db, t.dialect, name, cb, function(err)
        vim.schedule(function() vim.notify("Copy: " .. tostring(err), vim.log.levels.ERROR) end)
        cb(true) -- fail closed: pretend it exists rather than clobber it
      end)
    end
  local input_fn = hooks.input or make_default_input()

  -- Pre-collect all collisions up-front so dialogs only appear when needed.
  local collision_state = {} --- [i] = {base=<new base or nil>}
  local checked = 0
  if #items == 0 then on_resolved({}) return end

  local function proceed_with_resolution()
    local results = {}
    local aborted = false

    local function finish()
      if not aborted then on_resolved(results) end
    end

    local function bump_until_free(i, base, suffix, cb)
      local candidate = base .. "_copy" .. (suffix > 1 and tostring(suffix) or "")
      exists_fn(target, candidate, items[i].schema, function(found)
        if not found then cb(candidate) else bump_until_free(i, base, suffix + 1, cb) end
      end)
    end

    local function step(i)
      if aborted then return end
      if i > #items then finish() return end
      local state_i = collision_state[i]
      if not state_i then
        results[i] = items[i].name
        step(i + 1)
        return
      end
      bump_until_free(i, items[i].name, 1, function(safe_default)
        if opts.skip_dialogs then
          results[i] = safe_default
          step(i + 1)
          return
        end
        input_fn(
          "Name for '" .. items[i].name .. "'"
            .. " at " .. target.conn .. "." .. tostring(target.db or "") .. ": ",
          safe_default,
          function(chosen)
            if chosen == nil then
              aborted = true
              on_cancel()
              return
            end
            exists_fn(target, chosen, items[i].schema, function(found2)
              if found2 and chosen ~= safe_default then
                vim.notify("'" .. chosen .. "' also exists — using an automatic suffix",
                  vim.log.levels.INFO)
                bump_until_free(i, chosen, 1, function(bumped)
                  results[i] = bumped
                  step(i + 1)
                end)
              else
                results[i] = chosen
                step(i + 1)
              end
            end)
          end
        )
      end)
              else
                results[i] = chosen
                step(i + 1)
              end
            end)
          end
        )
      end)
    end

    step(1)
  end

  local function probe_next(i)
    if i > #items then
      proceed_with_resolution()
      return
    end
    exists_fn(target, items[i].name, items[i].schema, function(found)
      if found then collision_state[i] = { base = items[i].name } end
      probe_next(i + 1)
    end)
  end

  probe_next(1)
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
  local cfg = config.config.db_browser or {}
  local pos = cfg.split_position or "right"
  local width = 60
  local height = 12
  return { width = width, height = height, dir = pos }
end

-- ------------------------------------------------------------ size display

local function format_bytes(n)
  if type(n) ~= "number" then return nil end
  if n < 1024 then return string.format("%d B", n)
  elseif n < 1024 * 1024 then return string.format("%.1f KB", n / 1024)
  elseif n < 1024 * 1024 * 1024 then return string.format("%.1f MB", n / (1024 * 1024))
  else return string.format("%.2f GB", n / (1024 * 1024 * 1024)) end
end

--- Look up a plan item's byte size from the sizes map (bare and, for PG,
--- "schema.name" keys).
local function item_bytes(sizes, item)
  if not sizes or next(sizes) == nil then return nil end
  local v = sizes[item.final]
  if v == nil and item.schema then v = sizes[item.schema .. "." .. item.orig] end
  if v == nil then v = sizes[item.orig] end
  if type(v) == "number" then return v end
  return nil
end

-- ---------------------------------------------------------- confirm dialog

--- Show the pre-flight confirmation with size estimate and rename mapping.
---@param source table {conn, db, dialect}
---@param target table {conn, db, dialect}
---@param plan table[] {kind, orig, final, schema, kind_tag}
---@param sizes table|nil name -> bytes map from catalog.sizes()
local function show_paste_confirm(source, target, plan, sizes, on_confirm, on_cancel)
  local popts = popup_options()
  local same_dialect = source.dialect == target.dialect
  local same_server = source.conn == target.conn

  local total_bytes = 0
  local any_size = false
  for _, p in ipairs(plan) do
    if p.kind == "table" or p.kind == "view" then
      local b = item_bytes(sizes, p)
      if b then any_size = true; total_bytes = total_bytes + b end
    end
  end

  local status_text
  if not same_dialect then
    status_text = "MISMATCH - dialect differs"
  elseif not same_server then
    status_text = "Cross-server (SELECT+INSERT)"
  else
    status_text = "Ready"
  end

  local lines = {
    "  Source:  " .. source.conn .. "." .. tostring(source.db or "(conn)")
      .. " (" .. source.dialect .. ")",
    "  Target:  " .. target.conn .. "." .. tostring(target.db or "(conn)")
      .. " (" .. target.dialect .. ")",
    "  Status:  " .. status_text,
    "",
    "  Items:   " .. #plan .. "        Size: ~"
      .. (any_size and format_bytes(total_bytes) or "unknown"),
  }

  -- Warn before a heavy cross-server load: SELECT* loads the whole result
  -- set into memory before batching INSERTs.
  if same_dialect and not same_server and total_bytes > 100 * 1024 * 1024 then
    table.insert(lines, "           ⚠ >100 MB cross-server copy may be slow")
  end

  table.insert(lines, "")
  table.insert(lines, "  Plan:")
  local renamed = 0
  for i, p in ipairs(plan) do
    local label
    if p.kind_tag and p.kind_tag ~= "" then
      label = "    " .. p.final .. p.kind_tag
    else
      label = "    " .. p.final
    end
    if p.final ~= p.orig then
      renamed = renamed + 1
      label = "    " .. p.orig .. " → " .. p.final .. p.kind_tag
    end
    local b = item_bytes(sizes, p)
    if b and b > 0 then
      label = label .. string.rep(" ", math.max(1, 34 - #label)) .. "(" .. format_bytes(b) .. ")"
    end
    table.insert(lines, label)
    if i >= 8 then
      table.insert(lines, "    ... and " .. (#plan - 8) .. " more")
      break
    end
  end
  if renamed > 0 then
    table.insert(lines, "")
    table.insert(lines, "  " .. renamed .. " name conflict" .. (renamed > 1 and "s" or "") .. " resolved via dialog")
  end
  table.insert(lines, "")
  table.insert(lines, "  [y] Start  [n] Cancel")

  local height = math.min(math.max(12, #lines + 2), 26)
  local dlg = dialog.open({
    title = "Paste",
    width = math.max(popts.width, 56),
    height = height,
    border = "rounded",
    backdrop = true,
  })

  local km = { buffer = dlg.buf, noremap = true, silent = true, nowait = true }
  vim.keymap.set("n", "y", function()
    dlg:close()
    if on_confirm then on_confirm() end
  end, km)
  vim.keymap.set("n", "n", function()
    dlg:close()
    if on_cancel then on_cancel() end
  end, km)

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

local function show_paste_progress(source, target, jobs, on_close)
  local popts = popup_options()
  local height = math.max(14, 8 + #jobs)
  height = math.min(height, 24)

  local opts = {
    title = "Copying",
    width = popts.width,
    height = height,
    border = "rounded",
    backdrop = true,
    on_close = on_close,
  }

  local dlg = dialog.open(opts)
  local results = {}
  local total = #jobs
  local completed = 0
  local failed = 0
  local errors = {}
  local cancelled = false

  for _, j in ipairs(jobs) do
    results[j.label] = { status = "pending", row_count = "", elapsed = "" }
  end

  local function render()
    local lines = {}
    local highlights = {}
    local done = completed + failed
    local pct = total > 0 and math.floor(done / total * 100) or 0
    local bar_len = 20
    local filled = math.floor(done / total * bar_len)
    local bar = string.rep("█", filled) .. string.rep("░", bar_len - filled)
    table.insert(lines, "  Source: " .. source.conn .. "." .. tostring(source.db or "(conn)"))
    table.insert(lines, "  Target: " .. target.conn .. "." .. tostring(target.db or "(conn)"))
    table.insert(lines, "")
    local bar_line = "  " .. bar .. "  " .. done .. "/" .. total .. " (" .. pct .. "%)"
    table.insert(lines, bar_line)
    table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #bar_line, hl_group = "PosteDbCopyProgress" })
    table.insert(lines, "")

    for _, j in ipairs(jobs) do
      local r = results[j.label]
      local shown = j.label .. (j.tag or "")
      if r.status == "done" then
        local line = "  ✓ " .. shown
        if r.row_count ~= "" then
          line = line .. "  (" .. r.row_count .. (r.elapsed ~= "" and ", " .. r.elapsed or "") .. ")"
        elseif r.elapsed ~= "" then
          line = line .. "  (" .. r.elapsed .. ")"
        end
        table.insert(lines, line)
        table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #line, hl_group = "PosteDbCopySuccess" })
      elseif r.status == "copying" then
        table.insert(lines, "  ⟳ " .. shown .. "  (copying...)")
      elseif r.status == "error" then
        local line = "  ✘ " .. shown
        table.insert(lines, line)
        table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #line, hl_group = "PosteDbCopyError" })
      else
        table.insert(lines, "  ◻ " .. shown .. "  (pending)")
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

  local function advance(label, status, row_count, elapsed, err_msg)
    results[label] = { status = status, row_count = row_count or "", elapsed = elapsed or "" }
    if status == "done" then
      completed = completed + 1
    elseif status == "error" then
      failed = failed + 1
      errors[label] = err_msg or "Unknown error"
    end
    render()

    if completed + failed == total and failed > 0 then
      vim.defer_fn(function()
        show_summary_dialog(completed, failed, errors)
      end, 500)
    end
  end

  local function start_copy()
    local idx = 0
    local function process_next()
      if cancelled then return end
      idx = idx + 1
      if idx > total then return end
      local j = jobs[idx]

      results[j.label] = { status = "copying", row_count = "", elapsed = "" }
      render()

      j.work(function(ok, row_count, elapsed, err)
        if ok then
          advance(j.label, "done", row_count, elapsed)
        else
          advance(j.label, "error", nil, nil, err)
        end
        process_next()
      end)
    end

    process_next()
  end

  return start_copy, function()
    cancelled = true
    dlg:close()
  end
end

-- --------------------------------------------------------------- executors

local KIND_TAGS = {
  view = " (view)",
  trigger = " (trigger)",
  PROCEDURE = " (procedure)",
  FUNCTION = " (function)",
}

local function execute_sql_on_target(target, sql, cb)
  run_sql_on_conn(target.conn, target.db, sql, function(output)
    local ok = check_response(output, "execute", function(err) cb(false, nil, nil, err) end)
    if not ok then return end
    cb(true, "-", "?")
  end, function(err) cb(false, nil, nil, err) end)
end

--- Replace a routine's own name inside its SHOW CREATE/pg_get_functiondef
--- text (first occurrence after the PROCEDURE/FUNCTION keyword, so DEFINER
--- clauses are untouched).
local function rename_routine_in_def(dialect, def, src, tgt)
  local upper = def:upper()
  local kw_pos = upper:find("PROCEDURE") or upper:find("FUNCTION")
  if not kw_pos then return def end

  if dialect == "mysql" or dialect == "mariadb" then
    local open = def:find("`", kw_pos, true)
    while open do
      local close = def:find("`", open + 1, true)
      if not close then break end
      if def:sub(open + 1, close - 1) == src then
        return def:sub(1, open) .. "`" .. tgt .. "`" .. def:sub(close + 1)
      end
      open = def:find("`", close + 1, true)
      if open and open > close and open < kw_pos + 200 then
        -- keep scanning just past this token pair; stop runaway scans early
        break
      end
      open = nil
    end
    -- Fallback: any direct `src` mention right after the keyword.
    local plain_idx = def:find("`" .. src .. "`", kw_pos, true)
    if plain_idx then
      return def:sub(1, plain_idx) .. "`" .. tgt .. "`" .. def:sub(plain_idx + #src + 2)
    end
    return def
  end

  -- Postgres: name immediately precedes the parameter list.
  local paren = def:find("%(", kw_pos)
  if not paren then return def end
  local before = def:sub(kw_pos + 1, paren - 1)
  local trimmed = before:gsub('%s+', '')
  if trimmed:sub(-#src) == src then
    local start_pos = kw_pos + 1 + (#before - #trimmed) + (#trimmed - #src)
    return def:sub(1, start_pos - 1) .. tgt .. def:sub(paren)
  end
  return def
end

-- ------------------------------------------------------------ orchestration

local function default_item_context(entry, ctx_defaults)
  entry.conn = entry.conn or ctx_defaults.conn
  entry.db = entry.db or ctx_defaults.db
  entry.dialect = entry.dialect or ctx_defaults.dialect
  return entry
end

--- Copy/paste pipeline shared by yank-paste and legacy multi-select.
---
--- Stage 1 probe sizes (async, tolerant) →
--- Stage 2 resolve conflicts via dialogs (tables/views only) →
--- Stage 3 confirm dialog → Stage 4 sequential execution with progress.
---
---@param source table {conn, db, dialect}
---@param target table {conn, db, dialect}
---@param items table[] {kind="table"|"view", name, conn?, db?, dialect?}
---@param triggers table[] parsed catalog trigger rows
---@param routines table[] {name, rtype, conn?, db?, dialect?}
---@param opts table|nil {on_complete=function()}
function M.paste_objects(source, target, items, triggers, routines, opts)
  opts = opts or {}

  if source.dialect ~= target.dialect then
    vim.notify(string.format(
      "Cannot paste: dialect mismatch (%s → %s). Both must be the same dialect.",
      source.dialect, target.dialect), vim.log.levels.ERROR)
    return
  end
  if #items == 0 and #triggers == 0 and #routines == 0 then
    vim.notify("Nothing to paste", vim.log.levels.INFO)
    return
  end

  local norm_items = {}
  for _, it in ipairs(items) do
    table.insert(norm_items, default_item_context(it, source))
  end
  local norm_routines = {}
  for _, r in ipairs(routines) do
    table.insert(norm_routines, default_item_context(r, source))
  end

  local resolvable = {}
  for _, it in ipairs(norm_items) do
    table.insert(resolvable, it) -- keep reference order stable
  end

  -- Views fetch their definitions lazily at execution time, so cache them
  -- here only when the item itself names one (no-op otherwise).

  catalog.sizes({ conn = source.conn, db = source.db, dialect = source.dialect }, function(sizes)
    M.resolve_conflict_names(target, resolvable, function(names)
      local plan = {}
      for i, it in ipairs(norm_items) do
        table.insert(plan, {
          kind = it.kind,
          orig = it.name,
          final = names[i] or it.name,
          schema = it.schema,
          kind_tag = it.kind == "view" and KIND_TAGS.view or "",
        })
      end
      for _, t in ipairs(triggers) do
        table.insert(plan, {
          kind = "trigger",
          orig = tostring(t.name),
          final = tostring(t.name),
          kind_tag = KIND_TAGS.trigger,
        })
      end
      for _, r in ipairs(norm_routines) do
        table.insert(plan, {
          kind = "routine",
          orig = r.name,
          final = r.name,
          rtype = r.rtype,
          kind_tag = KIND_TAGS[r.rtype] or "",
        })
      end

      show_paste_confirm(source, target, plan, sizes, function()
        local jobs = {}

        for i, it in ipairs(norm_items) do
          local final_name = plan[i].final
          if it.kind == "view" then
            jobs[#jobs + 1] = {
              label = final_name,
              tag = KIND_TAGS.view,
              work = function(cb)
                catalog.fetch_view_definition(
                  { conn = it.conn, db = it.db, dialect = it.dialect, name = it.name },
                  function(body, err)
                    if not body then cb(false, nil, nil, err); return end
                    local create_sql = "CREATE VIEW " .. quote(final_name, target.dialect)
                      .. " AS " .. body
                    execute_sql_on_target(target, create_sql, cb)
                  end)
              end,
            }
          else
            jobs[#jobs + 1] = {
              label = final_name,
              work = function(cb)
                copy_one_table(it, target, it.name, final_name,
                  function(row_count, elapsed) cb(true, row_count, elapsed) end,
                  function(err) cb(false, nil, nil, err) end)
              end,
            }
          end
        end

        for _, t in ipairs(triggers) do
          jobs[#jobs + 1] = {
            label = tostring(t.name),
            tag = KIND_TAGS.trigger,
            work = function(cb)
              local sql = catalog.compose_trigger_sql(target.dialect, t)
              execute_sql_on_target(target, sql, cb)
            end,
          }
        end

        for ji, r in ipairs(norm_routines) do
          local plan_entry = plan[#norm_items + #triggers + ji]
          jobs[#jobs + 1] = {
            label = plan_entry.final,
            tag = plan_entry.kind_tag,
            work = function(cb)
              catalog.fetch_routine_definition(r, function(def, err)
                if not def then cb(false, nil, nil, err); return end
                local sql = def
                if plan_entry.final ~= r.name then
                  sql = rename_routine_in_def(r.dialect, def, r.name, plan_entry.final)
                end
                execute_sql_on_target(target, sql, cb)
              end)
            end,
          }
        end

        local start_fn, cancel_fn = show_paste_progress(source, target, jobs, function()
          if opts.on_complete then opts.on_complete() end
        end)
        _G.poste_db_copy_cancel_last = cancel_fn
        start_fn()
      end, function()
        -- user cancelled at confirm
      end)
    end, function()
      -- user aborted during conflict naming
    end, { skip_dialogs = true })
  end)
end

--- Legacy compat shim for the old multi-select copy path (init.lua:start_copy).
--- Converts a flat list of table names into items and delegates to paste_objects.
function M.copy_tables(source, target, table_names, on_complete)
  local items = {}
  for _, name in ipairs(table_names) do
    table.insert(items, {
      kind = "table",
      name = name,
      conn = source.conn,
      db = source.db,
      dialect = source.dialect,
    })
  end
  M.paste_objects(source, target, items, {}, {}, { on_complete = on_complete })
end

return M