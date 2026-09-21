local dml = require("poste-db.dml")

describe("dml generation", function()
  local columns = {
    { name = "id", primary_key = true },
    { name = "title" },
    { name = "active" },
  }

  it("generates update statements with pk where clauses", function()
    local sql = dml.generate_update("blog", "posts", columns, {
      { col = 2, old_val = "old", new_val = "new" },
    }, { 7, "old", true }, "postgres")

    assert.equals('UPDATE "blog"."posts" SET "title" = \'new\' WHERE "id" = 7;', sql)
  end)

  it("emits exact bigint strings unquoted in SET and WHERE", function()
    local sql = dml.generate_update("blog", "posts", columns, {
      { col = 2, old_val = "old", new_val = "2084515900853196878" },
    }, { "2084515900853196878", "old", true }, "postgres")

    assert.equals('UPDATE "blog"."posts" SET "title" = 2084515900853196878 WHERE "id" = 2084515900853196878;', sql)
  end)

  it("keeps values beyond int64 exact — no LuaJIT %d clamping", function()
    -- uint64 above 2^63-1 round-trips through a double as text; %d used to
    -- clamp it to 9223372036854775807
    local sql = dml.generate_insert("", "posts", { { name = "id" } },
      { "9223372036854775808" }, "mysql")
    assert.equals("INSERT INTO `posts` (`id`) VALUES (9223372036854775808);", sql)

    -- an integer-valued float (1e20) must not clamp either
    sql = dml.generate_insert("", "posts", { { name = "big" } }, { 1e20 }, "mysql")
    assert.equals("INSERT INTO `posts` (`big`) VALUES (100000000000000000000);", sql)
  end)

  it("generates insert statements and skips [Auto] markers", function()
    local sql = dml.generate_insert("blog", "posts", columns, {
      "[Auto]",
      "hello",
      false,
    }, "mysql")

    assert.equals("INSERT INTO `blog`.`posts` (`title`, `active`) VALUES ('hello', FALSE);", sql)
  end)

  it("generates delete statements using all row values when no pk exists", function()
    local sql = dml.generate_delete("", "posts", {
      { name = "title" },
      { name = "active" },
    }, { "hello", false }, "sqlite")

    assert.equals('DELETE FROM "posts" WHERE "title" = \'hello\' AND "active" = FALSE;', sql)
  end)

  it("refuses a WHERE-less UPDATE instead of rewriting the whole table", function()
    -- no PK + every column NULL: no clause can target the row — the old
    -- generator emitted `UPDATE t SET …;` with no WHERE (full-table update)
    local no_pk_cols = {
      { name = "note" },
      { name = "extra" },
    }
    local sql, err = dml.generate_update("blog", "posts", no_pk_cols, {
      { col = 1, old_val = nil, new_val = "x" },
    }, { nil, nil }, "postgres")
    assert.is_nil(sql)
    assert.truthy(err:find("WHERE target"))
  end)

  it("refuses an UPDATE with no surviving SET column", function()
    local sql, err = dml.generate_update("blog", "posts", columns, {
      { col = 9, old_val = "x", new_val = "y" },  -- out-of-range column
    }, { 1, "old", true }, "postgres")
    assert.is_nil(sql)
    assert.truthy(err:find("settable"))
  end)

  it("refuses a DELETE with no WHERE target", function()
    -- the old generator emitted broken `WHERE ;` SQL for an all-NULL row
    local sql, err = dml.generate_delete("", "posts", {
      { name = "title" },
      { name = "active" },
    }, { nil, nil }, "sqlite")
    assert.is_nil(sql)
    assert.truthy(err:find("WHERE target"))
  end)

  it("generates a combined dml summary", function()
    local stmts = dml.generate_dml({
      modified_cells = {
        ["1:2"] = { col = 2, old_val = "old", new_val = "new" },
      },
      deleted_rows = {
        [2] = true,
      },
      added_rows = {
        { data = { nil, "inserted", true } },
      },
    }, {
      layout = {
        schema = "blog",
        table_name = "posts",
        columns = columns,
      },
      rows_source = {
        { 1, "old", true },
        { 2, "gone", false },
      },
    }, "postgres")

    local counts = { update = 0, delete = 0, insert = 0 }
    for _, stmt in ipairs(stmts) do
      counts[stmt.type] = counts[stmt.type] + 1
    end

    assert.equals(1, counts.update)
    assert.equals(1, counts.delete)
    assert.equals(1, counts.insert)
  end)

  it("emits statements in row order and SET parts in column order", function()
    -- keys inserted in scrambled order into the edit_state tables; the
    -- generated batch must still read 1, 2, 3 and "a" before "c"
    local cols = { { name = "a", primary_key = true }, { name = "b" }, { name = "c" } }
    local stmts = dml.generate_dml({
      modified_cells = {
        ["3:3"] = { col = 3, old_val = "x", new_val = "z3" },
        ["3:2"] = { col = 2, old_val = "x", new_val = "y3" },
        ["1:2"] = { col = 2, old_val = "x", new_val = "y1" },
        ["2:2"] = { col = 2, old_val = "x", new_val = "y2" },
      },
      deleted_rows = {},
      added_rows = {},
    }, {
      layout = { schema = "", table_name = "t", columns = cols },
      rows_source = {
        { 1, "x", "x" },
        { 2, "x", "x" },
        { 3, "x", "x" },
      },
    }, "postgres")

    local sqls = {}
    for _, s in ipairs(stmts) do sqls[#sqls + 1] = s.sql end
    assert.equals(3, #stmts)
    assert.equals('UPDATE "t" SET "b" = \'y1\' WHERE "a" = 1;', sqls[1])
    assert.matches('"a" = 2', sqls[2])
    assert.equals('UPDATE "t" SET "b" = \'y3\', "c" = \'z3\' WHERE "a" = 3;', sqls[3])
  end)

  it("skips and reports statements it refuses to generate", function()
    -- row 1 all-NULL beyond the PK-less layout: the update must be refused
    -- and surfaced via the skipped list, not emitted as table-wide SQL
    local stmts, skipped = dml.generate_dml({
      modified_cells = {
        ["1:2"] = { col = 2, old_val = nil, new_val = "new" },
      },
      deleted_rows = {},
      added_rows = {},
    }, {
      layout = {
        schema = "blog",
        table_name = "posts",
        columns = {
          { name = "note" },
          { name = "title" },
        },
      },
      rows_source = {
        { nil, nil },
      },
    }, "postgres")

    assert.equals(0, #stmts)
    assert.equals(1, #skipped)
    assert.truthy(skipped[1]:find("update row 1"))
  end)
end)

describe("generate_insert __expr gating", function()
  local cols = { { name = "note", ctype = "text" } }

  it("import path (no allow_expr): a crafted __expr: cell stays a string literal", function()
    -- a CSV cell is untrusted input: `__expr:` is the EDITOR's escape hatch
    -- and must never fire on imported data
    local sql = require("poste-db.dml").generate_insert(
      nil, "t", cols, { "__expr:(SELECT 1)" }, "postgres")
    assert.equals('INSERT INTO "t" ("note") VALUES (\'__expr:(SELECT 1)\');', sql)
  end)

  it("editor path (allow_expr): __expr: still emits raw SQL", function()
    local sql = require("poste-db.dml").generate_insert(
      nil, "t", cols, { "__expr:CURRENT_TIMESTAMP" }, "postgres", true)
    assert.equals('INSERT INTO "t" ("note") VALUES (CURRENT_TIMESTAMP);', sql)
  end)

  it("generate_update honors the same gate on both SET and WHERE values", function()
    local columns = {
      { name = "id", ctype = "integer", primary_key = true },
      { name = "note", ctype = "text" },
    }
    local sql = dml.generate_update(
      nil, "t", columns,
      { { col = 2, new_val = "__expr:now()" } },
      { 1, "keep" }, "postgres")
    assert.equals('UPDATE "t" SET "note" = \'__expr:now()\' WHERE "id" = 1;', sql)

    -- no-PK table: the WHERE falls back to every non-NULL column value, so
    -- the hatch-closed literal lands in the WHERE clause too
    local sql3 = dml.generate_update(
      nil, "t", { { name = "note", ctype = "text" } },
      { { col = 1, new_val = "y" } },
      { "__expr:1=1" }, "postgres")
    assert.equals('UPDATE "t" SET "note" = \'y\' WHERE "note" = \'__expr:1=1\';', sql3)
  end)
end)

describe("literal quoting", function()
  local cols = { { name = "zip" } }
  local function insert(val, dialect)
    return dml.generate_insert(nil, "t", cols, { val }, dialect)
  end

  it("escapes backslashes where the dialect honors them", function()
    -- MySQL/MariaDB/ClickHouse read `\` as an escape inside '…' too: doubling
    -- only the quote let `\'` eat the closing quote, and everything after it
    -- became a second statement (DROP TABLE users) inside one INSERT
    assert.equals([[INSERT INTO `t` (`zip`) VALUES ('\\''; DROP TABLE users; --');]],
      insert([[\'; DROP TABLE users; --]], "mysql"))
    assert.equals([[INSERT INTO `t` (`zip`) VALUES ('\\''; DROP TABLE users; --');]],
      insert([[\'; DROP TABLE users; --]], "clickhouse"))
    -- standard-conforming dialects: the backslash is plain text, so it must
    -- NOT be doubled (that would corrupt the stored value)
    assert.equals([[INSERT INTO "t" ("zip") VALUES ('\''; DROP TABLE users; --');]],
      insert([[\'; DROP TABLE users; --]], "postgres"))
    assert.equals([[INSERT INTO "t" ("zip") VALUES ('\''; DROP TABLE users; --');]],
      insert([[\'; DROP TABLE users; --]], "sqlite"))
  end)

  it("quotes a string that only looks numeric", function()
    -- bare `007` is the number 7 to the server, and `1.50` the number 1.5:
    -- the cell's own text has to survive the round trip
    assert.equals([[INSERT INTO `t` (`zip`) VALUES ('007');]], insert("007", "mysql"))
    assert.equals([[INSERT INTO "t" ("zip") VALUES ('1.50');]], insert("1.50", "postgres"))
    assert.equals([[INSERT INTO "t" ("zip") VALUES ('3.0');]], insert("3.0", "postgres"))
  end)

  it("still emits digits a double cannot hold as an exact literal", function()
    -- the value is a bigint preserved as text: quoting it would make it a
    -- string, emitting it as a number would move its digits
    assert.equals([[INSERT INTO "t" ("zip") VALUES (2084515900853196878);]],
      insert("2084515900853196878", "postgres"))
    assert.equals([[INSERT INTO "t" ("zip") VALUES (42);]], insert("42", "postgres"),
      "a plain integer that round-trips stays a bare literal")
  end)
end)

describe("the column type decides whether digits are a number", function()
  local function cols_with(ctype_field, ctype)
    local col = { name = "code" }
    col[ctype_field] = ctype
    return { col }
  end

  local function insert(ctype_field, ctype, val, dialect)
    return dml.generate_insert(nil, "t", cols_with(ctype_field, ctype), { val }, dialect)
  end

  it("quotes digits heading for a text column", function()
    -- bare 42 is an integer literal: postgres has no `text = integer`
    -- operator and MySQL answers by storing 42 where the cell said '042'
    assert.equals([[INSERT INTO "t" ("code") VALUES ('42');]], insert("ctype", "varchar", "42", "postgres"))
    assert.equals([[INSERT INTO `t` (`code`) VALUES ('007');]], insert("type", "text", "007", "mysql"))
    assert.equals([[INSERT INTO "t" ("code") VALUES ('42');]], insert("col_type", "character varying", "42", "postgres"))
  end)

  it("leaves digits bare for a numeric column", function()
    assert.equals([[INSERT INTO "t" ("code") VALUES (42);]], insert("ctype", "integer", "42", "postgres"))
    assert.equals([[INSERT INTO "t" ("code") VALUES (1.5);]], insert("type", "numeric(10,2)", "1.5", "postgres"))
    assert.equals([[INSERT INTO "t" ("code") VALUES ('1.50');]],
      insert("type", "numeric(10,2)", "1.50", "postgres"),
      "a precision a double cannot carry stays the cell's own text")
    assert.equals([[INSERT INTO "t" ("code") VALUES (2084515900853196878);]],
      insert("ctype", "bigint", "2084515900853196878", "postgres"))
  end)

  it("keeps working for a column with no type at all", function()
    -- callers that never had a type to pass (and every spec written before the
    -- type was plumbed through) read as permissive as they did
    assert.equals([[INSERT INTO "t" ("code") VALUES (42);]], insert("ctype", nil, "42", "postgres"))
  end)

  it("quotes the same value in a WHERE clause, where a mismatch fails the statement", function()
    -- no primary key, so every non-NULL value is a WHERE target; comparing a
    -- text column to a bare integer is something postgres refuses to plan at
    -- all (`operator does not exist: text = integer`)
    local cols = { { name = "code", ctype = "varchar" }, { name = "seq", ctype = "integer" } }
    local sql = dml.generate_delete(nil, "t", cols, { "42", 7 }, "postgres")
    assert.equals([[DELETE FROM "t" WHERE "code" = '42' AND "seq" = 7;]], sql)
  end)

  it("quotes it in an UPDATE SET too", function()
    local cols = { { name = "code", ctype = "varchar" }, { name = "id", ctype = "integer", primary_key = true } }
    local sql = dml.generate_update(nil, "t", cols,
      { { col = 1, new_val = "007" } }, { "42", 7 }, "postgres")
    assert.equals([[UPDATE "t" SET "code" = '007' WHERE "id" = 7;]], sql)
  end)
end)
