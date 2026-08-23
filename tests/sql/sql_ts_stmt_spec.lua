--- Tests for ts_stmt.lua — Tree-sitter-based statement boundary detection.

local has_sql_parser = require("poste-db.ts_stmt").check_parser()
local ts_stmt = require("poste-db.ts_stmt")

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

if not has_sql_parser then
  describe("Tree-sitter SQL parser availability", function()
    it("is skipped when the parser is unavailable", function()
      pending("Tree-sitter SQL parser unavailable in this Neovim environment")
    end)
  end)
  return
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

  it("suppresses digit-leading identifier fragment for mysql dialect", function()
    local buf = make_buf({ "SELECT * FROM 23_tablename WHERE id = 1;" })
    local errors = ts_stmt.find_error_nodes(buf, "mysql")
    assert.same({}, errors, "23_tablename is one legal unquoted identifier in MySQL")
  end)

  it("suppresses digit-leading identifier fragment for mariadb dialect", function()
    local buf = make_buf({ "SELECT * FROM 2024_log WHERE id = 1;" })
    local errors = ts_stmt.find_error_nodes(buf, "mariadb")
    assert.same({}, errors, "2024_log is one legal unquoted identifier in MariaDB")
  end)

  it("suppresses longer digit prefixes (no length cutoff)", function()
    -- Regression: the old `#text <= 2` cascading filter only hid 1-2 digit
    -- names; 3+ digit prefixes (234, 2024…) surfaced as errors.
    local buf = make_buf({ "SELECT * FROM 2024_log WHERE id = 1;" })
    local errors = ts_stmt.find_error_nodes(buf, "mysql")
    assert.same({}, errors, "2024_log must not be flagged")
  end)

  it("keeps digit-leading diagnostics for postgres dialect", function()
    local buf = make_buf({ "SELECT * FROM 2024_log;" })
    local errors = ts_stmt.find_error_nodes(buf, "postgres")
    assert.is_true(#errors > 0, "unquoted digit-leading identifier must stay an error for PG")
  end)

  it("keeps digit-leading diagnostics when dialect is unknown", function()
    local buf = make_buf({ "SELECT * FROM 2024_log;" })
    local errors = ts_stmt.find_error_nodes(buf)
    assert.is_true(#errors > 0, "digit-leading unquoted identifier must remain an error when dialect is unknown")
  end)

  it("keeps all-digit table name flagged for mysql", function()
    -- `from 234` is an ERROR whose text is "from 234" (not pure digits):
    -- a table cannot consist solely of digits in MySQL either.
    local buf = make_buf({ "SELECT * FROM 234;" })
    local errors = ts_stmt.find_error_nodes(buf, "mysql")
    assert.is_true(#errors > 0, "all-digit table name is invalid in MySQL")
  end)

  it("keeps digit fragment followed by whitespace for mysql", function()
    -- `234 _tablename` = bare all-digit table + alias → still invalid.
    local buf = make_buf({ "SELECT * FROM 234 _tablename;" })
    local errors = ts_stmt.find_error_nodes(buf, "mysql")
    assert.is_true(#errors > 0, "digit fragment is standalone here")
  end)

  it("suppresses numeric INTERVAL quantity for mysql", function()
    -- tree-sitter-sql only parses quoted `INTERVAL '7' DAY`; the numeric form
    -- is legal MySQL date arithmetic.
    local buf = make_buf({ "SELECT DATE_ADD(NOW(), INTERVAL 7 DAY) AS next_week, NOW(), CURDATE(), CURTIME();" })
    local errors = ts_stmt.find_error_nodes(buf, "mysql")
    assert.same({}, errors, "INTERVAL 7 DAY must not be flagged for mysql")
  end)

  it("suppresses numeric INTERVAL quantity for mariadb", function()
    local buf = make_buf({ "SELECT DATE_ADD(NOW(), INTERVAL 1 WEEK);" })
    local errors = ts_stmt.find_error_nodes(buf, "mariadb")
    assert.same({}, errors, "INTERVAL 1 WEEK must not be flagged for mariadb")
  end)

  it("keeps numeric INTERVAL quantity flagged for postgres", function()
    -- PostgreSQL requires the quoted form (INTERVAL '7 days').
    local buf = make_buf({ "SELECT NOW() + INTERVAL 7 DAY;" })
    local errors = ts_stmt.find_error_nodes(buf, "postgres")
    assert.is_true(#errors > 0, "numeric INTERVAL is invalid in postgres")
  end)

  it("keeps numeric INTERVAL quantity flagged when dialect is unknown", function()
    local buf = make_buf({ "SELECT DATE_ADD(NOW(), INTERVAL 7 DAY);" })
    local errors = ts_stmt.find_error_nodes(buf)
    assert.is_true(#errors > 0, "numeric INTERVAL must remain flagged when dialect is unknown")
  end)

  it("suppresses GROUP_CONCAT SEPARATOR for mysql", function()
    -- tree-sitter-sql does not parse `... SEPARATOR '-'` (MySQL-specific).
    local buf = make_buf({ "SELECT GROUP_CONCAT('a', 'b', 'c' SEPARATOR '-') AS concat_test;" })
    local errors = ts_stmt.find_error_nodes(buf, "mysql")
    assert.same({}, errors, "SEPARATOR must not be flagged for mysql")
  end)

  it("suppresses GROUP_CONCAT SEPARATOR for mariadb", function()
    local buf = make_buf({ "SELECT GROUP_CONCAT('a', 'b', 'c' SEPARATOR '-');" })
    local errors = ts_stmt.find_error_nodes(buf, "mariadb")
    assert.same({}, errors, "SEPARATOR must not be flagged for mariadb")
  end)

  it("keeps GROUP_CONCAT SEPARATOR flagged for postgres", function()
    -- PostgreSQL's string_agg is not expressed with SEPARATOR.
    local buf = make_buf({ "SELECT GROUP_CONCAT('a', 'b', 'c' SEPARATOR '-');" })
    local errors = ts_stmt.find_error_nodes(buf, "postgres")
    assert.is_true(#errors > 0, "SEPARATOR is invalid in postgres")
  end)

  it("suppresses mysql \\G terminator after a recognized statement", function()
    local buf = make_buf({ "SHOW CREATE TABLE posts\\G" })
    local errors = ts_stmt.find_error_nodes(buf, "mysql")
    assert.same({}, errors, "trailing \\G is a client terminator, not SQL")
  end)

  it("suppresses mysql \\G terminator merged into an unknown statement", function()
    local buf = make_buf({ "SHOW TABLE STATUS LIKE 'posts'\\G" })
    local errors = ts_stmt.find_error_nodes(buf, "mysql")
    assert.same({}, errors, "SHOW TABLE STATUS ... \\G must not be flagged for mysql")
  end)

  it("suppresses unknown SHOW variants for mysql", function()
    local buf = make_buf({ "SHOW COLUMNS FROM posts;" })
    local errors = ts_stmt.find_error_nodes(buf, "mysql")
    assert.same({}, errors, "SHOW COLUMNS must not be flagged for mysql")
  end)

  it("keeps SHOW flagged for postgres", function()
    -- SHOW is MySQL-only; the same text is invalid in PostgreSQL.
    local buf = make_buf({ "SHOW TABLE STATUS LIKE 'posts';" })
    local errors = ts_stmt.find_error_nodes(buf, "postgres")
    assert.is_true(#errors > 0, "SHOW must remain flagged for postgres")
  end)
end)

local sem_ok, sem = pcall(require, "poste-db.semantic_diagnostics")
if sem_ok and sem._test and sem._test.extract_references_from_node then
  describe("semantic reference extraction (digit-leading identifiers)", function()
    local extract = sem._test.extract_references_from_node

    local function extract_tables(sql)
      local buf = make_buf({ sql })
      local parser = assert(vim.treesitter.get_parser(buf, "sql"))
      local root = parser:parse()[1]:root()
      local stmt = nil
      for child in root:iter_children() do
        if child:type() == "statement" then stmt = child break end
      end
      local refs = extract(stmt, buf)
      local names = {}
      for _, t in ipairs(refs.tables) do names[#names + 1] = t.name end
      return names, refs, buf
    end

    it("rejoins digit fragment from SELECT FROM", function()
      local names = extract_tables("SELECT * FROM 123_abc;")
      assert.same({ "123_abc" }, names, "must look up 123_abc, not the _abc fragment")
    end)

    it("rejoins longer digit prefix (2024_log)", function()
      local names = extract_tables("select * from 2024_log where id = 1;")
      assert.same({ "2024_log" }, names)
    end)

    it("rejoins with AS alias", function()
      local names, refs = extract_tables("select * from 123_abc as t;")
      assert.same({ "123_abc" }, names)
      assert.equal("123_abc", refs.from_tables[1])
    end)

    it("rejoins INSERT INTO target", function()
      local names = extract_tables("insert into 123_abc values (1);")
      assert.same({ "123_abc" }, names)
    end)

    it("rejoins UPDATE target", function()
      local names = extract_tables("update 123_abc set x = 1;")
      assert.same({ "123_abc" }, names)
    end)

    it("does not merge when whitespace separates (234 _tablename)", function()
      local names = extract_tables("select * from 234 _tablename;")
      assert.same({ "_tablename" }, names, "digit fragment is a separate standalone name")
    end)

    it("leaves plain identifiers untouched", function()
      local names = extract_tables("select * from users;")
      assert.same({ "users" }, names)
    end)

    it("rejoins both sides of a JOIN", function()
      local names = extract_tables("select * from 23_tablename join 2024_log l on l.id = x.id;")
      assert.same({ "23_tablename", "2024_log" }, names)
    end)

    it("detects SELECT aliases from AS keyword", function()
      local _, refs = extract_tables("SELECT AVG(metric_01) AS avg_load FROM web_vitals;")
      assert.is_true(refs.select_aliases["avg_load"], "avg_load should be in select_aliases")
    end)

    it("detects multiple SELECT aliases", function()
      local _, refs = extract_tables("SELECT AVG(metric_01) AS avg_load, MAX(metric_05) AS max_ttfb FROM web_vitals;")
      assert.is_true(refs.select_aliases["avg_load"], "avg_load should be in select_aliases")
      assert.is_true(refs.select_aliases["max_ttfb"], "max_ttfb should be in select_aliases")
    end)

    it("does not flag bare column names as SELECT aliases", function()
      local _, refs = extract_tables("SELECT url, COUNT(*) FROM web_vitals;")
      assert.is_nil(refs.select_aliases["url"], "bare column url should not be in select_aliases")
      assert.is_nil(refs.select_aliases["count"], "COUNT should not be in select_aliases")
    end)

    it("records SELECT aliases case-insensitively", function()
      local _, refs = extract_tables("SELECT AVG(metric_01) AS AVG_LOAD FROM web_vitals;")
      assert.is_true(refs.select_aliases["avg_load"], "avg_load (lowercase) should match")
    end)

    it("includes column refs from ORDER BY for SELECT aliases (for validation skip)", function()
      local _, refs = extract_tables("SELECT AVG(metric_01) AS avg_load FROM web_vitals ORDER BY avg_load;")
      local found = false
      for _, col in ipairs(refs.columns) do
        if col.name:lower() == "avg_load" then found = true; break end
      end
      assert.is_true(found, "avg_load should appear in columns (from ORDER BY)")
      assert.is_true(refs.select_aliases["avg_load"], "avg_load should be in select_aliases")
    end)
  end)

  describe("semantic reference extraction (CTEs)", function()
    local extract = sem._test.extract_references_from_node

    local function extract_tables(sql)
      local buf = make_buf({ sql })
      local parser = assert(vim.treesitter.get_parser(buf, "sql"))
      local root = parser:parse()[1]:root()
      local stmt = nil
      for child in root:iter_children() do
        if child:type() == "statement" then stmt = child break end
      end
      local refs = extract(stmt, buf)
      local names = {}
      for _, t in ipairs(refs.tables) do names[#names + 1] = t.name end
      return names, refs, buf
    end

    it("does not flag recursive CTE self-reference", function()
      local names = extract_tables(
        "WITH RECURSIVE seq (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 3) "
          .. "INSERT INTO authors (username, email, bio) SELECT i, i, i FROM seq;"
      )
      assert.same({ "authors" }, names, "seq is a CTE, only the INSERT target must remain")
    end)

    it("does not flag plain CTE reference but keeps body tables", function()
      local names = extract_tables("WITH x AS (SELECT id FROM users WHERE active) SELECT * FROM x;")
      assert.same({ "users" }, names, "x is a CTE, users in the CTE body is a real table")
    end)

    it("does not flag chained CTE references", function()
      local names = extract_tables(
        "WITH a AS (SELECT 1 AS n), b AS (SELECT n FROM a) SELECT n FROM b;"
      )
      assert.same({}, names, "a and b are CTEs, no real tables in this statement")
    end)
  end)
end

describe("digit-fragment highlight (syntax.highlight_digit_prefix_fragments)", function()
  local syntax = require("poste-db.syntax")
  --- Byte spans (from, to) covered by digit-fragment extmarks in a buffer.
  local function fragment_spans(buf)
    local ns = vim.api.nvim_create_namespace("poste_db_digit_fragment")
    local spans = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      local details = m[4] or {}
      spans[#spans + 1] = { m[3], details.end_col }
    end
    table.sort(spans, function(a, b) return a[1] < b[1] end)
    return spans
  end
  local function name_span(line, name)
    local pos = line:find(name, 1, true) - 1
    return pos, pos + #name
  end

  it("recolors the digit prefix for mysql dialect", function()
    local sql = "SELECT * FROM 123_abc;"
    local buf = make_buf({ sql })
    syntax.highlight_digit_prefix_fragments(buf, "mysql")
    local s, e = name_span(sql, "123_abc")
    assert.same({ { s, e } }, fragment_spans(buf))
  end)

  it("recolors the digit prefix for mariadb dialect", function()
    local sql = "SELECT * FROM 2024_log;"
    local buf = make_buf({ sql })
    syntax.highlight_digit_prefix_fragments(buf, "mariadb")
    local s, e = name_span(sql, "2024_log")
    assert.same({ { s, e } }, fragment_spans(buf))
  end)

  it("recolors both sides of a JOIN", function()
    local sql = "SELECT * FROM 23_tablename JOIN 2024_log l ON l.id = x.id;"
    local buf = make_buf({ sql })
    syntax.highlight_digit_prefix_fragments(buf, "mysql")
    local s1, e1 = name_span(sql, "23_tablename")
    local s2, e2 = name_span(sql, "2024_log")
    assert.same({ { s1, e1 }, { s2, e2 } }, fragment_spans(buf))
  end)

  it("leaves whitespace-separated all-digit names untouched for mysql", function()
    local sql = "SELECT * FROM 234 _tablename;"
    local buf = make_buf({ sql })
    syntax.highlight_digit_prefix_fragments(buf, "mysql")
    assert.same({}, fragment_spans(buf))
  end)

  it("keeps the error color for postgres dialect", function()
    local sql = "SELECT * FROM 123_abc;"
    local buf = make_buf({ sql })
    syntax.highlight_digit_prefix_fragments(buf, "postgres")
    assert.same({}, fragment_spans(buf))
  end)

  it("keeps the error color when dialect is unknown", function()
    local sql = "SELECT * FROM 123_abc;"
    local buf = make_buf({ sql })
    syntax.highlight_digit_prefix_fragments(buf)
    assert.same({}, fragment_spans(buf))
  end)

  it("clears previous extmarks on re-run", function()
    local sql = "SELECT * FROM 123_abc;"
    local buf = make_buf({ sql })
    syntax.highlight_digit_prefix_fragments(buf, "mysql")
    assert.is_true(#fragment_spans(buf) > 0)
    syntax.highlight_digit_prefix_fragments(buf, "postgres")
    assert.same({}, fragment_spans(buf))
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
