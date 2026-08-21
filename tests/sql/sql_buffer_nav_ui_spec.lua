local ui = require("poste-sql.buffer.nav_ui")
local state = require("poste.state")

describe("buffer_nav_ui", function()
  before_each(function()
    _G.__saved_conn_name = state.sql and state.sql.context and state.sql.context.connection
  end)

  after_each(function()
    if state.sql and state.sql.context then
      state.sql.context.connection = _G.__saved_conn_name
    end
    _G.__saved_conn_name = nil
  end)
  it("formats connection urls for the winbar", function()
    assert.equals("localhost:5432/blog", ui.format_conn_short("postgres://user:pass@localhost:5432/blog?sslmode=require"))
    assert.equals("blog.sqlite", ui.format_conn_short("/tmp/blog.sqlite"))
  end)

  it("includes the connection name in the winbar text", function()
    if state.sql and state.sql.context then
      state.sql.context.connection = "inventory"
    end
    local text = ui.build_status_winbar_text({
      type = "resultset",
      total_rows = 5,
      total_execution_time_ms = 3,
      table_name = "users",
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    }, {}, 1, 1)
    assert.truthy(text:find("inventory: localhost:5432", 1, true))
    if state.sql and state.sql.context then
      state.sql.context.connection = nil
    end
  end)

  it("builds the status winbar text", function()
    local text = ui.build_status_winbar_text({
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
    assert.truthy(text:find("P:2/3", 1, true))
    assert.truthy(text:find("filter: status=open", 1, true))
    assert.truthy(text:find("search: needle (2/2)", 1, true))
    assert.is_falsy(text:find("localhost:5432/blog", 1, true))
    -- connection/db context moved onto the winbar; table name is omitted
    assert.truthy(text:find("localhost:5432", 1, true))
    assert.truthy(text:find("🄳 blog", 1, true))
    assert.is_falsy(text:find("🃎 posts", 1, true))
  end)

  it("builds the statusline context", function()
    local ctx = ui.build_statusline_context({
      type = "resultset",
      table_name = "posts",
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    })
    assert.truthy(ctx:find("localhost:5432", 1, true))
    assert.truthy(ctx:find("blog", 1, true))
    assert.truthy(ctx:find("posts", 1, true))
  end)

  it("includes the connection name when state.sql.context.connection is set", function()
    if state.sql and state.sql.context then
      state.sql.context.connection = "inventory"
    end
    local ctx = ui.build_statusline_context({
      type = "resultset",
      table_name = "posts",
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    })
    assert.truthy(ctx:find("inventory: localhost:5432", 1, true))
    assert.truthy(ctx:find("blog", 1, true))
    assert.truthy(ctx:find("posts", 1, true))
    if state.sql and state.sql.context then
      state.sql.context.connection = nil
    end
  end)

  it("prefers the resolved database over the connection URL db", function()
    local ctx = ui.build_statusline_context({
      type = "resultset",
      table_name = "inventory_items",
      database = "inventory",
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    })
    assert.truthy(ctx:find("localhost:5432", 1, true))
    assert.truthy(ctx:find("inventory", 1, true))
    assert.is_falsy(ctx:find("blog", 1, true))
  end)

  it("omits the table name when include_table is false", function()
    local ctx = ui.build_statusline_context({
      type = "resultset",
      table_name = "warehouses",
      database = "blog",
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    }, { include_table = false })
    assert.truthy(ctx:find("localhost:5432", 1, true))
    assert.truthy(ctx:find("blog", 1, true))
    assert.is_falsy(ctx:find("warehouses", 1, true))
    assert.is_falsy(ctx:find("🃎", 1, true))
  end)

  it("builds pending changes text only when dirty", function()
    local dirty = ui.build_pending_changes_text({
      edit_state = {
        dirty = true,
        modified_cells = { ["1:2"] = true },
        deleted_rows = { [3] = true },
        added_rows = { { row_idx = 4 } },
      },
    })
    local clean = ui.build_pending_changes_text({ edit_state = { dirty = false } })

    assert.truthy(dirty)
    assert.is_nil(clean)
  end)

  it("builds a truncated SQL statusline", function()
    local width = 40
    local text = ui.build_sql_statusline(
      "SELECT p.id, p.title FROM posts p LEFT JOIN comments c ON c.post_id = p.id ORDER BY p.title",
      width)
    assert.truthy(text:find("SELECT p.id, p.title", 1, true))
    assert.truthy(text:find("…", 1, true))
    assert.is_true(vim.fn.strdisplaywidth(text:gsub("%%#.-%%#", "")) <= width)
  end)

  it("does not put context into the SQL statusline", function()
    local text = ui.build_sql_statusline("SELECT title FROM posts", 80)
    assert.truthy(text:find("SELECT title FROM posts", 1, true))
    assert.is_falsy(text:find("localhost:5432", 1, true))
    assert.is_falsy(text:find("🄳", 1, true))
  end)

  it("builds an empty SQL statusline for nil/blank SQL", function()
    assert.equals("", ui.build_sql_statusline(nil, 40))
    assert.equals("", ui.build_sql_statusline("", 40))
    assert.equals("", ui.build_sql_statusline("   \n  ", 40))
  end)

  it("escapes % in SQL statusline", function()
    local text = ui.build_sql_statusline("SELECT 100% AS rate", 60)
    assert.truthy(text:find("100%%%% AS rate", 1, true))
    -- after stripping highlight tags, every % must be part of an escaped pair
    local body = text:gsub("%%#PosteDbDatasetMeta#", "")
    assert.is_falsy((body:gsub("%%%%", "")):find("%%", 1, true))
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
    assert.is_falsy(right:find("localhost:5432/blog", 1, true))
  end)
end)
