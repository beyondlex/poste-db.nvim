local detect = require("poste-db.nav.detect")

describe("nav_detect", function()
  it("extracts the SQL block around the current line", function()
    local info = detect.extract_sql_block({
      "### query",
      "select",
      "from authors",
      "### other",
    }, 2, "select", 6)

    assert.same({
      block_start = 2,
      block_end = 3,
      offset = 5,
      sql_text = "select\nfrom authors",
    }, info)
  end)

  it("resolves dot_column aliases to a table target", function()
    local target = detect.resolve_detected_table_target({
      ctx_type = "dot_column",
      ctx_data = "p",
      tables = {
        { name = "posts", alias = "p" },
      },
    }, "p.title", 1, "title", {
      connection = "conn",
      database = "blog",
    })

    assert.same({
      action = "navigate_to_table",
      database = "blog",
      table_name = "posts",
      column_name = "title",
    }, target)
  end)
end)

-- nav/handlers.lua extends the cursor column forward to the first non-word
-- character, so `end_col` is the 0-based index just past the word under the
-- cursor ("select u.name" with the cursor on name → end_col = 13).
describe("nav_detect alias prefix", function()
  local parsed = {
    ctx_type = "column",
    tables = {
      { name = "comments", alias = "c" },
      { name = "posts", alias = "u" },
    },
  }
  local ctx = { connection = "conn", database = "blog" }

  it("resolves the prefix alias when the cursor sits on the column", function()
    local target = detect.resolve_detected_table_target(parsed, "select u.name from x", 13, "name", ctx)

    assert.same({
      action = "navigate_to_table",
      database = "blog",
      table_name = "posts",
      column_name = "name",
    }, target)
  end)

  it("falls back to the first table for an unknown prefix instead of guessing", function()
    local target = detect.resolve_detected_table_target(parsed, "select z.name from x", 13, "name", ctx)

    assert.same({
      action = "navigate_to_table",
      database = "blog",
      table_name = "comments",
      column_name = "name",
    }, target)
  end)
end)

-- The after-dot word is only the column when the cursor word ends right
-- before a dot (cursor on the alias of `alias.column`). A comma, space or
-- paren after the word means the cursor word IS the column; the old
-- unconditional scan stole the next token, so `SELECT p.title,o.x` with
-- the cursor on title navigated to column "o".
describe("nav_detect column word scan", function()
  local parsed = {
    ctx_type = "dot_column",
    ctx_data = "p",
    tables = { { name = "posts", alias = "p" } },
  }
  local ctx = { connection = "conn", database = "blog" }

  it("keeps the cursor column when a comma without space follows", function()
    -- "SELECT p.title,o.x": `title` ends at 0-based col 14, "," is next.
    local target = detect.resolve_detected_table_target(parsed, "SELECT p.title,o.x", 14, "title", ctx)

    assert.same("title", target.column_name)
  end)

  it("still reads the column after the dot when the cursor sits on the alias", function()
    -- "SELECT p.title": `p` ends at 0-based col 8, "." is next.
    local target = detect.resolve_detected_table_target(parsed, "SELECT p.title", 8, "p", ctx)

    assert.same("title", target.column_name)
  end)

  it("applies the same guard inside an INSERT column list", function()
    local ins = {
      ctx_type = "insert_column",
      ctx_data = "t",
      tables = { { name = "t" } },
    }
    -- "INSERT INTO t (a,b)": `a` ends at 0-based col 16, "," is next.
    local target = detect.resolve_detected_table_target(ins, "INSERT INTO t (a,b)", 16, "a", ctx)

    assert.same("a", target.column_name)
  end)
end)
