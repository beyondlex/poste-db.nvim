local types = require("poste-db.types")

describe("types is_numeric", function()
  it("recognizes numeric types whatever the dialect suffixes them with", function()
    -- introspection hands back the declared name, modifiers and all
    for _, t in ipairs({
      "int", "int4", "INT8", "integer", "bigint", "smallint", "serial",
      "numeric(10,2)", "decimal", "double precision", "float8", "real",
      "money", "uint64", "int32", "mediumint",
    }) do
      assert.is_true(types.is_numeric(t:lower()), t)
    end
  end)

  it("says no to the types that hold text, dates, and everything else", function()
    for _, t in ipairs({
      "text", "varchar", "character varying(255)", "char", "citext", "name",
      "date", "timestamp with time zone", "uuid", "jsonb", "bytea",
      "numrange", "daterange", "boolean", "interval", "array",
    }) do
      assert.is_false(types.is_numeric(t:lower()), t)
    end
  end)

  it("treats a missing type as numeric", function()
    -- callers that never learned the column type must keep working the way
    -- they did before the type was plumbed through
    assert.is_true(types.is_numeric(""))
  end)

  it("pins the limit of the root-word lookup: int4range reads as numeric", function()
    -- the root ends at the first digit, so `int4range` matches `int`. Nothing
    -- can be corrupted by it: a digit cell is not a range, so the INSERT fails
    -- whether the literal is bare or quoted.
    assert.is_true(types.is_numeric("int4range"))
  end)

  it("takes the caller's contract: unwrap first, then classify", function()
    -- ClickHouse spells a nullable Int32 `Nullable(Int32)`, whose root word is
    -- `nullable`. The lookup stays narrow here and the unwrap is its own step,
    -- so each path (the renderer's normalization, the import mapper) applies it
    -- once instead of every classifier second-guessing its input.
    assert.is_false(types.is_numeric("nullable(int32)"))
    assert.is_true(types.is_numeric(types.unwrap_modifier("nullable(int32)")))
  end)
end)

describe("types unwrap_modifier", function()
  local function unwrapped(name)
    return types.unwrap_modifier(name:lower())
  end

  it("reveals the type a ClickHouse modifier wraps", function()
    assert.equals("int32", unwrapped("Nullable(Int32)"))
    assert.equals("uint64", unwrapped("Nullable(UInt64)"))
    assert.equals("string", unwrapped("LowCardinality(String)"))
  end)

  it("unwraps nested modifiers down to the innermost type", function()
    assert.equals("string", unwrapped("LowCardinality(Nullable(String))"))
    assert.equals("uuid", unwrapped("LowCardinality(Nullable(Nullable(UUID)))"), "repeats until stable")
  end)

  it("leaves the wrapped type's own parameters intact", function()
    assert.equals("datetime64(3)", unwrapped("Nullable(DateTime64(3))"))
    assert.equals("decimal(10, 2)", unwrapped("Nullable(Decimal(10, 2))"))
  end)

  it("does not unwrap containers, whose element type is not the column's type", function()
    for _, name in ipairs({ "Array(Int32)", "Map(String, UInt8)", "Tuple(Int32, String)" }) do
      assert.equals(name:lower(), unwrapped(name), name)
    end
  end)

  it("is idempotent, and quiet about the names it cannot unwrap", function()
    for _, name in ipairs({ "int32", "", "text", "nullable(int32" }) do
      assert.equals(name, unwrapped(name), "unmatched parentheses are left as the name they are")
      assert.equals(name, types.unwrap_modifier(unwrapped(name)))
    end
  end)
end)

describe("types is_integer", function()
  it("matches on the root word, the way is_numeric does", function()
    assert.is_true(types.is_integer("integer"))
    assert.is_true(types.is_integer("int4"))
    assert.is_true(types.is_integer("bigint"))
    assert.is_true(types.is_integer("uint64"), "ClickHouse spells the width into the name")
    assert.is_false(types.is_integer("numeric(10,2)"), "a size-tagged decimal is not an int")
    assert.is_false(types.is_integer("double precision"))
    assert.is_false(types.is_integer(""), "no type given is not a claim that it is an int")
  end)

  it("pins what the root word costs: int4range reads as an integer", function()
    -- shares the root with `int4`, so the fraction guard now applies to a range
    -- column too. Nothing is lost: a digit cell is not a range, so the value
    -- stays the text the file said either way
    assert.is_true(types.is_integer("int4range"))
  end)
end)
