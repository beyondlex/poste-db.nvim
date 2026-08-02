local ui = require("poste-sql.buffer_nav_ui")

describe("buffer_nav_ui", function()
  it("builds preview float opts from shared defaults", function()
    local opts = ui.build_preview_float_opts("title")
    assert.equals("text", opts.filetype)
    assert.equals("title", opts.title)
    assert.equals(0.7, opts.width_ratio)
    assert.equals(120, opts.max_width)
    assert.equals(0.6, opts.height_ratio)
  end)

  it("formats connection urls for the winbar", function()
    assert.equals("localhost:5432/blog", ui.format_conn_short("postgres://user:pass@localhost:5432/blog?sslmode=require"))
    assert.equals("blog.sqlite", ui.format_conn_short("/tmp/blog.sqlite"))
  end)

  it("builds the status winbar text", function()
    local text = ui.build_status_winbar({
      type = "resultset",
      total_rows = 12,
      total_execution_time_ms = 7,
      table_name = "posts",
      columns = { [2] = { name = "title" } },
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    }, {
      sort = { col = 2, ascending = false },
      pagination_enabled = true,
      page = 2,
      num_pages = 3,
      padded_full = true,
      filter_active = true,
      filter_col_name = "status",
      filter_val = "open",
      search_text = "needle",
      search_matches = { { row = 1 }, { row = 2 } },
      search_idx = 2,
      edit_state = { dirty = false },
    }, 1, 1)

    assert.truthy(text:find("12 rows", 1, true))
    assert.truthy(text:find("title ↓", 1, true))
    assert.truthy(text:find("Page 2/3", 1, true))
    assert.truthy(text:find("filter: status=open", 1, true))
    assert.truthy(text:find("search: needle (2/2)", 1, true))
    assert.truthy(text:find("localhost:5432/blog", 1, true))
  end)

  it("builds status winbar halves", function()
    local left = ui.build_status_left({
      type = "resultset",
      total_rows = 1,
      total_execution_time_ms = 7,
      columns = { [2] = { name = "title" } },
    }, {
      sort = { col = 2, ascending = true },
      pagination_enabled = false,
      num_pages = 2,
      padded_full = true,
      filter_active = true,
      filter_col_name = "status",
      filter_val = "open",
      search_text = "needle",
      search_matches = {},
    })
    local right = ui.build_status_right({
      type = "resultset",
      table_name = "posts",
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    }, 3, 2, "pending changes")

    assert.truthy(left:find("1 row", 1, true))
    assert.truthy(left:find("title ↑", 1, true))
    assert.truthy(left:find("All", 1, true))
    assert.truthy(left:find("filter: status=open", 1, true))
    assert.truthy(left:find("search: needle (0)", 1, true))
    assert.truthy(right:find("pending changes", 1, true))
    assert.truthy(right:find("[2/3: posts]", 1, true))
    assert.truthy(right:find("localhost:5432/blog", 1, true))
  end)
end)
