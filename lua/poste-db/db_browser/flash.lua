--- Non-blocking flash for DB Browser.
---
--- vim.notify() writes to the message area, which parks a "Press ENTER" prompt
--- before the next command. DB Browser's routine feedback doesn't deserve to
--- block, so it goes to a short-lived float anchored above the statusline
--- instead. Only this module may set the flash window; callers go through
--- `notify.info(msg)` / `notify.warn(msg)`, which route here with a level.

local float_window = require("poste-db.float_window")
local width = require("poste-db.width")

local M = {}

local DUR_INFO_MS = 3000
local DUR_WARN_MS = 4000

local win = nil
local timer = nil

require("poste-db.db_browser.theme").register({
  PosteDbFlashInfo = { fg = "#9ece6a", bold = true },
  PosteDbFlashWarn = { fg = "#e0af68", bold = true },
})

local function close()
  if timer then
    timer:stop()
    timer = nil
  end
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  win = nil
end

--- Collapse to one line, then truncate to fit the editor width. Both the
--- fit check and the cut are in DISPLAY cells: a CJK message's byte length
--- is up to 3x its width, so a byte-based check overflowed the editor and
--- a byte-based cut split glyphs.
local function one_line(msg)
  local text = (msg or ""):gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local max = vim.o.columns - 6
  if max < 8 then return text end
  return width.truncate(text, max) .. (width.display_width(text) > max and "…" or "")
end

--- Show a non-blocking flash message, replacing any flash still on screen.
---@param msg string
---@param level integer|nil 2 (info, vim.log.levels.INFO) or 3 (warn); info by default
function M.flash(msg, level)
  close()
  local text = one_line(msg)
  if text == "" then return end

  -- Anchor just above the statusline (or the last window row when absent), so
  -- it never covers the command line and never steals focus.
  local text_w = width.display_width(text)
  local width_cells = math.min(text_w + 4, vim.o.columns)
  local row = math.max(0, vim.o.lines - vim.o.cmdheight - 2)
  local is_warn = (level or 0) == 3
  local buf, opened = float_window.open({
    lines = { text },
    relative = "editor",
    width = width_cells,
    height = 1,
    row = row,
    col = math.max(0, math.floor((vim.o.columns - width_cells) / 2)),
    border = false,
    zindex = 50,
    enter = false,
    winhl = "Normal:" .. (is_warn and "PosteDbFlashWarn" or "PosteDbFlashInfo"),
  })
  if not opened then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return
  end
  win = opened

  timer = vim.defer_fn(close, is_warn and DUR_WARN_MS or DUR_INFO_MS)
end

return M