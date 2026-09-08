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
