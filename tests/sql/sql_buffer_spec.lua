local buffer = require("poste-sql.buffer")
local D = require("poste-sql.dataset")

describe("buffer header test helpers", function()
  before_each(function()
    buffer._test.reset()
  end)

  it("stores header text and header index", function()
    buffer._test.set_header("│ id │ name │")
    local tab = D.tabs[1]
    assert.is_not_nil(tab)
    assert.equals("│ id │ name │", tab.header_text)
    assert.same({ 3, 10, 19 }, vim.tbl_map(function(entry) return entry.bs end,
      vim.tbl_filter(function(entry) return entry.sep end, tab.header_index)))
  end)

  it("clears tab state on reset", function()
    buffer._test.create_tab(1, { header_text = "header", header_index = { 1 } })
    buffer._test.reset()

    assert.equals(0, buffer._test.tab_count())
    assert.equals(0, buffer._test.active_tab_idx())
    assert.is_nil(D.T())
  end)

  it("normalizes resultset header and padding", function()
    local tab = buffer._test.create_tab(1)
    local padded, out_meta = buffer._test.normalize_rendered_page(tab, {
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
    assert.equals(2, out_meta.data_start_line)
    assert.equals(2, out_meta.data_end_line)
    assert.equals("│ id │", tab.header_text)
  end)

  it("normalizes non-resultset lines without inserting header padding", function()
    local tab = buffer._test.create_tab(1)
    local padded, out_meta = buffer._test.normalize_rendered_page(tab, {
      "hello",
      "world",
    }, { type = "raw" })

    assert.same({ "  hello", "  world" }, padded)
    assert.equals("raw", out_meta.type)
  end)
end)
