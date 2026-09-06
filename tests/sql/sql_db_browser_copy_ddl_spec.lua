-- Tests for lua/poste-db/db_browser/copy_ddl.lua
-- Pure transform helpers (no DB / no UI) — characterization coverage.

local ddl_mod = require("poste-db.db_browser.copy_ddl")

describe("db_browser copy_ddl quote_value", function()
  it("renders NULL for nil / vim.NULL", function()
    assert.equals("NULL", ddl_mod.quote_value(nil))
    assert.equals("NULL", ddl_mod.quote_value(vim.NULL))
  end)

  it("renders numbers and booleans unquoted", function()
    assert.equals("42", ddl_mod.quote_value(42))
    assert.equals("3.5", ddl_mod.quote_value(3.5))
    assert.equals("TRUE", ddl_mod.quote_value(true))
    assert.equals("FALSE", ddl_mod.quote_value(false))
  end)

  it("escapes single quotes in strings", function()
    assert.equals("'it''s'", ddl_mod.quote_value("it's"))
  end)

  it("JSON-encodes tables into a quoted literal", function()
    assert.equals('\'{"a":1}\'', ddl_mod.quote_value({ a = 1 }))
  end)

  it("falls back to NULL when a table cannot be encoded", function()
    assert.equals("NULL", ddl_mod.quote_value({ fn = function() end }))
  end)
end)

describe("db_browser copy_ddl result field extraction", function()
  it("prefers affected_rows, then row_count, then ?", function()
    assert.equals("5", ddl_mod.extract_row_count({ affected_rows = 5 }))
    assert.equals("7", ddl_mod.extract_row_count({ row_count = 7 }))
    assert.equals("3", ddl_mod.extract_row_count({ affected_rows = vim.NIL, row_count = "3" }))
    assert.equals("?", ddl_mod.extract_row_count({}))
  end)

  it("formats elapsed or ?", function()
    assert.equals("12ms", ddl_mod.extract_elapsed({ execution_time_ms = 12 }))
    assert.equals("?", ddl_mod.extract_elapsed({}))
    assert.equals("?", ddl_mod.extract_elapsed({ execution_time_ms = vim.NIL }))
  end)

  it("surfaces error over message, nil when clean", function()
    assert.equals("boom", ddl_mod.check_result_error({ results = { { error = "boom", message = "msg" } } }))
    assert.equals("msg", ddl_mod.check_result_error({ results = { { message = "msg" } } }))
    assert.is_nil(ddl_mod.check_result_error({ results = { { row_count = 1 } } }))
    assert.is_nil(ddl_mod.check_result_error({ results = {} }))
    assert.is_nil(ddl_mod.check_result_error(nil))
  end)
end)

describe("db_browser copy_ddl extract_schema_from_ddl", function()
  local qualified = 'CREATE TABLE "public"."posts" ('
  local bare = 'CREATE TABLE "posts" ('

  it("reads the schema from a qualified PG header", function()
    assert.equals("public", ddl_mod.extract_schema_from_ddl(qualified, "posts", "postgres"))
  end)

  it("returns nil for a bare header", function()
    assert.is_nil(ddl_mod.extract_schema_from_ddl(bare, "posts", "postgres"))
  end)

  it("returns nil for mysql regardless of the header", function()
    assert.is_nil(ddl_mod.extract_schema_from_ddl(qualified, "posts", "mysql"))
  end)
end)

describe("db_browser copy_ddl sequence helpers", function()
  it("extracts and dedupes nextval references", function()
    local ddl = "DEFAULT nextval('posts_id_seq'::regclass) , x int DEFAULT nextval('log_seq'::regclass)"
      .. " , y int DEFAULT nextval('posts_id_seq'::regclass)"
    assert.same({ "posts_id_seq", "log_seq" }, ddl_mod.extract_sequences_from_ddl(ddl))
  end)

  it("classifies the sequence column type from the DEFAULT context", function()
    local function ddl_of(col_type)
      return 'CREATE TABLE "posts" (\n  "id" ' .. col_type
        .. " DEFAULT nextval('posts_id_seq'::regclass)\n);"
    end
    assert.equals("bigint", ddl_mod.column_type_for_seq(ddl_of("bigint"), "posts_id_seq"))
    assert.equals("smallint", ddl_mod.column_type_for_seq(ddl_of("smallint"), "posts_id_seq"))
    assert.equals("integer", ddl_mod.column_type_for_seq(ddl_of("integer"), "posts_id_seq"))
    assert.equals("integer", ddl_mod.column_type_for_seq(ddl_of("bigint"), "unknown_seq"))
  end)

  it("renames only the first seq reference", function()
    local ddl = "a int DEFAULT nextval('posts_id_seq'::regclass), b int DEFAULT nextval('posts_id_seq'::regclass)"
    local renamed = ddl_mod.rename_seq_reference(ddl, "posts_id_seq", "posts_copy_id_seq")
    assert.matches("posts_copy_id_seq", renamed)
    assert.equals(1, select(2, renamed:gsub("posts_copy_id_seq", "")))
    assert.equals(1, select(2, renamed:gsub("posts_id_seq", "")))
  end)
end)

