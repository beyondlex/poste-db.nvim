--- SQL introspection utilities — float window display, column info, and DDL.
---
--- Extracted from sql/init.lua to reduce module size.
--- Provides show_table_ddl() and supporting functions.
-- luacheck: ignore 411

local state = require("poste.state")
local util = require("poste.util")
local float_window = require("poste-sql.float_window")
local helpers = require("poste-sql.introspect_helpers")
local route = require("poste-sql.introspect_route")
local exec = require("poste-sql.introspect_exec")
local context_resolver = require("poste-sql.introspect_context")
local const = require("poste-sql.constants")

local M = {}

---------------------------------------------------------------------------
-- Float window
---------------------------------------------------------------------------

--- Show or open a float window with text content.
--- @param lines string[]
--- @param title string
--- @param ft string|nil  filetype (default "sql")
function M.show_float(lines, title, ft)
  if not lines or #lines == 0 then
    vim.notify("No content to display", vim.log.levels.WARN, { title = "Poste SQL" })
    return
  end
  local float_buf, win = float_window.open_centered(lines, {
    filetype = ft or "sql",
    title = title,
    title_pos = "left",
    width_ratio = const.INTROSPECT_FLOAT_WIDTH_RATIO,
    max_width = const.INTROSPECT_FLOAT_MAX_WIDTH,
    width_padding = const.INTROSPECT_FLOAT_WIDTH_PADDING,
    height_ratio = const.INTROSPECT_FLOAT_HEIGHT_RATIO,
    min_height = const.INTROSPECT_FLOAT_MIN_HEIGHT,
    extra_height = const.INTROSPECT_FLOAT_EXTRA_HEIGHT,
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].scrolloff = 1
  vim.wo[win].cursorline = true

  local sopts = { buffer = float_buf, noremap = true, silent = true }
  vim.keymap.set("n", "j", "j", sopts)
  vim.keymap.set("n", "k", "k", sopts)
  vim.keymap.set("n", "d", "<C-d>", sopts)
  vim.keymap.set("n", "u", "<C-u>", sopts)
  vim.keymap.set("n", "g", "gg", sopts)
  vim.keymap.set("n", "G", "G", sopts)
  local close_fn = function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  local ck = state.get_keymap("sql_introspect", "close", "q")
  if ck then vim.keymap.set("n", ck, close_fn, sopts) end
  ck = state.get_keymap("sql_introspect", "close_alt", "<Esc>")
  if ck then vim.keymap.set("n", ck, close_fn, sopts) end
end

---------------------------------------------------------------------------
-- Column info
---------------------------------------------------------------------------

--- Show column info in a float window.
--- @param binary string
--- @param conn string
--- @param db string|nil
--- @param file string
--- @param table_name string Parent table
--- @param col_name string Column name under cursor
--- @param schema string|nil Schema name (for PG)
local function show_column_info(binary, conn, db, file, table_name, col_name, schema)
  -- Strip backtick/quote quoting from names (from RENAME/CHANGE COLUMN SQL)
  table_name = table_name:gsub("^`", ""):gsub("`$", ""):gsub('^"', ''):gsub('"$', '')
  col_name = col_name:gsub("^`", ""):gsub("`$", ""):gsub('^"', ''):gsub('"$', '')
  if not table_name or table_name == "" then
    vim.schedule(function()
      vim.notify("Cannot introspect column: empty table name", vim.log.levels.ERROR, { title = "Poste SQL" })
    end)
    return
  end

  local connections = require("poste-sql.connections")
  local url, url_err = connections.resolve_connection_url(conn)
  if not url then
    vim.schedule(function()
      vim.notify("Column info: " .. (url_err or "unknown error"), vim.log.levels.ERROR, { title = "Poste SQL" })
    end)
    return
  end

  local args = { binary, "introspect", "--connection-url", url,
    "--type", "columns", "--table", table_name }

  -- For MySQL, schema = database, so use schema as the database override
  -- For PG, keep db as the database and pass schema as --schema
  local cc = require("poste-sql.connections").get_connection_config(conn)
  local dialect = cc and cc.dialect or ""
  if dialect == "mysql" and schema and schema ~= "" then
    db = schema
    schema = nil
  end

  if schema and schema ~= "" then
    table.insert(args, "--schema")
    table.insert(args, schema)
  end
  if db and db ~= vim.NIL and db ~= "" then
    table.insert(args, "--database")
    table.insert(args, db)
  end

  state.log("INFO", "Column info args: " .. vim.inspect(args))

  exec.run_json_items_job(args, {
    title = "Poste SQL",
    failure_message = "Failed to parse introspection response",
    empty_message = "No columns found for table '" .. table_name .. "'",
    stderr_prefix = "Column info stderr: ",
    exit_kind = "Column introspection",
    on_items = function(items)
      local col = nil
      for _, c in ipairs(items) do
        if c.name == col_name then col = c; break end
      end
      if not col then
        vim.notify("Column '" .. col_name .. "' not found in table '" .. table_name .. "'", vim.log.levels.WARN, { title = "Poste SQL" })
        return
      end
      M.show_float(helpers.build_column_info_lines(table_name, col), "Column: " .. col_name, "sql")
    end,
  })
end

---------------------------------------------------------------------------
-- Table DDL
---------------------------------------------------------------------------

--- List all tables in a database and show them in a float window.
--- @param binary string
--- @param conn string
--- @param db_name string
local function list_tables_in_db(binary, conn, db_name)
  local connections = require("poste-sql.connections")
  local url, url_err = connections.resolve_connection_url(conn)
  if not url then
    vim.notify("Table listing: " .. (url_err or "unknown error"), vim.log.levels.ERROR, { title = "Poste SQL" })
    return
  end
  local args = { binary, "introspect", "--connection-url", url, "--type", "tables", "--database", db_name }
  exec.run_json_items_job(args, {
    title = "Poste SQL",
    failure_message = "Failed to list tables",
    empty_message = "No tables found in database '" .. db_name .. "'",
    stderr_prefix = "introspect stderr: ",
    exit_kind = "Table listing",
    on_items = function(items)
      M.show_float(helpers.build_table_lines(items), "Tables: " .. db_name)
    end,
  })
end

--- Show DDL for the table under the cursor in a floating window.
function M.show_table_ddl()
  local binary = state.find_poste_binary()
  if not binary then
    vim.notify("Poste binary not found.", vim.log.levels.ERROR, { title = "Poste SQL" })
    return
  end

  -- Check if cursor is on a -- @database <name> line → list tables
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1] or ""
  local entry = route.resolve_table_ddl_entry(line_text)
  if entry and entry.kind == "database" then
    local db_name = entry.db_name
    local ctx = require("poste-sql.context").resolve_full_context(buf, line_num)
    local conn = ctx.connection
    if not conn then
      vim.notify("No connection context for database '" .. db_name .. "'", vim.log.levels.WARN, { title = "Poste SQL" })
      return
    end
    local connections = require("poste-sql.connections")
    local url, url_err = connections.resolve_connection_url(conn)
    if not url then
      vim.notify("Table listing: " .. (url_err or "unknown error"), vim.log.levels.ERROR, { title = "Poste SQL" })
      return
    end
    local cmd = { "introspect", "--connection-url", url, "--type", "tables", "--database", db_name }
    exec.run_json_items_job(cmd, {
      title = "Poste SQL",
      failure_message = "Failed to list tables",
      empty_message = "No tables found in database '" .. db_name .. "'",
      stderr_prefix = "introspect stderr: ",
      exit_kind = "Table listing",
      on_items = function(items)
        M.show_float(helpers.build_table_lines(items), "Tables: " .. db_name)
      end,
    })
    return
  end

  if entry and entry.kind == "connection" then
    local conn_name = entry.conn_name
    local config = require("poste-sql.connections").get_connection_config(conn_name)
    if not config then
      vim.notify("Connection '" .. conn_name .. "' not found in connections.toml", vim.log.levels.WARN, { title = "Poste SQL" })
      return
    end
    M.show_float(helpers.build_connection_lines(config), "Connection: " .. conn_name)
    return
  end

  local cword = vim.fn.expand("<cword>")
  if not cword or cword == "" then
    vim.notify("No word under cursor", vim.log.levels.WARN, { title = "Poste SQL" })
    return
  end
  if route.is_sql_keyword(cword) then
    vim.notify("'" .. cword .. "' is a SQL keyword", vim.log.levels.INFO, { title = "Poste SQL" })
    return
  end

  local sql_context = require("poste-sql.context")
  local buf = vim.api.nvim_get_current_buf()
  local ctx = sql_context.resolve_full_context(buf)
  local conn = ctx.connection
  if not conn or conn == "" then
    vim.notify("No SQL connection context. Add -- @connection <name> to the file header.", vim.log.levels.ERROR, { title = "Poste SQL" })
    return
  end

  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    file = vim.fn.getcwd() .. "/query.sql"
  end
  local db = ctx.database

  -- Try to detect if cursor is on a column name via Rust context detection
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local col = cursor[2]
  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local line_text = all_lines[line_num] or ""
  local line_len = #line_text

  local end_col = col
  while end_col < line_len do
    local ch = line_text:sub(end_col + 1, end_col + 1)
    if ch:match("[%w_]") then end_col = end_col + 1 else break end
  end

  -- Check for .column suffix (alias.column → column part)
  local after_dot_col = nil
  local nxt = line_text:sub(end_col + 1, end_col + 1)
  if nxt == "." then
    local cm = line_text:match("^([%w_]+)", end_col + 2)
    if cm then after_dot_col = cm end
  end

  if after_dot_col then
    -- alias.column pattern: resolve alias via context detection
    local block_start = 1
    if line_num > 1 then
      for i = line_num - 1, 1, -1 do
        if all_lines[i] and all_lines[i]:match("^###") then block_start = i + 1; break end
      end
    end
    local block_end = #all_lines
    for i = line_num + 1, #all_lines do
      if all_lines[i] and all_lines[i]:match("^###") then block_end = i - 1; break end
    end
    if block_start <= line_num and line_num <= block_end then
      local before_parts = {}
      for i = block_start, line_num - 1 do
        table.insert(before_parts, all_lines[i] or "")
      end
      -- Include alias.column for context: extend end_col past .column
      local xtra = end_col + 1 + #after_dot_col
      table.insert(before_parts, line_text:sub(1, xtra))
      local offset = #table.concat(before_parts, "\n")
      if offset > 0 then
        offset = offset - 1
      end
      local block_parts = {}
      for i = block_start, block_end do table.insert(block_parts, all_lines[i] or "") end
      local sql_text = table.concat(block_parts, "\n")
      local dial = ""
      local cc = require("poste-sql.connections").get_connection_config(conn)
      if cc and cc.dialect then dial = " --dialect " .. cc.dialect end
      local cmd = string.format("%s context detect %d%s", vim.fn.shellescape(binary), offset, dial)
      local out = vim.fn.system(cmd, sql_text)
      if vim.v.shell_error == 0 and out and out ~= "" then
        local ok, parsed = pcall(vim.json.decode, out)
        if ok and parsed then
          util.clean_nil(parsed)
          local target = context_resolver.resolve_detected_target(parsed, cword, db, after_dot_col)
          if target and target.kind == "column" and target.parent_table then
            show_column_info(binary, conn, target.db or db, file, target.parent_table, target.column_name, target.parent_schema)
            return
          end
        end
      end
    end
  end

  -- Check if cword is a column name (not a table) via context detection
  local block_start = 1
  if line_num > 1 then
    for i = line_num - 1, 1, -1 do
      if all_lines[i] and all_lines[i]:match("^###") then block_start = i + 1; break end
    end
  end
  local block_end = #all_lines
  for i = line_num + 1, #all_lines do
    if all_lines[i] and all_lines[i]:match("^###") then block_end = i - 1; break end
  end

  if block_start <= line_num and line_num <= block_end then
    local before_parts = {}
    for i = block_start, line_num - 1 do
      table.insert(before_parts, all_lines[i] or "")
    end
    table.insert(before_parts, line_text:sub(1, end_col))
    local offset = #table.concat(before_parts, "\n")
    -- Adjust offset to point to the last character of the word, not the
    -- character after it (e.g., for "authors;" the offset should be on
    -- "s" not on ";"). This ensures the Rust binary detects the correct
    -- context type (e.g., schema_table for schema-qualified table refs).
    if offset > 0 then
      offset = offset - 1
    end

    local block_parts = {}
    for i = block_start, block_end do table.insert(block_parts, all_lines[i] or "") end
    local sql_text = table.concat(block_parts, "\n")

    local dial = ""
    local cc = require("poste-sql.connections").get_connection_config(conn)
    if cc and cc.dialect then dial = " --dialect " .. cc.dialect end

    local cmd = string.format("%s context detect %d%s",
      vim.fn.shellescape(binary), offset, dial)
    local out = vim.fn.system(cmd, sql_text)
    if vim.v.shell_error == 0 and out and out ~= "" then
      local ok, parsed = pcall(vim.json.decode, out)
      if ok and parsed then
        util.clean_nil(parsed)
        local target = context_resolver.resolve_detected_target(parsed, cword, db)
        if target then
          if target.kind == "list_tables" and target.db then
            list_tables_in_db(binary, conn, target.db)
            return
          end
          if target.kind == "column" and target.parent_table and target.parent_table:lower() ~= target.column_name:lower() then
            show_column_info(binary, conn, target.db or db, file, target.parent_table, target.column_name, target.parent_schema)
            return
          end
          if target.kind == "ddl" and target.table_name then
            db = target.db or db
            cword = target.table_name
          end
        end
      end
    end
  end

  -- Fallback: show DDL (table mode)
  local connections = require("poste-sql.connections")
  local url, url_err = connections.resolve_connection_url(conn)
  if not url then
    vim.notify("DDL: " .. (url_err or "unknown error"), vim.log.levels.ERROR, { title = "Poste SQL" })
    return
  end

  local args = { binary, "introspect", "--connection-url", url, "--type", "ddl", "--table", cword }
  if db and db ~= vim.NIL and db ~= "" then
    table.insert(args, "--database"); table.insert(args, db)
  end

  state.log("INFO", "DDL args: " .. vim.inspect(args))

  exec.run_json_items_job(args, {
    title = "Poste SQL",
    failure_message = "Failed to parse DDL response",
    empty_message = "No DDL found for table '" .. cword .. "'",
    stderr_prefix = "DDL stderr: ",
    exit_kind = "DDL introspection",
    on_items = function(items)
      local ddl_text = items[1].ddl
      if not ddl_text or ddl_text == "" then
        vim.notify("No DDL found for table '" .. cword .. "'", vim.log.levels.WARN, { title = "Poste SQL" })
        return
      end

      local lines = vim.split(ddl_text, "\n", { plain = true })
      M.show_float(lines, "DDL: " .. cword, "sql")
    end,
  })
end

return M
