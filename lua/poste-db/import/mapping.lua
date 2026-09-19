local M = {}

local INTEGER_TYPES = {
  integer = true, int = true, int2 = true, int4 = true, int8 = true,
  smallint = true, bigint = true, serial = true, bigserial = true,
  tinyint = true, mediumint = true,
}

--- Root type names that hold numbers. Introspection reports `numeric(10,2)` or
--- `double precision`, so only the leading word is looked up.
local NUMERIC_TYPES = vim.tbl_extend("force", INTEGER_TYPES, {
  numeric = true, decimal = true, dec = true, fixed = true,
  float = true, float4 = true, float8 = true, double = true, real = true,
  money = true, smallmoney = true, oid = true,
})

local function is_numeric_col(ctype)
  if ctype == "" then return true end
  local root = ctype:match("^%a[%a_]*")
  return root == nil or NUMERIC_TYPES[root] == true
end

--- A double carries 53 bits of mantissa, so `9050341234567890123` arrives back as
--- `…889920` — the digits themselves move. Past that range the text must stay text;
--- dml then emits its exact digits rather than the corrupted number.
local MAX_EXACT_DOUBLE = 2 ^ 53

function M.coerce_value(str, col_type)
  if str == nil or str == vim.NIL then return vim.NIL end
  local s = tostring(str):gsub("^%s+", ""):gsub("%s+$", "")

  if s == "" then return nil end

  -- NULL/true/false literals match case-insensitively: CSV exports write
  -- NULL (databases), null (JSON tools), True/False (Python csv), and only
  -- the all-lower and all-upper spellings used to coerce.
  local lower = s:lower()
  if lower == "null" or lower == "(null)" then return vim.NIL end

  local ctype = (col_type or ""):lower()
  if lower == "true" then return true end
  if lower == "false" then return false end
  if ctype == "boolean" or ctype == "bool" then
    if s == "1" then return true end
    if s == "0" then return false end
  end

  -- A digit-string becomes a number only when the column holds numbers (`007`
  -- in a varchar column is the text `007`), the value fits a double, and an
  -- integer column is not being handed a fraction.
  local num = tonumber(s)
  if num and s:match("^%-?%d+%.?%d*$")
    and is_numeric_col(ctype)
    and math.abs(num) < MAX_EXACT_DOUBLE
    and not (INTEGER_TYPES[ctype] and num ~= math.floor(num)) then
    return num
  end

  return s
end

function M.build_column_map(parsed_cols, table_cols)
  local col_map = {}
  local unmatched_import = {}
  local matched_table = {}
  local unmatched_table = {}

  for ii, name in ipairs(parsed_cols) do
    local found = false
    for ti, tc in ipairs(table_cols) do
      if tc.name:lower() == name:lower() then
        table.insert(col_map, {
          import_idx = ii,
          import_name = name,
          table_col = tc,
          table_idx = ti,
        })
        matched_table[ti] = true
        found = true
        break
      end
    end
    if not found then
      table.insert(unmatched_import, name)
    end
  end

  for ti, tc in ipairs(table_cols) do
    if not matched_table[ti] then
      table.insert(unmatched_table, tc)
    end
  end

  return col_map, unmatched_import, unmatched_table
end

function M.build_row_values(import_row, col_map, num_table_cols)
  local row_values = {}
  for i = 1, num_table_cols do
    row_values[i] = nil
  end
  for _, mc in ipairs(col_map) do
    row_values[mc.table_idx] = import_row[mc.import_idx]
  end
  return row_values
end

function M.normalize_columns(table_cols)
  local cols = {}
  for _, tc in ipairs(table_cols) do
    table.insert(cols, {
      name = tc.name,
      type = tc.col_type,
      primary_key = tc.is_pk,
    })
  end
  return cols
end

function M.validate_and_type(import_rows, col_map, table_cols, unmatched_table)
  local valid = {}
  local bad = {}

  for ri, import_row in ipairs(import_rows) do
    local row_vals = M.build_row_values(import_row, col_map, #table_cols)
    local row_errors = {}

    for _, mc in ipairs(col_map) do
      local raw_val = import_row[mc.import_idx]
      local coerced = M.coerce_value(raw_val, mc.table_col.col_type)
      row_vals[mc.table_idx] = coerced

      if mc.table_col.is_pk and (coerced == nil or coerced == vim.NIL) then
        if not (mc.table_col.extra and mc.table_col.extra:find("auto", 1, true)) then
          table.insert(row_errors, string.format("  %s: primary key column '%s' cannot be null",
            ri + 1, mc.table_col.name))
        end
      end
    end

    if #row_errors > 0 then
      table.insert(bad, { row_idx = ri + 1, import_row = import_row, errors = row_errors })
    else
      table.insert(valid, row_vals)
    end
  end

  return valid, bad
end

return M
