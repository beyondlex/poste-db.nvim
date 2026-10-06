--- Go-to-definition --- route categorizer: connection, database, or table word.
local const = require("poste-db.constants")

local M = {}

--- Categorize the go-to-definition target from the cursor line alone. The
--- table branch reads the word with <cword>, so this must run with the SQL
--- buffer as the current window — which goto-definition always does.
function M.resolve_definition_route(line_text)
  local conn_match = const.match_directive(line_text, const.DIRECTIVE_CONNECTION)
  if conn_match then
    return { kind = "connection", conn_name = vim.trim(conn_match) }
  end

  local db_match = const.match_directive(line_text, const.DIRECTIVE_DATABASE)
  if db_match then
    return { kind = "database", db_name = vim.trim(db_match) }
  end

  local table_name = vim.fn.expand("<cword>")
  if table_name and table_name ~= "" then
    return {
      kind = "table",
      table_name = table_name,
    }
  end

  return nil
end

return M
