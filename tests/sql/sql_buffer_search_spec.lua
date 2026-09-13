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

describe("buffer_search step_history", function()
  local step = search._test.step_history
  -- most-recent-first: index 1 is the newest entry
  local hist = { "foo", "bar", "baz" }

  it("moves from free text (idx 0) to the most recent entry on <Up>", function()
    assert.same({ "foo", 1 }, { step(hist, 0, 1) })
  end)

  it("walks older on repeated <Up>", function()
    local t, i = step(hist, 1, 1)
    assert.same({ "bar", 2 }, { t, i })
    t, i = step(hist, 2, 1)
    assert.same({ "baz", 3 }, { t, i })
  end)

  it("clamps at the oldest entry", function()
    assert.same({ nil, 3 }, { step(hist, 3, 1) })
  end)

  it("walks newer on <Down> and signals restore at idx 0", function()
    local t, i = step(hist, 3, -1)
    assert.same({ "bar", 2 }, { t, i })
    t, i = step(hist, 2, -1)
    assert.same({ "foo", 1 }, { t, i })
    t, i = step(hist, 1, -1)
    assert.same({ nil, 0 }, { t, i }) -- caller restores the original text
  end)

  it("does nothing on <Down> while already at free text", function()
    assert.same({ nil, 0 }, { step(hist, 0, -1) })
  end)

  it("no-ops on empty history", function()
    assert.same({ nil, 0 }, { step({}, 0, 1) })
    assert.same({ nil, 0 }, { step({}, 0, -1) })
  end)
end)

describe("buffer_search record_search", function()
  local rec = search._test.record_search

  before_each(function()
    search.search_history = {}
  end)

  it("stores most-recent-first", function()
    rec("alice")
    rec("bob")
    assert.same({ "bob", "alice" }, search.search_history)
  end)

  it("dedups by re-inserting at the front", function()
    rec("alice")
    rec("bob")
    rec("alice")
    assert.same({ "alice", "bob" }, search.search_history)
  end)

  it("ignores nil and empty", function()
    rec(nil)
    rec("")
    assert.same({}, search.search_history)
  end)
end)
