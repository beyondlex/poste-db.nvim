--- Page-count bookkeeping. `num_pages`/`page` are read by the winbar, by
--- H/L/g g/G, and (through `buffer.search`'s is_paginated) by search
--- highlighting, so they have to describe the rows that actually exist — the
--- view shrinks under a filter or sort without any paginated render path
--- running again.
local D = require("poste-db.dataset")
local page = require("poste-db.buffer.page")

describe("dataset.apply_page_bounds", function()
  local function tab_for(page_size)
    return { page_size = page_size, page = 1, num_pages = 1 }
  end

  it("counts a partial last page", function()
    local cases = { { 200, 4 }, { 101, 3 }, { 100, 2 }, { 51, 2 }, { 50, 1 }, { 1, 1 } }
    for _, c in ipairs(cases) do
      local tab = tab_for(50)
      assert.equals(c[2], D.apply_page_bounds(tab, c[1]), c[1] .. " rows")
      assert.equals(c[2], tab.num_pages)
      assert.equals(1, tab.page)
    end
  end)

  it("pulls the current page back inside the count", function()
    -- 200 rows puts you on page 4; a filter that leaves 10 makes page 4 vanish
    local tab = tab_for(50)
    tab.num_pages, tab.page = 4, 4
    assert.equals(1, D.apply_page_bounds(tab, 10))
    assert.equals(1, tab.num_pages)
    assert.equals(1, tab.page)
  end)

  it("treats a missing or empty row count as one page", function()
    -- render_dataset used to compare `nil > page_size` here and error out
    local tab = tab_for(50)
    tab.page = 3
    assert.equals(1, D.apply_page_bounds(tab, nil))
    assert.equals(1, tab.num_pages)
    assert.equals(1, tab.page)
    assert.equals(1, D.apply_page_bounds(tab_for(50), 0))
  end)

  it("keeps a page that is still reachable", function()
    local tab = tab_for(50)
    tab.page = 2
    assert.equals(4, D.apply_page_bounds(tab, 200))
    assert.equals(2, tab.page)
  end)

  it("clamps a page below the first", function()
    local tab = tab_for(50)
    tab.page = 0
    D.apply_page_bounds(tab, 200)
    assert.equals(1, tab.page)
  end)
end)

describe("buffer.page.refresh_page", function()
  local saved = {
    tabs = D.tabs,
    active_tab_idx = D.active_tab_idx,
    dataset_window = D.dataset_window,
    format = package.loaded["poste-db.format"],
    buffer = package.loaded["poste-db.buffer"],
    notify = vim.notify,
  }
  local tab, renders

  before_each(function()
    vim.notify = function() end -- toggle_pagination reports through it
    tab = {
      layout = { rows = {}, columns = { { name = "id", type = "int" } }, total_rows = 200 },
      meta = { table_name = "t" },
      page = 1, page_size = 50, num_pages = 1,
      pagination_enabled = true,
      cursor = { row = 1, col = 1 },
      view_indices = nil,
    }
    D.tabs = { tab }
    D.active_tab_idx = 1
    D.dataset_window = 1000 -- refresh_page only needs it to exist
    renders = {}
    package.loaded["poste-db.format"] = {
      render_page = function(_, p, size)
        renders[#renders + 1] = { fn = "render_page", page = p, size = size }
        return { "line" }, { type = "resultset" }
      end,
      render_view = function(_, _, p, size)
        renders[#renders + 1] = { fn = "render_view", page = p, size = size }
        return { "line" }, { type = "resultset" }
      end,
    }
    package.loaded["poste-db.buffer"] = {
      apply_rendered_page = function() end,
    }
  end)

  after_each(function()
    vim.notify = saved.notify
    D.tabs = saved.tabs
    D.active_tab_idx = saved.active_tab_idx
    D.dataset_window = saved.dataset_window
    package.loaded["poste-db.format"] = saved.format
    package.loaded["poste-db.buffer"] = saved.buffer
  end)

  it("renders one page and counts the pages the view fills", function()
    tab.page = 3
    page.refresh_page()
    assert.equals(1, #renders)
    assert.equals("render_page", renders[1].fn)
    assert.equals(3, renders[1].page)
    assert.equals(50, renders[1].size)
    assert.equals(4, tab.num_pages)
    assert.equals(50, tab.visible_rows)
  end)

  it("resets the count when a filter shrinks the view below a page", function()
    tab.page = 4
    tab.num_pages = 4
    tab.view_indices = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
    page.refresh_page()
    -- the whole filtered view is on screen, so the buffer holds one page:
    -- advertising 4 while H/L walked 2..4 repainted the same rows
    assert.equals(1, tab.num_pages, "stale page count")
    assert.equals(1, tab.page)
    assert.equals("render_view", renders[1].fn)
    assert.equals(10, renders[1].size, "renders every row, not one page")
    assert.equals(10, tab.visible_rows)
  end)

  it("and when pagination is switched off", function()
    page.toggle_pagination() -- on -> off; the toggle refreshes once itself
    assert.is_false(tab.pagination_enabled)
    renders = {}
    page.refresh_page()
    assert.equals(4, tab.num_pages, "200 rows are still 4 pages worth of rows")
    assert.equals(200, renders[1].size)
    assert.equals(200, tab.visible_rows)
  end)
end)
