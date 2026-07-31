local M = {}

local function quote_ident(name, dialect)
  if dialect == "mysql" then
    return "`" .. name .. "`"
  end
  return '"' .. name .. '"'
end

local function quote_schema(schema, dialect)
  if not schema or schema == "" then return "" end
  return quote_ident(schema, dialect) .. "."
end

local function quote_val(val)
  if val == nil or val == vim.NIL then
    return "NULL"
  end
  if type(val) == "string" then
    local expr = val:match("^__expr:(.*)$")
    if expr then return expr end
  end
  if type(val) == "boolean" then
    return val and "TRUE" or "FALSE"
  end
  if type(val) == "number" then
    if val == math.floor(val) then
      return string.format("%d", val)
    end
    return tostring(val)
  end
  if type(val) == "string" then
    local num = tonumber(val)
    if num and val:match("^%-?%d+%.?%d*$") then
      if num == math.floor(num) then
        return string.format("%d", num)
      end
      return tostring(num)
    end
    return "'" .. val:gsub("'", "''") .. "'"
  end
  if type(val) == "table" then
    local ok, encoded = pcall(vim.json.encode, val)
    if ok then
      return "'" .. encoded:gsub("'", "''") .. "'"
    end
    return "NULL"
  end
  return "'" .. tostring(val) .. "'"
end

local function find_pk_columns(columns)
  local pks = {}
  for i, col in ipairs(columns or {}) do
    if col.primary_key then
      pks[#pks + 1] = i
    end
  end
  return pks
end

local function build_where(columns, pk_cols, row_values, dialect)
  if #pk_cols > 0 then
    local parts = {}
    for _, ci in ipairs(pk_cols) do
      local col = columns[ci]
      local val = row_values[ci]
      parts[#parts + 1] = quote_ident(col.name, dialect) .. " = " .. quote_val(val)
    end
    return table.concat(parts, " AND ")
  end
  local parts = {}
  for i, col in ipairs(columns or {}) do
    local val = row_values[i]
    if val ~= nil and val ~= vim.NIL then
      parts[#parts + 1] = quote_ident(col.name, dialect) .. " = " .. quote_val(val)
    end
  end
  return table.concat(parts, " AND ")
end

function M.generate_update(schema, table_name, columns, modifications, row_values, dialect)
  local set_parts = {}
  for _, mod in ipairs(modifications or {}) do
    local col = columns and columns[mod.col]
    if col then
      set_parts[#set_parts + 1] = quote_ident(col.name, dialect) .. " = " .. quote_val(mod.new_val)
    end
  end

  local where = ""
  if row_values then
    local pk_cols = find_pk_columns(columns)
    where = build_where(columns, pk_cols, row_values, dialect)
  end

  local sql = "UPDATE " .. quote_schema(schema, dialect) .. quote_ident(table_name, dialect)
    .. " SET " .. table.concat(set_parts, ", ")
  if where ~= "" then
    sql = sql .. " WHERE " .. where
  end
  return sql .. ";"
end

function M.generate_insert(schema, table_name, columns, row_values, dialect)
  local col_parts = {}
  local val_parts = {}

  for i, col in ipairs(columns or {}) do
    local val = row_values and row_values[i]
    if val ~= "[Auto]" and val ~= nil then
      col_parts[#col_parts + 1] = quote_ident(col.name, dialect)
      val_parts[#val_parts + 1] = quote_val(val)
    end
  end

  return "INSERT INTO " .. quote_schema(schema, dialect) .. quote_ident(table_name, dialect)
    .. " (" .. table.concat(col_parts, ", ") .. ")"
    .. " VALUES (" .. table.concat(val_parts, ", ") .. ");"
end

function M.generate_delete(schema, table_name, columns, row_values, dialect)
  local pk_cols = find_pk_columns(columns)
  local where = build_where(columns, pk_cols, row_values or {}, dialect)
  return "DELETE FROM " .. quote_schema(schema, dialect) .. quote_ident(table_name, dialect)
    .. " WHERE " .. where .. ";"
end

function M.generate_dml(es, tab, dialect)
  local stmts = {}
  if not tab or not tab.layout then return stmts end

  local columns = tab.layout.columns
  local rows_source = tab.rows_source
  if not columns or not rows_source then return stmts end

  local schema = tab.layout.schema or ""
  local table_name = tab.layout.table_name or ""

  local row_mods = {}
  for row_key, mod in pairs(es.modified_cells or {}) do
    local row_idx = tonumber(row_key:match("^(%d+):"))
    if row_idx then
      row_mods[row_idx] = row_mods[row_idx] or {}
      row_mods[row_idx][#row_mods[row_idx] + 1] = mod
    end
  end

  for row_idx, mods in pairs(row_mods) do
    if row_idx <= #rows_source then
      local original_row = {}
      for i = 1, #columns do
        original_row[i] = rows_source[row_idx][i]
      end
      for _, mod in ipairs(mods) do
        original_row[mod.col] = mod.old_val
      end
      stmts[#stmts + 1] = {
        sql = M.generate_update(schema, table_name, columns, mods, original_row, dialect),
        type = "update",
      }
    end
  end

  for row_idx, _ in pairs(es.deleted_rows or {}) do
    if row_idx <= #rows_source then
      stmts[#stmts + 1] = {
        sql = M.generate_delete(schema, table_name, columns, rows_source[row_idx], dialect),
        type = "delete",
      }
    end
  end

  for _, added in ipairs(es.added_rows or {}) do
    local row_values
    if added.row_idx and tab.layout.rows and tab.layout.rows[added.row_idx] then
      row_values = tab.layout.rows[added.row_idx]
    else
      row_values = added.data
    end
    stmts[#stmts + 1] = {
      sql = M.generate_insert(schema, table_name, columns, row_values, dialect),
      type = "insert",
    }
  end

  return stmts
end

return M
