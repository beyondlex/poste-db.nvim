local statement = require("poste-db.statement")

describe("statement find_block_for_line", function()
  it("returns whole buffer when no markers exist", function()
    local buf = { "select 1", "select 2" }
    local s, e = statement._test.find_block_for_line(buf, 1)
    assert.equals(1, s)
    assert.equals(2, e)
  end)

  it("finds block boundaries for a line inside a block", function()
    local buf = { "### query", "select 1", "select 2", "### cleanup", "drop table" }
    local s, e = statement._test.find_block_for_line(buf, 2)
    assert.equals(2, s)
    assert.equals(3, e)
  end)

  it("finds block boundaries for the first line of a block", function()
    local buf = { "### query", "select 1", "### cleanup", "drop table" }
    local s, e = statement._test.find_block_for_line(buf, 2)
    assert.equals(2, s)
    assert.equals(2, e)
  end)

  it("returns nil for lines before the first block", function()
    local buf = { "-- @connection test", "### query", "select 1" }
    local s, e = statement._test.find_block_for_line(buf, 1)
    assert.equals(1, s)
    assert.equals(1, e)
  end)

  it("handles line at end of buffer", function()
    local buf = { "### query", "select 1" }
    local s, e = statement._test.find_block_for_line(buf, 2)
    assert.equals(2, s)
    assert.equals(2, e)
  end)
end)

