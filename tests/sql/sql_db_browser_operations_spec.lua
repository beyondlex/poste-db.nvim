-- Tests for lua/poste-db/db_browser/operations.lua
-- Pure SQL-template and node-helper tests (no real DB / no UI).

local operations = require("poste-db.db_browser.operations")
local t = operations._test

local function table_node(overrides)
  local base = {
    node_type = "table",
    name = "users",
    meta = { schema = "public", database = "blog" },
  }
  return vim.tbl_extend("force", base, overrides or {})
end

local function column_node(overrides)
  local base = {
    node_type = "column",
    name = "email",
    meta = { col_type = "VARCHAR", nullable = true },
  }
  return vim.tbl_extend("force", base, overrides or {})
end

describe("db_browser operations safe_str", function()
  it("returns nil for nil / vim.NULL", function()
    assert.is_nil(t.safe_str(nil))
    assert.is_nil(t.safe_str(vim.NULL))
  end)

  it("stringifies other values", function()
    assert.equals("text", t.safe_str("text"))
    assert.equals("42", t.safe_str(42))
    assert.equals("true", t.safe_str(true))
  end)
end)

describe("db_browser operations get_columns_from_node", function()
  it("returns nil when node has no column children", function()
    assert.is_nil(t.get_columns_from_node(table_node({ children = {} })))
    assert.is_nil(t.get_columns_from_node(table_node({ children = { { node_type = "index", name = "ix" } } })))
  end)

  it("extracts column name/type/pk/nullable", function()
    local cols = t.get_columns_from_node(table_node({
      children = {
        { node_type = "column", name = "id",   meta = { col_type = "INT4", is_pk = true,  nullable = false } },
        { node_type = "column", name = "bio",  meta = { col_type = "TEXT" } },
        { node_type = "column", name = "flag", meta = { col_type = "BOOL", nullable = false } },
        { node_type = "index",  name = "ix_id" },
      },
    }))
    assert.same({
      { name = "id",   col_type = "INT4", is_pk = true,  nullable = false },
      { name = "bio",  col_type = "TEXT", is_pk = false, nullable = true },
      { name = "flag", col_type = "BOOL", is_pk = false, nullable = false },
    }, cols)
  end)

  it("defaults col_type to TEXT, is_pk to false and nullable to true when meta is empty", function()
    local cols = t.get_columns_from_node(table_node({ children = { { node_type = "column", name = "c", meta = {} } } }))
    assert.same({ { name = "c", col_type = "TEXT", is_pk = false, nullable = true } }, cols)
  end)
end)

describe("db_browser operations qualified_table_ref", function()
  it("quotes bare table for mysql/sqlite", function()
    assert.equals("`users`", t.qualified_table_ref(table_node(), "mysql"))
    assert.equals('"users"', t.qualified_table_ref(table_node(), "sqlite"))
  end)

  it("prefixes the schema for postgres", function()
    assert.equals('"public"."users"', t.qualified_table_ref(table_node(), "postgres"))
  end)

  it("ignores the schema for non-postgres dialects", function()
    assert.equals("`users`", t.qualified_table_ref(table_node(), "mysql"))
  end)
end)

describe("db_browser operations build_directive_lines", function()
  it("starts with a blank line and offset 2 when no directives", function()
    local lines, offset = t.build_directive_lines(table_node({ meta = {} }), nil)
    assert.same({ "" }, lines)
    assert.equals(2, offset)
  end)

  it("emits connection then database headers in order", function()
    local lines, offset = t.build_directive_lines(table_node(), "prod")
    assert.same({ "", "-- @connection prod", "-- @database blog" }, lines)
    assert.equals(4, offset)
  end)
end)

describe("db_browser operations build_alter_column_sql (postgres)", function()
  it("emits TYPE change plus optional SET NOT NULL / SET DEFAULT / COMMENT", function()
    local sql = t.build_alter_column_sql(table_node(), column_node(), {
      col_type = "TEXT", nullable = false, default_val = "''", comment_val = "note",
    }, "postgres")
    assert.same({
      'ALTER TABLE "users" ALTER COLUMN "email" TYPE TEXT;',
      'ALTER TABLE "users" ALTER COLUMN "email" SET NOT NULL;',
      "ALTER TABLE \"users\" ALTER COLUMN \"email\" SET DEFAULT '';",
      "COMMENT ON COLUMN \"users\".\"email\" IS 'note';",
    }, sql)
  end)

  it("skips SET NOT NULL when nullable and SET DEFAULT when empty default", function()
    local sql = t.build_alter_column_sql(table_node(), column_node(), {
      col_type = "VARCHAR(255)", nullable = true, default_val = nil, comment_val = nil,
    }, "postgres")
    assert.same({ 'ALTER TABLE "users" ALTER COLUMN "email" TYPE VARCHAR(255);' }, sql)
  end)

  it("emits SET DEFAULT '' for an explicit empty-string default", function()
    local sql = t.build_alter_column_sql(table_node(), column_node(), {
      col_type = "TEXT", nullable = true, default_val = "", comment_val = nil,
    }, "postgres")
    assert.equals("ALTER TABLE \"users\" ALTER COLUMN \"email\" SET DEFAULT '';", sql[2])
  end)

  it("escapes single quotes inside comments", function()
    local sql = t.build_alter_column_sql(table_node(), column_node(), {
      col_type = "TEXT", nullable = true, default_val = nil, comment_val = "it's",
    }, "postgres")
    assert.equals("COMMENT ON COLUMN \"users\".\"email\" IS 'it''s';", sql[2])
  end)
end)

describe("db_browser operations build_alter_column_sql (mysql)", function()
  it("emits a single MODIFY COLUMN statement", function()
    local sql = t.build_alter_column_sql(table_node(), column_node(), {
      col_type = "INT", nullable = false, default_val = "0", comment_val = "zero",
    }, "mysql")
    assert.same({ "ALTER TABLE `users` MODIFY COLUMN `email` INT NOT NULL DEFAULT 0 COMMENT 'zero';" }, sql)
  end)
end)

describe("db_browser operations build_alter_column_sql (generic)", function()
  it("emits a single ALTER COLUMN statement", function()
    local sql = t.build_alter_column_sql(table_node(), column_node(), {
      col_type = "TEXT", nullable = true, default_val = nil, comment_val = nil,
    }, "sqlite")
    assert.same({ "ALTER TABLE \"users\" ALTER COLUMN \"email\" TYPE TEXT;" }, sql)
  end)
end)