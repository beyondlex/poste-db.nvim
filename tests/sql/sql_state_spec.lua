local state = require("poste-db.state")

describe("poste-db.state defaults", function()
  it("exposes default context", function()
    assert.same({ connection = nil, database = nil }, state.context)
  end)

  it("exposes nil last_dataset", function()
    assert.is_nil(state.last_dataset)
  end)

  it("exposes empty pagination", function()
    assert.same({}, state.pagination)
  end)

  it("exposes default cell position", function()
    assert.same({ row = 1, col = 1 }, state.cell)
  end)

  it("exposes toggle flags", function()
    assert.is_true(state.highlight_cell)
    assert.is_false(state._hide_header_float)
    assert.is_false(state._hide_row_numbers)
    assert.is_false(state._trace)
    assert.is_false(state._raw_mode)
  end)

  it("exposes db_browser connection nil", function()
    assert.same({ connection = nil }, state.db_browser)
  end)

  it("exposes empty icons table", function()
    assert.same({}, state.icons)
  end)
end)