local util = require("poste.util")
local detect = require("poste-sql.nav_detect")

local M = {}

local function handle_connection_directive(buf, conn_name)
  local connections = require("poste-sql.connections")
  local search_dir = vim.api.nvim_buf_get_name(buf)
  if search_dir ~= "" then
    search_dir = vim.fn.fnamemodify(search_dir, ":h")
  else
    search_dir = vim.fn.getcwd()
  end
  local config_path = connections.find_connections_toml(search_dir)
  if not config_path then
    vim.notify("connections.toml not found", vim.log.levels.WARN)
    return true
  end
  local config_lines = vim.fn.readfile(config_path)
  if not config_lines then
    vim.notify("Cannot read connections.toml", vim.log.levels.WARN)
    return true
  end
  local target_line = nil
  local pattern = '^%[' .. vim.pesc(conn_name) .. '%]'
  for i, l in ipairs(config_lines) do
    if l:match(pattern) then
      target_line = i
      break
    end
  end
  if not target_line then
    vim.notify("Connection '" .. conn_name .. "' not found in connections.toml", vim.log.levels.WARN)
    return true
  end
  vim.cmd("normal! m'")
  vim.cmd("edit " .. vim.fn.fnameescape(config_path))
  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  return true
end

local function handle_database_directive(buf, line_num, db_name)
  local ctx = require("poste-sql.context")
  local full_ctx = ctx.resolve_full_context(buf, line_num)
  if not full_ctx.connection then
    vim.notify("No connection context for database '" .. db_name .. "'. Add -- @connection <name> to the file.", vim.log.levels.WARN)
    return true
  end
  vim.cmd("normal! m'")
  require("poste-sql.db_browser").navigate_to(full_ctx.connection, db_name)
  return true
end

local function handle_table_reference(buf, line_num, line_text, cursor, full_ctx, table_name)
  local data = require("poste-sql.completion_data")
  local bin = data.find_binary()
  local column_name = nil

  if bin then
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local nav_line_text = all_lines[line_num] or ""
    local col = cursor[2]
    local line_len = #nav_line_text

    local end_col = col
    while end_col < line_len do
      local ch = line_text:sub(end_col + 1, end_col + 1)
      if ch:match("[%w_]") then end_col = end_col + 1 else break end
    end

    local block = detect.extract_sql_block(all_lines, line_num, line_text, end_col)
    if block then
      local conn_config = require("poste-sql.connections").get_connection_config(full_ctx.connection)
      local cmd = detect.build_context_detect_command(bin, block.offset, conn_config and conn_config.dialect or nil)
      local output = vim.fn.system(cmd, block.sql_text)
      if vim.v.shell_error == 0 then
        local ok, parsed = pcall(vim.json.decode, output)
        if ok and parsed then
          util.clean_nil(parsed)
          local target = detect.resolve_detected_table_target(parsed, line_text, end_col, table_name, full_ctx)
          if target then
            if target.action == "navigate_to" then
              vim.cmd("normal! m'")
              require("poste-sql.db_browser").navigate_to(
                target.connection or full_ctx.connection,
                target.database or full_ctx.database or table_name
              )
              return true
            end
            table_name = target.table_name or table_name
            column_name = target.column_name
            if target.database then
              full_ctx.database = target.database
            end
          end
        end
      end
    end
  end

  vim.cmd("normal! m'")
  require("poste-sql.db_browser").navigate_to_table(full_ctx.connection, full_ctx.database, table_name, column_name)
  return true
end

function M.goto_definition()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1] or ""
  local conn_match = line_text:match("^%s*--%s*@connection%s+(.+)")
  if conn_match then
    handle_connection_directive(buf, vim.trim(conn_match))
    return
  end
  local db_match = line_text:match("^%s*--%s*@database%s+(.+)")
  if db_match then
    handle_database_directive(buf, line_num, vim.trim(db_match))
    return
  end
  local table_name = vim.fn.expand("<cword>")
  if table_name and table_name ~= "" then
    local ctx = require("poste-sql.context")
    local full_ctx = ctx.resolve_full_context(buf, line_num)
    if full_ctx.connection then
      handle_table_reference(buf, line_num, line_text, cursor, full_ctx, table_name)
      return
    end
  end
  vim.notify("No connection context. Add -- @connection <name> to the file header.", vim.log.levels.WARN)
end

M._test = {
  resolve_detected_table_target = detect.resolve_detected_table_target,
}

return M
