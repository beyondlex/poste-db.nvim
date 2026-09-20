--- EXPLAIN — run the statement under the cursor through the dialect's
--- EXPLAIN form and render the plan in the introspection float.
---
--- The wrappers below are plan-only forms: plain EXPLAIN never executes the
--- statement (postgres/mysql/clickhouse), and EXPLAIN QUERY PLAN neither
--- (sqlite) — so wrapping a write statement is safe. mssql is unsupported:
--- its SET SHOWPLAN_TEXT must run as a separate batch, which exec-file
--- cannot express.

local M = {}

local const = require("poste-db.constants")

local EXPLAIN_PREFIX = {
  postgres = "EXPLAIN ",
  mysql = "EXPLAIN ",
  clickhouse = "EXPLAIN ",
  sqlite = "EXPLAIN QUERY PLAN ",
}

--- `extract_stmt_at_cursor` returns a synthetic block: leading `-- @`
--- directives, a `###` marker, then the statement. EXPLAIN must wrap only
--- the SQL, so strip directives, markers, and comment lines. Comments can't
--- affect a plan and dropping them keeps the single-statement check honest.
local function clean_stmt(content)
  local out = {}
  for _, l in ipairs(vim.split(content or "", "\n", { plain = true })) do
    if not const.is_directive_comment(l)
      and not l:match("^%s*###%s*$")
      and not l:match("^%s*%-%-") then
      out[#out + 1] = l
    end
  end
  return table.concat(out, "\n")
end

--- Index of the first `;` that actually ends a statement, or nil.
--- A plain `find(";")` counted separators that are part of the statement's own
--- text: `SELECT 'a;b'` (and any PL/pgSQL `$$ … ; … $$` body) got refused with
--- "EXPLAIN runs a single statement". Quote, comment and dollar-quote bodies
--- are skipped; an unterminated opener swallows the rest of the input, which
--- leaves the database to reject the statement — EXPLAIN's job here is only
--- to refuse a cursor sitting on several statements.
--- @param sql string
--- @return number|nil
local function find_statement_break(sql)
  local i, n = 1, #sql
  while i <= n do
    local c = sql:sub(i, i)
    if c == ";" then
      return i
    elseif c == "'" or c == '"' or c == "`" then
      -- Run to the closing quote. A doubled quote (`''`) is an escaped quote
      -- inside the literal, so the scan steps over the pair and keeps going.
      local j = i
      while true do
        j = sql:find(c, j + 1, true)
        if not j then return nil end
        if sql:sub(j + 1, j + 1) ~= c then break end
        j = j + 1
      end
      i = j + 1
    elseif c == "-" and sql:sub(i, i + 1) == "--" then
      local nl = sql:find("\n", i, true)
      i = nl and (nl + 1) or (n + 1)
    elseif c == "/" and sql:sub(i, i + 1) == "/*" then
      local close = sql:find("*/", i + 2, true)
      i = close and (close + 2) or (n + 1)
    elseif c == "$" then
      local tag = sql:match("^%$[%w_]*%$", i)
      if tag then
        local body = sql:find(tag, i + #tag, true)
        i = body and (body + #tag) or (n + 1)
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return nil
end

--- Wrap a statement in the dialect's EXPLAIN form.
--- @param dialect string|nil base dialect (nil behaves like postgres)
--- @param stmt string
--- @return string|nil wrapped, string|nil error_message
function M.wrap_sql(dialect, stmt)
  local prefix = EXPLAIN_PREFIX[dialect or "postgres"]
  if not prefix then
    return nil, ("EXPLAIN is not supported for dialect '%s'"):format(tostring(dialect))
  end
  local trimmed = stmt:match("^%s*(.-)%s*$")
  if trimmed == "" then
    return nil, "no statement under cursor"
  end
  local inner = trimmed:gsub("%s*;%s*$", "")
  -- exec-file splits the file into statements; an EXPLAIN wrapping several
  -- of them would explain (at best) only the first.
  if find_statement_break(inner) then
    return nil, "EXPLAIN runs a single statement — put the cursor on one statement"
  end
  return prefix .. inner, nil
end

local function cell_text(v)
  if v == nil or v == vim.NIL then return "" end
  return tostring(v)
end

--- Pull human-readable plan lines out of a legacy exec_run response.
--- Single-column results (pg/mysql/clickhouse tree text) render one cell per
--- line; sqlite's EXPLAIN QUERY PLAN returns id/parent/detail columns — its
--- "detail" column carries the readable text; anything else renders row
--- cells joined with " | ".
--- @param resp table|nil legacy response from exec_run.run_sql
--- @return string[]|nil lines, string|nil error_message
function M.plan_lines(resp)
  if not resp then
    return nil, "EXPLAIN failed (no response)"
  end
  local result = resp.results and resp.results[1]
  if not result then
    return nil, "EXPLAIN returned no plan"
  end
  if result.error and result.error ~= "" then
    return nil, result.error
  end

  local columns = result.columns or {}
  local detail_idx
  for i, col in ipairs(columns) do
    if type(col) == "table" and col.name and col.name:lower() == "detail" then
      detail_idx = i
      break
    end
  end

  local lines = {}
  for _, row in ipairs(result.rows or {}) do
    if #columns <= 1 then
      lines[#lines + 1] = cell_text(row[1])
    elseif detail_idx then
      lines[#lines + 1] = cell_text(row[detail_idx])
    else
      local cells = {}
      for _, c in ipairs(row) do cells[#cells + 1] = cell_text(c) end
      lines[#lines + 1] = table.concat(cells, " | ")
    end
  end
  if #lines == 0 then
    return nil, "EXPLAIN returned no plan"
  end
  return lines, nil
end

--- EXPLAIN the statement under the cursor and show the plan in a float.
function M.explain()
  local src_buf = vim.api.nvim_get_current_buf()
  local state = require("poste-db.state")
  if not state.find_poste_binary() then
    vim.notify("Poste binary not found.", vim.log.levels.ERROR, { title = "PosteDb" })
    return
  end

  local statement = require("poste-db.statement")
  local buf_lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
  local content = statement.extract_stmt_at_cursor(buf_lines, vim.fn.line("."), src_buf)
  local stmt = clean_stmt(content)
  if stmt:match("^%s*$") then
    vim.notify("No statement under cursor.", vim.log.levels.WARN, { title = "PosteDb" })
    return
  end

  local ctx = require("poste-db.context").resolve_full_context(src_buf)
  local conn = ctx.connection or ""
  local conn_dialect
  if conn ~= "" then
    local cfg = require("poste-db.connections").get_connection_config(conn)
    conn_dialect = cfg and cfg.dialect or nil
  end
  local dialect = conn_dialect or "postgres"

  local sql, err = M.wrap_sql(dialect, stmt)
  if not sql then
    vim.notify(err, vim.log.levels.WARN, { title = "PosteDb" })
    return
  end

  local database = ctx.database or ""
  local conn_url = nil
  if conn ~= "" then
    conn_url = require("poste-db.connections").resolve_connection_url(conn)
  end

  local resp = require("poste-db.exec_run").run_sql(sql, {
    src_file = vim.api.nvim_buf_get_name(src_buf),
    conn_url = conn_url,
    database = database,
    log_source = "explain",
    log_extra = { connection = conn ~= "" and conn or nil },
  })

  local lines, plan_err = M.plan_lines(resp)
  if not lines then
    vim.notify("EXPLAIN: " .. plan_err, vim.log.levels.ERROR, { title = "PosteDb" })
    return
  end

  local title = conn ~= ""
    and ("EXPLAIN: " .. conn .. (database ~= "" and "/" .. database or ""))
    or "EXPLAIN"
  -- Plan trees carry their own indentation/arrows; sql highlighting would be
  -- noise, so render as plain text.
  require("poste-db.introspect").show_float(lines, title, "text")
end

return M
