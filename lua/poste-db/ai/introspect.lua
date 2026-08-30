--- Shared introspect wrapper for the AI module — runs one db_browser
--- introspection query; cb(items_table_or_nil). Items are
--- { name, type, comment } for tables and { name, type, comment, ... } for
--- columns (see db_browser/tree.lua node factories).
local M = {}

function M.run(conn, kind, table_name, db, cb)
  local async = require("poste-db.db_browser.async")
  async.run_introspect(conn, kind, nil, table_name, db, function(parsed)
    if type(parsed) == "table" and type(parsed.items) == "table" then
      cb(parsed.items)
    else
      cb(nil)
    end
  end, vim.fn.getcwd())
end

return M
