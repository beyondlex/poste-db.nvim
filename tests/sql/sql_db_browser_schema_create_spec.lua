--- db_browser schema_create — the CREATE SCHEMA form's SQL generation.
--- The module has no test seam (gen_grant is local), so the spec drives the
--- form contract: stub forms_advanced.open, capture on_change/on_validate/
--- on_submit and assert the SQL a user's grant choices produce.
local function stub(name, tbl)
  package.preload[name] = function() return tbl end
end

local captured = {}
stub("poste-db.db_browser.forms_advanced", {
  open = function(opts) captured.opts = opts end,
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

local schema_create = require("poste-db.db_browser.schema_create")

describe("db_browser schema_create", function()
  local opts

  before_each(function()
    captured = {}
    schema_create.open({ name = "mydb", type = "database" }, { root_nodes = {} })
    opts = assert(captured.opts, "forms_advanced.open not called")
  end)

  describe("generate_sql (on_change)", function()
    it("grants on ALL TABLES IN SCHEMA put the schema name after the object", function()
      -- regression: the generator emitted
      --   GRANT SELECT ON ALL TABLES IN SCHEMA IN SCHEMA "mydb" TO "app_role";
      -- (the fixed "IN SCHEMA <name>" tail duplicated the object's own
      -- "IN SCHEMA"), which postgres rejects.
      local lines = opts.on_change({
        name = "mydb",
        grants = { { type = "grant", grantee = "app_role", privileges = { "SELECT" },
                     on_object = "ALL TABLES IN SCHEMA" } },
      })
      assert.equals('GRANT SELECT ON ALL TABLES IN SCHEMA "mydb" TO "app_role";', lines[2])
    end)

    it("grants on SCHEMA itself carry the schema name", function()
      -- regression: `GRANT SELECT ON SCHEMA TO "app_role";` — no schema name,
      -- a syntax error on every postgres server.
      local lines = opts.on_change({
        name = "mydb",
        grants = { { type = "grant", grantee = "app_role", privileges = { "SELECT", "INSERT" },
                     on_object = "SCHEMA" } },
      })
      assert.equals('GRANT SELECT, INSERT ON SCHEMA "mydb" TO "app_role";', lines[2])
    end)

    it("grants on ALL SEQUENCES / ALL FUNCTIONS follow the same shape", function()
      local mk = function(on_object)
        return opts.on_change({
          name = "mydb",
          grants = { { type = "grant", grantee = "r", privileges = {}, on_object = on_object } },
        })[2]
      end
      assert.equals('GRANT ALL ON ALL SEQUENCES IN SCHEMA "mydb" TO "r";', mk("ALL SEQUENCES IN SCHEMA"))
      assert.equals('GRANT ALL ON ALL FUNCTIONS IN SCHEMA "mydb" TO "r";', mk("ALL FUNCTIONS IN SCHEMA"))
    end)

    it("grant_usage names the schema", function()
      local lines = opts.on_change({
        name = "mydb",
        grants = { { type = "grant_usage", grantee = "app_role" } },
      })
      assert.equals('GRANT USAGE ON SCHEMA "mydb" TO "app_role";', lines[2])
    end)

    it("with_grant_option is appended", function()
      local lines = opts.on_change({
        name = "mydb",
        grants = { { type = "grant", grantee = "r", privileges = { "USAGE" },
                     on_object = "SCHEMA", with_grant_option = true } },
      })
      assert.equals('GRANT USAGE ON SCHEMA "mydb" TO "r" WITH GRANT OPTION;', lines[2])
    end)

    it("a nameless schema previews a hint, no CREATE", function()
      local lines = opts.on_change({ name = "", grants = {} })
      assert.equals(1, #lines)
      assert.matches("^%-%-%-", lines[1])
    end)
  end)

  describe("on_validate", function()
    it("requires a schema name", function()
      local err = opts.on_validate({ name = "" })
      assert.truthy(err)
    end)

    it("accepts a named schema with a grantee-less grant (SQL preview shows it)", function()
      assert.is_nil(opts.on_validate({ name = "mydb", grants = {} }))
    end)
  end)

  describe("on_submit", function()
    it("executes the composed SQL against the form's database and node", function()
      local fields = {
        name = "mydb",
        grants = { { type = "grant", grantee = "app_role", privileges = { "SELECT" },
                     on_object = "ALL TABLES IN SCHEMA" } },
      }
      -- the form layer hands submit the JOINED sql (forms_advanced concats
      -- its preview lines); reproduce that here.
      opts.on_submit(fields, table.concat(opts.on_change(fields), "\n"))
      assert.equals('CREATE SCHEMA IF NOT EXISTS "mydb";\nGRANT SELECT ON ALL TABLES IN SCHEMA "mydb" TO "app_role";',
        captured.sql)
      assert.equals("conn1", captured.conn)
      assert.equals("mydb", captured.run_opts.database)
      assert.equals("database", captured.run_opts.node_type)
    end)
  end)

  describe("open guard", function()
    it("refuses non-postgres dialects without opening the form", function()
      captured = {}
      local util = require("poste-db.db_browser.util")
      local real = util.get_dialect
      util.get_dialect = function() return "mysql" end
      schema_create.open({ name = "db" }, { root_nodes = {} })
      util.get_dialect = real
      assert.is_nil(captured.opts)
    end)
  end)
end)
