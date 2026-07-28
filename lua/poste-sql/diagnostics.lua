--- Tree-sitter-based SQL syntax diagnostics.
--- Maps Tree-sitter ERROR nodes to vim.diagnostic entries.
--- On TextChanged/TextChangedI (debounced) and BufWritePost.

local ts_stmt = require("poste-sql.ts_stmt")

local M = {}

local _timer = nil
local DEBOUNCE_MS = 300
local ns = vim.api.nvim_create_namespace("poste_sql_diagnostics")

--- Update diagnostics for a buffer using Tree-sitter ERROR nodes.
--- @param buf number  buffer handle
function M.update_diagnostics(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local ft = vim.bo[buf].filetype
  if ft ~= "poste_sql" and ft ~= "poste_sqlite" and ft ~= "sql" then return end

  local errors = ts_stmt.find_error_nodes(buf)
  local diags = {}
  for _, err in ipairs(errors) do
    diags[#diags + 1] = {
      lnum = err.lnum - 1,
      col = err.col - 1,
      end_lnum = err.end_lnum - 1,
      end_col = err.end_col - 1,
      severity = vim.diagnostic.severity.ERROR,
      source = "poste-sql",
      message = err.text,
    }
  end
  vim.diagnostic.set(ns, buf, diags)
end

--- Debounced update.
--- @param buf number
function M.debounced_update(buf)
  if _timer then
    _timer:stop()
    _timer:close()
  end
  _timer = vim.defer_fn(function()
    _timer = nil
    if not vim.api.nvim_buf_is_valid(buf) then return end
    M.update_diagnostics(buf)
  end, DEBOUNCE_MS)
end

--- Clear diagnostics for a buffer.
--- @param buf number
function M.clear_diagnostics(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.diagnostic.reset(ns, buf)
  end
end

function M.setup(buf)
  buf = buf or 0
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end

  local group = vim.api.nvim_create_augroup("PosteSQLDiagnostics_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      M.debounced_update(buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = buf,
    callback = function()
      M.debounced_update(buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    buffer = buf,
    callback = function()
      M.clear_diagnostics(buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    buffer = buf,
    callback = function()
      M.debounced_update(buf)
    end,
  })

  M.update_diagnostics(buf)
end

return M