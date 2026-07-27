--- SQL directive comment highlighter.
--- Only handles -- @connection / @database / @protocol highlighting.
--- SQL keyword/type/function highlighting is handled by Tree-sitter
--- via after/queries/poste_sql/highlights.scm.

local M = {}

-- Define highlight groups for directive comments.
-- These are still needed because Tree-sitter doesn't understand
-- poste-specific -- @connection semantics.
vim.api.nvim_set_hl(0, "sqlDirective", { fg = "#D19A66", bold = true })
vim.api.nvim_set_hl(0, "sqlDirectiveValue", { fg = "#E5C07B" })
vim.api.nvim_set_hl(0, "sqlDirectiveComment", { link = "Special" })

local DIRECTIVE_NS = vim.api.nvim_create_namespace("poste_sql_directive")
local DIRECTIVE_KEYWORDS = { "connection", "database", "protocol" }

--- Highlight -- @connection / @database / @protocol lines using extmarks.
--- Uses priority 101-102 (> Tree-sitter's default 100) to override
--- the comment highlighting from after/queries/poste_sql/highlights.scm.
function M.highlight_directive_comments(buf)
  buf = buf or 0
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  vim.api.nvim_buf_clear_namespace(buf, DIRECTIVE_NS, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    for _, dir in ipairs(DIRECTIVE_KEYWORDS) do
      local dstart, dend = line:find("^--%s*@" .. dir)
      if dstart then
        vim.api.nvim_buf_set_extmark(buf, DIRECTIVE_NS, i - 1, 0, {
          end_col = dend, hl_group = "sqlDirectiveComment", priority = 101,
        })
        vim.api.nvim_buf_set_extmark(buf, DIRECTIVE_NS, i - 1, dstart - 1, {
          end_col = dend, hl_group = "sqlDirective", priority = 102,
        })
        local vstart, vend = line:find("%S.*$", dend + 1)
        if vstart then
          vim.api.nvim_buf_set_extmark(buf, DIRECTIVE_NS, i - 1, vstart - 1, {
            end_col = vend, hl_group = "sqlDirectiveValue", priority = 102,
          })
        end
        break
      end
    end
  end
end

return M