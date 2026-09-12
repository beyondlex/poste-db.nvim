--- Tests for poste-db/editor/column.lua ensure_primary_key connection resolution.
--- Regression: the db-browser ENT path renders a dataset whose layout carries a
--- table_name but no _conn_name, and poste-db.state.context is untouched (the
--- browser runs SQL directly). ensure_primary_key fell back to
--- get_state().sql.context.connection, but poste.state has no `.sql` field, so
--- pressing `i` (edit) on such a dataset crashed with "attempt to index field
--- 'sql' (a nil value)".

local column = require("poste-db.editor.column")
local saved = {}

local function stub_state(context)
  local real = package.loaded["poste-db.state"]
  package.loaded["poste-db.state"] = { context = context }
  return function()
    if real then package.loaded["poste-db.state"] = real
    else package.loaded["poste-db.state"] = nil end
  end
end

local function install_stubs()
  saved.exec_run = package.loaded["poste-db.exec_run"]
  saved.connections = package.loaded["poste-db.connections"]
  saved.log = package.loaded["poste-db.log"]
  package.loaded["poste-db.exec_run"] = { run_sql = function() return nil end }
  package.loaded["poste-db.connections"] = {
    resolve_connection_url = function(name) return "postgres://" .. name end,
  }
  package.loaded["poste-db.log"] = { debug = function() end, redact_url = function(u) return u end }
end

local function restore_stubs()
  for k, v in pairs(saved) do package.loaded[k] = v end
  column.clear_pk_cache()
end

local function layout_with(extra)
  local l = {
    table_name = "users",
    dialect = "postgres",
    columns = { { name = "id", type = "INT", ctype = "integer" } },
  }
  for k, v in pairs(extra or {}) do l[k] = v end
  return l
end

describe("editor column ensure_primary_key connection resolution", function()
  before_each(function()
    install_stubs()
  end)

  after_each(function()
    restore_stubs()
  end)

  it("no _conn_name and no context connection skips introspection without error", function()
    local restore_state = stub_state({ connection = nil, database = nil })
    local tab = { layout = layout_with(nil) }
    assert.does_not_error(function() column.ensure_primary_key(tab) end)
    assert.falsy(tab.layout.columns[1].primary_key)
    restore_state()
  end)

  it("falls back to poste-db.state.context.connection, not a nil poste.state.sql", function()
    local restore_state = stub_state({ connection = "dev", database = "app" })
    local tab = { layout = layout_with(nil) }
    assert.does_not_error(function() column.ensure_primary_key(tab) end)
    restore_state()
  end)

  it("uses _conn_name carried by the layout even without a SQL context", function()
    local restore_state = stub_state({ connection = nil, database = nil })
    local tab = { layout = layout_with({ _conn_name = "browser_conn", _database = "browser_db" }) }
    assert.does_not_error(function() column.ensure_primary_key(tab) end)
    restore_state()
  end)
end)