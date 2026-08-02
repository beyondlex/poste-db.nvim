local sort = require("poste-sql.buffer.nav_sort")
local D = require("poste-sql.dataset")

describe("buffer_nav_sort", function()
  it("cycles sort state and reset", function()
    local tab = { sort = nil }
    local next_sort, is_reset = sort.next_sort_state(tab, 2)
    assert.same({ col = 2, ascending = true }, next_sort)
    assert.is_false(is_reset)

    tab.sort = next_sort
    next_sort, is_reset = sort.next_sort_state(tab, 2)
    assert.same({ col = 2, ascending = false }, next_sort)
    assert.is_false(is_reset)

    tab.sort = next_sort
    next_sort, is_reset = sort.next_sort_state(tab, 2)
    assert.is_nil(next_sort)
    assert.is_true(is_reset)
  end)

  it("prepares current column sort payload", function()
    local saved_compute = D.compute_view_indices
    local saved_builder = sort.build_sort_render_payload
    local computed = false

    D.compute_view_indices = function(tab)
      computed = true
    end
    sort.build_sort_render_payload = function(tab, data, active_idx)
      return { "x" }, { type = "resultset" }, { keep_tabs = true, tab_index = active_idx }
    end

    local ok, err = pcall(function()
      local tab = { sort = nil }
      local data = { results = { { rows = { { 1 }, { 2 } } } } }
      local lines, meta, opts = sort.prepare_current_col_sort(tab, data, 3, 2)

      assert.is_true(computed)
      assert.same({ col = 2, ascending = true }, tab.sort)
      assert.same(data.results[1].rows, tab.rows_source)
      assert.same({ "x" }, lines)
      assert.same({ type = "resultset" }, meta)
      assert.same({ keep_tabs = true, tab_index = 3 }, opts)
    end)

    D.compute_view_indices = saved_compute
    sort.build_sort_render_payload = saved_builder
    assert.is_true(ok, err)
  end)
end)
