--- Column type classification, shared by everything that has to answer the same
--- question — *does this column hold numbers?*: the import mapper
--- (`import/mapping.lua`), the DML generators (`dml.lua`), the cell editor
--- (`editor/cell.lua`) and the dataset renderer's alignment (`format.lua`).
--- Introspection spells types with dialect suffixes and spaces (`numeric(10,2)`,
--- `double precision`, `INT4`) and ClickHouse wraps them in modifiers
--- (`Nullable(Int32)`), so the lookup is on the leading word of the unwrapped,
--- lowercased name.

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
--- @param ctype string already lowercased, modifiers already unwrapped
function M.is_numeric(ctype)
  if ctype == "" then return true end
  local root = ctype:match("^%a[%a_]*")
  return root == nil or NUMERIC[root] == true
end

-- ClickHouse wraps a type in modifiers that say nothing about what it holds:
-- `Nullable(Int32)` is an integer that may be missing, `LowCardinality(String)`
-- is text. Every classifier here keys on the leading word, so a wrapped name
-- reads as its wrapper (`Nullable` is not numeric) unless the wrapper comes off
-- first. Containers are *not* modifiers — an `Array(Int32)` column holds a list,
-- and it holds it whether or not the element type is numeric.
local MODIFIERS = { "^nullable%((.+)%)$", "^lowcardinality%((.+)%)$" }

--- Strip ClickHouse's type modifiers, outermost first. They nest
--- (`LowCardinality(Nullable(String))`), so this repeats until the name stops
--- changing.
--- @param ctype string already lowercased
--- @return string
function M.unwrap_modifier(ctype)
  local previous
  repeat
    previous = ctype
    for _, pattern in ipairs(MODIFIERS) do
      -- greedy `.+` so a parameterized inner type keeps its own parentheses
      -- (`nullable(datetime64(3))` -> `datetime64(3)`, not `datetime64(3`)
      local inner = ctype:match(pattern)
      if inner then ctype = inner end
    end
  until ctype == previous
  return ctype
end

--- Root-word integer test: the same name has to read as an integer to this check
--- as `is_numeric` reads it as numeric, or a ClickHouse `UInt64` cell is numeric
--- enough to parse and not-integer enough to skip the "an integer column was
--- handed a fraction" guard — which is the guard's whole point, since rounding
--- it silently stores something the file did not say.
--- @param ctype string already lowercased, modifiers already unwrapped
function M.is_integer(ctype)
  local root = ctype:match("^%a[%a_]*")
  return root ~= nil and INTEGER[root] == true
end

return M
