local D = require("poste-sql.dataset")
local nav = require("poste-sql.buffer.nav")
local ui = require("poste-sql.buffer.nav_ui")
local state = require("poste.state")

describe("buffer_nav helpers", function()
  before_each(function()
    D.tabs = {}
    D.active_tab_idx = 0
  end)

  it("build_header_index records UTF-8 separator byte positions", function()
    local idx = nav._test.build_header_index("  │ id │ name │")
    local seps = {}
    for _, entry in ipairs(idx) do
      if entry.sep then
        seps[#seps + 1] = entry.bs
      end
    end
    assert.same({ 3, 10, 19 }, seps)
  end)

  it("build_status_winbar includes the main status fragments", function()
    local tab = D.alloc_tab(1)
    tab.sort = { col = 2, ascending = false }
    tab.pagination_enabled = true
    tab.page = 2
    tab.num_pages = 3
    tab.layout = {}
    tab.filter_active = true
    tab.filter_col_name = "status"
    tab.filter_val = "open"
    tab.search_text = "needle"
    tab.search_matches = { { row = 1, col = 1 }, { row = 2, col = 2 } }
    tab.search_idx = 2
    tab.edit_state = { dirty = false }
    D.active_tab_idx = 1

    local meta = {
      type = "resultset",
      total_rows = 12,
      total_execution_time_ms = 7,
      table_name = "posts",
      columns = {
        [2] = { name = "title" },
      },
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    }
    tab.meta = meta

    local text = ui.build_status_winbar(meta, tab, #D.tabs, D.active_tab_idx)

    assert.truthy(text:find("12 rows", 1, true))
    assert.truthy(text:find("title ↓", 1, true))
    assert.truthy(text:find("Page 2/3", 1, true))
    assert.truthy(text:find("filter: status=open", 1, true))
    assert.truthy(text:find("search: needle (2/2)", 1, true))
    assert.truthy(text:find("localhost:5432/blog", 1, true))
  end)
end)

describe("buffer_nav horizontal scroll", function()
  before_each(function()
    D.tabs = {}
    D.active_tab_idx = 0
    if D.dataset_window and vim.api.nvim_win_is_valid(D.dataset_window) then
      pcall(vim.api.nvim_win_close, D.dataset_window, true)
    end
    D.dataset_window = nil
    D.close_header_float()
    state.sql.cell = { row = 1, col = 1 }
  end)

  it("restores the row-number column when scrolling back to the first column", function()
    local saved_columns = vim.o.columns
    vim.o.columns = 40

    local format = require("poste-sql.format")
    local buffer = require("poste-sql.buffer")
    local body = vim.json.encode({
      type = "resultset",
      total_rows = 50,
      results = {
        {
          columns = {
            { name = "id", type = "INTEGER" },
            { name = "name", type = "TEXT" },
            { name = "desc", type = "TEXT" },
            { name = "note", type = "TEXT" },
            { name = "data", type = "TEXT" },
          },
          rows = {
            { 1, "alice", "aaaaaaaaaaaaaaaaaaaaaaaaaaaa", "c", "d" },
          },
        },
      },
      connection = "postgres://localhost:5432/db",
      database = "db",
      dialect = "postgres",
    })
    local data = vim.json.decode(body)
    local layout = format.plan_resultset_layout(data)
    local lines, meta = format.render_page(layout, 1, 50)
    buffer.render_dataset(lines, meta, { layout = layout, data = data })

    local win = D.dataset_window
    assert.is_not_nil(win)
    vim.api.nvim_set_current_win(win)

    -- Scroll right until the window actually scrolls horizontally.
    for _ = 1, 6 do nav.move_cell(0, 1) end
    local scrolled = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
    assert.is_true(scrolled > 0, "expected window to have scrolled horizontally")

    -- Scroll back to the first data column.
    for _ = 1, 10 do nav.move_cell(0, -1) end
    local leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
    assert.equals(0, leftcol, "leftcol must return to 0 so the row-number column is visible")
    assert.equals(1, state.sql.cell.col)

    vim.o.columns = saved_columns
  end)
end)
