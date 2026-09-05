local mapping = require("poste-db.import.mapping")

describe("import mapping coerce_value", function()
  it("maps empty input to null-ish sentinels", function()
    assert.equals(vim.NIL, mapping.coerce_value(nil, "int"))
    assert.equals(vim.NIL, mapping.coerce_value(vim.NIL, "text"))
    assert.is_nil(mapping.coerce_value("", "text"))
    assert.is_nil(mapping.coerce_value("   ", "text"), "whitespace-only is empty")
  end)

  it("maps NULL spellings to vim.NIL", function()
    assert.equals(vim.NIL, mapping.coerce_value("NULL", "int"))
    assert.equals(vim.NIL, mapping.coerce_value("(NULL)", "text"))
    assert.equals("NULLish", mapping.coerce_value("NULLish", "text"), "prefix is not NULL")
  end)

  it("coerces booleans before numeric parsing", function()
    assert.is_true(mapping.coerce_value("true", "varchar"))
    assert.is_false(mapping.coerce_value("FALSE", "int"))
    assert.is_true(mapping.coerce_value("1", "boolean"), "1/0 only for boolean columns")
    assert.is_false(mapping.coerce_value("0", "bool"))
    assert.equals(1, mapping.coerce_value("1", "int"), "1 stays numeric on non-boolean columns")
  end)

  it("keeps numbers as numbers when they parse cleanly", function()
    assert.equals(42, mapping.coerce_value(" 42 ", "int"))
    assert.equals(3.5, mapping.coerce_value("3.5", "decimal"))
    assert.equals(-7, mapping.coerce_value("-7", "bigint"))
    assert.equals("1e3", mapping.coerce_value("1e3", "int"), "exponent form does not match the numeric pattern")
  end)

  it("pins the current quirk: non-integral value into an integer column falls back to string", function()
    -- The integer guard has an empty then-branch, so "3.7" into an INT column
    -- passes through as the raw string instead of truncating or erroring.
    -- Flagged in the audit; change deliberately, not silently.
    assert.equals("3.7", mapping.coerce_value("3.7", "integer"))
    assert.equals(3, mapping.coerce_value("3.0", "integer"), "integral floats still coerce to number")
  end)

  it("returns strings for everything else", function()
    assert.equals("abc", mapping.coerce_value("abc", "int"))
    assert.equals("2026-01-02", mapping.coerce_value("2026-01-02", "date"))
  end)
end)

describe("import mapping build_column_map", function()
  local table_cols = {
    { name = "ID", col_type = "int", is_pk = true },
    { name = "Name", col_type = "text", is_pk = false },
    { name = "Bonus", col_type = "decimal", is_pk = false },
  }

  it("matches case-insensitively and tracks order", function()
    local col_map, unmatched_import, unmatched_table = mapping.build_column_map(
      { "name", "id" }, table_cols)
    assert.equals(2, #col_map)
    assert.equals("Name", col_map[1].table_col.name, "name matches first by import order")
    assert.equals("ID", col_map[2].table_col.name)
    local unmatched_names = vim.tbl_map(function(tc) return tc.name end, unmatched_table)
    assert.same({ "Bonus" }, unmatched_names)
    assert.same({}, unmatched_import)
  end)

  it("reports unmatched columns on both sides", function()
    local col_map, unmatched_import, unmatched_table = mapping.build_column_map(
      { "id", "ghost" }, table_cols)
    assert.equals(1, #col_map)
    assert.same({ "ghost" }, unmatched_import)
    assert.equals(2, #unmatched_table, "Name and Bonus unmatched")
  end)
end)

describe("import mapping build_row_values", function()
  it("places values by table index and leaves gaps nil", function()
    local col_map = {
      { import_idx = 2, table_idx = 3 },
      { import_idx = 1, table_idx = 1 },
    }
    local row = { "a", "b", "c" }
    assert.same({ "a", nil, "b" }, mapping.build_row_values(row, col_map, 3))
  end)
end)

describe("import mapping validate_and_type", function()
  local table_cols = {
    { name = "id", col_type = "int", is_pk = true },
    { name = "name", col_type = "text", is_pk = false },
  }

  local function col_map()
    return {
      { import_idx = 1, import_name = "id", table_col = table_cols[1], table_idx = 1 },
      { import_idx = 2, import_name = "name", table_col = table_cols[2], table_idx = 2 },
    }
  end

  it("separates valid rows from rows with null primary keys", function()
    local import_rows = {
      { "1", "alice" },
      { "NULL", "bob" },
    }
    local valid, bad = mapping.validate_and_type(import_rows, col_map(), table_cols, {})
    assert.equals(1, #valid)
    assert.same({ 1, "alice" }, valid[1])
    assert.equals(1, #bad)
    assert.matches("primary key column 'id' cannot be null", bad[1].errors[1])
    -- row_idx is reported as ri+1, i.e. the line number in the original file
    -- counting the header row — pinned as-is.
    assert.equals(3, bad[1].row_idx)
  end)

  it("allows null PK when the column is auto-generated", function()
    local cols = col_map()
    cols[1].table_col = { name = "id", col_type = "int", is_pk = true, extra = "auto_increment" }
    local valid, bad = mapping.validate_and_type({ { "NULL", "x" } }, cols, table_cols, {})
    assert.equals(1, #valid)
    assert.equals(0, #bad)
  end)
end)
