local helpers = require("poste-db.introspect.helpers")

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
      { name = "authors", type = "BASE TABLE" },
      { name = "posts", type = "view" },
    })

    assert.same({
      "  authors",
      "  posts  (view)",
    }, lines)
  end)

  -- Entries arrive straight from the binary's JSON; a null (vim.NIL) or
  -- missing type/name used to reach the `..` operator and raise.
  it("build_table_lines survives a missing or null type", function()
    assert.same({ "  logs" }, helpers.build_table_lines({ { name = "logs" } }))
    assert.same({ "  logs" }, helpers.build_table_lines({ { name = "logs", type = vim.NIL } }))
    assert.same({ "  logs" }, helpers.build_table_lines({ { name = "logs", type = "" } }))
  end)

  it("build_table_lines keeps a placeholder row when the name is missing", function()
    assert.same({ "  ?  (VIEW)" }, helpers.build_table_lines({ { type = "VIEW" } }))
    assert.same({ "  ?" }, helpers.build_table_lines({ { name = vim.NIL } }))
  end)

  it("build_database_info_lines formats database metadata", function()
    local lines = helpers.build_database_info_lines({
      name = "blog",
      table_count = 12,
      total_size = "48 MB",
      encoding = "UTF8",
      charset = "utf8mb4",
      collation = "utf8mb4_general_ci",
      size_mb = 48.5,
      file = "/tmp/blog.sqlite",
    })

    assert.same({
      "  Name          blog  ",
      "  Table Count   12  ",
      "  Total Size    48 MB  ",
      "  Encoding      UTF8  ",
      "  Charset       utf8mb4  ",
      "  Collation     utf8mb4_general_ci  ",
      "  File          /tmp/blog.sqlite  ",
    }, lines)
  end)

  it("build_database_info_lines omits nil and empty fields", function()
    local lines = helpers.build_database_info_lines({
      name = "blog",
      table_count = 3,
      encoding = nil,
      file = "",
    })

    assert.same({
      "  Name          blog  ",
      "  Table Count   3  ",
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
