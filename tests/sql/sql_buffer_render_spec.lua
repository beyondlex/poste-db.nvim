local render = require("poste-db.buffer.render")

describe("buffer_render", function()
  it("normalizes a resultset page with header", function()
    local tab = {}
    local padded, meta = render.normalize_rendered_page(tab, {
      "┌────┐",
      "│ id │",
      "├────┤",
      "│ 1  │",
      "└────┘",
    }, {
      type = "resultset",
      header_line = 2,
      data_start_line = 4,
      data_end_line = 4,
      row_count = 1,
    })

    assert.equals("", padded[1])
    assert.equals("  │ 1  │", padded[#padded])
    assert.equals(2, meta.data_start_line)
    assert.equals(2, meta.data_end_line)
    assert.equals("│ id │", tab.header_text)
  end)

  it("builds buffer column start maps", function()
    local tab = {}
    render.build_column_start_maps(tab, {
      data_start_line = 4,
      col_starts = {
        {
          { ext_start = 1, ext_end = 3 },
          { ext_start = 5, ext_end = 8 },
        },
      },
      col_widths = { 2, 3 },
      header_col_starts = {
        { ext_start = 1, ext_end = 3 },
        { ext_start = 5, ext_end = 8 },
      },
    })

    assert.is_not_nil(tab.buffer_col_starts[4])
    assert.equals(4, tab.buffer_col_starts[4][1].disp_start)
    assert.equals(7, tab.buffer_col_starts[4][1].disp_end)
  end)

  it("inserts the sort indicator without corrupting the header text", function()
    local tab = { sort = { col = 1, ascending = true } }
    local _, meta = render.normalize_rendered_page(tab, {
      "┌──────────────┐",
      "│ # │ id    │ name   │",
      "├──────────────┤",
      "│ 1 │ 2     │ 3      │",
      "└──────────────┘",
    }, {
      type = "resultset",
      header_line = 2,
      data_start_line = 4,
      data_end_line = 4,
      row_count = 1,
    })
    assert.truthy(tab.header_text:find(" ↑", 1, true))
    assert.is_not_nil(tab.header_index)
    local sep_count = 0
    for _, c in ipairs(tab.header_index) do
      if c.sep then sep_count = sep_count + 1 end
    end
    assert.equals(4, sep_count, "indicator insertion must not eat a column separator")
  end)
end)
