local ident = require("poste-db.ident")

describe("ident.quote", function()
  it("quotes a simple name with double quotes for postgres", function()
    assert.equals('"users"', ident.quote("users", "postgres"))
  end)

  it("quotes a simple name with backticks for mysql", function()
    assert.equals("`users`", ident.quote("users", "mysql"))
  end)

  it("escapes double quotes inside name for postgres", function()
    assert.equals('"col""name"', ident.quote('col"name', "postgres"))
  end)

  it("escapes backticks inside name for mysql", function()
    assert.equals("`col``name`", ident.quote("col`name", "mysql"))
  end)

  it("returns empty string for nil input", function()
    assert.equals("", ident.quote(nil, "postgres"))
  end)

  it("returns empty string for empty input", function()
    assert.equals("", ident.quote("", "postgres"))
  end)

  it("returns * as-is", function()
    assert.equals("*", ident.quote("*", "postgres"))
  end)

  it("quotes each part of a qualified name separately", function()
    assert.equals('"schema"."table"', ident.quote("schema.table", "postgres"))
  end)

  it("quotes three-part qualified names", function()
    assert.equals('"db"."schema"."table"', ident.quote("db.schema.table", "postgres"))
  end)
end)

describe("ident.quote_qualified", function()
  it("returns just the table name when no schema", function()
    assert.equals('"users"', ident.quote_qualified(nil, "users", "postgres"))
  end)

  it("returns schema.table when schema provided", function()
    assert.equals('"public"."users"', ident.quote_qualified("public", "users", "postgres"))
  end)

  it("uses backticks for mysql", function()
    assert.equals("`public`.`users`", ident.quote_qualified("public", "users", "mysql"))
  end)
end)

describe("ident.quote_literal", function()
  it("returns NULL for nil", function()
    assert.equals("NULL", ident.quote_literal(nil))
  end)

  it("returns NULL for vim.NIL", function()
    assert.equals("NULL", ident.quote_literal(vim.NIL))
  end)

  it("returns number as-is", function()
    assert.equals("42", ident.quote_literal(42))
  end)

  it("returns boolean as TRUE/FALSE", function()
    assert.equals("TRUE", ident.quote_literal(true))
    assert.equals("FALSE", ident.quote_literal(false))
  end)

  it("wraps string in single quotes and escapes single quotes", function()
    assert.equals("'hello'", ident.quote_literal("hello"))
    assert.equals("'it''s'", ident.quote_literal("it's"))
  end)

  it("escapes backslashes for mysql", function()
    assert.equals("'\\\\'", ident.quote_literal("\\", "mysql"))
  end)
end)