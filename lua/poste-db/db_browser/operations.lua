--- Operations dispatched from the DB Browser context menu.
--- Each function: op(node, context) → performs the action.
local cli = require("poste.cli")
local async = require("poste-db.db_browser.async")
local icons = require("poste-db.db_browser.icons")
local forms = require("poste-db.db_browser.forms")
local ident = require("poste-db.ident")
local util = require("poste-db.db_browser.util")
local compat = require("poste-db.compat")
local notify = require("poste-db.db_browser.notify")

local HEADER_LINES = icons.HEADER_LINES
local M = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function safe_str(v)
  if v == nil or v == vim.NULL or type(v) == "userdata" then return nil end
  return tostring(v)
end

local function get_dialect(node, context)
  return util.get_dialect(node, context and context.root_nodes or {})
end

local function get_connection_name(node, context)
  return util.get_connection(node)
end

local function get_search_dir(context)
  return util.get_search_dir(context and context.source_buf)
end

local function find_table_node(context, start_idx)
  return util.find_table_node(context and context.line_to_node or {}, start_idx)
end

local function insert_into_source(context, lines, cursor_offset, cursor_col)
  if not context.source_buf or not vim.api.nvim_buf_is_valid(context.source_buf) then
    notify.warn("No source SQL buffer found")
    return false
  end
  local line_count = vim.api.nvim_buf_line_count(context.source_buf)
  vim.api.nvim_buf_set_lines(context.source_buf, line_count, line_count, false, lines)
  local target_win = vim.fn.bufwinid(context.source_buf)
  if target_win and target_win ~= -1 then
    vim.api.nvim_set_current_win(target_win)
    if cursor_offset then
      vim.api.nvim_win_set_cursor(target_win, { line_count + cursor_offset, cursor_col or 0 })
    end
  end
  return true
end

--- Qualified, quoted table reference for generated SQL.
--- PG applies the schema prefix; other dialects quote the bare name.
local function qualified_table_ref(table_node, dialect)
  local schema_prefix = ""
  if table_node.meta and table_node.meta.schema and dialect == "postgres" then
    schema_prefix = ident.quote(table_node.meta.schema, dialect) .. "."
  end
  return schema_prefix .. ident.quote(table_node.name, dialect)
end

--- Directive header (`-- @connection` / `-- @database`) for generated SQL.
--- Returns the lines and the cursor offset relative to the first inserted line.
local function build_directive_lines(table_node, conn)
  local lines = { "" }
  local cursor_offset = 2
  if conn then
    table.insert(lines, "-- @connection " .. conn)
    cursor_offset = cursor_offset + 1
  end
  if table_node.meta and table_node.meta.database then
    table.insert(lines, "-- @database " .. table_node.meta.database)
    cursor_offset = cursor_offset + 1
  end
  return lines, cursor_offset
end

--- Build ALTER COLUMN migration statements for a modified column.
--- @param table_node table  the parent table node
--- @param node table  the column node being modified
--- @param values { col_type: string, nullable: boolean, default_val: string|nil, comment_val: string|nil }
--- @param dialect string
--- @return string[]  SQL lines (leading blank / trailing blank added by callers)
local function build_alter_column_sql(table_node, node, values, dialect)
  local col_type = values.col_type
  local nullable = values.nullable
  local default_val = values.default_val
  local comment_val = values.comment_val
  local col_ref = ident.quote(node.name, dialect)

  if dialect == "postgres" then
    local lines = { "ALTER TABLE " .. ident.quote(table_node.name, dialect) .. " ALTER COLUMN " .. col_ref .. " TYPE " .. col_type .. ";" }
    if not nullable then
      table.insert(lines, "ALTER TABLE " .. ident.quote(table_node.name, dialect) .. " ALTER COLUMN " .. col_ref .. " SET NOT NULL;")
    end
    if default_val ~= nil and default_val ~= "" then
      table.insert(lines, "ALTER TABLE " .. ident.quote(table_node.name, dialect) .. " ALTER COLUMN " .. col_ref .. " SET DEFAULT " .. default_val .. ";")
    elseif default_val == "" then
      table.insert(lines, "ALTER TABLE " .. ident.quote(table_node.name, dialect) .. " ALTER COLUMN " .. col_ref .. " SET DEFAULT '';")
    end
    if comment_val ~= nil and comment_val ~= "" then
      table.insert(lines, "COMMENT ON COLUMN " .. ident.quote(table_node.name, dialect) .. "." .. col_ref .. " IS '" .. tostring(comment_val):gsub("'", "''") .. "';")
    end
    return lines
  elseif dialect == "mysql" or dialect == "mariadb" then
    local parts = { "ALTER TABLE " .. ident.quote(table_node.name, dialect) .. " MODIFY COLUMN " .. col_ref .. " " .. col_type }
    if not nullable then table.insert(parts, " NOT NULL") end
    if default_val ~= nil and default_val ~= "" then table.insert(parts, " DEFAULT " .. default_val)
    elseif default_val == "" then table.insert(parts, " DEFAULT ''") end
    if comment_val ~= nil and comment_val ~= "" then
      table.insert(parts, " COMMENT '" .. tostring(comment_val):gsub("'", "''") .. "'")
    end
    table.insert(parts, ";")
    return { table.concat(parts, "") }
  else
    local parts = { "ALTER TABLE " .. ident.quote(table_node.name, dialect) .. " ALTER COLUMN " .. col_ref .. " TYPE " .. col_type }
    if not nullable then table.insert(parts, " NOT NULL") end
    if default_val ~= nil and default_val ~= "" then table.insert(parts, " DEFAULT " .. default_val)
    elseif default_val == "" then table.insert(parts, " DEFAULT ''") end
    table.insert(parts, ";")
    return { table.concat(parts, "") }
  end
