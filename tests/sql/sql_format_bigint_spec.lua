--- Regression tests for bigint precision in the dataset renderer.
--- Bigints above 2^53 arrive as JSON strings (from poste Rust binary);
--- the renderer must display the exact digits and keep the column
--- right-aligned like any numeric column.

local format = require("poste-db.format")

describe("format bigint precision", function()
  it("renders the exact bigint string in a dataset cell", function()
    local body = vim.json.encode({
      type = "resultset",
      total_rows = 1,
      results = {
        {
          columns = {
            { name = "id", type = "INT8" },
            { name = "name", type = "TEXT" },
          },
          rows = {
            { "2084515900853196878", "alice" },
          },
        },
      },
      connection = "",
      database = "",
      dialect = "postgres",
    })

    local lines, meta = format.format_dataset({ body = body })

    assert.equals("resultset", meta.type)
    local rendered = table.concat(lines, "\n")
    assert.is_true(rendered:find("2084515900853196878", 1, true) ~= nil, "must contain exact bigint digits")
    assert.is_false(rendered:find("2084515900853196800", 1, true) ~= nil, "must not contain rounded value")
  end)

  it("right-aligns a bigint column whose values are strings", function()
    local data = {
      type = "resultset",
      total_rows = 2,
      results = {
        {
          columns = {
            { name = "id", type = "INT8" },
          },
          rows = {
            { "2084515900853196878" },
            { 1 },
          },
        },
      },
      connection = "",
      database = "",
      dialect = "postgres",
    }

    local layout = format.plan_resultset_layout(data)

    assert.is_true(layout.numeric_cols[2], "bigint column should be flagged numeric for right-alignment")
  end)

  it("flags a size-tagged or dialect-spelled numeric declaration for alignment", function()
    -- the alignment question is the same one the import mapper and the DML
    -- generators ask, so it now goes through the same root-word lookup:
    -- `decimal(10,2)` and ClickHouse's `UInt64` align like the bare name does,
    -- and a text column full of digit strings still does not
    local layout = format.plan_resultset_layout({
      type = "resultset",
      total_rows = 1,
      results = { {
        columns = {
          { name = "amount", type = "decimal(10,2)" },
          { name = "counter", type = "UInt64" },
          { name = "zip", type = "varchar(10)" },
        },
        rows = { { "10.50", "18446744073709551615", "10001" } },
      } },
      connection = "",
      database = "",
      dialect = "mysql",
    })
    -- [1] is the row-number gutter, so the columns start at [2]
    assert.is_true(layout.numeric_cols[2])
    assert.is_true(layout.numeric_cols[3])
    assert.is_false(layout.numeric_cols[4], "a text column of digits is left-aligned like text")
  end)

  it("keeps a float column right-aligned when a row is Infinity", function()
    -- the binary sends a non-finite double as text because JSON has no spelling
    -- for it, so the display path sees "Infinity" in a `float8` column. A row
    -- of it must not cost the whole column the alignment its type declares.
    local layout = format.plan_resultset_layout({
      type = "resultset",
      total_rows = 2,
      results = { {
        columns = { { name = "ratio", type = "float8" } },
        rows = { { "Infinity" }, { 1.5 } },
      } },
      connection = "",
      database = "",
      dialect = "postgres",
    })
    assert.is_true(layout.numeric_cols[2], "an Infinity row still belongs in a right-aligned float column")
  end)

  it("does not let the Infinity spelling right-align a text column", function()
    -- the spelling is only an exemption for a column whose own type is
    -- numeric; a varchar of "Infinity"/"NaN" is text and stays left-aligned
    local layout = format.plan_resultset_layout({
      type = "resultset",
      total_rows = 1,
      results = { {
        columns = { { name = "note", type = "text" } },
        rows = { { "Infinity" } },
      } },
      connection = "",
      database = "",
      dialect = "postgres",
    })
    assert.is_false(layout.numeric_cols[2])
  end)

  it("accepts ClickHouse's bare inf and nan spellings in a float column", function()
    -- ClickHouse returns every value as text and spells these without the
    -- quotes the SQL engines print, so the alignment check has to know both
    local layout = format.plan_resultset_layout({
      type = "resultset",
      total_rows = 2,
      results = { {
        columns = { { name = "ratio", type = "Float64" } },
        rows = { { "nan" }, { "-inf" } },
      } },
      connection = "",
      database = "",
      dialect = "clickhouse",
    })
    assert.is_true(layout.numeric_cols[2])
  end)

  it("formats floats with a capped decimal precision", function()
    assert.equals("578.472", format.format_number(578.47196567559))
    assert.equals("123.45", format.format_number(123.45))
    assert.equals("3.1416", format.format_number(math.pi))
    -- tiny magnitudes stay significant, not rounded to 0
    assert.equals("1.2345e-06", format.format_number(0.0000012345))
    -- integers keep their exact form
    assert.equals("120000000", format.format_number(120000000))
    assert.equals("2", format.format_number(2))
  end)
end)

