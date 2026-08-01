local ui = require("poste-sql.buffer_nav_ui")
local float_window = require("poste-sql.float_window")

local M = {}

function M.build_preview_lines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

function M.open_preview_float(title, text, ft)
  local lines = M.build_preview_lines(text)
  local opts = ui.build_preview_float_opts(title)
  opts.filetype = ft
  local float_buf, win = float_window.open_centered(lines, opts)

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].scrolloff = 1
  vim.wo[win].cursorline = true

  return float_buf, win
end

function M.set_preview_keymaps(buf, close_fn)
  local sopts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("n", "j", "<C-e>", sopts)
  vim.keymap.set("n", "k", "<C-y>", sopts)
  vim.keymap.set("n", "d", "<C-d>", sopts)
  vim.keymap.set("n", "u", "<C-u>", sopts)
  vim.keymap.set("n", "g", "gg", sopts)
  vim.keymap.set("n", "G", "G", sopts)
  vim.keymap.set("n", "<Space>", "<C-f>", sopts)
  vim.keymap.set("n", "<BS>", "<C-b>", sopts)
  vim.keymap.set("n", "q", close_fn, sopts)
  vim.keymap.set("n", "<Esc>", close_fn, sopts)
end

return M
