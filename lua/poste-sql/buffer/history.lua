--- Dataset request history sidebar — JetBrains-style list of executed
--- requests. One entry per request (one result set, possibly multi-tab);
--- moving across items switches the rendered dataset.
---
--- Implemented as a floating window anchored to the left edge of the
--- dataset window (v1). Keymaps inside the sidebar:
---   j/k        move selection
---   <CR>       switch to the selected request
---   d          delete the selected request
---   q / <Esc>  close the sidebar

local D = require("poste-sql.dataset")

local M = {}

local SIDEBAR_WIDTH = 40
local LABEL_COL_WIDTH = 18

local buf = nil
local win = nil
local hl_ns = vim.api.nvim_create_namespace("poste_sql_history")

--- Display width (CJK/emoji-aware) — `vim.fn.strdisplaywidth`.
local function display_width(s)
  return vim.fn.strdisplaywidth(s or "")
end

--- Truncate a string to `max_width` display cells, reserving one cell for
--- the trailing ellipsis. Never splits a UTF-8 character.
local function truncate_display(s, max_width)
  if display_width(s) <= max_width then return s end
  local out, w = {}, 0
  for _, ch in ipairs(vim.fn.split(s, "\\zs")) do
    local cw = display_width(ch)
    if w + cw > max_width - 1 then break end
    w = w + cw
    out[#out + 1] = ch
  end
  return table.concat(out) .. "…"
end

--- Right-pad a string to `width` display cells (keeps the time column
--- aligned even when labels contain multi-byte characters).
local function pad_display(s, width)
  return s .. string.rep(" ", math.max(0, width - display_width(s)))
end

--- Build the sidebar lines: `[i] label  time`, active marked with ▸,
--- errors prefixed with ✗. The time column shows the wall-clock moment the
--- request executed (时:分:秒.毫秒); label is truncated/padded by display
--- width so the time column stays right-aligned.
local function build_lines()
  local lines = {}
  for i, entry in ipairs(D.history) do
    local label = truncate_display(entry.label or "?", LABEL_COL_WIDTH)
    local marker = entry.error and "✗" or (i == D.active_history and "▸" or " ")
    local time = D.format_wallclock(entry.ts_sec, entry.ts_nsec)
    lines[#lines + 1] = string.format("%s[%d] %s %s", marker, i, pad_display(label, LABEL_COL_WIDTH), time)
  end
  if #lines == 0 then
    lines[1] = "  (no history)"
  end
  return lines
end

--- Re-render the sidebar content and highlights (safe no-op when closed).
function M.refresh()
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local lines = build_lines()
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  if D.active_history >= 1 and D.active_history <= #lines then
    vim.api.nvim_buf_add_highlight(buf, hl_ns, "PosteDbDatasetSearchCurrent",
      D.active_history - 1, 0, -1)
  end
  for i, entry in ipairs(D.history) do
    if entry.error then
      vim.api.nvim_buf_add_highlight(buf, hl_ns, "DiagnosticError", i - 1, 0, 1)
    end
  end
end

local function set_cursor_line(lnum)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local n = D.history_count()
  if n == 0 then return end
  vim.api.nvim_win_set_cursor(win, { math.max(1, math.min(lnum, n)), 0 })
end

local function move(rel)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local cur = vim.api.nvim_win_get_cursor(win)[1]
  set_cursor_line(cur + rel)
end

local function activate()
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  require("poste-sql.buffer").switch_history_entry(lnum)
  M.refresh()
end

local function delete_current()
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  require("poste-sql.buffer").delete_history_entry(lnum)
  M.refresh()
  set_cursor_line(math.min(lnum, D.history_count()))
end

--- Open the sidebar (re-focus if already open).
function M.open()
  local dataset_win = D.dataset_window
  if not dataset_win or not vim.api.nvim_win_is_valid(dataset_win) then return end
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    return
  end

  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "poste_history", { buf = buf })

  local height = math.max(1, vim.api.nvim_win_get_height(dataset_win) - 2)
  win = vim.api.nvim_open_win(buf, true, {
    relative = "win",
    win = dataset_win,
    row = 0,
    col = 0,
    width = SIDEBAR_WIDTH,
    height = height,
    style = "minimal",
    border = "rounded",
  })
  -- Highlight the line under the cursor while navigating (j/k); the active
  -- request keeps its own background marker via extmark in refresh().
  vim.wo[win].cursorline = true

  local km = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("n", "j", function() move(1) end, km)
  vim.keymap.set("n", "k", function() move(-1) end, km)
  vim.keymap.set("n", "<CR>", activate, km)
  vim.keymap.set("n", "d", delete_current, km)
  vim.keymap.set("n", "q", M.close, km)
  vim.keymap.set("n", "<Esc>", M.close, km)

  M.refresh()
  set_cursor_line(D.active_history)
end

function M.toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    M.close()
  else
    M.open()
  end
end

function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  win = nil
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  buf = nil
end

function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

--- Sidebar buffer handle (for tests).
function M.buf()
  return buf
end

--- Sidebar window handle (for tests).
function M.win()
  return win
end

return M
