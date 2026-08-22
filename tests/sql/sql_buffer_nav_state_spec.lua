local state = require("poste-db.buffer.nav_state")
local D = require("poste-db.dataset")

describe("buffer_nav_state", function()
  local saved_T = nil

  before_each(function()
    saved_T = require("poste-db.dataset").T
    D.tabs = {}
    D.active_tab_idx = 0
  end)

  after_each(function()
    require("poste-db.dataset").T = saved_T
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

  it("returns resultset data tabs only when data exists", function()
    local tab = { meta = { type = "resultset" }, data = {} }
    D.T = function()
      return tab
    end
    assert.same(tab, state.get_resultset_data_tab())
  end)
end)
