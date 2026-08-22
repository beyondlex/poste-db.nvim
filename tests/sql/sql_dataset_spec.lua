local D = require("poste-db.dataset")

describe("dataset compute_view_indices", function()
  before_each(function()
    D.tabs = {}
    D.active_tab_idx = 0
  end)

  it("sorts rows by numeric column ascending", function()
    local tab = D.alloc_tab(1)
    tab.rows_source = {
      { 3, false, "c" },
      { 1, true,  "a" },
      { 2, false, "b" },
    }
    tab.sort = { col = 1, ascending = true }

    D.compute_view_indices(tab)

    assert.same({ 2, 3, 1 }, tab.view_indices)
  end)

  it("sorts rows by boolean column descending", function()
    local tab = D.alloc_tab(1)
    tab.rows_source = {
      { "row1", false },
      { "row2", true },
      { "row3", false },
    }
    tab.sort = { col = 2, ascending = false }

    D.compute_view_indices(tab)

    assert.same({ 2, 1, 3 }, tab.view_indices)
  end)

  it("applies filtered_indices before sorting", function()
    local tab = D.alloc_tab(1)
    tab.rows_source = {
      { 30, "z" },
      { 10, "x" },
      { 20, "y" },
    }
    tab.filtered_indices = { 1, 3 }
    tab.sort = { col = 1, ascending = true }

    D.compute_view_indices(tab)

    assert.same({ 3, 1 }, tab.view_indices)
  end)

  it("uses filtered_indices without sort", function()
    local tab = D.alloc_tab(1)
    tab.rows_source = {
      { "row1" },
      { "row2" },
      { "row3" },
    }
    tab.filtered_indices = { 3, 1 }

    D.compute_view_indices(tab)

    assert.same({ 3, 1 }, tab.view_indices)
  end)

  it("sorts numeric strings numerically (bigints arrive as strings)", function()
    local tab = D.alloc_tab(1)
    tab.rows_source = {
      { "100" },
      { "9" },
      { "2084515900853196878" },
    }
    tab.sort = { col = 1, ascending = true }

    D.compute_view_indices(tab)

    assert.same({ 2, 1, 3 }, tab.view_indices)
  end)
end)
