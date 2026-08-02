local helpers = require("poste-sql.introspect.helpers")

describe("introspect helpers", function()
  it("build_connection_lines formats populated fields", function()
    local lines = helpers.build_connection_lines({
      dialect = "postgres",
      host = "localhost",
      port = 5432,
      database = "blog",
      user = "alice",
      path = "/tmp/postgres.sock",
    })

    assert.same({
      "     Dialect  postgres",
      "        Host  localhost",
      "        Port  5432",
      "    Database  blog",
      "        User  alice",
      "      Socket  /tmp/postgres.sock",
    }, lines)
  end)

  it("build_table_lines formats table name and type", function()
    local lines = helpers.build_table_lines({
      { name = "authors", type = "table" },
      { name = "posts", type = "view" },
    })

    assert.same({
      "  authors  (table)",
      "  posts  (view)",
    }, lines)
  end)

  it("build_column_info_lines includes optional metadata", function()
    local lines = helpers.build_column_info_lines("authors", {
      type = "text",
      nullable = false,
      default = vim.NIL,
      extra = "auto_increment",
      max_length = 255,
      comment = "display name",
    })

    assert.same({
      "  Table:    authors",
      "  Type:     text",
      "  Nullable: NO",
      "  Default:  (null)",
      "  Extra:    auto_increment",
      "  Max Len:  255",
      "  Comment:  'display name'",
    }, lines)
  end)
end)