describe("db_browser copy_ddl prepare_table_ddl", function()
  it("renames backticked tables on non-postgres without sequence statements", function()
    local ddl = "CREATE TABLE `posts` (\n  `id` bigint DEFAULT nextval('posts_id_seq'::regclass)\n);"
    local out = ddl_mod.prepare_table_ddl(ddl, "posts_copy", "posts", nil, "mysql")
    assert.equals("CREATE TABLE `posts_copy` (\n  `id` bigint DEFAULT nextval('posts_id_seq'::regclass)\n);", out)
  end)

  it("renames quoted tables on postgres when no sequences are present", function()
    local ddl = 'CREATE TABLE "posts" (\n  "title" text\n);'
    local out = ddl_mod.prepare_table_ddl(ddl, "posts_copy", "posts", nil, "postgres")
    assert.equals('CREATE TABLE "posts_copy" (\n  "title" text\n);', out)
  end)

  it("prepends a CREATE SEQUENCE and rewrites the DEFAULT for a bare seq ref", function()
    local ddl = 'CREATE TABLE "posts" (\n  "id" bigint DEFAULT nextval(\'posts_id_seq\'::regclass)\n);'
    local out = ddl_mod.prepare_table_ddl(ddl, "posts_copy", "posts", nil, "postgres")
    assert.equals(
      'CREATE SEQUENCE IF NOT EXISTS "posts_copy_id_seq" AS bigint;\n'
        .. 'CREATE TABLE "posts_copy" (\n  "id" bigint DEFAULT nextval(\'posts_copy_id_seq\'::regclass)\n);',
      out)
  end)

  it("quotes a schema-qualified seq ref once (no doubled schema prefix)", function()
    local ddl = 'CREATE TABLE "public"."posts" (\n  "id" bigint DEFAULT nextval(\'public.posts_id_seq\'::regclass)\n);'
    local out = ddl_mod.prepare_table_ddl(ddl, "posts_copy", "posts", "public", "postgres")
    assert.equals(
      'CREATE SEQUENCE IF NOT EXISTS "public"."posts_copy_id_seq" AS bigint;\n'
        .. 'CREATE TABLE "public"."posts_copy" (\n  "id" bigint DEFAULT nextval(\'public.posts_copy_id_seq\'::regclass)\n);',
      out)
  end)
end)

describe("db_browser copy_ddl dialect_table_exists_sql", function()
  it("uses information_schema + DATABASE() on mysql", function()
    local sql = ddl_mod.dialect_table_exists_sql("mysql", nil)
    assert.matches("information_schema%.TABLES", sql)
    assert.matches("TABLE_SCHEMA = DATABASE%(%)", sql)
  end)

  it("scopes postgres to the schema, defaulting to public", function()
    assert.matches("table_schema = 'app'", ddl_mod.dialect_table_exists_sql("postgres", "app"))
    assert.matches("table_schema = 'public'", ddl_mod.dialect_table_exists_sql("postgres", nil))
  end)

  it("uses sqlite_master for other dialects", function()
    assert.matches("sqlite_master", ddl_mod.dialect_table_exists_sql("sqlite", nil))
  end)
end)

describe("db_browser copy_ddl rename_routine_in_def", function()
  it("renames a mysql routine without touching the DEFINER clause", function()
    local def = "CREATE DEFINER=`root`@`localhost` PROCEDURE `proc_a`(IN x INT) BEGIN SELECT 1; END"
    local out = ddl_mod.rename_routine_in_def("mysql", def, "proc_a", "proc_copy")
    assert.matches("PROCEDURE `proc_copy`%(", out)
    assert.matches("DEFINER=`root`@`localhost`", out)
  end)

  it("renames a schema-qualified mysql routine name", function()
    local def = "CREATE PROCEDURE `myschema`.`proc_a`() BEGIN END"
    local out = ddl_mod.rename_routine_in_def("mysql", def, "proc_a", "proc_copy")
    assert.equals("CREATE PROCEDURE `myschema`.`proc_copy`() BEGIN END", out)
  end)

  it("renames a postgres function name before the parameter list", function()
    local out = ddl_mod.rename_routine_in_def(
      "postgres", "CREATE FUNCTION func_a() RETURNS void AS $$ BEGIN END $$;", "func_a", "func_copy")
    assert.equals("CREATE FUNCTION func_copy() RETURNS void AS $$ BEGIN END $$;", out)
  end)

  it("returns the definition unchanged when no routine keyword is present", function()
    local def = "CREATE TABLE t (id int);"
    assert.equals(def, ddl_mod.rename_routine_in_def("postgres", def, "t", "t_copy"))
  end)
end)
