--- Non-blocking flash for DB Browser.
---
--- vim.notify() writes to the message area, which parks a "Press ENTER" prompt
--- before the next command. DB Browser's routine feedback doesn't deserve to
--- block, so it goes to a short-lived float anchored above the statusline
--- instead. Only this module may set the flash window; callers just fire
--- `flash.info(msg)` / `flash.warn(msg)`.

local M = {}

local float_window = require("poste-db.float_window")

local DUR_INFO_MS = 3000
local DUR_WARN_MS = 4000

local win = nil
local timer = nil

local function setup_hl()
  vim.api.nvim_set_hl(0, "PosteDbFlashInfo", { fg = "#9ece6a", bold = true })
  vim.api.nvim_set_hl(0, "PosteDbFlashWarn", { fg = "#e0af68", bold = true })
end
setup_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = setup_hl })

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

--- Truncate to fit the editor width (multi-line messages become one line).
local function one_line(msg)
  local text = (msg or ""):gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local max = vim.o.columns - 6
  if max < 8 or #text <= max then return text end
  return text:sub(1, max - 1) .. "…"
end

--- Show a non-blocking flash message, replacing any flash still on screen.
---@param msg string
---@param level integer|nil 0 (info) or 3 (warn); MAPS.level in effect by default
function M.flash(msg, level)
  close()
  local text = one_line(msg)
  if text == "" then return end

  -- Anchor just above the statusline (or the last window row when absent), so
  -- it never covers the command line and never steals focus.
  local width = math.min(#text + 4, vim.o.columns)
  local row = math.max(0, vim.o.lines - vim.o.cmdheight - 2)
  local is_warn = (level or 0) == 3
  local buf, opened = float_window.open({
    lines = { text },
    relative = "editor",
    width = width,
    height = 1,
    row = row,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
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