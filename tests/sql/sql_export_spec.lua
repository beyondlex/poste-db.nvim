-- Tests for lua/poste-db/export.lua
-- Pure formatter tests (csv/tsv/json/markdown/sql-insert) + filename generation.

local export = require("poste-db.export")

local function data_result(overrides)
  local base = {
    columns = { { name = "id" }, { name = "name" }, { name = "bio" } },
    rows = {
      { 1, "Alice", "hello, world" },
      { 2, 'Bob "the" builder', nil },
    },
    table_name = "users",
    schema = "public",
    dialect = "postgres",
    row_count = 2,
  }
  return vim.tbl_extend("force", base, overrides or {})
end

describe("export format_csv", function()
  it("writes header row", function()
    local out = export._test.format_csv(data_result())
    assert.equals("id,name,bio", out:sub(1, string.find(out, "\n") - 1))
  end)

  it("emits one line per row", function()
    local lines = vim.split(export._test.format_csv(data_result()), "\n")
    assert.same({ "id,name,bio", "1,Alice,\"hello, world\"", '2,"Bob ""the"" builder",' }, lines)
  end)

  it("quotes fields containing comma, quote or newline", function()
    local out = export._test.format_csv(data_result({ rows = { { "a,b", 'c"d', "e\nf" } } }))
    assert.equals('id,name,bio\n"a,b","c""d","e\nf"', out)
  end)

  it("renders nil cells as empty fields", function()
    local out = export._test.format_csv(data_result({ rows = { { nil, "", nil } } }))
    assert.equals("id,name,bio\n,,", out)
  end)
end)

describe("export format_tsv", function()
  it("separates cells with tabs and writes header", function()
    local out = export._test.format_tsv(data_result({ columns = { { name = "a" }, { name = "b" } }, rows = { { "x", 5 } } }))
    assert.equals("a\tb\nx\t5", out)
  end)

  it("replaces tabs and newlines in cell values with spaces", function()
    local out = export._test.format_tsv(data_result({ columns = { { name = "a" } }, rows = { { "l1\nl2" }, { "t\tab" } } }))
    assert.equals("a\nl1 l2\nt ab", out)
  end)
end)

describe("export format_json", function()
  it("encodes rows as an array of objects keyed by column", function()
    local out = export._test.format_json(data_result())
    local parsed = vim.json.decode(out)
    assert.same({
      { id = 1, name = "Alice", bio = "hello, world" },
      { id = 2, name = 'Bob "the" builder' },
    }, parsed)
  end)
end)

describe("export format_markdown", function()
  it("builds a pipe table with header separator row", function()
    local out = export._test.format_markdown(data_result())
    local lines = vim.split(out, "\n")
    assert.equals("| id | name | bio |", lines[1])
    assert.equals("| --- | --- | --- |", lines[2])
    assert.equals("| 1 | Alice | hello, world |", lines[3])
  end)

  it("escapes pipe characters in cell values", function()
    local out = export._test.format_markdown(data_result({ columns = { { name = "a" } }, rows = { { "x|y" } } }))
    assert.equals("| a |\n| --- |\n| x\\|y |", out)
  end)
end)

describe("export format_sql_insert", function()
  it("emits INSERT with qualified quoted table and columns", function()
    local out = export._test.format_sql_insert(data_result())
    local lines = vim.split(out, "\n")
    assert.equals('INSERT INTO "public"."users" ("id", "name", "bio") VALUES (1, \'Alice\', \'hello, world\');', lines[1])
    assert.equals('INSERT INTO "public"."users" ("id", "name", "bio") VALUES (2, \'Bob "the" builder\', NULL);', lines[2])
  end)

  it("uses the quoted table name without schema when schema is empty", function()
    local out = export._test.format_sql_insert(data_result({ schema = "" }))
    assert.matches('^INSERT INTO "users" ', out)
  end)

  it("escapes single quotes in string values", function()
    local out = export._test.format_sql_insert(data_result({ columns = { { name = "a" } }, rows = { { "it's" } } }))
    assert.equals("INSERT INTO \"public\".\"users\" (\"a\") VALUES ('it''s');", out)
  end)

  it("renders booleans as TRUE/FALSE", function()
    local out = export._test.format_sql_insert(data_result({ columns = { { name = "a" } }, rows = { { true }, { false } } }))
    assert.equals("INSERT INTO \"public\".\"users\" (\"a\") VALUES (TRUE);\nINSERT INTO \"public\".\"users\" (\"a\") VALUES (FALSE);", out)
  end)

  it("quotes identifiers with mysql backticks", function()
    local out = export._test.format_sql_insert(data_result({ columns = { { name = "a" } }, rows = { { 1 } }, dialect = "mysql" }))
    assert.equals("INSERT INTO `public`.`users` (`a`) VALUES (1);", out)
  end)
end)

describe("export sql_escape_val", function()
  it("turns nil into NULL", function()
    assert.equals("NULL", export._test.sql_escape_val(nil))
    assert.equals("NULL", export._test.sql_escape_val(vim.NIL))
  end)

  it("keeps numbers literal and booleans as TRUE/FALSE", function()
    assert.equals("42", export._test.sql_escape_val(42))
    assert.equals("TRUE", export._test.sql_escape_val(true))
    assert.equals("FALSE", export._test.sql_escape_val(false))
  end)

  it("escapes quotes and control bytes", function()
    assert.equals("'a''b'", export._test.sql_escape_val("a'b"))
    assert.equals("'\\x00'", export._test.sql_escape_val(string.char(0)))
    assert.equals("'\\x1B'", export._test.sql_escape_val(string.char(27)))
  end)
end)

describe("export generate_filename", function()
  it("prefixes with the result table name and appends extension", function()
    local name = export._test.generate_filename({ results = { { table_name = "users" } } }, ".csv")
    assert.matches("^users_%d%d%d%d%d%d%d%d_%d%d%d%d%d%d%.csv$", name)
  end)

  it("falls back to export prefix when no table name", function()
    local name = export._test.generate_filename({ results = {} }, ".json")
    assert.matches("^export_%d%d%d%d%d%d%d%d_%d%d%d%d%d%d%.json$", name)
  end)
end)

describe("export complete", function()
  it("offers formats first", function()
    local formats = export.complete("", "")
    assert.same({ "csv", "tsv", "json", "md", "sql" }, formats)
  end)

  it("offers clipboard destination after a format", function()
    local dests = export.complete("", "PosteDbExport csv")
    assert.same({ "clipboard" }, dests)
  end)
end)