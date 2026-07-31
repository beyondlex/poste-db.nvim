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
end)
