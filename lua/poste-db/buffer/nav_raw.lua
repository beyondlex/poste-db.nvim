--- Dataset raw mode — show raw table data in a floating window.
local C = require("poste-db.constants")
local float_window = require("poste-db.float_window")

local M = {}

local RAW_MAX_ROWS = 500

local raw_win = nil

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
  local lines = fmt.render_page(layout, 1, page_size)

  local omitted = total_rows - page_size
  if omitted > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("  %d more row(s) omitted (showing first %d of %d)", omitted, page_size, total_rows)
  end

  -- The buffer carries the table; the float is a viewport over it, so size it
  -- off the editor and let buffer navigation handle scrolling (nowrap for
  -- horizontal, native j/k or <C-e>/<C-y> for vertical).
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.min(#lines + 2, vim.o.lines - 8)
  height = math.max(height, 3)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local _, win = float_window.open({
    lines = lines,
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    zindex = 50,
    title = string.format(" Raw Mode — %s ", layout.table_name or ""),
    buf_options = { buftype = "nofile", swapfile = false },
    win_options = {
      wrap = false,
      cursorline = true,
      number = false,
      relativenumber = false,
      cursorcolumn = false,
      signcolumn = "no",
      foldcolumn = "0",
      sidescrolloff = 0,
    },
    close_keys = { "q", "<Esc>" },
    close_modes = { "n", "v" },
  })
  if win then raw_win = win end
end

--- Show the raw float, or close it when already open (q-closed floats leave a
--- stale id behind; the validity check makes that a no-op).
function M.toggle()
  if raw_win and vim.api.nvim_win_is_valid(raw_win) then
    vim.api.nvim_win_close(raw_win, true)
    raw_win = nil
    return
  end
  raw_win = nil
  M.show()
end

return M