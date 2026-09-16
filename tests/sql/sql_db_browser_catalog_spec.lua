--- db_browser catalog spec — the pure SQL builders + row parsers
--- (no live connection; catalog.lua exports them for exactly this).
local catalog = require("poste-db.db_browser.catalog")

describe("db_browser catalog", function()
  describe("view_body_from_ddl", function()
    it("strips an UPPERCASE MySQL DDL header (options + backticks)", function()
      local body = catalog.view_body_from_ddl(
        "CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER "
        .. "VIEW `v1` AS select 1 as a")
      assert.equals("select 1 as a", body)
    end)

    it("strips a lowercase sqlite_master DDL header (stored as written)", function()
      -- regression: the old scan was case-sensitive, so the whole
      -- "create view …" text passed through and the paste engine composed
      -- "CREATE VIEW x AS create view v as …" — invalid SQL on the target
      local body = catalog.view_body_from_ddl(
        "create view v1 as select 1 as a")
      assert.equals("select 1 as a", body)
    end)

    it("strips a mixed-case DDL header", function()
      local body = catalog.view_body_from_ddl(
        "Create View `v1` As select * from t")
      assert.equals("select * from t", body)
    end)

    it("passes a bare pg_get_viewdef body through untouched", function()
      local body = catalog.view_body_from_ddl(
        "SELECT t.a, t.b FROM public.t t")
      assert.equals("SELECT t.a, t.b FROM public.t t", body)
    end)

    it("passes a body that merely contains ' view … as ' through", function()
      -- only a leading CREATE marks DDL: a PG body with the words inside a
      -- literal must not be split
      local body = catalog.view_body_from_ddl(
        "SELECT note FROM t WHERE note = 'a view as such'")
      assert.equals("SELECT note FROM t WHERE note = 'a view as such'", body)
    end)

    it("returns the text unchanged when no AS separator exists", function()
      local text = "CREATE VIEW v1"
      assert.equals(text, catalog.view_body_from_ddl(text))
    end)
  end)

  describe("compose_trigger_sql", function()
    it("composes a MySQL trigger from parsed parts", function()
      local sql = catalog.compose_trigger_sql("mysql", {
        name = "tg", timing = "AFTER", event_type = "INSERT",
        table_name = "t1", stmt = "SET @x = 1",
      })
      assert.equals(
        "CREATE TRIGGER `tg` AFTER INSERT ON `t1` FOR EACH ROW SET @x = 1", sql)
    end)

    it("passes a pg/sqlite trigger definition through", function()
      local sql = catalog.compose_trigger_sql("postgres", {
        name = "tg", def = "CREATE TRIGGER tg BEFORE DELETE ON t FOR EACH ROW EXECUTE FUNCTION f()",
      })
      assert.equals(
        "CREATE TRIGGER tg BEFORE DELETE ON t FOR EACH ROW EXECUTE FUNCTION f()", sql)
    end)
  end)

  describe("list_objects_sql / trigger_defs_sql / routine_names_sql", function()
    it("cover mysql, postgres and sqlite; nil elsewhere", function()
      for _, d in ipairs({ "mysql", "mariadb", "postgres", "sqlite" }) do
        assert.truthy(catalog.list_objects_sql(d), d .. " list_objects")
        assert.truthy(catalog.trigger_defs_sql(d), d .. " trigger_defs")
      end
      assert.is_nil(catalog.list_objects_sql("mssql"))
      assert.is_nil(catalog.routine_names_sql("sqlite"))
      -- every postgres listing must exclude the system namespaces
      assert.truthy(catalog.list_objects_sql("postgres"):find("pg_catalog", 1, true))
    end)
  end)

  describe("result_to_maps", function()
    it("zips columns onto row values by position", function()
      local maps = catalog.result_to_maps({
        columns = { { name = "name" }, { name = "bytes" } },
        rows = { { "t1", 10 }, { "t2", 20 } },
      })
      assert.equals(2, #maps)
      assert.equals("t1", maps[1].name)
      assert.equals(20, maps[2].bytes)
    end)

    it("tolerates a missing/empty result", function()
      assert.equals(0, #catalog.result_to_maps(nil))
      assert.equals(0, #catalog.result_to_maps({}))
    end)
  end)
end)
