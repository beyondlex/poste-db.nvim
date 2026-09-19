--- Item 13: dialect-correct SQL the DB Browser generates (T-SQL has neither
--- LIMIT nor RENAME TO/COLUMN) and ident.quote-based DDL quoting.
local ops_sql = require("poste-db.db_browser.ops_sql")
local db_create = require("poste-db.db_browser.db_create")

local function table_node(overrides)
  return vim.tbl_extend("force", {
    node_type = "table",
    name = "orders",
    meta = { schema = "public", database = "blog" },
  }, overrides or {})
end

describe("db_browser generated SELECT row cap", function()
  it("uses LIMIT outside T-SQL", function()
    assert.equals('SELECT * FROM "orders" LIMIT 100;',
      ops_sql.select_star_sql('"orders"', "postgres"))
    assert.equals('SELECT * FROM "orders" LIMIT 25;',
      ops_sql.select_star_sql('"orders"', "sqlite", 25))
  end)

  it("uses TOP for mssql, which has no LIMIT clause", function()
    assert.equals("SELECT TOP 100 * FROM [orders];", ops_sql.select_star_sql("[orders]", "mssql"))
  end)
end)

describe("db_browser rename SQL", function()
  it("spells a table rename per dialect", function()
    assert.equals('ALTER TABLE "orders" RENAME TO "purchases";',
      ops_sql.rename_table_sql(table_node(), "purchases", "postgres"))
    assert.equals("RENAME TABLE `orders` TO `purchases`;",
      ops_sql.rename_table_sql(table_node(), "purchases", "mysql"))
    assert.equals('ALTER TABLE "orders" RENAME TO "purchases";',
      ops_sql.rename_table_sql(table_node(), "purchases", "sqlite"))
  end)

  it("renames an mssql table through sp_rename, unquoted and schema-qualified", function()
    assert.equals("EXEC sp_rename 'dbo.orders', 'purchases';",
      ops_sql.rename_table_sql(
        table_node({ meta = { schema = "dbo", database = "blog" } }), "purchases", "mssql"))
    assert.equals("EXEC sp_rename 'orders', 'purchases';",
      ops_sql.rename_table_sql(table_node({ meta = {} }), "purchases", "mssql"))
  end)

  it("renames a column through sp_rename for mssql", function()
    local col = { node_type = "column", name = "total", meta = { col_type = "INT" } }
    assert.equals("EXEC sp_rename 'dbo.orders.total', 'amount', 'COLUMN';",
      ops_sql.rename_column_sql(
        table_node({ meta = { schema = "dbo", database = "blog" } }), col, "amount", "mssql"))
    assert.equals('ALTER TABLE "orders" RENAME COLUMN "total" TO "amount";',
      ops_sql.rename_column_sql(table_node(), col, "amount", "postgres"))
    assert.equals("ALTER TABLE `orders` CHANGE COLUMN `total` `amount` INT;",
      ops_sql.rename_column_sql(table_node(), col, "amount", "mysql"))
  end)

  it("doubles an apostrophe inside an sp_rename name instead of ending the literal", function()
    local col = { node_type = "column", name = "o'brien", meta = {} }
    assert.equals("EXEC sp_rename 'orders.o''brien', 'name', 'COLUMN';",
      ops_sql.rename_column_sql(table_node({ meta = {} }), col, "name", "mssql"))
  end)
end)

describe("db_browser CREATE DATABASE quoting", function()
  it("escapes an embedded double quote instead of ending the identifier", function()
    assert.equals('CREATE DATABASE "a""b";',
      db_create._test.generate_sql({ name = 'a"b' }, "postgres")[1])
  end)

  it("quotes with the dialect's own rule", function()
    assert.equals("CREATE DATABASE IF NOT EXISTS `weird``name`;",
      db_create._test.generate_sql({ name = "weird`name" }, "mysql")[1])
    assert.equals("CREATE DATABASE [db];",
      db_create._test.generate_sql({ name = "db" }, "mssql")[1])
  end)

  it("keeps the postgres OWNER clause quoted", function()
    assert.equals('CREATE DATABASE "blog" OWNER "postgres";',
      db_create._test.generate_sql({ name = "blog", owner = "postgres" }, "postgres")[1])
  end)
end)
