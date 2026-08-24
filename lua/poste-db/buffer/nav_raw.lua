--- Dataset raw mode — show raw table data in a floating window.
local C = require("poste-db.constants")

local M = {}

local RAW_MAX_ROWS = 500
local MIN_FLOAT_WIDTH = 40

function M.show()
  local nav_state = require("poste-db.buffer.nav_state")
  local tab = nav_state.get_tab()
  if not tab or not nav_state.has_layout(tab) then
    vim.notify("No dataset to display in raw mode", vim.log.levels.WARN, { title = C.TITLE })
    return
  end

  local fmt = require("poste-db.format")
  local layout = tab.layout
  local total_rows = layout.total_rows or #layout.rows
  local page_size = math.min(RAW_MAX_ROWS, #layout.rows)
  local lines, meta = fmt.render_page(layout, 1, page_size)

  local omitted = total_rows - page_size
  if omitted > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("  %d more row(s) omitted (showing first %d of %d)", omitted, page_size, total_rows)
  end

  local table_width = 0
  for _, line in ipairs(lines) do
    local dw = vim.fn.strdisplaywidth(line)
    if dw > table_width then table_width = dw end
  end

  local editor_width = vim.o.columns
  local width = math.min(math.max(table_width + 4, MIN_FLOAT_WIDTH), editor_width - 4)
  local height = math.min(#lines + 2, vim.o.lines - 6)
  height = math.max(height, 3)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 50,
  }

  local title = string.format(" Raw Mode — %s ", layout.table_name or "")
  local ok, float_win = pcall(vim.api.nvim_open_win, buf, true, vim.tbl_extend("keep", { title = title, title_pos = "left" }, win_opts))
  if not ok then
    float_win = vim.api.nvim_open_win(buf, true, win_opts)
  end

  vim.wo[float_win].wrap = false
  vim.wo[float_win].cursorline = true
  vim.wo[float_win].number = false
  vim.wo[float_win].relativenumber = false
  vim.wo[float_win].cursorcolumn = false
  vim.wo[float_win].signcolumn = "no"
  vim.wo[float_win].foldcolumn = "0"
  vim.wo[float_win].sidescrolloff = 0

  local function close()
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
  end

  local sopts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("n", "q", close, sopts)
  vim.keymap.set("n", "<Esc>", close, sopts)
  vim.keymap.set("n", "j", "<C-e>", sopts)
  vim.keymap.set("n", "k", "<C-y>", sopts)
  vim.keymap.set("n", "d", "<C-d>", sopts)
  vim.keymap.set("n", "u", "<C-u>", sopts)
  vim.keymap.set("n", "g", "gg", sopts)
  vim.keymap.set("n", "G", "G", sopts)
  vim.keymap.set("n", "<Space>", "<C-f>", sopts)
  vim.keymap.set("n", "<BS>", "<C-b>", sopts)

  vim.keymap.set("v", "q", close, sopts)
  vim.keymap.set("v", "<Esc>", close, sopts)
  vim.keymap.set("v", "j", "j", sopts)
  vim.keymap.set("v", "k", "k", sopts)
  vim.keymap.set("v", "h", "h", sopts)
  vim.keymap.set("v", "l", "l", sopts)
end

M.toggle = M.show

return M