end

---------------------------------------------------------------------------
-- Operations
---------------------------------------------------------------------------

--- SELECT * LIMIT 100 for table/view; insert at end of source buffer.
function M.select_star(node, context)
  local table_node = node
  if node.node_type == "column" then
    table_node = find_table_node(context, context.line_to_node[node] and 0 or 0)
  end

  -- Fallback: walk up from current line to find table
  if not table_node or table_node.node_type ~= "table" then
    local buf_line = vim.fn.line(".")
    local idx = buf_line - HEADER_LINES
    table_node = find_table_node(context, idx)
  end

  if not table_node or (table_node.node_type ~= "table" and table_node.node_type ~= "view") then
    notify.info("Move cursor to a table or view node")
    return
  end

  local dialect = get_dialect(table_node, context)
  local conn = get_connection_name(table_node, context)

  local query_lines, cursor_offset = build_directive_lines(table_node, conn)
  table.insert(query_lines, "SELECT * FROM " .. qualified_table_ref(table_node, dialect) .. " LIMIT 100;")
  table.insert(query_lines, "")

  if insert_into_source(context, query_lines, cursor_offset) then
    notify.info("Generated SELECT for: " .. table_node.name)
  end
end

--- Show DDL for table/view in a float window.
function M.show_ddl(node, context)
  local table_node = node
  if node.node_type ~= "table" and node.node_type ~= "view" then
    -- For index/key nodes, walk up to table
    table_node = find_table_node(context, vim.fn.line(".") - HEADER_LINES)
  end

  if not table_node or (table_node.node_type ~= "table" and table_node.node_type ~= "view") then
    notify.info("DDL is only available for tables and views")
    return
  end

  local conn = get_connection_name(table_node, context)
  local search_dir = get_search_dir(context)
  local schema = table_node.meta and table_node.meta.schema
  local database = table_node.meta and table_node.meta.database

  local connections = require("poste-db.connections")
  local url, url_err = connections.resolve_connection_url(conn)
  if not url then
    vim.notify("DDL: " .. (url_err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  local cmd = { "introspect", "--connection-url", url, "--type", "ddl", "--table", table_node.name }
  if schema then
    table.insert(cmd, "--schema"); table.insert(cmd, schema)
  end
  if database then
    table.insert(cmd, "--database"); table.insert(cmd, database)
  end

  local log = require("poste-db.log")
  log.info("DB Browser DDL: " .. log.redact_cmd(cmd))

  cli.run_async(cmd, {
    on_stdout = function(data)
      if not data then return end
      while #data > 0 and data[#data] == "" do data[#data] = nil end
      if #data == 0 then return end
      local output = table.concat(data, "\n")
      local ok, parsed = pcall(vim.json.decode, output)
      if not ok or type(parsed) ~= "table" then
        vim.schedule(function()
          notify.warn("DDL: failed to parse output")
        end)
        return
      end

      local items = parsed.items
      if not items or #items == 0 then
        vim.schedule(function()
          notify.warn("DDL: no items in response")
        end)
        return
      end

      vim.schedule(function()
        local ddl = items[1].ddl or ""
        if ddl == "" then
          notify.warn("DDL: empty result")
          return
        end
        local lines = vim.split(ddl, "\n")
        local title = "DDL: " .. table_node.name
        require("poste-db.introspect").show_float(lines, title, "sql")
      end)
    end,
    on_stderr = function(data)
      if not data then return end
    end,
    on_exit = function(code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("DDL fetch failed (exit " .. tostring(code) .. ")", vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

--- Copy node name to system clipboard.
function M.copy_name(node)
  local name = node.name or ""
  vim.fn.setreg("+", name)
  notify.info("Copied: " .. name)
end

--- Rename table or column via vim.ui.input → generate ALTER SQL.
function M.rename(node, context)
  if node.node_type ~= "table" and node.node_type ~= "column" then
    notify.info("Rename is only available for tables and columns")
    return
  end

  local dialect = get_dialect(node, context)
  local label = node.node_type == "table" and "table" or "column"

  -- Temporarily disable dressing.nvim to avoid cmp completions
  local ok_dr, dr = pcall(require, "dressing")
  local dr_saved = ok_dr and dr.config and dr.config.input and dr.config.input.enabled
  if ok_dr and dr.config and dr.config.input then dr.config.input.enabled = false end

  vim.ui.input({
    prompt = "Rename " .. label .. " (" .. node.name .. "): ",
    default = node.name,
  }, function(input)
    if ok_dr and dr.config and dr.config.input then dr.config.input.enabled = dr_saved end
    if not input or input == "" or input == node.name then return end

    local conn = get_connection_name(node, context)
    local lines = { "" }
    local cursor_offset = 2  -- after empty line → ALTER line

    if node.node_type == "table" then
      if conn then
        table.insert(lines, "-- @connection " .. conn)
        cursor_offset = cursor_offset + 1
      end
      if node.meta and node.meta.database then
        table.insert(lines, "-- @database " .. node.meta.database)
        cursor_offset = cursor_offset + 1
      end

      if dialect == "mysql" then
        table.insert(lines, "RENAME TABLE " .. ident.quote(node.name, dialect) .. " TO " .. ident.quote(input, dialect) .. ";")
      elseif dialect == "sqlite" then
        table.insert(lines, "ALTER TABLE " .. ident.quote(node.name, dialect) .. " RENAME TO " .. ident.quote(input, dialect) .. ";")
      else
        table.insert(lines, "ALTER TABLE " .. ident.quote(node.name, dialect) .. " RENAME TO " .. ident.quote(input, dialect) .. ";")
      end
    elseif node.node_type == "column" then
      local table_node = find_table_node(context, vim.fn.line(".") - HEADER_LINES)
      if not table_node then
        notify.warn("Could not find parent table")
        return
      end
      if conn then
        table.insert(lines, "-- @connection " .. conn)
        cursor_offset = cursor_offset + 1
      end
      if table_node.meta and table_node.meta.database then
        table.insert(lines, "-- @database " .. table_node.meta.database)
        cursor_offset = cursor_offset + 1
      end
      if dialect == "mysql" then
        local col_type = node.meta and node.meta.col_type or "TEXT"
        table.insert(lines, "ALTER TABLE " .. ident.quote(table_node.name, dialect)
          .. " CHANGE COLUMN " .. ident.quote(node.name, dialect) .. " " .. ident.quote(input, dialect) .. " " .. col_type .. ";")
      else
        table.insert(lines, "ALTER TABLE " .. ident.quote(table_node.name, dialect)
          .. " RENAME COLUMN " .. ident.quote(node.name, dialect) .. " TO " .. ident.quote(input, dialect) .. ";")
      end
    end

    table.insert(lines, "")
    insert_into_source(context, lines, cursor_offset)
    notify.info("Generated RENAME " .. label .. " SQL")
  end)
end

--- Refresh (re-fetch children) for expandable nodes.
function M.refresh(node, context)
  if node.node_type == "column" or node.node_type == "index"
      or node.node_type == "key_item" or node.node_type == "fk_item"
      or node.node_type == "index_item" then
    notify.info("Cannot refresh leaf nodes")
    return
  end

  util.refresh_subtree(node, context, node.node_type, get_search_dir(context))
end

--- Execute SQL File: pick a .sql file and execute it against this database.
function M.exec_file(node, context)
  local conn = get_connection_name(node, context)
  local database = node.node_type == "database" and node.name
    or (node.meta and node.meta.database)

  -- Mode selection
  local modes = {
    { value = "greedy", label = "Greedy", desc = "Continue on error" },
    { value = "transaction", label = "Transaction", desc = "Rollback on any error" },
  }
  vim.ui.select(modes, {
    prompt = "Execution mode:",
    format_item = function(m) return m.label .. "  " .. m.desc end,
  }, function(choice)
    if not choice then return end

    -- File selection via beyondlex/finder
    local ok, finder = pcall(require, "finder")
    if ok then
      finder.open({
        mode = "both",
        initial_path = vim.fn.getcwd(),
        extensions = { "sql" },
        on_confirm = function(path)
          if not path then return end
          local file_exec = require("poste-db.file_exec")
          file_exec.run({
            filepath = path,
            conn = conn,
            database = database,
            mode = choice.value,
          })
        end,
        on_cancel = function() end,
      })
    else
      -- Fallback: vim.ui.input with file completion
      vim.ui.input({
        prompt = "SQL file path: ",
        default = vim.fn.getcwd() .. "/",
        completion = "file",
      }, function(path)
        if not path or path == "" then return end
        local file_exec = require("poste-db.file_exec")
        file_exec.run({
          filepath = path,
          conn = conn,
          database = database,
          mode = choice.value,
        })
      end)
    end
  end)
end

--- Insert a new query block with connection context.
function M.new_query(node, context)
  local conn = get_connection_name(node, context)
  local lines = { "" }
  local cursor_offset = 2  -- empty + first blank line
  if conn then
    table.insert(lines, "-- @connection " .. conn)
    cursor_offset = cursor_offset + 1
  end
  if node.node_type == "database" then
    table.insert(lines, "USE " .. ident.quote(node.name, dialect) .. ";")
    cursor_offset = cursor_offset + 1
  end
  table.insert(lines, "")
  table.insert(lines, "")

  insert_into_source(context, lines, cursor_offset)
  notify.info("New query block created")
end

--- Set default database/schema: insert USE or SET search_path.
function M.set_default(node, context)
  local dialect = get_dialect(node, context)
  local conn = get_connection_name(node, context)
  local lines = { "" }
  local cursor_offset = 2  -- empty + USE/SET line
  if conn then
    table.insert(lines, "-- @connection " .. conn)
    cursor_offset = cursor_offset + 1
  end

  if node.node_type == "database" then
    table.insert(lines, "USE " .. ident.quote(node.name, dialect) .. ";")
  elseif node.node_type == "schema" then
    if dialect == "postgres" then
      table.insert(lines, "SET search_path TO " .. ident.quote(node.name, dialect) .. ";")
    elseif dialect == "mysql" or dialect == "mariadb" then
      table.insert(lines, "USE " .. ident.quote(node.name, dialect) .. ";")
    else
      table.insert(lines, "-- schema: " .. node.name)
    end
  end
  table.insert(lines, "")

  insert_into_source(context, lines, cursor_offset)
  notify.info("Set default: " .. node.name)
end

--- Open connections.toml at this connection's entry.
function M.edit_conn(node, context)
  local conn_name = node.node_type == "connection" and node.name
    or (node.meta and node.meta.connection)
  if not conn_name then
    notify.warn("No connection name found")
    return
  end

  local connections = require("poste-db.connections")
  local config_path = connections.find_connections_toml(get_search_dir(context))
  if not config_path then
    notify.warn("connections.toml not found")
    return
  end

  local target_win = vim.fn.bufwinid(context.source_buf)
  if target_win and target_win ~= -1 then
    vim.api.nvim_set_current_win(target_win)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(config_path))

  -- Jump to the connection entry (TOML [section] header)
  local search_target = '[' .. conn_name .. ']'
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local found_line = nil
  for i, line in ipairs(lines) do
    if line:find(search_target, 1, true) then
      found_line = i
      break
    end
  end
  if found_line then
    vim.api.nvim_win_set_cursor(0, { found_line, 0 })
  else
    notify.warn("Connection '" .. conn_name .. "' not found in file")
  end
end

--- Modify Column: open form with type/nullable/default, generate ALTER SQL.
function M.modify_col(node, context)
  if node.node_type ~= "column" then
    notify.info("Modify is only available for columns")
    return
  end

  local table_node = find_table_node(context, vim.fn.line(".") - HEADER_LINES)
  if not table_node then
    notify.warn("Could not find parent table")
    return
  end

  local dialect = get_dialect(table_node, context)
  local conn = get_connection_name(table_node, context)
  local types = require("poste-db.db_browser.completion").get_types(dialect)

  local fields = {
    { label = "Type",     key = "col_type", value = node.meta and node.meta.col_type or "", kind = "select", choices = types },
    { label = "Nullable", key = "nullable", value = not not (node.meta and node.meta.nullable), kind = "bool" },
    { label = "Default",  key = "default",  value = safe_str(node.meta and node.meta.default), kind = "text" },
    { label = "Comment",  key = "comment",  value = safe_str(node.meta and node.meta.comment), kind = "text" },
  }

  compat.set("dialect", dialect)

  forms.open("Modify Column: " .. table_node.name .. "." .. node.name, fields, function(updated)
    local lines, cursor_offset = build_directive_lines(table_node, conn)
    vim.list_extend(lines, build_alter_column_sql(table_node, node, {
      col_type = updated[1].value,
      nullable = updated[2].value,
      default_val = updated[3].value,
      comment_val = updated[4].value,
    }, dialect))
    table.insert(lines, "")
    insert_into_source(context, lines, cursor_offset)
    notify.info("Generated ALTER SQL for column: " .. node.name)
  end)
end

--- New Table: open form with table name, generate CREATE TABLE template.
function M.new_table(node, context)
  local dialect = get_dialect(node, context)
  local conn = get_connection_name(node, context)
  local schema = node.node_type == "schema" and node.name or nil
  local database = node.node_type == "database" and node.name or (node.meta and node.meta.database)

  local fields = {
    { label = "Name", key = "table_name", value = "", kind = "text" },
  }

  local title = "New Table"
  if node.node_type == "database" then title = "New Table: " .. node.name end
  if node.node_type == "schema" then title = "New Table: " .. (schema or "") end

  forms.open(title, fields, function(updated)
    local table_name = updated[1].value
    if table_name == "" then
      notify.warn("Table name cannot be empty")
      return
    end

    local lines = { "" }
    local cursor_offset = 2
    if conn then
      table.insert(lines, "-- @connection " .. conn)
      cursor_offset = cursor_offset + 1
    end
    if database then
      table.insert(lines, "-- @database " .. database)
      cursor_offset = cursor_offset + 1
    end

    local qualified = ident.quote(table_name, dialect)
    if schema and dialect == "postgres" then
      qualified = ident.quote(schema, dialect) .. "." .. ident.quote(table_name, dialect)
    end

    table.insert(lines, "CREATE TABLE " .. qualified .. " (")
    table.insert(lines, "  id SERIAL PRIMARY KEY,")
    table.insert(lines, "  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
    table.insert(lines, ");")
    table.insert(lines, "")

    insert_into_source(context, lines, cursor_offset)
    notify.info("Generated CREATE TABLE: " .. table_name)
  end)
end

--- Create Table Template: insert CREATE TABLE snippet with tab stops.
function M.create_table_template(node, context)
  local conn = get_connection_name(node, context)

  if not context.source_buf or not vim.api.nvim_buf_is_valid(context.source_buf) then
    notify.warn("No source SQL buffer found")
    return
  end

  local target_win = vim.fn.bufwinid(context.source_buf)
  if target_win and target_win ~= -1 then
    vim.api.nvim_set_current_win(target_win)
  end

  local line_count = vim.api.nvim_buf_line_count(context.source_buf)
  local insert_line = { "" }
  if conn then
    insert_line = { "", "-- @connection " .. conn, "" }
  end
  vim.api.nvim_buf_set_lines(context.source_buf, line_count, line_count, false, insert_line)
  line_count = vim.api.nvim_buf_line_count(context.source_buf)
  vim.api.nvim_win_set_cursor(0, { line_count, 0 })

  local snippet = [[
create table ${1:table_name} (
  ${2:column_name} ${3:INTEGER} ${4:NOT NULL}
);
]]

  local ok, _ = pcall(vim.snippet.expand, snippet)
  if not ok then
    vim.api.nvim_buf_set_lines(context.source_buf, line_count - 1, line_count, false, {
      "create table ",
      "  ",
      ");",
    })
    vim.api.nvim_win_set_cursor(0, { line_count - 1, 13 })
  end

  notify.info("Generated CREATE TABLE template")
end

--- New Column: open form with name/type/nullable/default, generate ALTER TABLE ADD COLUMN.
function M.new_column(node, context)
  local table_node = node
  if node.node_type ~= "table" then
    table_node = find_table_node(context, vim.fn.line(".") - HEADER_LINES)
  end
  if not table_node or table_node.node_type ~= "table" then
    notify.info("Move cursor to a table node")
    return
  end

  local dialect = get_dialect(table_node, context)
  local conn = get_connection_name(table_node, context)
  local types = require("poste-db.db_browser.completion").get_types(dialect)

  local fields = {
    { label = "Name",     key = "col_name",  value = "",     kind = "text" },
    { label = "Type",     key = "col_type",  value = "TEXT", kind = "select", choices = types },
    { label = "Nullable", key = "nullable",  value = true,   kind = "bool" },
    { label = "Default",  key = "default",   value = "",     kind = "text" },
  }

  compat.set("dialect", dialect)

  forms.open("New Column: " .. table_node.name, fields, function(updated)
    local col_name = updated[1].value
    local col_type = updated[2].value
    local nullable = updated[3].value
    local default_val = updated[4].value

    if col_name == "" then
      notify.warn("Column name cannot be empty")
      return
    end

    local lines = { "" }
    local cursor_offset = 2
    if conn then
      table.insert(lines, "-- @connection " .. conn)
      cursor_offset = cursor_offset + 1
    end
    if table_node.meta and table_node.meta.database then
      table.insert(lines, "-- @database " .. table_node.meta.database)
      cursor_offset = cursor_offset + 1
    end

    local add_col = "ALTER TABLE " .. ident.quote(table_node.name, dialect) .. " ADD COLUMN " .. ident.quote(col_name, dialect) .. " " .. col_type
    if not nullable then add_col = add_col .. " NOT NULL" end
    if default_val ~= "" then add_col = add_col .. " DEFAULT " .. default_val end
    add_col = add_col .. ";"

    if dialect == "mysql" then
      add_col = "ALTER TABLE " .. ident.quote(table_node.name, dialect) .. " ADD COLUMN " .. ident.quote(col_name, dialect) .. " " .. col_type
      if not nullable then add_col = add_col .. " NOT NULL" end
      if default_val ~= "" then add_col = add_col .. " DEFAULT " .. default_val end
      add_col = add_col .. ";"
    end

    table.insert(lines, add_col)
    table.insert(lines, "")

    insert_into_source(context, lines, cursor_offset)
    notify.info("Generated ADD COLUMN: " .. col_name)
  end)
end

--- Get column names/types from a table node (must be expanded).
local function get_columns_from_node(table_node)
  if not table_node.children or #table_node.children == 0 then return nil end
  local cols = {}
  for _, child in ipairs(table_node.children) do
    if child.node_type == "column" then
      table.insert(cols, {
        name = child.name,
        col_type = child.meta and child.meta.col_type or "TEXT",
        is_pk = child.meta and child.meta.is_pk or false,
        nullable = child.meta and child.meta.nullable ~= false,
      })
    end
  end
  if #cols == 0 then return nil end
  return cols
end

--- INSERT template: generate INSERT INTO ... VALUES based on table columns.
function M.insert_template(node, context)
  local table_node = node
  if node.node_type ~= "table" then
    table_node = find_table_node(context, vim.fn.line(".") - HEADER_LINES)
  end
  if not table_node or table_node.node_type ~= "table" then
    notify.info("Move cursor to a table node")
    return
  end

  local cols = get_columns_from_node(table_node)
  if not cols then
    notify.warn("Expand the table first to see columns")
    return
  end

  local dialect = get_dialect(table_node, context)
  local conn = get_connection_name(table_node, context)

  local col_names = {}
  for _, c in ipairs(cols) do
    if not c.is_pk then
      table.insert(col_names, ident.quote(c.name, dialect))
    end
  end

  local lines, cursor_offset = build_directive_lines(table_node, conn)
  table.insert(lines, "INSERT INTO " .. qualified_table_ref(table_node, dialect) .. " (" .. table.concat(col_names, ", ") .. ")")
  table.insert(lines, "VALUES ()")
  table.insert(lines, "")
  cursor_offset = cursor_offset + 1  -- land on VALUES line

  insert_into_source(context, lines, cursor_offset, 8)  -- col 8 = inside VALUES ()
  notify.info("Generated INSERT template for: " .. table_node.name)
end

--- UPDATE template: generate UPDATE ... SET ... WHERE based on table columns.
function M.update_template(node, context)
  local table_node = node
  if node.node_type ~= "table" then
    table_node = find_table_node(context, vim.fn.line(".") - HEADER_LINES)
  end
  if not table_node or table_node.node_type ~= "table" then
    notify.info("Move cursor to a table node")
    return
  end

  local cols = get_columns_from_node(table_node)
  if not cols then
    notify.warn("Expand the table first to see columns")
    return
  end

  local dialect = get_dialect(table_node, context)
  local conn = get_connection_name(table_node, context)

  local pk_cols = {}
  local set_cols = {}
  for _, c in ipairs(cols) do
    if c.is_pk then
      table.insert(pk_cols, ident.quote(c.name, dialect))
    else
      table.insert(set_cols, "  " .. ident.quote(c.name, dialect) .. " = 'val'")
    end
  end

  local lines, cursor_offset = build_directive_lines(table_node, conn)
  table.insert(lines, "UPDATE " .. qualified_table_ref(table_node, dialect))
  table.insert(lines, "SET")
  for _, sc in ipairs(set_cols) do table.insert(lines, sc .. ",") end
  -- Remove trailing comma from last SET column
  local last = lines[#lines]
  lines[#lines] = last:sub(1, -2)
  if #pk_cols > 0 then
    table.insert(lines, "WHERE " .. table.concat(pk_cols, " = ? AND ") .. " = ?;")
  else
    table.insert(lines, "WHERE ?;")
  end
  table.insert(lines, "")

  insert_into_source(context, lines, cursor_offset)
  notify.info("Generated UPDATE template for: " .. table_node.name)
end

--- Import data from CSV/TSV/JSON into this table.
function M.import_data(node, context)
  if node.meta and node.meta.table_type == "VIEW" then
    notify.warn("Cannot import data into a view")
    return
  end
  if node.node_type ~= "table" then
    notify.info("Import is only available for tables")
    return
  end
  require("poste-db.import").run(node, context)
end

--- Drop Table: show confirmation dialog, then execute DROP TABLE.
-----------------------------------------------------------------------------

local execute_drop  -- forward declaration

--- Show a confirmation dialog for dropping a table (red warning text).
local function show_drop_confirm(table_node, qualified, conn, schema_prefix, context)
  local dialog = require("poste.dialog")
  local layout = require("poste.layout")

  local width = 56
  local sql = "DROP TABLE " .. qualified .. ";"

  local lines = {}
  local highlights = {}

  local line_n = 0
  lines[#lines + 1] = "  DANGER: This will permanently drop the table:"
  highlights[#highlights + 1] = { line = line_n, col_start = 2, col_end = #lines[line_n + 1], hl_group = "DiagnosticError" }
  line_n = line_n + 1

  lines[#lines + 1] = "    " .. qualified
  highlights[#highlights + 1] = { line = line_n, col_start = 4, col_end = 4 + #qualified, hl_group = "DiagnosticError" }
  line_n = line_n + 1

  lines[#lines + 1] = ""
  line_n = line_n + 1

  lines[#lines + 1] = "  " .. sql
  line_n = line_n + 1

  lines[#lines + 1] = ""
  line_n = line_n + 1

  local km = layout.keymaps({
    mapping = { { key = "y", label = "Confirm" }, { key = "n", label = "Cancel" } },
    indent = 4,
  })
  lines[#lines + 1] = km.lines[1]
  for _, h in ipairs(km.highlights) do
    highlights[#highlights + 1] = { line = line_n, col_start = h.col_start, col_end = h.col_end, hl_group = h.hl_group }
  end

  local height = #lines + 2
  local dlg = dialog.open({
    title = " Drop Table ",
    width = width,
    height = height,
    border = "rounded",
    backdrop = true,
    close_on_leave = false,
  })
  vim.keymap.set("n", "y", function()
    dlg:close()
    vim.schedule(function()
      execute_drop(table_node, qualified, conn, schema_prefix, context)
    end)
  end, { buffer = dlg.buf, noremap = true, silent = true, nowait = true })
  vim.keymap.set("n", "n", function() dlg:close() end, { buffer = dlg.buf, noremap = true, silent = true, nowait = true })
  dlg:update(lines, highlights)
end

--- Execute DROP TABLE and refresh the browser tree.
execute_drop = function(table_node, qualified, conn, schema_prefix, context)
  local sql_lines = {}
  table.insert(sql_lines, "DROP TABLE " .. qualified .. ";")
  local sql = table.concat(sql_lines, "\n")

  local search_dir = get_search_dir(context)
  local connections = require("poste-db.connections")
  local url, err = connections.resolve_connection_url(conn)
  if not url then
    vim.notify("Drop table failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return
  end

  -- Find parent db/schema node to refresh
  local parent = table_node.parent
  while parent and parent.node_type ~= "database" and parent.node_type ~= "schema" do
    parent = parent.parent
  end

  local database = table_node.meta and table_node.meta.database or nil
  local exec_run = require("poste-db.exec_run")
  local job_id = exec_run.run_async(sql, {
    src_file = search_dir .. "/browser_drop.sql",
    conn_url = url,
    database = database,
    mode = "greedy",
  }, {
    on_response = function(resp)
      vim.schedule(function()
        if resp.has_error then
          vim.notify("Failed to drop table '" .. qualified .. "'", vim.log.levels.ERROR)
          return
        end
        notify.info("Dropped table: " .. qualified)
        if parent then
          util.refresh_subtree(parent, context, parent.node_type, search_dir)
        end
      end)
    end,
    on_error = function(message)
      vim.schedule(function()
        vim.notify("Failed to drop table '" .. qualified .. "': " .. message, vim.log.levels.ERROR)
      end)
    end,
  })

  if not job_id or job_id <= 0 then
    vim.notify("Failed to start poste job", vim.log.levels.ERROR)
  end
end

--- Drop a table: confirm dialog, then execute DROP TABLE and refresh tree.
function M.drop_table(node, context)
  local table_node = node
  if node.node_type ~= "table" then
    table_node = find_table_node(context, vim.fn.line(".") - HEADER_LINES)
  end
  if not table_node or table_node.node_type ~= "table" then
    notify.info("Move cursor to a table node")
    return
  end

  local dialect = get_dialect(table_node, context)
  local conn = get_connection_name(table_node, context)
  local schema_prefix = ""
  if table_node.meta and table_node.meta.schema and dialect == "postgres" then
    schema_prefix = ident.quote(table_node.meta.schema, dialect) .. "."
  end

  local qualified = schema_prefix .. ident.quote(table_node.name, dialect)
  show_drop_confirm(table_node, qualified, conn, schema_prefix, context)
end

--- Build qualified name and lookup for a single table node.
local function prepare_drop_item(table_node, context)
  local dialect = get_dialect(table_node, context)
  local conn = get_connection_name(table_node, context)
  local schema_prefix = ""
  if table_node.meta and table_node.meta.schema and dialect == "postgres" then
    schema_prefix = ident.quote(table_node.meta.schema, dialect) .. "."
  end
  local qualified = schema_prefix .. ident.quote(table_node.name, dialect)

  local parent = table_node.parent
  while parent and parent.node_type ~= "database" and parent.node_type ~= "schema" do
    parent = parent.parent
  end

  return {
    label = qualified,
    sql = "DROP TABLE " .. qualified .. ";",
    parent = parent,
    conn = conn,
    database = table_node.meta and table_node.meta.database or nil,
    table_node = table_node,
  }
end

local function drop_progress_hl()
  if not vim.api.nvim_get_hl(0, { name = "PosteDbDropProgress" }).fg then
    vim.api.nvim_set_hl(0, "PosteDbDropProgress", { fg = "#565f89" })
    vim.api.nvim_set_hl(0, "PosteDbDropError", { fg = "#f7768e" })
    vim.api.nvim_set_hl(0, "PosteDbDropDone", { fg = "#9ece6a" })
  end
end
drop_progress_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = drop_progress_hl })

local function start_batch_drop(items, conn_label, search_dir, context)
  local exec_run = require("poste-db.exec_run")
  local connections = require("poste-db.connections")
  local progress_dlg = nil
  local results = {}
  local completed = 0
  local failed = 0
  local errors = {}
  local cancelled = false
  local total = #items

  for _, it in ipairs(items) do
    results[it.label] = { status = "pending" }
  end

  local function render_progress()
    if not progress_dlg then return end
    local lines = {}
    local highlights = {}
    local done = completed + failed
    local pct = total > 0 and math.floor(done / total * 100) or 0
    local bar_len = 20
    local filled = math.floor(done / total * bar_len)
    local bar = string.rep("█", filled) .. string.rep("░", bar_len - filled)
    table.insert(lines, "  Connection: " .. conn_label)
    table.insert(lines, "")
    local bar_line = "  " .. bar .. "  " .. done .. "/" .. total .. " (" .. pct .. "%)"
    table.insert(lines, bar_line)
    table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #bar_line, hl_group = "PosteDbDropProgress" })
    table.insert(lines, "")

    for _, it in ipairs(items) do
      local r = results[it.label]
      if r.status == "done" then
        local line = "  ✓ " .. it.label
        table.insert(lines, line)
        table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #line, hl_group = "PosteDbDropDone" })
      elseif r.status == "dropping" then
        table.insert(lines, "  ⟳ " .. it.label .. "  (dropping...)")
      elseif r.status == "error" then
        local line = "  ✘ " .. it.label
        table.insert(lines, line)
        table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #line, hl_group = "PosteDbDropError" })
      else
        table.insert(lines, "  ◻ " .. it.label .. "  (pending)")
      end
    end

    if done == total then
      table.insert(lines, "")
      table.insert(lines, "  Done. " .. completed .. " dropped, " .. failed .. " failed.")
      if failed > 0 then
        table.insert(lines, "  Press [q] to see errors")
      end
    end

    if progress_dlg and progress_dlg.win and vim.api.nvim_win_is_valid(progress_dlg.win) then
      progress_dlg:update(lines, highlights)
    end
  end

  local dialog = require("poste.dialog")
  progress_dlg = dialog.open({
    title = "Dropping",
    width = 60,
    height = math.min(math.max(14, 8 + total), 24),
    border = "rounded",
    backdrop = true,
  })
  render_progress()

  local function show_summary()
    if failed == 0 then
      if progress_dlg and progress_dlg.win and vim.api.nvim_win_is_valid(progress_dlg.win) then
        progress_dlg:close()
      end
      return
    end
    local summary_lines = {
      "  Succeeded: " .. completed .. "  |  Failed: " .. failed,
      "",
    }
    for label, err in pairs(errors) do
      summary_lines[#summary_lines + 1] = "  ✘ " .. label
      local clean = err:gsub("\n", " "):gsub("\r", "")
      local line_len = 50
      local pos = 1
      while pos <= #clean do
        local chunk = clean:sub(pos, pos + line_len - 1)
        summary_lines[#summary_lines + 1] = "      " .. chunk
        pos = pos + line_len
      end
    end
    local height = math.min(math.max(6, 4 + #summary_lines), 24)
    local sdlg = dialog.open({
      title = "Drop Complete",
      width = 60,
      height = height,
      border = "rounded",
      backdrop = false,
    })
    sdlg:update(summary_lines)
    vim.keymap.set("n", "q", function() sdlg:close() end, { buffer = sdlg.buf, noremap = true, silent = true, nowait = true })
  end

  local function refresh_all_parents()
    local seen = {}
    for _, it in ipairs(items) do
      if it.parent and not seen[it.parent] then
        seen[it.parent] = true
        it.parent.children = nil
        it.parent.expanded = false
        it.parent.loading = true
      end
    end
    util.render_tree(context)
    local parents = {}
    for p in pairs(seen) do table.insert(parents, p) end
    local idx = 0
    local function next_refresh()
      idx = idx + 1
      if idx > #parents then return end
      local p = parents[idx]
      async.fetch_children(p, function()
        p.expanded = true
        vim.schedule(function()
          next_refresh()
        end)
      end, search_dir)
    end
    next_refresh()
  end

  local function process_next(idx)
    if cancelled then
      if progress_dlg and progress_dlg.win and vim.api.nvim_win_is_valid(progress_dlg.win) then
        progress_dlg:close()
      end
      return
    end
    if idx > total then
      if progress_dlg and progress_dlg.win and vim.api.nvim_win_is_valid(progress_dlg.win) then
        progress_dlg:close()
      end
      show_summary()
      refresh_all_parents()
      return
    end
    local it = items[idx]
    results[it.label] = { status = "dropping" }
    render_progress()

    local url, err = connections.resolve_connection_url(it.conn)
    if not url then
      results[it.label] = { status = "error" }
      errors[it.label] = err or "unknown"
      failed = failed + 1
      render_progress()
      process_next(idx + 1)
      return
    end

    local job_id = exec_run.run_async(it.sql, {
      src_file = search_dir .. "/browser_batch_drop.sql",
      conn_url = url,
      database = it.database,
      mode = "greedy",
    }, {
      on_response = function(resp)
        vim.schedule(function()
          if cancelled then return end
          if resp.has_error then
            results[it.label] = { status = "error" }
            errors[it.label] = "DROP failed"
            failed = failed + 1
          else
            results[it.label] = { status = "done" }
            completed = completed + 1
          end
          render_progress()
          process_next(idx + 1)
        end)
      end,
      on_error = function(message)
        vim.schedule(function()
          if cancelled then return end
          results[it.label] = { status = "error" }
          errors[it.label] = message
          failed = failed + 1
          render_progress()
          process_next(idx + 1)
        end)
      end,
    })

    if not job_id or job_id <= 0 then
      results[it.label] = { status = "error" }
      errors[it.label] = "Failed to start poste job"
      failed = failed + 1
      render_progress()
      process_next(idx + 1)
    end
  end

  vim.keymap.set("n", "q", function()
    cancelled = true
    if progress_dlg and progress_dlg.win and vim.api.nvim_win_is_valid(progress_dlg.win) then
      progress_dlg:close()
    end
  end, { noremap = true, silent = true, nowait = true })

  process_next(1)
end

--- Batch drop tables: confirm dialog, then sequentially drop with progress.
function M.batch_drop_tables(selected_nodes, context)
  local items = {}
  for node in pairs(selected_nodes) do
    if node.node_type == "table" then
      table.insert(items, prepare_drop_item(node, context))
    end
  end
  if #items == 0 then
    notify.info("No table nodes selected")
    return
  end

  table.sort(items, function(a, b) return a.label < b.label end)

  local conn_label = items[1].conn
  local search_dir = get_search_dir(context)

  local lines = {
    "  DANGER: This will permanently drop the following tables:",
    "",
  }
  for _, it in ipairs(items) do
    table.insert(lines, "    " .. it.label)
  end
  table.insert(lines, "")
  table.insert(lines, string.format("  %d table(s) at %s", #items, conn_label))
  table.insert(lines, "")

  local layout = require("poste.layout")
  local km = layout.keymaps({
    mapping = { { key = "y", label = "Drop" }, { key = "n", label = "Cancel" } },
    indent = 4,
  })
  table.insert(lines, km.lines[1])
  local height = #lines + 2
  height = math.min(height, 26)

  local dialog = require("poste.dialog")
  local dlg = dialog.open({
    title = " Drop Tables ",
    width = 60,
    height = height,
    border = "rounded",
    backdrop = true,
    close_on_leave = false,
  })

  local highlights = {}
  highlights[1] = { line = 0, col_start = 2, col_end = #lines[1], hl_group = "DiagnosticError" }

  vim.keymap.set("n", "y", function()
    dlg:close()
    vim.schedule(function() start_batch_drop(items, conn_label, search_dir, context) end)
  end, { buffer = dlg.buf, noremap = true, silent = true, nowait = true })
  vim.keymap.set("n", "n", function() dlg:close() end, { buffer = dlg.buf, noremap = true, silent = true, nowait = true })
  dlg:update(lines, highlights)
end

function M.create_database(node, context)
  require("poste-db.db_browser.db_create").open(node, context)
end

function M.create_schema(node, context)
  require("poste-db.db_browser.schema_create").open(node, context)
end

M._test = {
  safe_str = safe_str,
  get_columns_from_node = get_columns_from_node,
  qualified_table_ref = qualified_table_ref,
  build_directive_lines = build_directive_lines,
  build_alter_column_sql = build_alter_column_sql,
}

return M
