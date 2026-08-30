--- Guard for unfiltered destructive SQL — DELETE/UPDATE statements that lack
--- a WHERE clause (and would therefore hit every row).
---
--- Two duties:
---   1. Buffer lint: purple HINT diagnostics via `M.update(buf)` / `M.clear(buf)`
---      (wired from diagnostics.lua, alongside the syntax + semantic checks).
---   2. Run-time confirm gate: `M.scan_text()` + `M.confirm_message()` power the
---      confirmation dialog in sql_runner.run_sql_request() before execution.
---
--- Tree-sitter-sql drives both paths; a regex fallback covers text that does
--- not parse (parser missing, ERROR fragments). The classifier operates on a
--- small plain-table node shape ({ type, children }) so it is unit-testable
--- without a parser; TSNode subtrees are converted at the parse boundary.

local M = {}

local ns = vim.api.nvim_create_namespace("poste_db_missing_where")
local ns_hl = vim.api.nvim_create_namespace("poste_db_missing_where_highlight")

M.MESSAGES = {
  delete = "DELETE statement without a WHERE clause — this will remove ALL rows in the table",
  update = "UPDATE statement without a WHERE clause — this will modify ALL rows in the table",
}

--- True when `node` has a direct `where` clause child.
--- @param node table { children = table[] }
--- @return boolean
local function clauses_have_where(node)
  for _, c in ipairs(node.children or {}) do
    if c.type == "where" then return true end
  end
  return false
end

--- Classify a DML statement container (plain table: { type, children }) and
--- return its kind ("delete"/"update") when it lacks a top-level WHERE clause,
--- nil otherwise.
---
--- tree-sitter-sql keeps the DELETE WHERE inside the statement's `from` clause
--- (a sibling of the `delete` node), while UPDATE carries `where` directly on
--- the `update` node. A `where` inside a nested subquery (e.g. `UPDATE t
--- SET x = (SELECT ... WHERE ...)`) does NOT count — it filters the subquery,
--- not the rows being changed.
--- @param node table { type = "statement"|"transaction", children = table[] }
--- @return string|nil "delete"|"update" when unfiltered; nil otherwise
function M.missing_where(node)
  if not node then return nil end
  local found_delete = false
  local delete_filtered = false
  for _, c in ipairs(node.children or {}) do
    local t = c.type
    if t == "delete" then
      found_delete = true
    elseif t == "update" then
      if not clauses_have_where(c) then return "update" end
    elseif t == "from" then
      if clauses_have_where(c) then delete_filtered = true end
    end
  end
  if found_delete then
    if delete_filtered then return nil end
    return "delete"
  end
  return nil
end