describe("statement extract_table_name", function()
  it("returns nil for nil input", function()
    assert.is_nil(statement.extract_table_name(nil))
  end)

  it("returns nil for empty string", function()
    assert.is_nil(statement.extract_table_name(""))
  end)

  it("extracts FROM table", function()
    assert.equals("users", statement.extract_table_name("select * from users"))
  end)

  it("extracts UPDATE table", function()
    assert.equals("posts", statement.extract_table_name("update posts set title = 'foo'"))
  end)

  it("extracts INSERT INTO table", function()
    assert.equals("comments", statement.extract_table_name("insert into comments values (1)"))
  end)

  it("extracts FROM table (not JOIN target)", function()
    assert.equals("posts", statement.extract_table_name("select * from posts join authors on authors.id = posts.author_id"))
  end)

  it("returns nil for 2+ JOINs", function()
    assert.is_nil(statement.extract_table_name("select * from posts join authors on authors.id = posts.author_id join comments on comments.post_id = posts.id"))
  end)

  it("a 'join' inside a string literal does not count as a JOIN", function()
    -- two literals containing "join" used to trip join_count >= 2 and return
    -- nil, degrading the label to "result n" (09-12 carry)
    assert.equals("logs", statement.extract_table_name(
      "select * from logs where msg = 'join' and other = 'join again'"))
    -- one real JOIN plus a literal still extracts the FROM table
    assert.equals("logs", statement.extract_table_name(
      "select * from logs join t on t.id = logs.t_id where msg = 'join'"))
    -- doubled-quote escapes stay inside the literal
    assert.equals("logs", statement.extract_table_name(
      "select * from logs where msg = 'it''s a join'"))
  end)

  it("strips backtick quotes", function()
    assert.equals("users", statement.extract_table_name("select * from `users`"))
  end)

  it("strips double-quote quotes", function()
    assert.equals("users", statement.extract_table_name('select * from "users"'))
  end)

  it("handles schema-qualified table names", function()
    assert.equals("users", statement.extract_table_name("select * from public.users"))
  end)

  it("strips mssql bracket quotes", function()
    assert.equals("users", statement.extract_table_name("select * from [users]"))
  end)

  it("strips mssql bracket-qualified names ([db].[table] forms)", function()
    assert.equals("users", statement.extract_table_name("select * from [dbo].[users]"))
    assert.equals("orders", statement.extract_table_name("update [sales].[orders] set x = 1"))
  end)

  it("keeps only the last part of a three-part reference", function()
    -- `db.schema.tbl` and `schema.tbl` cannot be told apart in text, so the
    -- leftovers used to be handed on as the table name: `mydb.public.users`
    -- came back as `public.users`, which ident.quote (rightly) reads as one
    -- name, and the DML targeted a table called `public.users`.
    assert.equals("users", statement.extract_table_name("select * from mydb.public.users"))
    assert.equals("Orders", statement.extract_table_name("update [sales].[Orders] set x = 1"))
  end)

  it("keeps a dot inside a quoted name as part of the name", function()
    -- a table really called `staging.v1`, not `v1` in schema `staging`
    assert.equals("staging.v1", statement.extract_table_name('select * from "staging.v1"'))
    assert.equals("staging.v1", statement.extract_table_name("select * from `staging.v1`"))
    assert.equals("staging.v1", statement.extract_table_name("select * from [staging.v1]"))
    -- the qualifier still comes off, but only up to the quote boundaries: the
    -- last part is `staging.v1` quoted as one name, so its dot stays
    assert.equals("staging.v1", statement.extract_table_name('select * from "public"."staging.v1"'))
  end)

  it("keeps the case of a quoted name, and folds an unquoted one", function()
    -- the quotes are what says "exactly this name"; without them the engines
    -- fold identifiers to lower case, and the result has to match either way
    assert.equals("Users", statement.extract_table_name('update "Users" set x = 1'))
    assert.equals("MixedCase", statement.extract_table_name('SELECT count(*) FROM "MixedCase" x'))
    assert.equals("order_items", statement.extract_table_name("select * from ORDER_ITEMS"))
  end)

  it("reads a quoted name that contains a space", function()
    -- `%S+` stopped the token at the space, so `"Order Items"` read as `order`
    -- — a name that exists and is not the one being queried.
    assert.equals("Order Items", statement.extract_table_name('select * from "Order Items"'))
    assert.equals("Order Items", statement.extract_table_name('select * from "Order Items" where a = 1'))
    assert.equals("Order Items", statement.extract_table_name("select * from [Order Items]"))
    assert.equals("my tbl", statement.extract_table_name("select * from `my tbl`"))
  end)

  it("unescapes a doubled quote inside a name", function()
    -- the name the engine stored has one quote; handing on the doubled form
    -- would make ident.quote escape it a second time
    assert.equals('a"b', statement.extract_table_name('select * from "a""b"'))
    assert.equals("a]b", statement.extract_table_name("select * from [a]]b]"))
  end)

  it("returns nil when the chain does not end in a name", function()
    assert.is_nil(statement.extract_table_name("select * from users."))
    assert.is_nil(statement.extract_table_name("select * from .hidden"))
  end)

  it("ends a bare name at a delimiter glued onto it", function()
    -- no space between the table and its column list, which is how a lot of
    -- generated INSERTs read
    assert.equals("users", statement.extract_table_name("insert into users(a,b) values (1,2)"))
    assert.equals("users", statement.extract_table_name("select * from users;"))
  end)

  it("returns nil for a comma table list", function()
    -- the 2+ JOIN guard above cannot see `FROM a, b`, and picking the first
    -- table would let the DML edit a row of the wrong one
    assert.is_nil(statement.extract_table_name("select * from users,orders"))
    assert.is_nil(statement.extract_table_name("select * from users , orders"))
    assert.is_nil(statement.extract_table_name('select * from "users", orders'))
    assert.is_nil(statement.extract_table_name("update users, orders set x = 1"))
  end)

  it("returns nil for a subquery in the table position", function()
    -- `(select` used to come back as a table name, and the DML builder quoted
    -- it into `"(select"` — a table that does not exist
    assert.is_nil(statement.extract_table_name("select * from (select 1) x"))
  end)

  it("still hands back a CTE name (recorded limitation)", function()
    -- `WITH t AS (...) SELECT * FROM t` points at a row set that exists only
    -- for this query; the extraction has no statement structure to tell that
    -- apart, so `t` comes back as the table. Pinned here so a change is a
    -- decision, not a surprise.
    assert.equals("t", statement.extract_table_name("with t as (select 1) select * from t"))
  end)

  it("keeps a non-ASCII bare name whole", function()
    -- byte-wise scanning must not mistake a UTF-8 continuation byte for a
    -- delimiter
    assert.equals("用户", statement.extract_table_name("select * from 用户 where a = 1"))
  end)

  it("lowercases the result", function()
    assert.equals("users", statement.extract_table_name("select * from USERS"))
  end)

  it("strips inline comments", function()
    assert.equals("users", statement.extract_table_name("select * from users -- comment"))
  end)

  it("strips block comments", function()
    assert.equals("users", statement.extract_table_name("select * from users /* block */"))
  end)
end)

