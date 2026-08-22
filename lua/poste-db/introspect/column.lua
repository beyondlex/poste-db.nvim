--- Introspection --- column-level detail fetching and display.
local const = require("poste-db.constants")
local exec = require("poste-db.introspect.exec")
local ui = require("poste-db.introspect.ui")

local M = {}

function M.show_column_info(conn, db, table_name, col_name, schema, show_float)
  table_name = table_name:gsub("^`", ""):gsub("`$", ""):gsub('^"', ''):gsub('"$', '')
  col_name = col_name:gsub("^`", ""):gsub("`$", ""):gsub('^"', ''):gsub('"$', '')
  if not table_name or table_name == "" then
    vim.schedule(function()
      vim.notify("Cannot introspect column: empty table name", vim.log.levels.ERROR, { title = const.PLUGIN_TITLE })
    end)
    return
  end

  local connections = require("poste-db.connections")
  local url, url_err = connections.resolve_connection_url(conn)
  if not url then
    vim.schedule(function()
      vim.notify("Column info: " .. (url_err or "unknown error"), vim.log.levels.ERROR, { title = const.PLUGIN_TITLE })
    end)
    return
  end

  local args = { "introspect", "--connection-url", url, "--type", "columns", "--table", table_name }

  local cc = connections.get_connection_config(conn)
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

  exec.run_json_items_job(args, {
    title = const.PLUGIN_TITLE,
    failure_message = "Failed to parse introspection response",
    empty_message = "No columns found for table '" .. table_name .. "'",
    stderr_prefix = "Column info stderr: ",
    exit_kind = "Column introspection",
    on_items = function(items)
      ui.show_column_info(items, table_name, col_name, show_float)
    end,
  })
end

return M