--- Collect the DML statement containers (TSNode "statement" nodes) in `root`,
--- descending through "transaction" groups.
--- @param root TSNode
--- @return TSNode[]
local function container_tsnodes(root)
  local containers = {}
  local function visit(node)
    local t = node:type()
    if t == "statement" then
      containers[#containers + 1] = node
      return
    end
    for c in node:iter_children() do visit(c) end
  end
  visit(root)
  return containers
end

--- Convert a TSNode subtree to the plain { type, children } shape.
--- @param node TSNode
--- @return table { type, children }
local function to_plain(node)
  local plain = { type = node:type(), children = {} }
  for c in node:iter_children() do
    plain.children[#plain.children + 1] = to_plain(c)
  end
  return plain
end

local function get_parser(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "sql")
  if ok and parser then return parser end
  return nil
end

--- Compute unfiltered DML statements in a buffer (0-based ranges, diagnostics
--- ready). Empty when tree-sitter-sql is unavailable or nothing is risky.
--- @param buf number
--- @return table[] each entry: { kind, lnum, col, end_lnum, end_col }
function M.compute(buf)
  local hits = {}
  local parser = get_parser(buf)
  if not parser then return hits end
  local ok, trees = pcall(parser.parse, parser)
  if not ok or not trees or #trees == 0 then return hits end
  for _, stmt in ipairs(container_tsnodes(trees[1]:root())) do
    local kind = M.missing_where(to_plain(stmt))
    if kind then
      local s, sc, e, ec = stmt:range()
      hits[#hits + 1] = { kind = kind, lnum = s, col = sc, end_lnum = e, end_col = ec }
    end
  end
  return hits
end

--- Set purple HINT diagnostics for unfiltered DELETE/UPDATE statements.
--- @param buf number
function M.update(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local hits = M.compute(buf)
  local diags = {}
  for _, h in ipairs(hits) do
    diags[#diags + 1] = {
      lnum = h.lnum,
      col = h.col,
      end_lnum = h.end_lnum,
      end_col = h.end_col,
      severity = vim.diagnostic.severity.HINT,
      source = "poste-db",
      message = M.MESSAGES[h.kind],
    }
  end
  vim.diagnostic.set(ns, buf, diags, { priority = 200 })
  vim.api.nvim_buf_clear_namespace(buf, ns_hl, 0, -1)
  for _, h in ipairs(hits) do
    vim.api.nvim_buf_set_extmark(buf, ns_hl, h.lnum, h.col, {
      end_row = h.end_lnum,
      end_col = h.end_col,
      hl_group = "PosteDbMissingWhere",
      hl_mode = "combine",
      priority = 200,
    })
  end
end

--- Clear the missing-WHERE diagnostics for a buffer.
--- @param buf number
function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.diagnostic.reset(ns, buf)
    vim.api.nvim_buf_clear_namespace(buf, ns_hl, 0, -1)
  end
end

--- Trim, collapse whitespace and truncate a SQL snippet for confirm dialogs.
--- @param text string|nil
--- @param max number|nil
--- @return string
function M.snippet(text, max)
  max = max or 64
  local s = (text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #s > max then s = s:sub(1, max - 3) .. "..." end
  return s
end

--- Strip comments and quoted literals so keyword scanning is not fooled by
--- `-- where` comments or a WHERE token inside a string value.
--- @param sql string
--- @return string
local function sanitize(sql)
  return (sql:gsub("%-%-[^\n]*", " ")
    :gsub("/%*.-%*/", " ")
    :gsub("'[^']*'", " ")
    :gsub('"[^"]*"', " ")
    :gsub("`[^`]*`", " "))
end

--- Regex fallback for `scan_text`: split on `;`, flag DELETE/UPDATE chunks
--- without a top-level WHERE. Parens are dropped before scanning so a WHERE
--- inside a subquery does not count as the statement's filter.
--- @param sql string
--- @return table[] each entry: { kind, snippet }
function M.regex_scan(sql)
  local hits = {}
  if not sql or #sql == 0 then return hits end
  for chunk in (sanitize(sql) .. ";"):gmatch("[^;]*") do
    local stmt = chunk:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if stmt ~= "" then
      local upper = stmt:upper()
      local kw
      if upper:match("^DELETE%s") then
        kw = "delete"
      elseif upper:match("^UPDATE%s") then
        kw = "update"
      end
      if kw then
        local body = stmt:gsub("%b()", " ")
        if body:upper():find("%sWHERE%s") == nil then
          hits[#hits + 1] = { kind = kw, snippet = stmt }
        end
      end
    end
  end
  return hits
end

--- Scan SQL text for DELETE/UPDATE statements that lack a WHERE clause.
--- Uses tree-sitter when available; falls back to `regex_scan`. The result is
--- a list of { kind, snippet } used by the execution confirm gate.
--- @param sql string
--- @return table[]
function M.scan_text(sql)
  if not sql or #sql == 0 then return {} end
  local hits = {}
  local buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, vim.split(sql, "\n", { plain = true }))
  local parser = get_parser(buf)
  if parser then
    local ok, trees = pcall(parser.parse, parser)
    if ok and trees and #trees > 0 then
      for _, stmt in ipairs(container_tsnodes(trees[1]:root())) do
        local kind = M.missing_where(to_plain(stmt))
        if kind then
          hits[#hits + 1] = {
            kind = kind,
            snippet = M.snippet(vim.treesitter.get_node_text(stmt, buf)),
          }
        end
      end
    end
  end
  vim.api.nvim_buf_delete(buf, { force = true })
  if #hits == 0 then return M.regex_scan(sql) end
  return hits
end

--- Build the confirm question for a list of risky statements.
--- @param risky table[] { kind, snippet }
--- @return string
function M.confirm_message(risky)
  local n = #risky
  local kinds = {}
  local seen = {}
  for _, r in ipairs(risky) do
    if not seen[r.kind] then
      seen[r.kind] = true
      kinds[#kinds + 1] = (r.kind == "delete") and "DELETE statement" or "UPDATE statement"
    end
  end
  local head
  if n == 1 and risky[1].snippet and risky[1].snippet ~= "" then
    head = string.format("%s without a WHERE clause:\n  %s", kinds[1], risky[1].snippet)
  elseif n == 1 then
    head = kinds[1] .. " without a WHERE clause"
  else
    head = string.format("SQL contains %d statement(s) without a WHERE clause (%s)",
      n, table.concat(kinds, ", "))
  end
  return head .. "\n\nThis affects ALL rows — execute anyway?"
end

M._test = {
  missing_where = M.missing_where,
  regex_scan = M.regex_scan,
  confirm_message = M.confirm_message,
  snippet = M.snippet,
  sanitize = sanitize,
}

return M