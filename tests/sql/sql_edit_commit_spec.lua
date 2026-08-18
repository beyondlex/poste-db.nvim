--- Tests for edit_commit/init.lua — dataset refresh data propagation.
--- Regression: after dataset R-refresh, tab.data fell back to the stale
--- state.last_response (set only by the sql_runner request path), so cell
--- preview (K) / yank / sort read pre-refresh rows while the buffer showed
--- the new ones.

local captured = {}

local FRESH_ROWS = { { 1, "old" }, { 11, "new" } }
local FRESH_BODY = {
  type = "resultset",
  results = {
    {
      columns = { { name = "id" }, { name = "name" } },
      rows = FRESH_ROWS,
      row_count = 2,
    },
  },
  total_rows = 2,
}

local state_stub = {
  sql = { context = { connection = nil, database = nil } },
  find_poste_binary = function() return "/tmp/poste" end,
  log = function() end,
}

local function install_stubs()
  package.loaded["poste.state"] = state_stub
  package.loaded["poste-sql.editor"] = { clear_pk_cache = function() end }
  package.loaded["poste-sql.sql_runner"] = { get_exec_seq = function() return 42 end }
  package.loaded["poste-sql.connections"] = {
    resolve_connection_url = function(name) return "mysql://" .. name, nil end,
  }
  package.loaded["poste-sql.statement"] = { extract_table_name = function() return nil end }
  package.loaded["poste-sql.sql_format"] = {
    format_dataset = function(parsed)
      local ok, body = pcall(vim.json.decode, parsed.body)
      return { "│ id │" }, { type = "resultset", row_count = ok and body.results[1].row_count or 0 },
        { rows = ok and body.results[1].rows or {} }
    end,
  }
  package.loaded["poste-sql.buffer"] = {
    render_dataset = function(lines, meta, opts)
      captured.lines = lines
      captured.meta = meta
      captured.opts = opts
    end,
  }
  package.loaded["poste-sql.exec_run"] = {
    run_async = function(sql, opts, callbacks)
      captured.sql = sql
      local resp = {
        status = "ok",
        latency_ms = 5,
        body = vim.json.encode(FRESH_BODY),
        connection = "mysql://dev",
        database = "db",
        results = FRESH_BODY.results,
      }
      callbacks.on_response(resp)
      return 7
    end,
  }
end

describe("edit_commit refresh_dataset", function()
  before_each(function()
    install_stubs()
    captured.opts = nil
    captured.sql = nil
    require("poste-sql.edit_commit").refresh_dataset({
      original_sql = "SELECT * FROM tb;",
      src_file = "test.sql",
      src_buf = 7,
      layout = { _conn_name = "dev", _database = "db" },
    })
    -- refresh_dataset schedules render via vim.schedule; flush the loop.
    vim.wait(100, function() return captured.opts ~= nil end)
  end)

  it("re-executes the original SELECT", function()
    assert.match("SELECT %* FROM tb", captured.sql)
  end)

  it("passes the fresh resultset as render data (not the stale last_response)", function()
    assert.is_not_nil(captured.opts, "render_dataset was not called")
    assert.is_not_nil(captured.opts.data, "refresh must pass opts.data")
    assert.equals("resultset", captured.opts.data.type)
    assert.same(FRESH_ROWS, captured.opts.data.results[1].rows)
    assert.same(FRESH_ROWS, captured.opts.layout.rows)
  end)

  it("keeps layout/original_sql/src routing for the new tab", function()
    assert.equals("SELECT * FROM tb;", captured.opts.original_sql)
    assert.equals("test.sql", captured.opts.src_file)
    assert.equals(7, captured.opts.src_buf)
    assert.equals(42, captured.opts.exec_seq)
  end)
end)