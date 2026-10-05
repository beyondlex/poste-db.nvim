--- db_browser db_create — the CREATE DATABASE form's contract, including the
--- async Owner populate. The Owner list needs a server round-trip, which used
--- to run synchronously inside open() and froze the UI for up to the exec
--- timeout; the form now opens immediately with empty choices and the async
--- response fills them through the forms_advanced handle. The stubs capture
--- that wiring: forms_advanced.open's returned handle, and the exec_run
--- callbacks the spec fires by hand.
local function stub(name, tbl)
  package.preload[name] = function() return tbl end
end

local captured
stub("poste-db.db_browser.forms_advanced", {
  open = function(opts)
    captured.opts = opts
    captured.handle = {
      set_choices = function(key, choices)
        captured.choices = captured.choices or {}
        table.insert(captured.choices, { key = key, choices = choices })
        return true
      end,
      is_closed = function() return captured.closed == true end,
    }
    return captured.handle
  end,
})
stub("poste-db.db_browser.util", {
  get_dialect = function() return "postgres" end,
  get_connection = function() return "conn1" end,
  run_ddl_and_refresh = function(sql, conn, context, opts)
    captured.sql = sql
    captured.conn = conn
    captured.run_opts = opts
  end,
})
stub("poste-db.db_browser.notify", { info = function() end, warn = function() end })
stub("poste-db.connections", {
  resolve_connection_url = function() return "postgres://u:p@h:5432/db1", nil end,
})

-- exec_run is required lazily by db_create (inside its populate helper), so
-- the stub must be in place before open() runs; run_async hands back the
-- callbacks for the spec to deliver.
local exec_calls
stub("poste-db.exec_run", {
  run_async = function(sql, opts, callbacks)
    exec_calls[#exec_calls + 1] = { sql = sql, opts = opts, callbacks = callbacks }
    return 42
  end,
})

local db_create = require("poste-db.db_browser.db_create")

--- Deliver a legacy-shaped exec response through the captured run_async
--- callbacks (exec_run delivers on_response exactly once per run).
local function deliver(resp)
  exec_calls[1].callbacks.on_response(resp)
end

describe("db_browser db_create", function()
  local opts

  before_each(function()
    captured = {}
    exec_calls = {}
    db_create.open({ name = "server1", type = "connection" }, { root_nodes = {} })
    opts = assert(captured.opts, "forms_advanced.open not called")
  end)

  describe("async Owner populate", function()
    it("opens the form before any server round-trip", function()
      -- The whole point of the async populate: open() must not run a query
      -- inline, so the form opts exist with the owner choices still empty.
      assert.is_truthy(opts)
      local owner = nil
      for _, f in ipairs(opts.sections[1].fields) do
        if f.key == "owner" then owner = f end
      end
      assert.truthy(owner, "postgres form carries an owner field")
      assert.same({}, owner.choices)
      assert.equals(1, #exec_calls)
    end)

    it("queries pg_roles over the resolved connection, greedily", function()
      assert.equals("SELECT rolname FROM pg_roles ORDER BY rolname", exec_calls[1].sql)
      assert.equals("postgres://u:p@h:5432/db1", exec_calls[1].opts.conn_url)
      assert.equals("browser", exec_calls[1].opts.log_source)
    end)

    it("fills the owner choices from the response rows", function()
      deliver({ results = { { rows = { { "postgres" }, { "app_rw" } } } } })
      assert.same({ key = "owner", choices = { "postgres", "app_rw" } }, captured.choices[1])
    end)

    it("concatenates rows across every result", function()
      deliver({ results = {
        { rows = { { "postgres" } } },
        { rows = { { "reader" }, { "writer" } } },
      } })
      assert.same({ "postgres", "reader", "writer" }, captured.choices[1].choices)
    end)

    it("a null rolname (vim.NIL) never reaches the picker", function()
      deliver({ results = { { rows = { { vim.NIL }, { "real" } } } } })
      assert.same({ "real" }, captured.choices[1].choices)
    end)

    it("an empty or failed answer leaves the choices empty", function()
      deliver({ results = {} })
      assert.is_nil(captured.choices)
      deliver({ results = { { rows = {} } } })
      assert.is_nil(captured.choices)
      deliver(nil)
      assert.is_nil(captured.choices)
    end)

    it("a response after the form closed does not fill anything", function()
      captured.closed = true
      deliver({ results = { { rows = { { "postgres" } } } } })
      assert.is_nil(captured.choices)
    end)

    it("no query at all when the connection does not resolve", function()
      local connections = require("poste-db.connections")
      local real = connections.resolve_connection_url
      connections.resolve_connection_url = function() return nil end
      exec_calls = {}
      db_create.open({ name = "server1" }, { root_nodes = {} })
      connections.resolve_connection_url = real
      assert.equals(0, #exec_calls)
    end)
  end)

  describe("non-postgres dialects", function()
    it("mysql never queries roles and carries charset/collation selects", function()
      local util = require("poste-db.db_browser.util")
      local real_dialect = util.get_dialect
      util.get_dialect = function() return "mysql" end
      exec_calls = {}
      captured = {}
      db_create.open({ name = "server1" }, { root_nodes = {} })
      util.get_dialect = real_dialect
      assert.truthy(captured.opts)
      assert.equals(0, #exec_calls, "no role query for mysql")
      local keys = {}
      for _, f in ipairs(captured.opts.sections[1].fields) do keys[f.key] = true end
      assert.truthy(keys.charset)
      assert.truthy(keys.collation)
      assert.falsy(keys.owner)
    end)

    it("sqlite is refused without opening a form", function()
      local util = require("poste-db.db_browser.util")
      local real_dialect = util.get_dialect
      util.get_dialect = function() return "sqlite" end
      captured = {}
      db_create.open({ name = "file.db" }, { root_nodes = {} })
      util.get_dialect = real_dialect
      assert.is_nil(captured.opts)
    end)
  end)

  describe("form contract", function()
    it("on_change composes postgres CREATE DATABASE with an owner", function()
      local lines = opts.on_change({ name = "newdb", owner = "app_rw" })
      assert.equals('CREATE DATABASE "newdb" OWNER "app_rw";', lines[1])
    end)

    it("on_change omits OWNER when unset", function()
      local lines = opts.on_change({ name = "newdb" })
      assert.equals('CREATE DATABASE "newdb";', lines[1])
    end)

    it("mysql on_change carries charset and collation", function()
      local util = require("poste-db.db_browser.util")
      local real_dialect = util.get_dialect
      util.get_dialect = function() return "mysql" end
      captured = {}
      db_create.open({ name = "server1" }, { root_nodes = {} })
      util.get_dialect = real_dialect
      local lines = captured.opts.on_change({
        name = "newdb", charset = "utf8mb4", collation = "utf8mb4_unicode_ci",
      })
      assert.equals("CREATE DATABASE IF NOT EXISTS `newdb` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;", lines[1])
    end)

    it("on_validate requires a name", function()
      local err, key = opts.on_validate({ name = "" })
      assert.equals("Database name is required", err)
      assert.equals("name", key)
      assert.is_nil(opts.on_validate({ name = "newdb" }))
    end)

    it("on_submit executes against the node's connection and connection node type", function()
      local node = { name = "server1", type = "connection" }
      opts.on_submit({ name = "newdb" }, 'CREATE DATABASE "newdb";')
      assert.equals('CREATE DATABASE "newdb";', captured.sql)
      assert.equals("conn1", captured.conn)
      assert.same(node, captured.run_opts.target_node)
      assert.equals("connection", captured.run_opts.node_type)
    end)
  end)
end)
