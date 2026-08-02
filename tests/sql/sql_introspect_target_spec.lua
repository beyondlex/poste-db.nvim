local target = require("poste-sql.introspect_target")

describe("introspect target resolver", function()
  it("resolves directive actions", function()
    assert.same({ kind = "database", db_name = "blog" }, target.resolve_directive_action({
      kind = "database",
      db_name = "blog",
    }))
    assert.same({ kind = "connection", conn_name = "primary" }, target.resolve_directive_action({
      kind = "connection",
      conn_name = "primary",
    }))
  end)

  it("resolves list table targets", function()
    assert.same({ kind = "list_tables", db = "blog" }, target.resolve_detected_action({
      kind = "list_tables",
      db = "blog",
    }, "main", "authors"))
  end)

  it("resolves ddl targets with fallback db", function()
    assert.same({ kind = "ddl", db = "blog", table_name = "authors" }, target.resolve_detected_action({
      kind = "ddl",
      table_name = "authors",
      db = "blog",
    }, "main", "authors"))
  end)

  it("resolves column targets and preserves schema", function()
    assert.same({
      kind = "column",
      db = "main",
      parent_table = "posts",
      parent_schema = "blog",
      column_name = "title",
    }, target.resolve_detected_action({
      kind = "column",
      db = "main",
      parent_table = "posts",
      parent_schema = "blog",
      column_name = "title",
    }, "main", "title"))
  end)

  it("drops ambiguous column targets where table and column match", function()
    assert.is_nil(target.resolve_detected_action({
      kind = "column",
      parent_table = "name",
      column_name = "name",
    }, "main", "name"))
  end)
end)
