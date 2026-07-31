local detect = require("poste-sql.nav_detect")
local handlers = require("poste-sql.nav_handlers")
local const = require("poste-sql.constants")

local M = {}

function M.goto_definition()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1] or ""
  local conn_match = const.match_directive(line_text, const.DIRECTIVE_CONNECTION)
  if conn_match then
    handlers.handle_connection_directive(buf, vim.trim(conn_match))
    return
  end
  local db_match = const.match_directive(line_text, const.DIRECTIVE_DATABASE)
  if db_match then
    handlers.handle_database_directive(buf, line_num, vim.trim(db_match))
    return
  end
  local table_name = vim.fn.expand("<cword>")
  if table_name and table_name ~= "" then
    local ctx = require("poste-sql.context")
    local full_ctx = ctx.resolve_full_context(buf, line_num)
    if full_ctx.connection then
      handlers.handle_table_reference(buf, line_num, line_text, cursor, full_ctx, table_name)
      return
    end
  end
  vim.notify("No connection context. Add -- @connection <name> to the file header.", vim.log.levels.WARN)
end

M._test = {
  resolve_detected_table_target = detect.resolve_detected_table_target,
}

return M
