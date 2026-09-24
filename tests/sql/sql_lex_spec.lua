local lex = require("poste-db.lex")

describe("lex.find_use_database", function()
  it("reads a plain, lowercase and semicolon'd name", function()
    assert.equals("mydb", lex.find_use_database("USE mydb"))
    assert.equals("mydb", lex.find_use_database("use mydb"))
    assert.equals("mydb", lex.find_use_database("USE mydb;"))
  end)

  it("ignores surrounding whitespace and tabs", function()
    assert.equals("mydb", lex.find_use_database("  USE mydb  "))
    assert.equals("mydb", lex.find_use_database("\tUSE\tmydb\t"))
  end)

  it("returns nil for nil, empty, whitespace-only and bare USE", function()
    assert.is_nil(lex.find_use_database(nil))
    assert.is_nil(lex.find_use_database(""))
    assert.is_nil(lex.find_use_database("   "))
    assert.is_nil(lex.find_use_database("USE"))
  end)

  it("does not match USE as a prefix of a longer word", function()
    assert.is_nil(lex.find_use_database("USER u"))
    assert.is_nil(lex.find_use_database("USEFUL x"))
  end)

  it("stops a bare name at whitespace, so a trailing comment is not part of it", function()
    assert.equals("mydb", lex.find_use_database("USE mydb -- switch"))
  end)

  it("stops a bare name at the semicolon even when a comment follows it", function()
    -- `USE mydb;-- note` used to return "mydb;--" because the `;` strip only
    -- fired at the very end of the token.
    assert.equals("mydb", lex.find_use_database("USE mydb;-- note"))
  end)

  it("returns a quoted name that contains spaces intact", function()
    -- The old `%S+` scan cut at the space inside the quotes and returned "my".
    assert.equals("my db", lex.find_use_database("USE `my db`"))
    assert.equals("my db", lex.find_use_database('USE "my db";'))
    assert.equals("my db", lex.find_use_database("USE 'my db'"))
  end)

  it("does not let a block comment become the database name", function()
    -- `USE /* default */ mydb` used to return "/*" + "default*/" verbatim.
    assert.equals("mydb", lex.find_use_database("USE /* default */ mydb"))
    assert.equals("mydb", lex.find_use_database("USE/* inline */mydb"))
  end)

  it("skips several leading comments and returns nil when nothing follows", function()
    assert.equals("mydb", lex.find_use_database("/* a */ /* b */ USE mydb"))
    assert.is_nil(lex.find_use_database("/* only a comment */"))
  end)

  it("does not treat a quote inside a leading comment as a name delimiter", function()
    assert.equals("mydb", lex.find_use_database("/* don't */ USE mydb"))
  end)

  it("returns nil for an unterminated quoted name", function()
    -- The old code stripped the leading quote and returned the rest; a name
    -- whose quotes never close is a half-written line, not a database.
    assert.is_nil(lex.find_use_database('USE "my db'))
  end)

  it("returns nil for a full-line -- comment", function()
    assert.is_nil(lex.find_use_database("-- USE mydb"))
  end)

  it("returns nil when the name sits inside a string on the same line", function()
    assert.is_nil(lex.find_use_database("x = 'USE mydb'"))
  end)
end)

describe("lex.is_comment_or_string", function()
  it("spots line comments, strings and backticks at a byte position", function()
    assert.is_true(lex.is_comment_or_string("SELECT 1 -- hi", 12))
    assert.is_true(lex.is_comment_or_string("SELECT 'a b'", 9))
    assert.is_true(lex.is_comment_or_string("SELECT `a b`", 9))
    assert.is_false(lex.is_comment_or_string("SELECT 'a b'", 8))
  end)

  it("handles quote escaping inside strings", function()
    assert.is_true(lex.is_comment_or_string([[SELECT 'a\'b -- x']], 14))
    assert.is_true(lex.is_comment_or_string("SELECT 'it''s -- x'", 15))
  end)

  it("keeps standard-SQL non-nesting block comments", function()
    -- SQL block comments do not nest: the first */ closes them all, so text
    -- after it is code again.
    local s = "/* /* x */ still */ y"
    assert.is_true(lex.is_comment_or_string(s, 7))
    assert.is_false(lex.is_comment_or_string(s, 14))
  end)

  it("answers false for out-of-range and degenerate positions", function()
    assert.is_false(lex.is_comment_or_string("abc", 99))
    assert.is_false(lex.is_comment_or_string("abc", 0))
    assert.is_false(lex.is_comment_or_string("", 1))
  end)
end)

describe("lex.block_comment_depth_after", function()
  it("counts a comment opening and closing on one line", function()
    assert.equals(0, lex.block_comment_depth_after("/* x */ SELECT", 0))
    assert.equals(1, lex.block_comment_depth_after("SELECT /* x", 0))
    assert.equals(0, lex.block_comment_depth_after("rest */ SELECT", 1))
  end)

  it("carries depth across lines so a scanner can skip a whole region", function()
    local depth = 0
    depth = lex.block_comment_depth_after("/* start", depth)
    depth = lex.block_comment_depth_after("USE middle -- looks real", depth)
    depth = lex.block_comment_depth_after("*/ USE real", depth)
    assert.equals(0, depth)
  end)

  it("ignores markers inside strings and line comments", function()
    assert.equals(0, lex.block_comment_depth_after("SELECT '/* not a comment */'", 0))
    assert.equals(1, lex.block_comment_depth_after("SELECT 1 -- /* unterminated", 0))
    assert.equals(0, lex.block_comment_depth_after("SELECT `x/*y`", 0))
  end)

  it("respects backslash escapes in '-strings but not in `-strings", function()
    assert.equals(0, lex.block_comment_depth_after([[SELECT 'it\'s /* x']], 0))
    assert.equals(1, lex.block_comment_depth_after([[SELECT `a\b` /* x]], 0))
  end)

  it("saturates at zero for a stray closer", function()
    assert.equals(0, lex.block_comment_depth_after("x */ y", 0))
  end)
end)

describe("lex.find_block_for_line", function()
  it("starts after the nearest ### marker above the cursor", function()
    local lines = { "### first", "SELECT 1;", "### second", "SELECT 2;" }
    assert.equals(3, lex.find_block_for_line(lines, 4))
    assert.equals(1, lex.find_block_for_line(lines, 2))
  end)

  it("starts at 1 when no marker exists above", function()
    assert.equals(1, lex.find_block_for_line({ "SELECT 1;", "SELECT 2;" }, 2))
  end)
end)
