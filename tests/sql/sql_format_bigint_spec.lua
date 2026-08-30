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
