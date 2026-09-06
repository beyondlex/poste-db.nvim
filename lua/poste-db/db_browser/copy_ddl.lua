--- Pure DDL/result transform helpers for cross-connection copy.
--- Extracted from db_browser/copy.lua: string/table in, string/table out —
--- no IO, no dialogs, directly unit-testable.
local ident = require("poste-db.ident")

local quote = ident.quote

local M = {}


function M.has_value(v)
  return v ~= nil and v ~= vim.NIL
end

function M.quote_value(val)
  if not M.has_value(val) then
    return "NULL"
  end
  local t = type(val)
  if t == "number" then
    return tostring(val)
  elseif t == "boolean" then
    return val and "TRUE" or "FALSE"
  elseif t == "string" then
    return "'" .. val:gsub("'", "''") .. "'"
  elseif t == "table" then
    local ok, json_str = pcall(vim.json.encode, val)
    if ok then
      return "'" .. json_str:gsub("'", "''") .. "'"
    end
    return "NULL"
  end
  return "'" .. tostring(val):gsub("'", "''") .. "'"
end

function M.extract_row_count(r)
  if M.has_value(r.affected_rows) then return tostring(r.affected_rows) end
  if M.has_value(r.row_count) then return tostring(r.row_count) end
  return "?"
end

function M.extract_elapsed(r)
  if M.has_value(r.execution_time_ms) then return tostring(r.execution_time_ms) .. "ms" end
  return "?"
end

function M.check_result_error(decoded)
  if decoded and decoded.results and decoded.results[1] then
    local r = decoded.results[1]
    if M.has_value(r.error) then return r.error end
    if M.has_value(r.message) then return r.message end
  end
  return nil
end

function M.extract_schema_from_ddl(ddl, table_name, dialect)
  if dialect == "mysql" or dialect == "mariadb" then
    return nil
  end
  local quoted = '"' .. table_name .. '"'
  local pattern = '^CREATE TABLE "([^"]+)"%.' .. quoted
  local schema = ddl:match(pattern)
  if schema then return schema end
  return nil
end

function M.extract_sequences_from_ddl(ddl, schema)
  local sequences = {}
  local seen = {}
  for seq_name in ddl:gmatch("nextval%('([^']+)'%:%:regclass%)") do
    if not seen[seq_name] then
      seen[seq_name] = true
      table.insert(sequences, seq_name)
    end
  end
  return sequences
end

function M.column_type_for_seq(ddl, seq_name)
  local seq_ref = "nextval('" .. seq_name .. "'::regclass)"
  local seq_pos = ddl:find(seq_ref, 1, true)
  if not seq_pos then return "integer" end
  local before = ddl:sub(1, seq_pos - 1)
  local col_type = before:match('"[^"]+"%s+(%w+)%s+[^,]-%s+DEFAULT%s*$')
  if not col_type then
    col_type = before:match('"[^"]+"%s+(%w+)%s+DEFAULT%s*$')
  end
  if col_type == "bigint" then return "bigint" end
  if col_type == "smallint" then return "smallint" end
  return "integer"
end

function M.rename_seq_reference(ddl, seq_name, new_seq_name)
  local old = "nextval('" .. seq_name .. "'::regclass)"
  local new = "nextval('" .. new_seq_name .. "'::regclass)"
  -- old/new contain parens and quotes; gsub would treat them as pattern
  -- magic and never match — escape both sides for a literal replacement.
  return (ddl:gsub(vim.pesc(old), new:gsub("%%", "%%%%"), 1))
end

function M.prepare_table_ddl(ddl, target_table_name, table_name, schema, dialect)
  local modified = ddl:gsub("`" .. table_name .. "`", "`" .. target_table_name .. "`")
  modified = modified:gsub('"' .. table_name .. '"', '"' .. target_table_name .. '"')

  if dialect ~= "postgres" then
    return modified
  end

  local sequences = M.extract_sequences_from_ddl(modified, schema)
  if #sequences == 0 then
    return modified
  end

  local q = function(n) return quote(n, dialect) end
  local seq_stmts = {}
  for _, seq_name in ipairs(sequences) do
    local new_seq_name = seq_name:gsub(table_name, target_table_name)
    local seq_type = M.column_type_for_seq(ddl, seq_name)
    -- Qualified nextval refs leave new_seq_name carrying the schema already
    -- (quote() splits on the dot); prepending schema again would emit
    -- "schema"."schema"."seq", disagreeing with the rewritten DEFAULT ref.
    local qualified
    if schema and not new_seq_name:find(".", 1, true) then
      qualified = q(schema) .. "." .. q(new_seq_name)
    else
      qualified = q(new_seq_name)
    end
    table.insert(seq_stmts, "CREATE SEQUENCE IF NOT EXISTS " .. qualified .. " AS " .. seq_type .. ";")
    modified = M.rename_seq_reference(modified, seq_name, new_seq_name)
  end

  table.insert(seq_stmts, modified)
  return table.concat(seq_stmts, "\n")
end

function M.dialect_table_exists_sql(dialect, schema)
  if dialect == "mysql" or dialect == "mariadb" then
    -- information_schema (not SHOW TABLES) so views collide correctly too.
    return "SELECT TABLE_NAME FROM information_schema.TABLES"
      .. " WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '%s'"
  elseif dialect == "postgres" then
    return "SELECT EXISTS (SELECT FROM information_schema.tables"
      .. " WHERE table_schema = '" .. (schema or "public") .. "'"
      .. " AND table_name = '%s')"
  else
    return "SELECT name FROM sqlite_master"
      .. " WHERE type IN ('table','view') AND name='%s'"
  end
end

--- Replace a routine's own name inside its SHOW CREATE/pg_get_functiondef
--- text (first occurrence after the PROCEDURE/FUNCTION keyword, so DEFINER
--- clauses are untouched).
function M.rename_routine_in_def(dialect, def, src, tgt)
  local upper = def:upper()
  local kw_pos = upper:find("PROCEDURE") or upper:find("FUNCTION")
  if not kw_pos then return def end

  if dialect == "mysql" or dialect == "mariadb" then
    local open = def:find("`", kw_pos, true)
    while open do
      local close = def:find("`", open + 1, true)
      if not close then break end
      if def:sub(open + 1, close - 1) == src then
        -- open sits on the original backtick; drop it (the appended "`"
        -- replaces it) or MySQL reads a doubled backtick as a literal.
        return def:sub(1, open - 1) .. "`" .. tgt .. "`" .. def:sub(close + 1)
      end
      open = def:find("`", close + 1, true)
      if open and open > close and open < kw_pos + 200 then
        -- keep scanning just past this token pair; stop runaway scans early
        break
      end
      open = nil
    end
    -- Fallback: any direct `src` mention right after the keyword.
    local plain_idx = def:find("`" .. src .. "`", kw_pos, true)
    if plain_idx then
      return def:sub(1, plain_idx - 1) .. "`" .. tgt .. "`" .. def:sub(plain_idx + #src + 2)
    end
    return def
  end

  -- Postgres: name immediately precedes the parameter list.
  local paren = def:find("%(", kw_pos)
  if not paren then return def end
  local before = def:sub(kw_pos + 1, paren - 1)
  local trimmed = before:gsub('%s+', '')
  if trimmed:sub(-#src) == src then
    local start_pos = kw_pos + 1 + (#before - #trimmed) + (#trimmed - #src)
    return def:sub(1, start_pos - 1) .. tgt .. def:sub(paren)
  end
  return def
end

return M
