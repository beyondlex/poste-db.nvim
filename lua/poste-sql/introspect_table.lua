local const = require("poste-sql.constants")
local exec = require("poste-sql.introspect_exec")
local ui = require("poste-sql.introspect_ui")

local M = {}

local function resolve_url(conn)
  local connections = require("poste-sql.connections")
  local url, url_err = connections.resolve_connection_url(conn)
  if not url then
    return nil, url_err or "unknown error"
  end
  return url, nil
end

function M.show_database_tables(conn, db_name, show_float)
  local url, url_err = resolve_url(conn)
  if not url then
    vim.notify("Table listing: " .. url_err, vim.log.levels.ERROR, { title = const.PLUGIN_TITLE })
    return
  end

  local args = { "introspect", "--connection-url", url, "--type", "tables", "--database", db_name }
  exec.run_json_items_job(args, {
    title = const.PLUGIN_TITLE,
    failure_message = "Failed to list tables",
    empty_message = "No tables found in database '" .. db_name .. "'",
    stderr_prefix = "introspect stderr: ",
    exit_kind = "Table listing",
    on_items = function(items)
      ui.show_table_list(items, db_name, show_float)
    end,
  })
end

function M.show_table_ddl(conn, db, cword, show_float)
  local url, url_err = resolve_url(conn)
  if not url then
    vim.notify("DDL: " .. url_err, vim.log.levels.ERROR, { title = const.PLUGIN_TITLE })
    return
  end

  local args = { "introspect", "--connection-url", url, "--type", "ddl", "--table", cword }
  if db and db ~= vim.NIL and db ~= "" then
    table.insert(args, "--database")
    table.insert(args, db)
  end

  exec.run_json_items_job(args, {
    title = const.PLUGIN_TITLE,
    failure_message = "Failed to parse DDL response",
    empty_message = "No DDL found for table '" .. cword .. "'",
    stderr_prefix = "DDL stderr: ",
    exit_kind = "DDL introspection",
    on_items = function(items)
      ui.show_ddl(items, cword, show_float)
    end,
  })
end

return M
