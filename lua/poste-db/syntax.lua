--- SQL directive comment highlighter.
--- Only handles -- @connection / @database / @protocol highlighting.
--- SQL keyword/type/function highlighting is handled by Tree-sitter
--- via after/queries/poste_sql/highlights.scm.

local M = {}
local const = require("poste-db.constants")
local context = require("poste-db.context")
local connections = require("poste-db.connections")
local state = require("poste.state")
local compat = require("poste-db.compat")

local _hl_setup_done = false

local function ensure_hl()
  if _hl_setup_done then return end
  _hl_setup_done = true
  vim.api.nvim_set_hl(0, "PosteDbSqlDirective", { fg = "#D19A66", bold = true })
  vim.api.nvim_set_hl(0, "PosteDbSqlDirectiveValue", { fg = "#E5C07B" })
  vim.api.nvim_set_hl(0, "PosteDbSqlDirectiveComment", { link = "Special" })
end

local DIRECTIVE_NS = vim.api.nvim_create_namespace("poste_db_directive")
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

local DIGIT_PREFIX_NS = vim.api.nvim_create_namespace("poste_db_digit_fragment")

--- Resolve the connection dialect for a buffer (lowercase), or nil.
--- Checks: ### dialect header → connection config → g:poste_db_dialect → filetype.
--- @param buf number  buffer handle
--- @return string|nil
local function get_dialect(buf)
  -- Check ### dialect header in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, math.min(20, vim.api.nvim_buf_line_count(buf)), false)
  for _, line in ipairs(lines) do
    local d = line:match("^### dialect%s+(%S+)")
    if d then return d:lower() end
  end

  -- Resolve from connection config
  local ctx = context.resolve_context(buf)
  local conn = ctx.connection
  if not conn then
    conn = state.sql and state.sql.context and state.sql.context.connection
  end
  if conn then
    local cfg = connections.get_connection_config(conn)
    if cfg and cfg.dialect and cfg.dialect ~= "" then
      return cfg.dialect:lower()
    end
  end

  -- Fallback to global dialect option
  local global_dialect = compat.opt("dialect")
  if global_dialect and global_dialect ~= "" then
    return global_dialect:lower()
  end

  -- Fallback based on filetype
  local ft = vim.bo[buf].filetype
  if ft == "poste_sqlite" then
    return "sqlite"
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

------------------------------------------------------------------------
--- Re-highlight constructs tree-sitter-sql can't parse.
------------------------------------------------------------------------

local ERROR_CONSTRUCT_NS = vim.api.nvim_create_namespace("poste_db_error_construct")

--- Lowercased markers identifying ERROR nodes that are known false positives
--- (constructs tree-sitter-sql doesn't parse but the user's SQL is valid).
--- Kept in sync with ts_stmt.find_error_nodes' filter list.
local KNOWN_CONSTRUCT_MARKERS = {
  "pragma", "glob", "natural join", "savepoint", "release",
  "explain query plan", "query plan", "values", "or replace", "or ignore",
  "or abort", "or fail", "or rollback", "percentile_", "within group",
  "interval", "separator", "show ",
  "create or replace", "invisible", "collate", "character set",
}

local CONSTRUCT_KEYWORDS = {
  PRAGMA = true, GLOB = true, SAVEPOINT = true, RELEASE = true,
  NATURAL = true, EXPLAIN = true, QUERY = true, PLAN = true,
  VALUES = true, INSERT = true, OR = true, INTO = true, BY = true,
  REPLACE = true, ROLLBACK = true, ABORT = true, FAIL = true, IGNORE = true,
  WITHIN = true, GROUP = true, ORDER = true, SELECT = true, FROM = true,
  WHERE = true, JOIN = true, LIMIT = true, AS = true, ASC = true, DESC = true,
  INTERVAL = true, SEPARATOR = true, SHOW = true,
  PERCENTILE_CONT = true, PERCENTILE_DISC = true,
  CREATE = true, TABLE = true, SEQUENCE = true, INVISIBLE = true, INT = true,
  PRIMARY = true, KEY = true, AUTO_INCREMENT = true, VARCHAR = true,
  CHAR = true, COLLATE = true, CHARACTER = true,
  IF = true, EXISTS = true,
}

