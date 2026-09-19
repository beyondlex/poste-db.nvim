local ui = require("poste-db.buffer.nav_ui")
local state = require("poste-db.state")

local saved_connections = package.loaded["poste-db.connections"]

describe("buffer_nav_ui", function()
  before_each(function()
    _G.__saved_conn_name = state and state.context and state.context.connection
    -- default stub: name lookup never hits (tests pin the state-name and
    -- host:port fallbacks); individual tests override name_for_url
    package.loaded["poste-db.connections"] = { name_for_url = function() return nil end }
  end)

  after_each(function()
    if state and state.context then
      state.context.connection = _G.__saved_conn_name
    end
    _G.__saved_conn_name = nil
    package.loaded["poste-db.connections"] = saved_connections
  end)
  it("formats connection urls for the winbar", function()
    assert.equals("localhost:5432/blog", ui.format_conn_short("postgres://user:pass@localhost:5432/blog?sslmode=require"))
    assert.equals("blog.sqlite", ui.format_conn_short("/tmp/blog.sqlite"))
  end)

  it("shows the name reverse-looked-up from the connection url", function()
    -- the binary echoes urls only (exec_file.rs); name_for_url maps the
    -- dataset's own url back to its connections.toml entry
    package.loaded["poste-db.connections"].name_for_url = function(url)
      if url:match("db%.internal") then return "prod" end
      return nil
    end
    local text = ui.build_status_winbar_text({
      type = "resultset",
      total_rows = 5,
      total_execution_time_ms = 3,
      table_name = "users",
      connection = "postgres://user:pass@db.internal:5432/blog",
    }, {}, 1, 1)
    assert.truthy(text:find("prod", 1, true))
    assert.is_falsy(text:find("db.internal:5432", 1, true))
  end)

  it("prefers the url's own name over a stale session connection name", function()
    package.loaded["poste-db.connections"].name_for_url = function() return "prod" end
    if state and state.context then
      state.context.connection = "stale-dev"
    end
    local text = ui.build_status_winbar_text({
      type = "resultset",
      total_rows = 5,
      total_execution_time_ms = 3,
      table_name = "users",
      connection = "postgres://user:pass@db.internal:5432/blog",
    }, {}, 1, 1)
    assert.truthy(text:find("prod", 1, true))
    assert.is_falsy(text:find("stale%-dev", 1, true))
  end)

  it("shows a bare non-url connection value as-is", function()
    -- error/affected metas carry context.connection (a name) verbatim
    local ctx = ui.build_statusline_context({
      type = "resultset",
      connection = "prod",
      database = "blog",
    })
    assert.truthy(ctx:find("prod", 1, true))
  end)

  it("includes the connection name in the winbar text", function()
    if state and state.context then
      state.context.connection = "inventory"
    end
    local text = ui.build_status_winbar_text({
      type = "resultset",
      total_rows = 5,
      total_execution_time_ms = 3,
      table_name = "users",
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    }, {}, 1, 1)
    assert.truthy(text:find("inventory", 1, true))
    assert.is_falsy(text:find("localhost:5432", 1, true))
    if state and state.context then
      state.context.connection = nil
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
      layout = true,
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
    assert.truthy(text:find("\239\135\128 blog", 1, true))
    assert.is_falsy(text:find("posts", 1, true))
  end)

  it("shows connection/db context on the winbar for affected results", function()
    if state and state.context then
      state.context.connection = "my-blog"
    end
    local text = ui.build_status_winbar_text({
      type = "affected",
      connection = "mysql://user:pass@localhost:13306/blog",
      database = "blog",
    }, {}, 1, 1)
    assert.is_not_nil(text)
    assert.truthy(text:find("my-blog", 1, true))
    assert.truthy(text:find("\239\135\128 blog", 1, true))
    assert.is_falsy(text:find("localhost:13306", 1, true))
    if state and state.context then
      state.context.connection = nil
    end
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

  it("includes the connection name when state.context.connection is set", function()
    if state and state.context then
      state.context.connection = "inventory"
    end
    local ctx = ui.build_statusline_context({
      type = "resultset",
      table_name = "posts",
      connection = "postgres://user:pass@localhost:5432/blog?sslmode=require",
    })
    assert.truthy(ctx:find("inventory", 1, true))
    assert.is_falsy(ctx:find("localhost:5432", 1, true))
    assert.truthy(ctx:find("blog", 1, true))
    assert.truthy(ctx:find("posts", 1, true))
    if state and state.context then
      state.context.connection = nil
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

  it("shortens multi-column SELECT in statusline", function()
    local text = ui.build_sql_statusline(
      "SELECT p.id, p.title, p.status FROM posts p WHERE p.id = 1", 80)
    assert.truthy(text:find("SELECT p.id, ... FROM", 1, true))
    assert.is_falsy(text:find("p.title", 1, true))
    assert.is_falsy(text:find("p.status", 1, true))
  end)

  it("preserves single-column SELECT in statusline", function()
    local text = ui.build_sql_statusline("SELECT p.title FROM posts p", 80)
    assert.truthy(text:find("SELECT p.title FROM", 1, true))
  end)

  it("preserves non-SELECT queries in statusline", function()
    local text = ui.build_sql_statusline("WITH cte AS (SELECT id FROM posts) SELECT * FROM cte", 80)
    assert.truthy(text:find("WITH cte", 1, true))
  end)

  it("builds a truncated SQL statusline", function()
    local width = 40
    local text = ui.build_sql_statusline(
      "SELECT p.id, p.title FROM posts p LEFT JOIN comments c ON c.post_id = p.id ORDER BY p.title",
      width)
    assert.truthy(text:find("SELECT p.id, ... FROM", 1, true))
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
    assert.truthy(text:find("100%% AS rate", 1, true))
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
      layout = true,
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

  it("doubles data-borne percent signs so they stay literal in the winbar", function()
    local left = ui.build_status_left({
      type = "resultset",
      total_rows = 2,
      total_execution_time_ms = 1,
      columns = { { name = "pct%" } },
    }, {
      sort = { col = 1, ascending = true },
      layout = true,
      pagination_enabled = false,
      num_pages = 2,
      filter_active = true,
      filter_col_name = "rate",
      filter_val = "100%",
      search_text = "50%",
      search_matches = { 1 },
    })
    local right = ui.build_status_right({
      type = "resultset",
      table_name = "a%b",
    }, 2, 1, nil)

    assert.truthy(left:find("pct%%", 1, true))
    assert.truthy(left:find("rate=100%%", 1, true))
    assert.truthy(left:find("search: 50%% ", 1, true))
    assert.truthy(right:find("[1/2: a%%b]", 1, true))

    -- After the highlight groups are removed, nothing may still look like a
    -- statusline item: every data `%` has to arrive doubled.
    local rest = (left .. right):gsub("%%#[%w%.]+#", ""):gsub("%%%%", "")
    assert.is_falsy(rest:find("%", 1, true))
  end)
end)
