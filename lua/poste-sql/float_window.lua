local M = {}

function M.centered_dimensions(lines, opts)
  opts = opts or {}
  local width_ratio = opts.width_ratio or 0.7
  local max_width = opts.max_width or 120
  local width_padding = opts.width_padding or 2
  local height_ratio = opts.height_ratio or 0.6
  local min_height = opts.min_height or 3
  local extra_height = opts.extra_height or 1

  local width = 0
  for _, line in ipairs(lines or {}) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width + width_padding, math.min(math.floor(vim.o.columns * width_ratio), max_width))

  local height = math.floor(vim.o.lines * height_ratio)
  height = math.max(min_height, math.min((lines and #lines or 0) + extra_height, height))

  return {
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  }
end

function M.open_centered(lines, opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
  if opts.filetype then
    vim.bo[buf].filetype = opts.filetype
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local dims = M.centered_dimensions(lines, opts)
  local win_opts = {
    relative = "editor",
    width = dims.width,
    height = dims.height,
    row = dims.row,
    col = dims.col,
    style = "minimal",
    border = opts.border or "rounded",
    title = opts.title,
    title_pos = opts.title_pos or "left",
  }
  if opts.win_opts then
    win_opts = vim.tbl_extend("force", win_opts, opts.win_opts)
  end

  local ok, win = pcall(vim.api.nvim_open_win, buf, true, win_opts)
  if not ok then
    win_opts.title = nil
    win_opts.title_pos = nil
    win = vim.api.nvim_open_win(buf, true, win_opts)
  end

  if opts.winhl then
    vim.api.nvim_set_option_value("winhl", opts.winhl, { win = win })
  end
  if opts.win_opts_apply then
    opts.win_opts_apply(buf, win)
  end

  return buf, win
end

return M
