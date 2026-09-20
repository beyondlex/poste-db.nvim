local explain = require("poste-db.explain")

describe("explain", function()
  describe("wrap_sql", function()
    it("wraps with the dialect's plan-only form", function()
      assert.equals("EXPLAIN SELECT 1", explain.wrap_sql("postgres", "SELECT 1;"))
      assert.equals("EXPLAIN select 1", explain.wrap_sql("mysql", "select 1"))
      assert.equals("EXPLAIN SELECT 1", explain.wrap_sql("clickhouse", "SELECT 1;"))
      assert.equals("EXPLAIN QUERY PLAN SELECT 1", explain.wrap_sql("sqlite", "SELECT 1;"))
    end)

    it("treats nil dialect as postgres", function()
      assert.equals("EXPLAIN SELECT 1", explain.wrap_sql(nil, "SELECT 1"))
    end)

    it("rejects dialects without a plan-only EXPLAIN", function()
      local wrapped, err = explain.wrap_sql("mssql", "SELECT 1")
      assert.is_nil(wrapped)
      assert.truthy(err:find("mssql"))
    end)

    it("strips one trailing semicolon and rejects multi-statement text", function()
      assert.equals("EXPLAIN SELECT 1", explain.wrap_sql("postgres", "  SELECT 1 ;  "))
      local wrapped, err = explain.wrap_sql("postgres", "SELECT 1; SELECT 2;")
      assert.is_nil(wrapped)
      assert.truthy(err:find("single statement"))
    end)

    -- The single-statement check used to be a plain `find(";")`, so it also
    -- counted separators that are part of the statement's own text.
    it("ignores semicolons inside quoted literals", function()
      assert.equals("EXPLAIN SELECT 'a;b'", explain.wrap_sql("postgres", "SELECT 'a;b'"))
      assert.equals("EXPLAIN SELECT \"a;b\" FROM `t;x`",
        explain.wrap_sql("mysql", 'SELECT "a;b" FROM `t;x`'))
      -- a doubled quote is an escaped quote inside the literal, not its close
      assert.equals("EXPLAIN SELECT 'it''s; ok'", explain.wrap_sql("postgres", "SELECT 'it''s; ok'"))
      assert.equals("EXPLAIN SELECT '$x;'", explain.wrap_sql("postgres", "SELECT '$x;'"))
    end)

    it("ignores semicolons in comments and dollar-quoted bodies", function()
      assert.equals("EXPLAIN SELECT 1 -- note; end",
        explain.wrap_sql("postgres", "SELECT 1 -- note; end"))
      assert.equals("EXPLAIN SELECT 1 /* a;b */", explain.wrap_sql("postgres", "SELECT 1 /* a;b */"))
      local plpgsql = "CREATE FUNCTION f() AS $$ BEGIN SELECT 1; END; $$ LANGUAGE plpgsql"
      assert.equals("EXPLAIN " .. plpgsql, explain.wrap_sql("postgres", plpgsql))
      -- $1 placeholders are not dollar-quote tags
      assert.equals("EXPLAIN SELECT $1, $2", explain.wrap_sql("postgres", "SELECT $1, $2"))
    end)

    it("still rejects a real statement break after quoted text", function()
      for _, sql in ipairs({
        "SELECT 'a'; SELECT 2",
        "INSERT INTO t VALUES ('a;b', 'c'); INSERT INTO t VALUES (1)",
        "SELECT $$ a $$ ; SELECT 2",
        "SELECT ';'; SELECT 2",
      }) do
        local wrapped, err = explain.wrap_sql("postgres", sql)
        assert.is_nil(wrapped, sql)
        assert.truthy(err:find("single statement"), sql)
      end
    end)

    it("rejects empty statements", function()
      local wrapped, err = explain.wrap_sql("postgres", "   ")
      assert.is_nil(wrapped)
      assert.truthy(err:find("no statement"))
    end)
  end)

  describe("plan_lines", function()
    it("renders single-column tree text one cell per line", function()
      local lines, err = explain.plan_lines({
        results = { {
          columns = { { name = "QUERY PLAN" } },
          rows = { { "Seq Scan on t  (cost=0..1)" }, { "  -> Filter: (id > 1)" } },
        } },
      })
      assert.is_nil(err)
      assert.same({ "Seq Scan on t  (cost=0..1)", "  -> Filter: (id > 1)" }, lines)
    end)

    it("renders the detail column for sqlite EXPLAIN QUERY PLAN", function()
      local lines, err = explain.plan_lines({
        results = { {
          columns = { { name = "id" }, { name = "parent" }, { name = "detail" } },
          rows = { { 1, 0, "SCAN t" }, { 2, 0, "USE INDEX" } },
        } },
      })
      assert.is_nil(err)
      assert.same({ "SCAN t", "USE INDEX" }, lines)
    end)

    it("joins multi-column rows when there is no detail column", function()
      local lines, err = explain.plan_lines({
        results = { {
          columns = { { name = "a" }, { name = "b" } },
          rows = { { 1, "x" }, { 2, vim.NIL } },
        } },
      })
      assert.is_nil(err)
      assert.same({ "1 | x", "2 | " }, lines)
    end)

    it("surfaces statement errors", function()
      local lines, err = explain.plan_lines({
        results = { { columns = {}, rows = {}, error = "relation does not exist" } },
      })
      assert.is_nil(lines)
      assert.truthy(err:find("relation does not exist"))
    end)

    it("reports a missing response", function()
      local lines, err = explain.plan_lines(nil)
      assert.is_nil(lines)
      assert.truthy(err:find("no response"))
    end)
  end)
end)
