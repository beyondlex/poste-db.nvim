local D = require("poste-sql.dataset")
local nav = require("poste-sql.buffer_nav")

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

  it("format_conn_short shortens postgres connection URLs", function()
    local short = nav._test.format_conn_short("postgres://user:pass@localhost:5432/blog?sslmode=require")
    assert.equals("localhost:5432/blog", short)
  end)

  it("format_conn_short falls back to last path segment", function()
    local short = nav._test.format_conn_short("/tmp/blog.sqlite")
    assert.equals("blog.sqlite", short)
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

    local text = nav._test.build_status_winbar(meta)

    assert.truthy(text:find("12 rows", 1, true))
    assert.truthy(text:find("title ↓", 1, true))
    assert.truthy(text:find("Page 2/3", 1, true))
    assert.truthy(text:find("filter: status=open", 1, true))
    assert.truthy(text:find("search: needle (2/2)", 1, true))
    assert.truthy(text:find("localhost:5432/blog", 1, true))
  end)
end)
