local M = {}

--- One identifier, in the dialect's own quoting, with nothing left to split.
local function quote_one(name, dialect)
  if dialect == "mysql" or dialect == "mariadb" or dialect == "clickhouse" then
    return "`" .. name:gsub("`", "``") .. "`"
  end
  if dialect == "mssql" then
    return "[" .. name:gsub("]", "]]") .. "]"
  end
  return '"' .. name:gsub('"', '""') .. '"'
end

--- `schema.table.col` as separate parts, or nil when the dots are not separators:
--- an empty part means the name itself contains them (`my..table`, `.hidden`,
--- `trailing.`). Splitting those would rewrite which object the SQL points at,
--- and a name with a dot in it is legal — Postgres and MySQL both accept
--- `CREATE TABLE "my..table"`, and the browser introspects such a table by its
--- exact name.
local function split_name(name)
  local parts = {}
  local prev = 1
  for i = 1, #name do
    if name:sub(i, i) == "." then
      parts[#parts + 1] = name:sub(prev, i - 1)
      prev = i + 1
    end
  end
  parts[#parts + 1] = name:sub(prev)
  if #parts < 2 then return nil end
  for _, part in ipairs(parts) do
    if part == "" then return nil end
  end
  return parts
end

function M.quote(name, dialect, depth)
  depth = depth or 0
  if not name or name == "" or name == "*" then return name or "" end
  -- Unreachable from a caller that does not pass `depth`: split_name hands the
  -- parts down already dot-free, so the recursion is one level deep. It still
  -- quotes rather than returns the name, because a raw identifier is both wrong
  -- and injectable, and this guard is the only path that could emit one.
  if depth > 10 then return quote_one(name, dialect) end
  local parts = split_name(name)
  if parts then
    for i, part in ipairs(parts) do
      parts[i] = M.quote(part, dialect, depth + 1)
    end
    return table.concat(parts, ".")
  end
  return quote_one(name, dialect)
end

function M.quote_qualified(schema, table_name, dialect)
  if schema and schema ~= "" then
    return M.quote(schema, dialect) .. "." .. M.quote(table_name, dialect)
  end
  return M.quote(table_name, dialect)
end

function M.quote_literal(val, dialect)
  if val == nil or val == vim.NIL then return "NULL" end
  if type(val) == "boolean" then return val and "TRUE" or "FALSE" end
  if type(val) == "number" then return tostring(val) end
  local s = tostring(val):gsub("'", "''")
  -- Backslash dialects: MySQL/MariaDB and ClickHouse both treat `\` as an
  -- escape character inside single-quoted literals — a raw `\` in the value
  -- would swallow the next char (e.g. `a\b` reads as `a` + backspace).
  if dialect == "mysql" or dialect == "mariadb" or dialect == "clickhouse" then
    s = s:gsub("\\", "\\\\")
  end
  return "'" .. s .. "'"
end

return M