local ctx = require("poste-sql.introspect.context")

describe("introspect context", function()
  it("resolves dot_column targets as columns", function()
    local target = ctx.resolve_detected_target({
      ctx_type = "dot_column",
      ctx_data = "p",
      tables = {
        { name = "posts", alias = "p", schema = "blog" },
      },
    }, "title", "blog", "body")

    assert.same({
      kind = "column",
      db = "blog",
      parent_table = "posts",
      parent_schema = "blog",
      column_name = "body",
    }, target)
  end)

  it("resolves schema_table targets as ddl lookups", function()
    local target = ctx.resolve_detected_target({
      ctx_type = "schema_table",
      ctx_data = "blog",
    }, "authors", "main")

    assert.same({
      kind = "ddl",
      db = "blog",
      table_name = "authors",
    }, target)
  end)

  it("resolves schema-qualified tables as list tables targets", function()
    local target = ctx.resolve_detected_target({
      ctx_type = "table",
      tables = {
        { name = "authors", schema = "blog" },
      },
    }, "blog", "main")

    assert.same({
      kind = "list_tables",
      db = "blog",
    }, target)
  end)

  it("resolves table matches as ddl targets", function()
    local target = ctx.resolve_detected_target({
      ctx_type = "table",
      tables = {
        { name = "authors", schema = "blog" },
      },
    }, "authors", "main")

    assert.same({
      kind = "ddl",
      db = "blog",
      table_name = "authors",
    }, target)
  end)

  it("resolves non-table columns as column targets", function()
    local target = ctx.resolve_detected_target({
      ctx_type = "column",
      tables = {
        { name = "authors", schema = "blog" },
      },
    }, "name", "main")

    assert.same({
      kind = "column",
      db = "main",
      parent_table = "authors",
      parent_schema = "blog",
      column_name = "name",
    }, target)
  end)
end)
