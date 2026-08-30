-- Tests for lua/poste-db/dml_guard.lua
-- The classifier is a pure function over { type, children } tables (no
-- tree-sitter needed), so the unit tests are deterministic. scan_text prefers
-- tree-sitter and falls back to regex_scan; the integration cases below were
-- chosen so both engines agree, keeping them environment-independent.

local guard = require("poste-db.dml_guard")

local function stmt(children)
  return { type = "statement", children = children }
end

local function node(type, children)
  local n = { type = type }
  if children then n.children = children end
  return n
end

describe("dml_guard missing_where (plain-table classifier)", function()
  it("flags DELETE without a WHERE clause", function()
    assert.equals("delete", guard.missing_where(stmt({
      node("delete", { node("keyword_delete") }),
      node("from", { node("keyword_from"), node("object_reference") }),
    })))
  end)

  it("passes DELETE with a WHERE clause inside the from clause", function()
    assert.is_nil(guard.missing_where(stmt({
      node("delete", { node("keyword_delete") }),
      node("from", { node("keyword_from"), node("object_reference"), node("where") }),
    })))
  end)

  it("flags UPDATE without a WHERE clause", function()
    assert.equals("update", guard.missing_where(stmt({
      node("update", { node("keyword_update"), node("relation"), node("keyword_set") }),
    })))
  end)

  it("passes UPDATE with a WHERE clause on the update node", function()
    assert.is_nil(guard.missing_where(stmt({
      node("update", { node("keyword_update"), node("relation"), node("keyword_set"), node("where") }),
    })))
  end)

  it("treats a subquery WHERE as NOT filtering the target rows", function()
    assert.equals("update", guard.missing_where(stmt({
      node("update", { node("keyword_set"), node("subquery", { node("where") }) }),
    })))
  end)

  it("ignores non-DML statements", function()
    assert.is_nil(guard.missing_where(stmt({ node("select"), node("from") })))
    assert.is_nil(guard.missing_where(nil))
    assert.is_nil(guard.missing_where({ type = "insert" }))
  end)
end)

describe("dml_guard regex_scan", function()
  it("flags DELETE/UPDATE without WHERE", function()
    assert.equals(1, #guard.regex_scan("DELETE FROM users"))
    assert.equals(1, #guard.regex_scan("UPDATE users SET name = 'x'"))
  end)

  it("passes statements with a WHERE clause", function()
    assert.equals(0, #guard.regex_scan("DELETE FROM users WHERE id = 1"))
    assert.equals(0, #guard.regex_scan("UPDATE users SET name = 'x' WHERE id = 1"))
  end)

  it("counts multiple statements and skips safe ones", function()
    local hits = guard.regex_scan("update t set a=1; DELETE FROM x WHERE y=2; DELETE FROM z")
    assert.equals(2, #hits)
  end)

  it("ignores WHERE inside string literals and comments", function()
    assert.equals(0, #guard.regex_scan("SELECT * FROM t WHERE name = 'DELETE FROM fake'"))
    assert.equals(1, #guard.regex_scan("UPDATE users SET name = 'x' -- WHERE id = 1"))
  end)

  it("ignores subquery WHERE as the statement filter", function()
    assert.equals(1, #guard.regex_scan("UPDATE t SET x=(SELECT y FROM z WHERE a=1)"))
    assert.equals(0, #guard.regex_scan("DELETE FROM a WHERE b IN (SELECT c FROM d)"))
  end)

  it("returns {} for empty input", function()
    assert.same({}, guard.regex_scan(""))
    assert.same({}, guard.regex_scan(nil))
  end)
end)

describe("dml_guard scan_text", function()
  it("detects an unfiltered DELETE/UPDATE", function()
    assert.equals(1, #guard.scan_text("DELETE FROM users;"))
    assert.equals(1, #guard.scan_text("UPDATE users SET name = 'x';"))
  end)

  it("passes filtered statements", function()
    assert.equals(0, #guard.scan_text("DELETE FROM users WHERE id = 1;"))
    assert.equals(0, #guard.scan_text("UPDATE users SET name = 'x' WHERE id = 1;"))
    assert.equals(0, #guard.scan_text("SELECT * FROM users; INSERT INTO t VALUES (1);"))
  end)

  it("handles multi-statement text and CTE deletes", function()
    assert.equals(2, #guard.scan_text("update t set a=1; delete from x where y=2; DELETE FROM z;"))
    assert.equals(1, #guard.scan_text("WITH x AS (SELECT id FROM old) DELETE FROM users;"))
  end)

  it("returns {} for empty input", function()
    assert.same({}, guard.scan_text(""))
    assert.same({}, guard.scan_text(nil))
  end)
end)

describe("dml_guard confirm_message", function()
  it("quotes a single risky statement with its snippet", function()
    local msg = guard.confirm_message({ { kind = "delete", snippet = "DELETE FROM users" } })
    assert.matches("DELETE statement", msg)
    assert.matches("DELETE FROM users", msg)
    assert.matches("execute anyway", msg)
  end)

  it("summarizes multiple kinds", function()
    local msg = guard.confirm_message({
      { kind = "delete", snippet = "DELETE FROM a" },
      { kind = "delete", snippet = "DELETE FROM b" },
      { kind = "update", snippet = "UPDATE c SET d=1" },
    })
    assert.matches("3 statement", msg)
    assert.matches("DELETE statement", msg)
    assert.matches("UPDATE statement", msg)
  end)
end)

describe("dml_guard snippet", function()
  it("collapses whitespace and truncates", function()
    assert.equals("DELETE FROM users", guard.snippet("DELETE FROM     users"))
    local long = guard.snippet("UPDATE very_long_table_name SET a=1,b=2,c=3,d=4,e=5,f=6,g=7,h=8,i=9,j=10,k=11 WHERE id = 999999")
    assert.is_true(#long <= 64)
    assert.matches("%.%.%.$", long)
  end)
end)

return {}