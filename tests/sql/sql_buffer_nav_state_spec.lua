local state = require("poste-sql.buffer_nav_state")
local D = require("poste-sql.dataset")

describe("buffer_nav_state", function()
  before_each(function()
    D.tabs = {}
    D.active_tab_idx = 0
  end)

  it("returns nil helpers for missing tabs", function()
    assert.is_nil(state.get_tab())
    assert.is_nil(state.get_resultset_tab())
  end)

  it("detects dirty and layout/data state", function()
    local tab = { edit_state = { dirty = true }, layout = {}, data = {} }
    assert.is_true(state.is_dirty(tab))
    assert.is_true(state.has_layout(tab))
    assert.is_true(state.has_data(tab))
  end)
end)
