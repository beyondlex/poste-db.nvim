local exec_run = require("poste-db.exec_run")

describe("exec_run", function()
  describe("build_response", function()
    it("classifies a SELECT as resultset and keeps rows", function()
      local resp = exec_run.build_response({
        { type = "result", seq = 1, status = "ok", sql = "SELECT * FROM t",
          row_count = 2, affected_rows = vim.NIL, execution_time_ms = 3,
          columns = { { name = "x", type = "INTEGER" } }, rows = { { 1 }, { 2 } } },
        { type = "summary", total_time_ms = 31, dialect = "sqlite",
          connection = "sqlite::memory:", database = nil },
      }, "sqlite::memory:", "")

      assert.equals("ok", resp.status)
      assert.equals(31, resp.latency_ms)
      local body = vim.json.decode(resp.body)
      assert.equals("resultset", body.type)
      assert.equals(2, body.total_rows)
      assert.equals(1, #body.results)
      assert.equals(2, body.results[1].row_count)
      assert.is_nil(body.results[1].affected_rows)
      assert.same({ 2 }, body.results[1].rows[2])
      assert.equals("sqlite::memory:", resp.connection)
      assert.equals("sqlite", resp.dialect)
    end)

    it("classifies INSERTs as affected and sums affected rows", function()
      local resp = exec_run.build_response({
        { type = "result", seq = 1, status = "ok", sql = "INSERT ...",
          row_count = 0, affected_rows = 1, execution_time_ms = 1 },
        { type = "result", seq = 2, status = "ok", sql = "INSERT ...",
          row_count = 0, affected_rows = 3, execution_time_ms = 1 },
        { type = "summary", total_time_ms = 5, dialect = "postgres",
          connection = "pg://x", database = "app" },
      }, "pg://x", "app")

      local body = vim.json.decode(resp.body)
      assert.equals("affected", body.type)
      assert.equals(4, body.total_affected)
      assert.is_false(resp.has_error)
      assert.equals("ok", resp.status)
    end)

    it("sets has_error when a statement fails", function()
      local resp = exec_run.build_response({
        { type = "result", seq = 1, status = "error", sql = "SELECT * FROM missing",
          error = "no such table: missing", execution_time_ms = 0 },
        { type = "summary", total_time_ms = 9, dialect = "sqlite",
          connection = "sqlite::memory:", database = nil },
      }, "sqlite::memory:", "")

      assert.equals("error", resp.status)
      assert.is_true(resp.has_error)
      local body = vim.json.decode(resp.body)
      assert.is_true(body.has_error)
      assert.equals("no such table: missing", body.results[1].error)
    end)

    it("classifies a SELECT as resultset even if affected_rows is reported as 0", function()
      -- Regression: some drivers/binary versions report affected_rows=0 for a
      -- SELECT; must not be misclassified as an affected/Query OK response.
      local resp = exec_run.build_response({
        { type = "result", seq = 1, status = "ok", sql = "SELECT * FROM t",
          row_count = 5, affected_rows = 0, execution_time_ms = 2,
          columns = { { name = "x", type = "INTEGER" } },
          rows = { { 1 }, { 2 }, { 3 }, { 4 }, { 5 } } },
        { type = "summary", total_time_ms = 7, dialect = "postgres",
          connection = "pg://x", database = "app" },
      }, "pg://x", "app")

      local body = vim.json.decode(resp.body)
      assert.equals("resultset", body.type)
      assert.equals(5, body.total_rows)
    end)

    it("classifies a SELECT as resultset from SQL text even when the result is DML-shaped", function()
      -- MySQL: a binary/driver may emit a SELECT as a DML-shaped result event
      -- (affected_rows as a number, no columns/rows). The SQL keyword must win.
      local resp = exec_run.build_response({
        { type = "result", seq = 1, status = "ok", sql = "select * from merchant ;",
          row_count = 0, affected_rows = 0, execution_time_ms = 4, columns = {}, rows = {} },
        { type = "summary", total_time_ms = 9, dialect = "mysql",
          connection = "mysql://dba:xxx@host:3306/cpm_order_dev", database = "cpm_order_dev" },
      }, "mysql://dba:xxx@host:3306/cpm_order_dev", "cpm_order_dev")

      local body = vim.json.decode(resp.body)
      assert.equals("resultset", body.type)
      assert.is_false(resp.has_error)
    end)

    it("keeps a real DML as affected even with SQL text present", function()
      local resp = exec_run.build_response({
        { type = "result", seq = 1, status = "ok", sql = "update merchant set name = 'x' where id = 1",
          row_count = 0, affected_rows = 1, execution_time_ms = 2, columns = {}, rows = {} },
        { type = "summary", total_time_ms = 5, dialect = "mysql",
          connection = "mysql://dba:xxx@host:3306/cpm_order_dev", database = "cpm_order_dev" },
      }, "mysql://dba:xxx@host:3306/cpm_order_dev", "cpm_order_dev")

      local body = vim.json.decode(resp.body)
      assert.equals("affected", body.type)
      assert.equals(1, body.total_affected)
    end)

    it("propagates rolled_back from the transaction-mode summary", function()
      local resp = exec_run.build_response({
        { type = "result", seq = 1, status = "error", sql = "UPDATE t SET x=1",
          row_count = 0, affected_rows = vim.NIL, execution_time_ms = 1,
          error = "constraint failed" },
        { type = "summary", total_time_ms = 4, dialect = "postgres",
          connection = "pg://x", database = "app", rolled_back = true },
      }, "pg://x", "app")

      assert.equals("error", resp.status)
      assert.is_true(vim.json.decode(resp.body).rolled_back)
    end)

    it("omits rolled_back when the summary does not carry it", function()
      local resp = exec_run.build_response({
        { type = "result", seq = 1, status = "ok", sql = "UPDATE t SET x=1",
          row_count = 0, affected_rows = 1, execution_time_ms = 1 },
        { type = "summary", total_time_ms = 4, dialect = "postgres",
          connection = "pg://x", database = "app" },
      }, "pg://x", "app")

      assert.equals("ok", resp.status)
      assert.is_nil(vim.json.decode(resp.body).rolled_back)
    end)
  end)

  describe("detect_use", function()
    it("detects a lone USE statement", function()
      assert.equals("inventory", exec_run.detect_use("USE inventory;"))
      assert.equals("inventory", exec_run.detect_use("  USE inventory  "))
    end)

    it("detects USE with a trailing comment and captures only the db name", function()
      -- Regression: the comment-tail pattern had no capture group, so match()
      -- returned the whole statement and it leaked into database_name.
      assert.equals("mydb", exec_run.detect_use("USE mydb -- switch context"))
      assert.equals("mydb", exec_run.detect_use("USE mydb; -- switch context"))
    end)

    it("detects lowercase use statements (case-insensitive SQL keywords)", function()
      -- A lowercase `use db;` used to fall through: detect_use missed it, the
      -- statement reached the database as real SQL (syntax error on postgres)
      -- while the uppercase form switched the context.
      assert.equals("inventory", exec_run.detect_use("use inventory;"))
      assert.equals("inventory", exec_run.detect_use("Use inventory"))
      assert.equals("mydb", exec_run.detect_use("use mydb -- switch context"))
    end)

    it("ignores non-USE SQL", function()
      assert.is_nil(exec_run.detect_use("SELECT * FROM t"))
      assert.is_nil(exec_run.detect_use("USE inventory\nSELECT 1"))
    end)
  end)

  describe("is_query_sql", function()
    it("classifies DML with RETURNING (any case) as a query", function()
      -- pg/sqlite `update … returning x` returns rows; the classification
      -- used to depend on the keyword being uppercase.
      assert.is_true(exec_run.is_query_sql("update t set x = 1 returning x"))
      assert.is_true(exec_run.is_query_sql("UPDATE t SET x = 1 RETURNING x"))
      assert.is_true(exec_run.is_query_sql("with del as (delete from t returning *) select * from del"))
    end)

    it("does not let identifiers or literals flip the classification", function()
      -- word boundaries keep `my_returning_col` from matching, and literals
      -- are stripped before the keyword scan
      assert.is_false(exec_run.is_query_sql("update t set note = 'RETURNING user'"))
      assert.is_false(exec_run.is_query_sql("update t set my_returning_col = 1"))
      assert.is_false(exec_run.is_query_sql("update t set x = 1 -- RETURNING later"))
    end)

    it("keeps plain DML as affected", function()
      assert.is_false(exec_run.is_query_sql("insert into t values (1)"))
      assert.is_false(exec_run.is_query_sql("  update t set x = 1"))
    end)
  end)

  describe("for_each_event", function()
    it("decodes jobstart line-split data (newlines stripped, trailing empty)", function()
      local events = {}
      -- jobstart with buffered stdout delivers each event as its own array
      -- element, with no embedded newlines, plus a trailing "".
      local data = {
        '{"type":"progress","seq":1,"total":1,"sql":"SELECT 1"}',
        '{"type":"result","seq":1,"total":1,"status":"ok","sql":"SELECT 1","row_count":1,"affected_rows":null}',
        '{"type":"summary","total":1,"succeeded":1,"failed":0,"total_rows":1,"total_affected":0,"connection":"sqlite::memory:","dialect":"sqlite","mode":"greedy","rolled_back":false}',
        "",
      }
      exec_run.for_each_event(data, function(ev) events[#events + 1] = ev end)
      assert.equals(3, #events)
      assert.equals("result", events[2].type)
      assert.equals(1, events[2].row_count)
      assert.equals("summary", events[3].type)
    end)

    it("ignores non-JSON and empty elements", function()
      local events = {}
      exec_run.for_each_event({ "", "not json", '{"type":"result"}', "" }, function(ev)
        events[#events + 1] = ev
      end)
      assert.equals(1, #events)
      assert.equals("result", events[1].type)
    end)

    it("decodes a single raw blob split by newlines (no trailing empty)", function()
      local events = {}
      local blob = '{"type":"progress"}\n{"type":"summary","total":1,"succeeded":1,"failed":0,"total_rows":1,"total_affected":0,"dialect":"sqlite","mode":"greedy","rolled_back":false}'
      local lines = vim.split(blob, "\n")
      exec_run.for_each_event(lines, function(ev) events[#events + 1] = ev end)
      assert.equals(2, #events)
    end)
  end)

  describe("strip_section_markers", function()
    it("removes ### section markers so exec-file sees clean SQL", function()
      local out = exec_run.strip_section_markers(
        "-- @connection malldev\n###\nselect * from merchant\n###\n"
      )
      assert.equals("-- @connection malldev\nselect * from merchant\n", out)
    end)

    it("keeps non-marker lines (including # in strings) intact", function()
      local out = exec_run.strip_section_markers("select * from t where note = 'a#b';\n")
      assert.equals("select * from t where note = 'a#b';\n", out)
    end)
  end)
end)
