local dml = require("poste-sql.dml")

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
end)
