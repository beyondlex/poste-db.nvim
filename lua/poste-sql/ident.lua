local M = {}

function M.quote(name, dialect, depth)
  depth = depth or 0
  if depth > 10 then return name or "" end
  if not name or name == "" or name == "*" then return name or "" end
  local dot = name:find(".", 1, true)
  if dot then
    local parts = {}
    local prev = 1
    for i = 1, #name do
      if name:sub(i, i) == "." then
        if prev < i then parts[#parts + 1] = name:sub(prev, i - 1) end
        prev = i + 1
      end
    end
    if prev <= #name then parts[#parts + 1] = name:sub(prev) end
    if #parts > 1 then
      for i, p in ipairs(parts) do
        parts[i] = M.quote(p, dialect, depth + 1)
      end
      return table.concat(parts, ".")
    end
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