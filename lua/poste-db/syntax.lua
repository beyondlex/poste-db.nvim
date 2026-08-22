--- SQL directive comment highlighter.
--- Only handles -- @connection / @database / @protocol highlighting.
--- SQL keyword/type/function highlighting is handled by Tree-sitter
--- via after/queries/poste_sql/highlights.scm.

local M = {}
local const = require("poste-db.constants")
local context = require("poste-db.context")
local connections = require("poste-db.connections")
local state = require("poste.state")

local _hl_setup_done = false

local function ensure_hl()
  if _hl_setup_done then return end
  _hl_setup_done = true
  vim.api.nvim_set_hl(0, "PosteDbSqlDirective", { fg = "#D19A66", bold = true })
  vim.api.nvim_set_hl(0, "PosteDbSqlDirectiveValue", { fg = "#E5C07B" })
  vim.api.nvim_set_hl(0, "PosteDbSqlDirectiveComment", { link = "Special" })
end

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
  ensure_hl()
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

local DIGIT_PREFIX_NS = vim.api.nvim_create_namespace("poste_sql_digit_fragment")

--- Resolve the connection dialect for a buffer (lowercase), or nil.
--- Mirrors diagnostics.get_dialect: buffer context → runtime connection.
--- @param buf number  buffer handle
--- @return string|nil
local function get_dialect(buf)
  local ctx = context.resolve_context(buf)
  local conn = ctx.connection
  if not conn then
    conn = state.sql and state.sql.context and state.sql.context.connection
  end
  if not conn then return nil end
  local cfg = connections.get_connection_config(conn)
  if cfg and cfg.dialect and cfg.dialect ~= "" then
    return cfg.dialect:lower()
  end
  return nil
end

--- tree-sitter-sql splits digit-leading identifiers (`123_abc`) into
--- ERROR[123] + identifier[_abc]; the ERROR fragment inherits nvim-treesitter's
--- @error color while `_abc` renders as a table name (@type). For MySQL/MariaDB
--- (where digit-leading unquoted identifiers are legal) recolor the fragment
--- with the @type group so the name renders as one token.
--- Geometry rule: ERROR text is pure digits AND its next sibling's first leaf
--- is an identifier starting exactly where the ERROR ends. `234 _tablename`
--- has a whitespace gap → untouched (it is a standalone all-digit name, illegal
--- even in MySQL). Non-mysql dialects keep the red @error signal; unknown
--- dialect (nil) is conservative and keeps it too.
--- @param buf number  Buffer handle
--- @param dialect string|nil  Optional dialect override (lowercase); nil
---   resolves via connection context.
function M.highlight_digit_prefix_fragments(buf, dialect)
  ensure_hl()
  buf = buf or 0
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  vim.api.nvim_buf_clear_namespace(buf, DIGIT_PREFIX_NS, 0, -1)
  dialect = dialect or get_dialect(buf)
  if dialect ~= "mysql" and dialect ~= "mariadb" then return end

  local ok_lang, lang = pcall(vim.treesitter.language.get_lang, "sql")
  if not (ok_lang and lang) then return end
  local ok_parse, parser = pcall(vim.treesitter.get_parser, buf, "sql")
  if not ok_parse or not parser then return end
  local ok_trees, trees = pcall(parser.parse, parser)
  if not ok_trees or not trees or #trees == 0 then return end

  local hl = "@type"
  if vim.fn.hlexists("@type") ~= 1 then
    if vim.fn.hlexists("Type") == 1 then
      hl = "Type"
    else
      hl = nil -- no usable group: skip coloring
    end
  end

  local stack = { trees[1]:root() }
  while #stack > 0 do
    local node = table.remove(stack)
    if node:type() == "ERROR" then
      local text = vim.treesitter.get_node_text(node, buf) or ""
      if text:match("^%d+$") then
        local _, _, er, ec = node:range()
        local next_node = node:next_sibling()
        if next_node and hl then
          local first = next_node
          while first:child_count() > 0 do
            first = first:child(0)
          end
          local fsr, fsc = first:range()
          if first:type() == "identifier" and fsr == er and fsc == ec then
            -- MySQL dialect: the ERROR digits are part of the identifier that
            -- follows immediately. Color the whole name like a table.
            local sr, sc = node:range()
            local _, _, fer, fec = first:range()
            pcall(vim.api.nvim_buf_set_extmark, buf, DIGIT_PREFIX_NS, sr, sc, {
              end_row = fer,
              end_col = fec,
              hl_group = hl,
              hl_mode = "combine",
              priority = 300,
            })
          end
        end
      end
    end
    for i = node:child_count() - 1, 0, -1 do
      stack[#stack + 1] = node:child(i)
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
