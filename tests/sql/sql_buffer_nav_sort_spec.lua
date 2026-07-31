local sort = require("poste-sql.buffer_nav_sort")

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
end)
