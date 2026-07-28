--- Tests for ts_stmt.lua — Tree-sitter-based statement boundary detection.

local ts_stmt = require("poste-sql.ts_stmt")

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "poste_sql"
  -- Wait for Tree-sitter to parse
  vim.wait(500, function()
    local ok, p = pcall(vim.treesitter.get_parser, buf, "sql")
    return ok and p ~= nil
  end)
  return buf
end

describe("find_stmt_span", function()
  it("returns correct span for single statement", function()
    local buf = make_buf({ "SELECT 1;", "SELECT 2;" })
    local span = ts_stmt.find_stmt_span(buf, 1)
    assert.same({ 1, 1 }, span)
  end)

  it("returns correct span for second statement", function()
    local buf = make_buf({ "SELECT 1;", "SELECT 2;" })
    local span = ts_stmt.find_stmt_span(buf, 2)
    assert.same({ 2, 2 }, span)
  end)

  it("handles semicolon in string literal", function()
    local buf = make_buf({ "SELECT 'hello;world' AS test;", "SELECT 2;" })
    local span = ts_stmt.find_stmt_span(buf, 1)
    assert.same({ 1, 1 }, span)
  end)

  it("handles dollar-quoted string", function()
    local buf = make_buf({ "SELECT $$abc;def$$;", "SELECT 2;" })
    local span = ts_stmt.find_stmt_span(buf, 2)
    assert.same({ 2, 2 }, span)
  end)

  it("handles multi-statement on same line", function()
    local buf = make_buf({ "SELECT 1; SELECT 2;" })
    local span = ts_stmt.find_stmt_span(buf, 1)
    -- Both statements on the same line are separate statements
    -- The cursor is on line 1, which contains both
    -- Tree-sitter will return the first statement for cursor at line 1
    assert.same({ 1, 1 }, span)
  end)

  it("handles multi-line statement", function()
    local buf = make_buf({ "SELECT *", "FROM users", "WHERE id = 1;", "SELECT 2;" })
    local span = ts_stmt.find_stmt_span(buf, 2)
    assert.same({ 1, 3 }, span)
  end)

  it("handles CTE (WITH clause)", function()
    local buf = make_buf({ "WITH cte AS (SELECT 1) SELECT * FROM cte;", "SELECT 2;" })
    local span = ts_stmt.find_stmt_span(buf, 1)
    assert.same({ 1, 1 }, span)
  end)

  it("handles INSERT with subquery", function()
    local buf = make_buf({ "INSERT INTO t SELECT * FROM u;", "SELECT 2;" })
    local span = ts_stmt.find_stmt_span(buf, 1)
    assert.same({ 1, 1 }, span)
  end)

  it("handles semicolon in double-quoted identifier", function()
    local buf = make_buf({ "SELECT \"col;name\" FROM users;", "SELECT 2;" })
    local span = ts_stmt.find_stmt_span(buf, 1)
    assert.same({ 1, 1 }, span)
  end)

  it("handles BEGIN/COMMIT transaction block", function()
    local buf = make_buf({ "BEGIN; UPDATE t SET x=1; COMMIT;", "SELECT 1;" })
    local span = ts_stmt.find_stmt_span(buf, 1)
    -- BEGIN/COMMIT is a transaction node
    assert.same({ 1, 1 }, span)
  end)
end)

describe("find_all_stmt_lines", function()
  it("returns all statement start lines", function()
    local buf = make_buf({ "SELECT 1;", "SELECT 2;", "SELECT 3;" })
    local lines = ts_stmt.find_all_stmt_lines(buf, 1, 3)
    assert.same({ 1, 2, 3 }, lines)
  end)

  it("skips blank lines between statements", function()
    local buf = make_buf({ "SELECT 1;", "", "SELECT 2;" })
    local lines = ts_stmt.find_all_stmt_lines(buf, 1, 3)
    assert.same({ 1, 3 }, lines)
  end)

  it("skips comment lines between statements", function()
    local buf = make_buf({ "SELECT 1;", "-- comment", "SELECT 2;" })
    local lines = ts_stmt.find_all_stmt_lines(buf, 1, 3)
    assert.same({ 1, 3 }, lines)
  end)

  it("handles multi-line statements", function()
    local buf = make_buf({ "SELECT *", "FROM users;", "SELECT count(*)", "FROM orders;" })
    local lines = ts_stmt.find_all_stmt_lines(buf, 1, 4)
    assert.same({ 1, 3 }, lines)
  end)

  it("works within a sub-range", function()
    local buf = make_buf({ "SELECT 1;", "SELECT 2;", "SELECT 3;", "SELECT 4;" })
    local lines = ts_stmt.find_all_stmt_lines(buf, 2, 4)
    assert.same({ 2, 3, 4 }, lines)
  end)
end)

describe("find_error_nodes", function()
  it("detects syntax error (FORM instead of FROM)", function()
    local buf = make_buf({ "SELECT * FORM users;" })
    local errors = ts_stmt.find_error_nodes(buf)
    assert.is_true(#errors > 0, "should detect FORM as error")
    assert.equals("Unexpected token: users", errors[1].text)
  end)

  it("returns empty for valid SQL", function()
    local buf = make_buf({ "SELECT * FROM users WHERE id = 1;" })
    local errors = ts_stmt.find_error_nodes(buf)
    assert.same({}, errors)
  end)

  it("does not flag USE statement as error", function()
    local buf = make_buf({ "use inventory;", "SELECT 1;" })
    local errors = ts_stmt.find_error_nodes(buf)
    assert.same({}, errors, "USE is a false positive, should be filtered")
  end)

  it("does not flag SET statement as error", function()
    local buf = make_buf({ "SET NAMES utf8;", "SELECT 1;" })
    local errors = ts_stmt.find_error_nodes(buf)
    assert.same({}, errors, "SET is a false positive, should be filtered")
  end)

  it("does not flag DESC/DESCRIBE as error", function()
    local buf = make_buf({ "desc posts;", "SELECT 1;" })
    local errors = ts_stmt.find_error_nodes(buf)
    assert.same({}, errors, "DESC is a false positive")
  end)

  it("does not flag ANALYZE, KILL, FLUSH, CALL, LOAD, REPAIR, CHECK as error", function()
    local stmts = { "ANALYZE;", "KILL 42;", "FLUSH TABLES;", "CALL p();", "LOAD DATA;", "REPAIR TABLE t;", "CHECK TABLE t;" }
    for _, sql in ipairs(stmts) do
      local buf = make_buf({ sql, "SELECT 1;" })
      local errors = ts_stmt.find_error_nodes(buf)
      assert.same({}, errors, sql .. " should be filtered")
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)
end)

describe("USE/SET boundary detection", function()
  it("finds span for USE statement", function()
    local buf = make_buf({ "use inventory;", "SELECT 1;" })
    local span = ts_stmt.find_stmt_span(buf, 1)
    assert.same({ 1, 1 }, span)
  end)

  it("finds span for SET statement", function()
    local buf = make_buf({ "SET NAMES utf8;", "SELECT 1;" })
    local span = ts_stmt.find_stmt_span(buf, 1)
    assert.same({ 1, 1 }, span)
  end)

  it("includes USE in all statement lines", function()
    local buf = make_buf({ "use inventory;", "SELECT 1;", "SELECT 2;" })
    local lines = ts_stmt.find_all_stmt_lines(buf, 1, 3)
    assert.same({ 1, 2, 3 }, lines)
  end)
end)