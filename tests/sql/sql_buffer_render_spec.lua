local render = require("poste-sql.buffer.render")

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
    assert.is_not_nil(tab.header_col_starts[1])
    assert.equals(3, tab.header_col_starts[1].disp_start)
  end)
end)