local function hl_err_tokens(buf, row, from_col, to_col)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  if to_col <= from_col then return end
  local seg = line:sub(from_col + 1, to_col)
  local base = from_col
  local i = 1
  while i <= #seg do
    local c = seg:sub(i, i)
    if c == "'" then
      local close = seg:find("'", i + 1, true)
      if close then
        pcall(vim.api.nvim_buf_set_extmark, buf, ERROR_CONSTRUCT_NS, row, base + i - 1, {
          end_col = base + close, hl_group = "String", priority = 300,
        })
        i = close + 1
      else
        i = i + 1
      end
    else
      local ws, we = seg:find("[%w_]+", i)
      if not ws then break end
      local word = seg:sub(ws, we):upper()
      if CONSTRUCT_KEYWORDS[word] then
        vim.api.nvim_buf_set_extmark(buf, ERROR_CONSTRUCT_NS, row, base + ws - 1, {
          end_col = base + we, hl_group = "Statement", priority = 300,
        })
      elseif word:match("^%d") then
        vim.api.nvim_buf_set_extmark(buf, ERROR_CONSTRUCT_NS, row, base + ws - 1, {
          end_col = base + we, hl_group = "Number", priority = 300,
        })
      end
      i = we + 1
    end
  end
end

--- Recolors ERROR nodes that are known tree-sitter false positives so they
--- render like normal SQL instead of @error red. nvim's TS highlighter marks
--- every ERROR node red by default; these constructs are valid in their
--- dialect despite not being parseable. A neutral base kills the redness and
--- keywords/strings/numbers inside get their usual groups.
--- Mirrors ts_stmt.find_error_nodes' known-false-positive list.
--- @param buf number  Buffer handle
--- @param dialect string|nil  Optional dialect override (unused, kept for symmetry)
function M.highlight_known_error_constructs(buf, dialect)
  ensure_hl()
  buf = buf or 0
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  vim.api.nvim_buf_clear_namespace(buf, ERROR_CONSTRUCT_NS, 0, -1)

  local ok_lang, lang = pcall(vim.treesitter.language.get_lang, "sql")
  if not (ok_lang and lang) then return end
  local ok_parse, parser = pcall(vim.treesitter.get_parser, buf, "sql")
  if not ok_parse or not parser then return end
  local ok_trees, trees = pcall(parser.parse, parser)
  if not ok_trees or not trees or #trees == 0 then return end

  local stack = { trees[1]:root() }
  while #stack > 0 do
    local node = table.remove(stack)
    if node:type() == "ERROR" then
      local text = vim.treesitter.get_node_text(node, buf) or ""
      local lower = text:lower()
      local known = false
      for _, marker in ipairs(KNOWN_CONSTRUCT_MARKERS) do
        if lower:find(marker, 1, true) then known = true break end
      end
      -- value-fragment cascades from a misparsed VALUES clause (`1, 'a'),`)
      if not known and lower:match("^%d+%s*,") then known = true end
      -- statement-terminator cascades (e.g. `; USE` after a CREATE DATABASE)
      if not known and lower:match("^%s*;") then known = true end
      if known then
          local sr, sc, er, ec = node:range()
          pcall(vim.api.nvim_buf_set_extmark, buf, ERROR_CONSTRUCT_NS, sr, sc, {
            end_row = er, end_col = ec, hl_group = "Normal", priority = 250,
          })
          if er == sr then
            hl_err_tokens(buf, sr, sc, ec)
          else
            hl_err_tokens(buf, sr, sc, #((vim.api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or "")))
            for row = sr + 1, er - 1 do
              hl_err_tokens(buf, row, 0, #((vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or "")))
            end
            hl_err_tokens(buf, er, 0, ec)
        end
      end
    end
    for i = node:child_count() - 1, 0, -1 do
      stack[#stack + 1] = node:child(i)
    end
  end
end

return M
