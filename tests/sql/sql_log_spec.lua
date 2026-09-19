local sql_log = require("poste-db.sql_log")

describe("sql_log", function()
  after_each(function()
    sql_log.set_log_path(nil)
  end)

  describe("format_entry", function()
    it("maps internal names to JSON keys and passes extras through", function()
      local raw = sql_log.format_entry({
        source = "dataset_commit",
        table_name = "posts",
        connection = "conn",
        dialect = "postgres",
        database = "blog",
        sql = "UPDATE posts SET title = 'x';",
        status = "success",
        elapsed_ms = 12,
        error_msg = "boom",
        edit_summary = { updates = 1 },
        affected_rows = 3,
      })

      local decoded = vim.json.decode(raw)
      assert.equals("dataset_commit", decoded.source)
      assert.equals("posts", decoded["table"])
      assert.equals("conn", decoded.connection)
      assert.equals("postgres", decoded.dialect)
      assert.equals("blog", decoded.database)
      assert.equals("UPDATE posts SET title = 'x';", decoded.sql)
      assert.equals("success", decoded.status)
      assert.equals(12, decoded.elapsed_ms)
      assert.equals("boom", decoded.error)
      assert.is_nil(decoded.error_msg, "internal name must not leak as its own key")
      assert.is_nil(decoded.table_name, "internal name must not leak as its own key")
      assert.same({ updates = 1 }, decoded.edit_summary)
      assert.equals(3, decoded.affected_rows)
      assert.is_string(decoded.ts)
    end)

    it("omits nil fields and tolerates an empty entry", function()
      local raw = sql_log.format_entry({})
      local decoded = vim.json.decode(raw)
      assert.is_nil(decoded.status)
      assert.is_string(decoded.ts)
    end)
  end)

  describe("record", function()
    it("writes a json line per entry to the configured path", function()
      local path = vim.fn.tempname() .. ".jsonl"
      sql_log.set_log_path(path)

      sql_log.record({ source = "exec", sql = "SELECT 1;", status = "success", elapsed_ms = 5 })
      sql_log.record({ source = "browser", status = "error", error_msg = "Timeout" })

      local lines = vim.fn.readfile(path)
      assert.equals(2, #lines)
      local first = vim.json.decode(lines[1])
      assert.equals("exec", first.source)
      assert.equals("SELECT 1;", first.sql)
      local second = vim.json.decode(lines[2])
      assert.equals("browser", second.source)
      assert.equals("Timeout", second.error)
    end)

    it("redacts credentials in connection URLs", function()
      local path = vim.fn.tempname() .. ".jsonl"
      sql_log.set_log_path(path)

      sql_log.record({ source = "exec", connection = "mysql://root:s3cret@localhost:3306/blog" })

      local lines = vim.fn.readfile(path)
      local decoded = vim.json.decode(lines[1])
      assert.equals("mysql://root:***@localhost:3306/blog", decoded.connection)
      assert.is_nil(lines[1]:find("s3cret", 1, true))
    end)

    it("truncates long error messages", function()
      local path = vim.fn.tempname() .. ".jsonl"
      sql_log.set_log_path(path)

      sql_log.record({ source = "exec", status = "error", error_msg = string.rep("x", 2000) })

      local decoded = vim.json.decode(vim.fn.readfile(path)[1])
      assert.equals(500, #decoded.error)
    end)
  end)

  describe("seam_base", function()
    it("returns nil when the caller opts out", function()
      assert.is_nil(sql_log.seam_base({ log = false, conn_url = "pg://x" }))
    end)

    it("defaults the source tag and redacts the URL connection", function()
      local base = sql_log.seam_base({ conn_url = "pg://u:pw@h/db", database = "app" })
      assert.equals("exec", base.source)
      assert.equals("pg://u:***@h/db", base.connection)
      assert.equals("app", base.database)
    end)

    it("prefers the caller-provided connection name over the URL", function()
      local base = sql_log.seam_base({
        conn_url = "pg://u:pw@h/db",
        log_source = "manual_exec",
        log_extra = { connection = "pg-dev" },
      })
      assert.equals("manual_exec", base.source)
      assert.equals("pg-dev", base.connection)
    end)
  end)
end)

describe("log.redact_url", function()
  local log = require("poste-db.log")

  it("covers a password that contains a slash", function()
    -- The old `[^@/]+` class stopped at the '/' and left the whole DSN in the
    -- journal verbatim.
    assert.equals("postgres://u:***@h:5432/db", log.redact_url("postgres://u:pa/ss@h:5432/db"))
    assert.equals("mysql://u:***@h/db", log.redact_url("mysql://u:p@ss@w@h/db"))
  end)

  it("redacts credentials carried in the query string", function()
    assert.equals("postgres://h:5432/db?password=***&sslmode=disable",
      log.redact_url("postgres://h:5432/db?password=hunter2&sslmode=disable"))
    assert.equals("https://api.h/reset?token=***", log.redact_url("https://api.h/reset?token=abc123"))
  end)

  it("redacts key=value DSNs (libpq and ODBC spellings)", function()
    assert.equals("connection failed for host=h user=root password=***",
      log.redact_url("connection failed for host=h user=root password=hunter2"))
    assert.equals("Driver={x};server=h;pwd=***",
      log.redact_url("Driver={x};server=h;Pwd=hunter2"))
    assert.equals("password=***", log.redact_url("password=hunter2"))
  end)

  it("leaves SQL and non-credential URLs intact", function()
    assert.equals([[UPDATE t SET password='hunter2' WHERE id=1]],
      log.redact_url([[UPDATE t SET password='hunter2' WHERE id=1]]))
    assert.equals("SET token = 1", log.redact_url("SET token = 1"))
    assert.equals("SELECT 1;token=2", log.redact_url("SELECT 1;token=2"))
    assert.equals("postgres://localhost:5432/db?user=a@b",
      log.redact_url("postgres://localhost:5432/db?user=a@b"))
    assert.equals("pg://u@h/db", log.redact_url("pg://u@h/db"))
  end)

  it("redacts a DSN that appears anywhere in a longer message", function()
    assert.equals("exec-file /tmp/x.sql --connection postgres://u:***@h/db --mode greedy",
      log.redact_url("exec-file /tmp/x.sql --connection postgres://u:pw@h/db --mode greedy"))
  end)

  it("passes non-strings through", function()
    assert.same(7, log.redact_url(7))
    assert.same(vim.NIL, log.redact_url(vim.NIL))
  end)

  it("keeps a query-string DSN out of the journal file", function()
    local path = vim.fn.tempname() .. ".jsonl"
    sql_log.set_log_path(path)
    sql_log.record({ source = "exec", connection = "postgres://h:5432/db?password=hunter2" })
    local line = vim.fn.readfile(path)[1]
    assert.is_nil(line:find("hunter2", 1, true))
    assert.matches("password=%*%*%*", line)
  end)
end)
