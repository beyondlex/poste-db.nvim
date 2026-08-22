local ts_stmt = require("poste-db.ts_stmt")
local state = require("poste.state")

local M = {}
local _setup_done = false

local _debounce_timer = nil
local _disabled = false

local C = require("poste.constants")
local sign_group = C.SIGN_GROUP_NAME .. "_boundary"

local BOUNDARY_SIGNS = {
  PosteDbBoundaryTop = "┌",
  PosteDbBoundaryMid = "│",
  PosteDbBoundaryBot = "└",
}

function M.setup()
  if _setup_done then return end
  _setup_done = true
  vim.api.nvim_set_hl(0, "PosteDbSqlBoundaryBorder", { link = "Comment" })
  state.apply_highlight_overrides({ "PosteDbSqlBoundaryBorder" })
  for name, text in pairs(BOUNDARY_SIGNS) do
    pcall(vim.fn.sign_define, name, { text = text, texthl = "PosteDbSqlBoundaryBorder" })
  end
end

local bound_sign_ids = {}  -- buf -> { line_0 -> sign_id }

local function clear_all(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    if bound_sign_ids[buf] then
      for _, sign_id in pairs(bound_sign_ids[buf]) do
        pcall(vim.fn.sign_unplace, sign_group, { id = sign_id })
      end
      bound_sign_ids[buf] = nil
    end
  end
end

local function apply_range(buf, start, stop)
  clear_all(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  -- Don't show boundary for single-line statements
  if start == stop then return end

  local ids = {}
  for line = start, stop do
    local sign_name
    if line == start then
      sign_name = "PosteDbBoundaryTop"
    elseif line == stop then
      sign_name = "PosteDbBoundaryBot"
    else
      sign_name = "PosteDbBoundaryMid"
    end
    local sign_id = vim.fn.sign_place(0, sign_group, sign_name, buf, { lnum = line + 1 })
    if sign_id and sign_id > 0 then
      ids[line] = sign_id
    end
  end
  bound_sign_ids[buf] = ids
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

return M