describe("format ClickHouse type modifiers", function()
  local function plan(col_type, values)
    local rows = {}
    for _, v in ipairs(values) do rows[#rows + 1] = { v } end
    return format.plan_resultset_layout({
      type = "resultset",
      total_rows = #rows,
      results = { { columns = { { name = "c", type = col_type } }, rows = rows } },
      connection = "",
      database = "",
      dialect = "clickhouse",
    })
  end

  it("sees the integer inside Nullable(Int32)", function()
    -- ClickHouse writes a nullable column's type as `Nullable(Int32)`, and the
    -- classifier reads the leading word: without the modifier coming off, every
    -- such column reads as text, and a ClickHouse table of nullable numbers is
    -- mostly such columns.
    local layout = plan("Nullable(Int32)", { 7, 42 })
    assert.equals("int32", layout.columns[1].ctype)
    assert.is_true(layout.numeric_cols[2])
  end)

  it("sees the integer inside a wrapped UInt64", function()
    local layout = plan("Nullable(UInt64)", { "18446744073709551615", 42 })
    assert.equals("uint64", layout.columns[1].ctype)
    assert.is_true(layout.numeric_cols[2])
  end)

  it("unwraps stacked modifiers down to the type they wrap", function()
    local layout = plan("LowCardinality(Nullable(String))", { "a", "b" })
    assert.equals("string", layout.columns[1].ctype, "the wrapped name normalizes like the bare one does")
    assert.is_false(layout.numeric_cols[2])
  end)

  it("keeps the exemption for non-finite text after unwrapping", function()
    local layout = plan("Nullable(Float64)", { "Infinity", 1.5 })
    assert.is_true(layout.numeric_cols[2])
  end)

  it("does not turn wrapped text into a number", function()
    -- the unwrap must not be a licence: what comes out is still classified on
    -- its own merits, so a nullable text column of digits stays text
    local layout = plan("Nullable(String)", { "007", "42" })
    assert.is_false(layout.numeric_cols[2])
  end)

  it("leaves container types alone", function()
    -- `Array(Int32)` holds a list, not a number: unwrapping a modifier stops
    -- where the containers begin
    local layout = plan("Array(Int32)", { "1", "2" })
    assert.equals("array(int32)", layout.columns[1].ctype)
    assert.is_false(layout.numeric_cols[2])
  end)
end)

describe("format affected rows", function()
  it("keeps the connection line out of the content and in the meta", function()
    local body = vim.json.encode({
      type = "affected",
      results = { { affected_rows = 5, execution_time_ms = 10 } },
      connection = "mysql://user:pass@localhost:13306/blog",
      database = "blog",
      dialect = "mysql",
    })
    local lines, meta = format.format_dataset({ body = body })

    assert.equals("affected", meta.type)
    assert.equals("mysql://user:pass@localhost:13306/blog", meta.connection)
    assert.equals("blog", meta.database)
    assert.same({ "", "  5 row(s) affected · 10ms", "" }, lines)
    local rendered = table.concat(lines, "\n")
    assert.is_nil(rendered:find("localhost:13306", 1, true))
    assert.is_nil(rendered:find("/ blog", 1, true))
  end)
end)
