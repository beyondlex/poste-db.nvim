--- Tree-sitter-based SQL statement boundary detection.
--- Replaces Rust CLI `poste context stmt` for finding statement spans.
--- Falls back to nil if Tree-sitter is unavailable, letting callers
--- fall through to Rust or Lua heuristics.

local M = {}

--- Check if the Tree-sitter SQL parser is available.
--- @return boolean
function M.check_parser()
  local ok, lang = pcall(vim.treesitter.language.get_lang, "sql")
  return ok and lang ~= nil
end

--- Get a Tree-sitter parser for the given buffer, or nil.
--- @param buf number
--- @return table|nil
local function get_parser(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "sql")
  if ok and parser then
    return parser
  end
  return nil
end

--- Walk the program root's children to find top-level statement-like nodes.
--- Treats ERROR nodes as statement-like (they include USE, SET, etc.
--- that tree-sitter-sql doesn't recognize).
--- @param root table  TSNode
--- @param buf number
--- @return table[]  list of TSNode
local function get_top_level_stmts(root, buf)
  local stmts = {}
  for child in root:iter_children() do
    local t = child:type()
    if t == "statement" then
      stmts[#stmts + 1] = child
    elseif t == "transaction" then
      stmts[#stmts + 1] = child
      for grandchild in child:iter_children() do
        if grandchild:type() == "statement" then
          stmts[#stmts + 1] = grandchild
        end
      end
    elseif t == "ERROR" then
      stmts[#stmts + 1] = child
    end
  end
  return stmts
end

--- Find the statement span containing a given cursor line using Tree-sitter.
--- @param buf number  buffer handle
--- @param cursor_line number  1-based line number
--- @return {start_line: number, end_line: number}|nil  1-based, inclusive
function M.find_stmt_span(buf, cursor_line)
  local parser = get_parser(buf)
  if not parser then return nil end

  local ok, trees = pcall(parser.parse, parser)
  if not ok or not trees or #trees == 0 then return nil end

  local root = trees[1]:root()
  local cursor_row = cursor_line - 1

  -- Walk top-level children to find the statement containing cursor_row
  for child in root:iter_children() do
    local t = child:type()
    if t == "statement" or t == "transaction" or t == "ERROR" then
      local s = child:start()
      local e = child:end_()
      if s <= cursor_row and cursor_row <= e then
        return { s + 1, e + 1 }
      end
    end
  end

  return nil
end

--- Find all statement boundary lines in a range using Tree-sitter.
--- Returns 1-based buffer line numbers of each statement's first content line.
--- @param buf number  buffer handle
--- @param start_line number  1-based
--- @param end_line number  1-based
--- @return number[]|nil  1-based statement start lines
function M.find_all_stmt_lines(buf, start_line, end_line)
  local parser = get_parser(buf)
  if not parser then return nil end

  local ok, trees = pcall(parser.parse, parser)
  if not ok or not trees or #trees == 0 then return nil end

  local root = trees[1]:root()
  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local stmts = get_top_level_stmts(root, buf)
  local result = {}

  for _, node in ipairs(stmts) do
    local s = node:start() + 1
    local e = node:end_() + 1

    -- Check if this statement overlaps with the requested range
    if s <= end_line and e >= start_line then
      -- Find the first non-blank, non-comment line in this statement
      local content_start = s
      while content_start <= e do
        local line = buf_lines[content_start] or ""
        local trimmed = line:match("^%s*(.*)$")
        if trimmed ~= "" and not trimmed:match("^%-%-") and not trimmed:match("^###") then
          break
        end
        content_start = content_start + 1
      end
      if content_start <= end_line then
        result[#result + 1] = content_start
      end
    end
  end

  return #result > 0 and result or nil
end

--- Find Tree-sitter ERROR nodes in a buffer for diagnostics.
--- Filters out known false positives (USE, SET statements that
--- tree-sitter-sql doesn't recognize).
--- @param buf number
--- @return {lnum: number, col: number, end_lnum: number, end_col: number, text: string}[]
function M.find_error_nodes(buf)
  local parser = get_parser(buf)
  if not parser then return {} end

  local ok, trees = pcall(parser.parse, parser)
  if not ok or not trees or #trees == 0 then return {} end

  local root = trees[1]:root()
  local errors = {}

  local query = vim.treesitter.query.parse("sql", "(ERROR) @err")
  for id, node, metadata in query:iter_captures(root, buf, 0, -1) do
    local text = vim.treesitter.get_node_text(node, buf) or ""

    -- Filter out false positives: statements that tree-sitter-sql
    -- doesn't recognize (MySQL-specific and other non-standard SQL),
    -- and cascading errors (short fragments from nested parser errors).
    local upper = text:upper()

    -- Filter cascading parser errors: single char, punctuation-only, or short parenthesized identifiers
    if #text <= 2 or upper:match("^%(%w+%)$") then
      goto continue
    end

    -- Filter known non-standard statements
    local stmt_kw = upper:match("^(%w+)%s") or upper:match("^(%w+);")
    if stmt_kw then
      local known_false_positives = {
        USE = true, SET = true, DESC = true, DESCRIBE = true,
        ANALYZE = true, KILL = true, FLUSH = true, CALL = true,
        LOAD = true, REPAIR = true, CHECK = true,
        ON = true, FOR = true, NOTIFY = true, TABLE = true,
        BEGIN = true, SETS = true, PERCENTILE_CONT = true,
      }
      if known_false_positives[stmt_kw] then
        goto continue
      end
    end

    -- Filter PG-specific constructs that the parser misparses
    if upper:match("^%(%w+%)%s+DO%s+UPDATE") or upper:match("^%(%w+%)%s+ON%s+CONFLICT") then
      goto continue
    end

    -- Filter SQLite-specific INSERT OR conflict clauses
    if upper:match("^OR%s+REPLACE%s+INTO") or upper:match("^OR%s+ROLLBACK%s+INTO")
      or upper:match("^OR%s+ABORT%s+INTO") or upper:match("^OR%s+FAIL%s+INTO")
      or upper:match("^OR%s+IGNORE%s+INTO") then
      goto continue
    end

    errors[#errors + 1] = {
      lnum = node:start() + 1,
      col = node:start() + 1,
      end_lnum = node:end_() + 1,
      end_col = node:end_() + 1,
      text = "Unexpected token: " .. text,
    }
    ::continue::
  end

  return errors
end

M._test = {
  find_stmt_span = M.find_stmt_span,
  find_all_stmt_lines = M.find_all_stmt_lines,
  find_error_nodes = M.find_error_nodes,
}

return M