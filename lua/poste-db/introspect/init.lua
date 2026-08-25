--- SQL introspection utilities — float window display, column info, and DDL.
---
--- Extracted from sql/init.lua to reduce module size.
--- Provides show_table_ddl() and supporting functions.
-- luacheck: ignore 411

local state = require("poste.state")
local util = require("poste.util")
local config = require("poste-db.config")
local helpers = require("poste-db.introspect.helpers")
local route = require("poste-db.introspect.route")
local detect = require("poste-db.introspect.detect")
local target_resolver = require("poste-db.introspect.target")
local context_resolver = require("poste-db.introspect.context")
local ui = require("poste-db.introspect.ui")
local column = require("poste-db.introspect.column")
local table_helper = require("poste-db.introspect.table")
local const = require("poste-db.constants")

local M = {}
local show_float_win = nil

---------------------------------------------------------------------------
-- Float window
---------------------------------------------------------------------------

--- Show or open a float window with text content.
--- @param lines string[]
--- @param title string
--- @param ft string|nil  filetype (default "sql")
function M.show_float(lines, title, ft)
  if not lines or #lines == 0 then
    vim.notify("No content to display", vim.log.levels.WARN, { title = const.PLUGIN_TITLE })
    return
  end
  local ok, float_buf, win = pcall(vim.lsp.util.open_floating_preview, lines, ft or "sql", {
    border = "rounded",
    title = title,
    title_pos = "left",
  })
  if not ok or not float_buf then
    return
  end

  show_float_win = win
  vim.api.nvim_set_current_win(win)

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
    show_float_win = nil
  end
  local ck = config.get_keymap("sql_introspect", "close", "q")
  if ck then vim.keymap.set("n", ck, close_fn, sopts) end
  ck = config.get_keymap("sql_introspect", "close_alt", "<Esc>")
  if ck then vim.keymap.set("n", ck, close_fn, sopts) end
end

-- Table DDL
---------------------------------------------------------------------------

--- Show DDL for the table under the cursor in a floating window.
function M.show_table_ddl()
  if show_float_win and vim.api.nvim_win_is_valid(show_float_win) then
    vim.api.nvim_set_current_win(show_float_win)
    return
  end

  local binary = state.find_poste_binary()
  if not binary then
    vim.notify("Poste binary not found.", vim.log.levels.ERROR, { title = const.PLUGIN_TITLE })
    return
  end

  -- Check if cursor is on a -- @database <name> line → list tables
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1] or ""
  local entry = route.resolve_table_ddl_entry(line_text)
  local directive_action = target_resolver.resolve_directive_action(entry)
  if directive_action and directive_action.kind == "database" then
    local db_name = directive_action.db_name
    local ctx = require("poste-db.context").resolve_full_context(buf, line_num)
    local conn = ctx.connection
    if not conn then
      vim.notify("No connection context for database '" .. db_name .. "'", vim.log.levels.WARN, { title = const.PLUGIN_TITLE })
      return
    end
    table_helper.show_database_info(conn, db_name, M.show_float)
    return
  end

  if directive_action and directive_action.kind == "connection" then
    local conn_name = directive_action.conn_name
    local config = require("poste-db.connections").get_connection_config(conn_name)
    if not config then
      vim.notify("Connection '" .. conn_name .. "' not found in connections.toml", vim.log.levels.WARN, { title = const.PLUGIN_TITLE })
      return
    end
    ui.show_connection(config, conn_name, M.show_float)
    return
  end

  local cword = vim.fn.expand("<cword>")
  if not cword or cword == "" then
    vim.notify("No word under cursor", vim.log.levels.WARN, { title = const.PLUGIN_TITLE })
    return
  end
  if route.is_sql_keyword(cword) then
    vim.notify("'" .. cword .. "' is a SQL keyword", vim.log.levels.INFO, { title = const.PLUGIN_TITLE })
    return
  end

  local sql_context = require("poste-db.context")
  local buf = vim.api.nvim_get_current_buf()
  local ctx = sql_context.resolve_full_context(buf)
  local conn = ctx.connection
  if not conn or conn == "" then
    vim.notify("No SQL connection context. Add -- @connection <name> to the file header.", vim.log.levels.ERROR, { title = const.PLUGIN_TITLE })
    return
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

  local function detect_target_at(slice_end_col, resolve_after_dot_col)
    local payload = detect.build_detect_payload(all_lines, line_num, slice_end_col)
    if not payload then
      return nil
    end

    local dial = ""
    local cc = require("poste-db.connections").get_connection_config(conn)
    if cc and cc.dialect then dial = " --dialect " .. cc.dialect end

    local ok_sys, result_obj = pcall(vim.system, { binary, "context", "detect", tostring(payload.offset) }, {
      stdin = payload.sql_text,
      timeout = 5000,
    })
    if not ok_sys then return nil end
    local result = result_obj:wait()
    if result.code ~= 0 or not result.stdout or result.stdout == "" then
      return nil
    end
    local out = result.stdout

    local ok, parsed = pcall(vim.json.decode, out)
    if not ok or not parsed then
      return nil
    end

    util.clean_nil(parsed)
    return context_resolver.resolve_detected_target(parsed, cword, db, resolve_after_dot_col)
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
    local detected_target = detect_target_at(end_col + 1 + #after_dot_col, after_dot_col)
    local action = target_resolver.resolve_detected_action(detected_target, db, cword)
    if action and action.kind == "column" and action.parent_table then
      column.show_column_info(conn, action.db or db, action.parent_table, action.column_name, action.parent_schema, M.show_float)
      return
    end
  end

  -- Check if cword is a column name (not a table) via context detection
  local detected_target = detect_target_at(end_col, nil)
  local action = target_resolver.resolve_detected_action(detected_target, db, cword)
  if action then
    if action.kind == "list_tables" and action.db then
      table_helper.show_database_tables(conn, action.db, M.show_float)
      return
    end
    if action.kind == "column" and action.parent_table then
      column.show_column_info(conn, action.db or db, action.parent_table, action.column_name, action.parent_schema, M.show_float)
      return
    end
    if action.kind == "ddl" and action.table_name then
      db = action.db or db
      cword = action.table_name
    end
  end

  -- Fallback: show DDL (table mode)
  table_helper.show_table_ddl(conn, db, cword, M.show_float)
end

return M
