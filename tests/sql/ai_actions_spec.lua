describe("poste-db.ai.mentions", function()
  local mentions = require("poste-db.ai.mentions")

  describe("match", function()
    it("matches connection/database tokens from connections.toml", function()
      local ref = mentions._test.match("my-blog/blog")
      assert.is_not_nil(ref)
      assert.are.equal("my-blog", ref.connection)
      assert.are.equal("blog", ref.database)
      assert.is_nil(ref.table)
    end)

    it("matches connection/database/table tokens", function()
      local ref = mentions._test.match("my-blog/blog/users")
      assert.is_not_nil(ref)
      assert.are.equal("my-blog", ref.connection)
      assert.are.equal("blog", ref.database)
      assert.are.equal("users", ref.table)
    end)

    it("rejects unknown connections", function()
      assert.is_nil(mentions._test.match("no-such-conn/db"))
      assert.is_nil(mentions._test.match("no-such-conn/db/users"))
    end)

    it("leaves file-like tokens alone (file fallback)", function()
      assert.is_nil(mentions._test.match("src/app.lua"))
      assert.is_nil(mentions._test.match("singleword"))
      assert.is_nil(mentions._test.match("test.sql"))
    end)
  end)

  describe("candidates", function()
    it("builds conn/db candidates from the connection list", function()
      local cands = mentions._test.candidates({
        { name = "my-blog", dialect = "mysql", host = "h1", database = "blog" },
        { name = "sqlite-dev", dialect = "sqlite", path = "./x.db" },
      })
      assert.are.equal(2, #cands)
      assert.are.equal("my-blog/blog", cands[1].label)
      assert.truthy(cands[1].description:find("mysql"))
      assert.are.equal("sqlite-dev/db", cands[2].label)
    end)
  end)

  describe("table_line", function()
    it("renders name, comment and columns", function()
      local line = mentions._test.table_line("posts", "User posts", {
        { name = "id", type = "int" },
        { name = "title", type = "varchar", comment = "标题" },
      })
      assert.truthy(line:find("^%- posts %(User posts%)"))
      assert.truthy(line:find("id: int"))
      assert.truthy(line:find("title: varchar %(标题%)"))
    end)

    it("renders bare tables without columns", function()
      assert.are.equal("- users", mentions._test.table_line("users", nil, nil))
    end)
  end)
end)

describe("poste-db.ai.actions", function()
  local actions = require("poste-db.ai.actions")

  describe("is_readonly", function()
    it("accepts clear read-only statements", function()
      assert.is_true(actions._test.is_readonly("SELECT * FROM users"))
      assert.is_true(actions._test.is_readonly("  select 1"))
      assert.is_true(actions._test.is_readonly("WITH t AS (SELECT 1) SELECT * FROM t"))
      assert.is_true(actions._test.is_readonly("SHOW TABLES"))
      assert.is_true(actions._test.is_readonly("EXPLAIN SELECT 1"))
    end)

    it("flags writes as not read-only", function()
      assert.is_false(actions._test.is_readonly("INSERT INTO users VALUES (1)"))
      assert.is_false(actions._test.is_readonly("UPDATE users SET a = 1"))
      assert.is_false(actions._test.is_readonly("DELETE FROM users"))
      assert.is_false(actions._test.is_readonly("DROP TABLE users"))
      assert.is_false(actions._test.is_readonly("CREATE TABLE t (id int)"))
    end)
  end)

  describe("strip_directives", function()
    it("removes leading @connection/@database directives", function()
      local sql = actions._test.strip_directives("-- @connection my-blog\n-- @database blog\nSELECT 1")
      assert.are.equal("SELECT 1", sql)
    end)

    it("keeps plain SQL untouched", function()
      assert.are.equal("SELECT 1", actions._test.strip_directives("SELECT 1"))
    end)
  end)

  describe("resolve_target", function()
    local state = require("poste-db.state")

    after_each(function()
      state.context.connection = nil
      state.context.database = nil
      local ok, scope = pcall(require, "poste-ai.chat.scope")
      if ok then scope.clear() end
    end)

    it("prefers the mentioned connection/database", function()
      local conn, db = actions._test.resolve_target({
        { type = "context", context = "db", data = { connection = "my-blog", database = "blog" } },
      })
      assert.are.equal("my-blog", conn)
      assert.are.equal("blog", db)
    end)

    it("prefers the poste-ai chat scope over the SQL context", function()
      local ok, scope = pcall(require, "poste-ai.chat.scope")
      if not ok then
        pending("poste-ai.nvim not on rtp")
        return
      end
      state.context.connection = "pg-ecommerce"
      scope.set("connection", "my-blog")
      scope.set("database", "blog")
      local conn, db = actions._test.resolve_target({})
      assert.are.equal("my-blog", conn)
      assert.are.equal("blog", db)
    end)

    it("falls back to the current SQL context", function()
      state.context.connection = "pg-ecommerce"
      state.context.database = "shop"
      local conn, db = actions._test.resolve_target({})
      assert.are.equal("pg-ecommerce", conn)
      assert.are.equal("shop", db)
    end)

    it("errors when nothing is known", function()
      local _, _, err = actions._test.resolve_target({})
      assert.truthy(err:find("connection"))
    end)
  end)

  describe("append_header", function()
    local scope
    before_each(function()
      local ok, s = pcall(require, "poste-ai.chat.scope")
      scope = ok and s or nil
    end)
    after_each(function()
      if scope then scope.clear() end
    end)

    it("builds @connection/@database directives from the chat scope", function()
      local lines = actions._test.append_header({ connection = "my-blog", database = "blog" }, "SELECT 1")
      assert.are.same({ "-- @connection my-blog", "-- @database blog" }, lines)
    end)

    it("omits @database when unbound", function()
      local lines = actions._test.append_header({ connection = "my-blog" }, "SELECT 1")
      assert.are.same({ "-- @connection my-blog" }, lines)
    end)

    it("returns nil without a connection binding", function()
      assert.is_nil(actions._test.append_header({}, "SELECT 1"))
      assert.is_nil(actions._test.append_header(nil, "SELECT 1"))
    end)

    it("returns nil when the block already carries a directive", function()
      assert.is_nil(actions._test.append_header(
        { connection = "my-blog" }, "-- @connection other\nSELECT 1"))
    end)
  end)

  describe("execute_sql", function()
    local captured
    local real_executor = package.loaded["poste-db.executor"]
    local real_format = package.loaded["poste-db.format"]
    local real_buffer = package.loaded["poste-db.buffer"]

    before_each(function()
      captured = { opts = nil, rendered = nil }
      package.loaded["poste-db.format"] = {
        format_dataset = function() return { "line" }, {}, nil end,
      }
      package.loaded["poste-db.buffer"] = {
        render_dataset = function(_, _, opts) captured.rendered = opts end,
      }
    end)

    after_each(function()
      package.loaded["poste-db.executor"] = real_executor
      package.loaded["poste-db.format"] = real_format
      package.loaded["poste-db.buffer"] = real_buffer
    end)

    it("executes against the mentioned connection and renders the dataset", function()
      package.loaded["poste-db.executor"] = {
        execute = function(opts)
          captured.opts = opts
          opts.on_response({ body = vim.json.encode({ results = {} }) })
        end,
      }
      local err, note
      actions.execute_sql("SELECT 1", {
        { type = "context", context = "db", data = { connection = "my-blog", database = "blog" } },
      }, function(e, n) err, note = e, n end)
      vim.wait(500, function() return note ~= nil or err ~= nil end)

      assert.is_nil(err)
      assert.truthy(note:find("my%-blog"))
      assert.are.equal("blog", captured.opts.database)
      assert.is_truthy(captured.opts.conn_url:find("my%-blog") or captured.opts.conn_url:find("mysql"))
      assert.truthy(captured.rendered.original_sql:find("SELECT 1"))
    end)

    it("strips the model's @connection directive before executing", function()
      package.loaded["poste-db.executor"] = {
        execute = function(opts)
          captured.opts = opts
          opts.on_response({ body = "{}" })
        end,
      }
      actions.execute_sql("-- @connection my-blog\nSELECT 1", {
        { type = "context", context = "db", data = { connection = "my-blog", database = "blog" } },
      }, function() end)
      vim.wait(500, function() return captured.opts ~= nil end)
      assert.is_false(captured.opts.sql:find("@connection") ~= nil)
    end)

    it("surfaces in-band database errors as a chat error and retains them", function()
      local state_sql = require("poste-db.state")
      local body = vim.json.encode({
        results = { { error = "Table 'x.missing' doesn't exist" } },
      })
      package.loaded["poste-db.executor"] = {
        execute = function(opts)
          opts.on_response({ has_error = true, body = body })
        end,
      }
      local err, note
      actions.execute_sql("SELECT * FROM missing", {
        { type = "context", context = "db", data = { connection = "my-blog", database = "blog" } },
      }, function(e, n) err, note = e, n end)
      vim.wait(500, function() return err ~= nil or note ~= nil end)

      assert.truthy(err:find("doesn't exist", 1, true))
      assert.is_nil(note)
      assert.are.equal("SELECT * FROM missing", state_sql.last_error.sql)
      assert.truthy(state_sql.last_error.message:find("doesn't exist"))
      state_sql.last_error = nil
    end)

    it("surfaces SQL errors to the chat callback", function()
      package.loaded["poste-db.executor"] = {
        execute = function(opts)
          opts.on_error("syntax error at or near SELEC")
        end,
      }
      local err
      actions.execute_sql("SELEC 1", {
        { type = "context", context = "db", data = { connection = "my-blog", database = "blog" } },
      }, function(e) err = e end)
      vim.wait(500, function() return err ~= nil end)
      assert.truthy(err:find("syntax error"))
    end)

    it("fails cleanly without any connection knowledge", function()
      local state = require("poste-db.state")
      local saved_conn = state.context.connection
      state.context.connection = nil
      local err
      actions.execute_sql("SELECT 1", {}, function(e) err = e end)
      state.context.connection = saved_conn
      assert.truthy(err:find("connection"))
    end)
  end)
end)
