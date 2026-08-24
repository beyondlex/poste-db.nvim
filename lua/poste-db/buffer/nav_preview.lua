--- Dataset cell preview --- floating window for cell value inspection.
local M = {}
local const = require("poste-db.constants")

function M.build_preview_lines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

--- Size a preview float for `lines`. Width tracks content (capped), height
--- accounts for soft-wrapped rows, both scaled against the whole editor.
--- Wrapping also applies to pre-wrapped lines (long single-line cells).
---
--- @param lines string[]         Preview content (unsplit lines)
--- @param opts? table            width_ratio/max_width/height_ratio/padding, defaults from constants
--- @return number width, number height
function M.compute_preview_size(lines, opts)
  opts = opts or {}
  local width_ratio = opts.width_ratio or const.FLOAT_WIDTH_RATIO
  local max_width = opts.max_width or const.FLOAT_MAX_WIDTH
  local height_ratio = opts.height_ratio or const.FLOAT_HEIGHT_RATIO
  local width_padding = opts.width_padding or 2

  local width = 0
  for _, line in ipairs(lines or {}) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  if opts.title then
    width = math.max(width, vim.fn.strdisplaywidth(opts.title))
  end
  local max_w = math.min(math.floor((vim.o.columns or 80) * width_ratio), max_width)
  width = math.min(width + width_padding, max_w)

  local inner = math.max(1, width - 2)
  local height = 0
  for _, line in ipairs(lines or {}) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / inner))
  end
  local max_h = math.floor((vim.o.lines or 24) * height_ratio)
  height = math.max(1, math.min(height, max_h))

  return width, height
end

--- Open a cursor-anchored float sized against the editor, not the dataset
--- window. `vim.lsp.util.open_floating_preview` clamps the float to the
--- current window's width and wraps at it, so a long cell squeezed into the
--- narrow split produced a ~2-row tall popup that needed constant scrolling.
function M.open_preview_float(title, text, ft)
  local lines = M.build_preview_lines(text)
  local width, height = M.compute_preview_size(lines, { title = title })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("syntax", ft, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  -- Anchor below the cursor when there is room; otherwise grow upward.
  local winline = math.max(vim.fn.winline(), 1)
  local lines_below = math.max(vim.fn.winheight(0) - winline, 0)
  local row
  if height <= lines_below then
    row = 1
  else
    height = math.max(math.min(height, winline - 2), 1)
    row = -height
  end

  -- Keep the float inside the editor when the cursor sits near the right edge.
  local col = 0
  if vim.fn.wincol() + width > vim.o.columns then
    col = math.max(vim.o.columns - width - vim.fn.wincol(), -vim.fn.wincol())
  end

  local win_opts = {
    relative = "cursor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "left",
  }
  local ok, win = pcall(vim.api.nvim_open_win, buf, true, win_opts)
  if not ok then
    win_opts.title = nil
    win_opts.title_pos = nil
    win = vim.api.nvim_open_win(buf, true, win_opts)
  end

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].smoothscroll = true
  vim.wo[win].scrolloff = 1
  vim.wo[win].cursorline = true

  return buf, win
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
