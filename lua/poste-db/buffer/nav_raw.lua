--- Dataset raw mode --- toggle between table and raw data views.
local D = require("poste-db.dataset")
local C = require("poste-db.constants")
local state = require("poste.state")

local M = {}

local raw_buffer = nil
local saved_hide_header_float = false

function M.is_active()
  return state.sql._raw_mode
end

function M.build_raw_lines(tab)
  local fmt = require("poste-db.format")
  return fmt.render_page(tab.layout, 1, #tab.layout.rows)
end

function M.enter(tab, win)
  if not tab or not tab.layout or not win then return nil end

  saved_hide_header_float = state.sql._hide_header_float
  state.sql._hide_header_float = true
  require("poste-db.buffer.header").close()

  local lines = M.build_raw_lines(tab)
  raw_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = raw_buffer })
  vim.api.nvim_set_option_value("swapfile", false, { buf = raw_buffer })
  vim.api.nvim_set_option_value("modifiable", true, { buf = raw_buffer })
  vim.api.nvim_buf_set_lines(raw_buffer, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = raw_buffer })
  local rk = state.get_keymap("sql_dataset", "toggle_raw_mode", "<leader>gp")
  if rk then
    vim.keymap.set("n", rk, function() require("poste-db.buffer.nav").toggle_raw_mode() end,
      { buffer = raw_buffer, noremap = true, silent = true })
  end
  state.sql._raw_mode = true

  vim.api.nvim_win_set_buf(win, raw_buffer)
  pcall(vim.api.nvim_set_option_value, "winbar", C.RAW_MODE_WINBAR, { win = win })
  pcall(vim.api.nvim_buf_set_name, raw_buffer, "poste://raw-mode")

  return raw_buffer
end

function M.exit()
  if not state.sql._raw_mode then return end

  local buf = D.dataset_buffer and vim.api.nvim_buf_is_valid(D.dataset_buffer) and D.dataset_buffer
  local win = D.dataset_window and vim.api.nvim_win_is_valid(D.dataset_window) and D.dataset_window
  if win and buf then
    pcall(vim.api.nvim_win_set_buf, win, buf)
  end
  if raw_buffer and vim.api.nvim_buf_is_valid(raw_buffer) then
    pcall(vim.api.nvim_buf_delete, raw_buffer, { force = true })
  end
  raw_buffer = nil
  state.sql._raw_mode = false
  state.sql._hide_header_float = saved_hide_header_float
end

function M.toggle()
  if M.is_active() then
    M.exit()
    require("poste-db.buffer.page").refresh_page()
    return
  end

  local nav_state = require("poste-db.buffer.nav_state")
  local tab = nav_state.get_tab()
  local win = nav_state.get_dataset_window()

  if not tab or not nav_state.has_layout(tab) then
    vim.notify("No dataset to display in raw mode", vim.log.levels.WARN, { title = C.TITLE })
    return
  end
  if not win then
    vim.notify("No dataset window", vim.log.levels.WARN, { title = C.TITLE })
    return
  end

  local raw_buffer = M.enter(tab, win)
  if not raw_buffer then return end

  vim.notify("Raw mode: ON (browse table)", vim.log.levels.INFO, { title = C.TITLE })
end

return M
