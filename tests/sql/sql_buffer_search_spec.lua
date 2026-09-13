--- Pure span helper behind the dataset search substring highlight: the
--- matched characters inside a cell get an fg extmark layered over the
--- cell-wide Search tint.
local search = require("poste-db.buffer.search")

describe("buffer_search match_span", function()
  local span = search._test.match_span

  it("finds the query at the start, middle and end of a cell", function()
    assert.same({ 1, 3 }, { span("alice", "ali") })
    assert.same({ 5, 7 }, { span("  alice ", "ice") })
    assert.same({ 3, 4 }, { span("blog", "og") })
  end)

  it("is case-insensitive (matches compute_matches)", function()
    assert.same({ 1, 3 }, { span("ALICE", "ali") })
    assert.same({ 1, 3 }, { span("alice", "ALI") })
  end)

  it("returns a byte span for multibyte content", function()
    -- 数据库 = 9 bytes, so "db" sits at bytes 10..11
    assert.same({ 10, 11 }, { span("数据库db", "db") })
  end)

  it("returns nil when the query does not appear", function()
    assert.is_nil(span("alice", "bob"))
    -- rendered text can drift from the raw value (truncation) — the caller
    -- falls back to the whole-cell highlight
    assert.is_nil(span("1,234…", "3456"))
  end)

  it("returns nil for empty inputs", function()
    assert.is_nil(span("", "x"))
    assert.is_nil(span("cell", ""))
    assert.is_nil(span(nil, "x"))
    assert.is_nil(span("cell", nil))
  end)
end)
