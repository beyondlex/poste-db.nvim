--- SQL directive comment highlighter.
--- Only handles -- @connection / @database / @protocol highlighting.
--- SQL keyword/type/function highlighting is handled by Tree-sitter
--- via after/queries/poste_sql/highlights.scm.

local M = {}
local const = require("poste-sql.constants")

-- Define highlight groups for directive comments.
-- These are still needed because Tree-sitter doesn't understand
-- poste-specific -- @connection semantics.
vim.api.nvim_set_hl(0, "PosteDbSqlDirective", { fg = "#D19A66", bold = true })
vim.api.nvim_set_hl(0, "PosteDbSqlDirectiveValue", { fg = "#E5C07B" })
vim.api.nvim_set_hl(0, "PosteDbSqlDirectiveComment", { link = "Special" })

local DIRECTIVE_NS = vim.api.nvim_create_namespace("poste_sql_directive")
local DIRECTIVE_KEYWORDS = {
  const.DIRECTIVE_CONNECTION,
  const.DIRECTIVE_DATABASE,
  const.DIRECTIVE_PROTOCOL,
}

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
          end_col = dend, hl_group = "PosteDbSqlDirectiveComment", priority = 101,
        })
        vim.api.nvim_buf_set_extmark(buf, DIRECTIVE_NS, i - 1, dstart - 1, {
          end_col = dend, hl_group = "PosteDbSqlDirective", priority = 102,
        })
        local vstart, vend = line:find("%S.*$", dend + 1)
        if vstart then
          vim.api.nvim_buf_set_extmark(buf, DIRECTIVE_NS, i - 1, vstart - 1, {
            end_col = vend, hl_group = "PosteDbSqlDirectiveValue", priority = 102,
          })
        end
        break
      end
    end
  end
end

--- SQL keyword highlighting for a single line via extmarks.
--- Used by log_viewer to highlight SQL in detail view.
--- @param buf number  Buffer handle
--- @param ns number   Namespace for extmarks
--- @param line_idx number  Buffer line (1-indexed)
--- @param text string  Text content to highlight (without buffer prefix)
--- @param offset number  Column offset in buffer where text starts
function M.highlight_line(buf, ns, line_idx, text, offset)
  local keywords = {
    "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
    "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "VIEW", "WITH",
    "AND", "OR", "NOT", "NULL", "IN", "AS", "ON", "JOIN", "LEFT", "RIGHT",
    "INNER", "OUTER", "FULL", "CROSS", "GROUP", "BY", "ORDER", "HAVING",
    "LIMIT", "OFFSET", "DISTINCT", "CASE", "WHEN", "THEN", "ELSE", "END",
    "EXISTS", "UNION", "ALL", "BETWEEN", "LIKE", "IS", "TRUE", "FALSE",
    "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CASCADE", "DEFAULT",
    "INTEGER", "INT", "BIGINT", "SMALLINT", "TEXT", "VARCHAR", "CHAR",
    "BOOLEAN", "BOOL", "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC",
    "DATE", "TIMESTAMP", "TIME", "JSON", "JSONB", "SERIAL", "BIGSERIAL",
    "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "CAST",
  }
  local kw_map = {}
  for _, kw in ipairs(keywords) do
    kw_map[kw] = true
  end

  local hl_group = "Statement"
  local i = 1
  while i <= #text do
    local word_start, word_end = text:find("[%w_]+", i)
    if not word_start then break end
    if kw_map[text:sub(word_start, word_end):upper()] then
      vim.api.nvim_buf_set_extmark(buf, ns, line_idx - 1, offset + word_start - 1, {
        end_col = offset + word_end,
        hl_group = hl_group,
        priority = 150,
        hl_mode = "combine",
      })
    end
    i = word_end + 1
  end
end

return M
