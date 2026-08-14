local M = {}

function M.quote(name, dialect)
  if not name or name == "" or name == "*" then return name or "" end
  if name:find(".") and not name:match("^[%w_]+%.[%w_]+$") then
    local parts = vim.split(name, ".", { plain = true })
    local q = {}
    for _, p in ipairs(parts) do
      q[#q + 1] = M.quote(p, dialect)
    end
    return table.concat(q, ".")
  end
  if dialect == "mysql" then
    return "`" .. name:gsub("`", "``") .. "`"
  end
  return '"' .. name:gsub('"', '""') .. '"'
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
  if dialect == "mysql" then
    s = s:gsub("\\", "\\\\")
  end
  return "'" .. s .. "'"
end

return M