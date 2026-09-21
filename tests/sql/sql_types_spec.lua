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

  it("pins the other direction: a wrapped type reads as not numeric", function()
    -- ClickHouse spells a nullable Int32 `Nullable(Int32)`, whose root word is
    -- `nullable`, so a digit cell aimed at it goes out quoted — which is what
    -- the server accepts on insert anyway. Widening the lookup is a change to
    -- make with a spec here, not by surprise.
    assert.is_false(types.is_numeric("nullable(int32)"))
  end)
end)

describe("types is_integer_name", function()
  it("matches whole normalized names only", function()
    assert.is_true(types.is_integer_name("integer"))
    assert.is_true(types.is_integer_name("int4"))
    assert.is_true(types.is_integer_name("bigint"))
    assert.is_false(types.is_integer_name("numeric(10,2)"), "a size-tagged decimal is not an int")
    assert.is_false(types.is_integer_name("int4range"), "shares the root word, holds a range")
    assert.is_false(types.is_integer_name("double precision"))
  end)
end)
