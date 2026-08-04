--- Regression tests for bigint precision in the dataset renderer.
--- Bigints above 2^53 arrive as JSON strings (from poste Rust binary);
--- the renderer must display the exact digits and keep the column
--- right-aligned like any numeric column.

local format = require("poste-sql.format")

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
end)
