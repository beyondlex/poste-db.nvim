local detect = require("poste-sql.nav_detect")
local handlers = require("poste-sql.nav_handlers")
local route = require("poste-sql.nav_route")

local M = {}

function M.goto_definition()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1] or ""
  local target = route.resolve_definition_route(buf, line_num, line_text, cursor)
  if not target then
    vim.notify("No connection context. Add -- @connection <name> to the file header.", vim.log.levels.WARN)
    return
  end

  if target.kind == "connection" then
    handlers.handle_connection_directive(buf, target.conn_name)
    return
  end
  if target.kind == "database" then
    handlers.handle_database_directive(buf, line_num, target.db_name)
    return
  end
  if target.kind == "table" then
    local ctx = require("poste-sql.context")
    local full_ctx = ctx.resolve_full_context(buf, line_num)
    handlers.handle_table_reference(buf, line_num, line_text, cursor, full_ctx, target.table_name)
  end
end

M._test = {
  resolve_detected_table_target = detect.resolve_detected_table_target,
}

return M
