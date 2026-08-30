local ts_stmt = require("poste-db.ts_stmt")
local state = require("poste.state")

local M = {}
local _setup_done = false

local _debounce_timer = nil
local _disabled = false

local ns = vim.api.nvim_create_namespace("poste_db_boundary")

function M.setup()
  if _setup_done then return end
  _setup_done = true
  -- full-width rectangle background for the statement under the cursor
  -- (hl_eol extmarks, poste_ai/poste_http style) — replaces the old
  -- sign-column border tree and frees the sign column for the execution
  -- status indicator
  vim.api.nvim_set_hl(0, "PosteDbSqlBoundary", { bg = 0x24301f })
  state.apply_highlight_overrides({ "PosteDbSqlBoundary" })
end

local function clear_all(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

local function apply_range(buf, start, stop)
  clear_all(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  -- Don't show boundary for single-line statements
  if start == stop then return end

  for line = start, stop do
    vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
      end_row = line + 1,
      end_col = 0,
      hl_group = "PosteDbSqlBoundary",
      hl_eol = true,
      hl_mode = "combine",
    })
  end
end

local function fetch_and_highlight(buf, cursor_line)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local span = ts_stmt.find_stmt_span(buf, cursor_line)
  if not span then return end

  local s, e = span[1], span[2]

  if s == e then
    local line_text = vim.api.nvim_buf_get_lines(buf, s - 1, s, false)[1] or ""
    if line_text:match("^%s*$") then
      clear_all(buf)
      return
    end
  end

  local lines = vim.api.nvim_buf_get_lines(buf, s - 1, e, false)
  local has_content = false
  for _, line in ipairs(lines) do
    local trimmed = (line or ""):match("^%s*(.*)$")
    if trimmed ~= "" and not trimmed:match("^%-%-") then
      has_content = true
      break
    end
  end
  if not has_content then
    clear_all(buf)
    return
  end
  apply_range(buf, s - 1, e - 1)
end

function M.update(buf, cursor_line)
  if _disabled then return end
  if _debounce_timer then
    _debounce_timer:stop()
    _debounce_timer:close()
    _debounce_timer = nil
  end

  _debounce_timer = vim.defer_fn(function()
    _debounce_timer = nil
    fetch_and_highlight(buf, cursor_line)
  end, 50)
end

function M.clear(buf)
  if _debounce_timer then
    _debounce_timer:stop()
    _debounce_timer:close()
    _debounce_timer = nil
  end
  clear_all(buf)
end

function M.toggle()
  _disabled = not _disabled
  if _disabled then
    M.clear(vim.api.nvim_get_current_buf())
    vim.notify("SQL boundary highlight: OFF", vim.log.levels.INFO, { title = "PosteDb" })
  else
    M.update(vim.api.nvim_get_current_buf(), vim.fn.line("."))
    vim.notify("SQL boundary highlight: ON", vim.log.levels.INFO, { title = "PosteDb" })
  end
end

vim.api.nvim_create_user_command("PosteDbBoundary", function()
  require("poste-db.statement_indicator").toggle()
end, { desc = "Toggle SQL statement boundary highlight" })

M._test = { get_ns = function() return ns end }

return M