describe("statement get_stmt_sql", function()
  it("returns empty string for nil start", function()
    assert.equals("", statement.get_stmt_sql({ "a" }, { 1 }, 2))
  end)

  it("returns single line", function()
    assert.equals("select 1", statement.get_stmt_sql({ "select 1", "select 2" }, { 1 }, 1))
  end)

  it("concatenates multi-line statement", function()
    assert.equals("select 1 select 2", statement.get_stmt_sql({ "select 1", "select 2", "select 3" }, { 1, 3 }, 1))
  end)

  it("stops at next statement line", function()
    assert.equals("select 1", statement.get_stmt_sql({ "select 1", "select 2" }, { 1, 2 }, 1, 2))
  end)

  it("respects max_end parameter", function()
    assert.equals("select 1 select 2", statement.get_stmt_sql({ "select 1", "select 2", "select 3" }, { 1 }, 1, 2))
  end)

  it("without max_end, the last statement truncates to its first line", function()
    -- Pinned semantics: callers that need the full text must pass max_end
    -- (response.lua passes `visual_sel_end or stmt_end or #buf_lines`).
    assert.equals("select *",
      statement.get_stmt_sql({ "select 1;", "select *", "from users;" }, { 1, 2 }, 2))
  end)
end)
describe("statement extract_stmt_at_cursor (Lua ;-heuristic fallback)", function()
  local rust_orig

  before_each(function()
    -- Force the Lua fallback: buf=nil skips Tree-sitter; stub the Rust probe
    -- (resolved dynamically via M.try_rust_stmt_span at call time).
    rust_orig = statement.try_rust_stmt_span
    statement.try_rust_stmt_span = function() return nil end
  end)

  after_each(function()
    statement.try_rust_stmt_span = rust_orig
  end)

  it("keeps the full head of the buffer's first multi-line statement", function()
    -- Regression: stmt_start used to initialize to cursor_line, chopping off
    -- the lines above the cursor when no `;`/directive preceded them.
    local lines = { "SELECT a,", "       b", "FROM t;" }
    local content, _, stmt_start, stmt_end = statement._test.extract_stmt_at_cursor(lines, 2, nil)
    assert.is_not_nil(content)
    assert.equals(1, stmt_start)
    assert.equals(3, stmt_end)
    assert.match("SELECT a,", content)
    assert.match("FROM t;", content)
  end)

  it("starts after top-of-file directives when no `;` precedes the cursor", function()
    local lines = { "-- @connection dev", "", "SELECT a,", "FROM t;" }
    local content, _, stmt_start = statement._test.extract_stmt_at_cursor(lines, 3, nil)
    assert.equals(3, stmt_start)
    assert.match("%-%- @connection dev", content)
    assert.match("SELECT a,", content)
  end)

  it("still pins the start after a preceding semicolon", function()
    local lines = { "SELECT 1;", "SELECT x,", "       y;" }
    local _, _, stmt_start = statement._test.extract_stmt_at_cursor(lines, 3, nil)
    assert.equals(2, stmt_start)
  end)
end)
