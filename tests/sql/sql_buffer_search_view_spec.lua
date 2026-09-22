--- Integration spec for the dataset search state after a view change.
---
--- `search_matches` stores VIEW positions, not source rows, so anything that
--- re-derives `view_indices` (sort, filter-by-cell) invalidates it: the
--- winbar's "i/n", the highlights and n/N all read the list as it stands.
--- `recompute_after_view_change` is the shared guard, and the sort path calls
--- it; these tests pin that the filter path does too.
local real_dataset = require("poste-db.dataset")
local format = require("poste-db.format")
local state = require("poste-db.state")

local saved = {
  ["poste-db.dataset"] = package.loaded["poste-db.dataset"],
  ["poste-db.buffer"] = package.loaded["poste-db.buffer"],
  ["poste-db.buffer.nav"] = package.loaded["poste-db.buffer.nav"],
  ["poste-db.buffer.header"] = package.loaded["poste-db.buffer.header"],
  ["poste-db.buffer.page"] = package.loaded["poste-db.buffer.page"],
  ["poste-db.highlights"] = package.loaded["poste-db.highlights"],
  ["poste-db.buffer.search"] = package.loaded["poste-db.buffer.search"],
}

local function make_data()
  return {
    type = "resultset",
    total_rows = 3,
    results = { {
      columns = { { name = "fruit", type = "TEXT" } },
      rows = { { "apple" }, { "banana" }, { "cherry" } },
    } },
    connection = "",
    database = "",
    dialect = "postgres",
  }
end

--- A tab shaped like the one the dataset keeps, with `query` already searched.
local function new_tab(query)
  local data = make_data()
  local _, meta, layout = format.format_resultset(data)
  return {
    data = data,
    meta = meta,
    layout = layout,
    rows_source = data.results[1].rows,
    page = 1,
    page_size = 10,
    num_pages = 1,
    pagination_enabled = false,
    search_text = query,
    search_matches = {},
    search_matches_by_page = {},
    search_total_matches = 0,
    search_idx = 0,
  }
end

describe("buffer_search view changes and search state", function()
  local search, tab, rendered

  before_each(function()
    package.loaded["poste-db.dataset"] = {
      dataset_buffer = nil, -- apply_search_highlights bails out without a buffer
      dataset_window = nil,
      search_ns = vim.api.nvim_create_namespace("poste_db_search_view_spec"),
      active_tab_idx = 1,
      tabs = {},
      T = function() return tab end,
      compute_view_indices = real_dataset.compute_view_indices,
    }
    rendered = 0
    package.loaded["poste-db.buffer"] = {
      render_dataset = function() rendered = rendered + 1 end,
    }
    package.loaded["poste-db.buffer.nav"] = {
      position_cursor = function() return "│ apple │" end,
    }
    package.loaded["poste-db.buffer.header"] = { update = function() end }
    package.loaded["poste-db.buffer.page"] = { refresh_page = function() end }
    package.loaded["poste-db.highlights"] = {
      find_cell_range = function() return nil end,
      highlight_cell = function() end,
    }
    package.loaded["poste-db.buffer.search"] = nil
    search = require("poste-db.buffer.search")
  end)

  after_each(function()
    for name, mod in pairs(saved) do package.loaded[name] = mod end
  end)

  it("filtering by a cell drops matches for the rows the filter removed", function()
    -- "an" matches only view row 2 (banana). Filtering the view down to row 1
    -- (apple) leaves nothing for the query to hit, so that stale match has to
    -- go: the winbar would otherwise advertise a match that n/N walks to a view
    -- position which is no longer on screen
    tab = new_tab("an")
    search.recompute_after_view_change()
    assert.equals(1, tab.search_total_matches, "the search starts out matching banana")

    state.cell.row, state.cell.col = 1, 1
    search.filter_by_current_cell()

    assert.equals(1, #tab.view_indices, "the filter narrowed the view to apple")
    assert.equals(0, tab.search_total_matches)
    assert.equals(0, #tab.search_matches)
    assert.equals(0, tab.search_idx)
    assert.equals(1, rendered, "and the narrowed view was rendered")
  end)

  it("keeps a match that survives the filter, at its new view position", function()
    -- the other half: the query still hits the filtered row, and the match must
    -- be re-derived rather than dropped — including its view position, which
    -- the pre-filter list recorded as 1 only because that row was first
    tab = new_tab("err")
    search.recompute_after_view_change()
    assert.equals(1, tab.search_total_matches)
    assert.equals(3, tab.search_matches[1].row, "cherry is view row 3 before the filter")

    state.cell.row, state.cell.col = 3, 1
    search.filter_by_current_cell()

    assert.equals(1, #tab.view_indices)
    assert.equals(1, tab.search_total_matches)
    assert.equals(1, tab.search_matches[1].row, "the only row left is now view row 1")
  end)

  it("clearing the filter leaves no search state behind", function()
    tab = new_tab("an")
    search.recompute_after_view_change()
    tab.filter_active = true
    tab.filter_col = 1

    search.clear_filter_search()

    assert.is_falsy(tab.filter_active)
    assert.is_nil(tab.filter_col)
    assert.is_nil(tab.search_text)
    assert.equals(0, #tab.search_matches)
    assert.equals(0, tab.search_total_matches)
  end)

  it("n and N walk the match list and wrap at both ends", function()
    -- the arithmetic lives in next/prev_search_match and had no test: `n` steps
    -- forward from the current index, `N` backward, and both wrap. The walk
    -- starts from a state the module itself produced, so the offset is pinned
    -- against a real `search_idx` rather than a hand-set one
    tab = new_tab("a")
    search.recompute_after_view_change()
    assert.equals(2, tab.search_total_matches, "apple and banana carry an a")
    assert.equals(1, tab.search_idx, "the recompute jumped to the first match")

    search.next_search_match()
    assert.equals(2, tab.search_idx)
    search.next_search_match()
    assert.equals(1, tab.search_idx, "n past the last match wraps to the first")
    search.prev_search_match()
    assert.equals(2, tab.search_idx, "N before the first wraps to the last")
    search.prev_search_match()
    assert.equals(1, tab.search_idx)
  end)
end)
