local statement = require("poste-sql.statement")

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

  it("strips backtick quotes", function()
    assert.equals("users", statement.extract_table_name("select * from `users`"))
  end)

  it("strips double-quote quotes", function()
    assert.equals("users", statement.extract_table_name('select * from "users"'))
  end)

  it("handles schema-qualified table names", function()
    assert.equals("users", statement.extract_table_name("select * from public.users"))
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
end)