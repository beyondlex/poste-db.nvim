--- Column type classification, shared by the import mapper (`import/mapping.lua`)
--- and the DML generators (`dml.lua`). Both have to answer the same question —
--- *does this column hold numbers?* — and introspection spells types with
--- dialect suffixes and spaces (`numeric(10,2)`, `double precision`, `INT4`), so
--- the lookup is on the leading word of the lowercased name.

local M = {}

local INTEGER = {
  integer = true, int = true, int2 = true, int4 = true, int8 = true,
  smallint = true, bigint = true, serial = true, bigserial = true,
  smallserial = true,
  tinyint = true, mediumint = true,
  -- ClickHouse/MySQL spell their widths into the name (`UInt64`, `Int32`). The
  -- root lookup drops the digits, so `uint` and `int` cover the whole family.
  uint = true,
}

local NUMERIC = vim.tbl_extend("force", INTEGER, {
  numeric = true, decimal = true, dec = true, fixed = true,
  float = true, float4 = true, float8 = true, double = true, real = true,
  money = true, smallmoney = true, oid = true,
})

--- Is this a column that holds numbers? An empty type means "introspection did
--- not tell us", which reads as numeric: that is the older, permissive behavior
--- the callers relied on before the type was plumbed through, and a digit string
--- reaching a column of unknown type is far more often meant as a number.
--- @param ctype string already lowercased
function M.is_numeric(ctype)
  if ctype == "" then return true end
  local root = ctype:match("^%a[%a_]*")
  return root == nil or NUMERIC[root] == true
end

--- Exact-name integer test, for the "an integer column was handed a fraction"
--- guard: `int4` yes, `numeric(10,2)` and `int4range` no.
--- @param ctype string already lowercased
function M.is_integer_name(ctype) return INTEGER[ctype] == true end

--- Root-word counterpart of `is_numeric`, restricted to the integer table: the
--- same name has to read as an integer to this check as it does to that one, or
--- a ClickHouse `UInt64` cell is numeric enough to parse and not-integer enough
--- to skip the fraction guard. `is_integer_name` stays exact because the import
--- mapper writes its guard around the names it is handed.
--- @param ctype string already lowercased
function M.is_integer(ctype)
  local root = ctype:match("^%a[%a_]*")
  return root ~= nil and INTEGER[root] == true
end

return M
