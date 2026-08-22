-- Tests for lua/poste-db/snippets.lua
-- Built-in + custom snippet registration and completion-item generation.

local snippets = require("poste-db.snippets")

describe("snippets", function()
  local original = snippets.snippets

  before_each(function()
    snippets.snippets = vim.deepcopy(original)
  end)

  describe("setup", function()
  it("registers a custom string snippet", function()
    snippets.setup({ snippets = { myq = "SELECT ${1:col} FROM ${2:tbl};" } })
    assert.same({ trigger = "myq", label = "myq", snippet = "SELECT ${1:col} FROM ${2:tbl};" }, snippets.snippets["myq"])
  end)

  it("registers a custom table snippet and forces its trigger", function()
    snippets.setup({ snippets = { q = { label = "q query", snippet = "select 1;" } } })
    assert.same("q", snippets.snippets["q"].trigger)
    assert.equals("q query", snippets.snippets["q"].label)
  end)

  it("keeps all built-in snippets when no custom snippets given", function()
    snippets.setup({})
    assert.is_not_nil(snippets.snippets["ct"])
    assert.is_not_nil(snippets.snippets["sf"])
  end)
end)

describe("snippets get_completion_items", function()
  it("returns an empty table for a non-matching prefix", function()
    assert.same({}, snippets.get_completion_items("zzz"))
  end)

  it("returns every built-in snippet for an empty prefix", function()
    local items = snippets.get_completion_items("")
    assert.equals(14, #items)
  end)

  it("filters by prefix", function()
    local items = snippets.get_completion_items("ct")
    local triggers = {}
    for _, item in ipairs(items) do
      table.insert(triggers, item.insertText)
    end
    table.sort(triggers)
    assert.same({ "ct", "cte" }, triggers)
  end)

  it("builds blink-compatible items with snippet data", function()
    local items = snippets.get_completion_items("sf")
    local item = items[1]
    assert.equals("select * from", item.label)
    assert.equals("sf", item.insertText)
    assert.equals("sf", item.filterText)
    assert.equals("zzzsf", item.sortText)
    assert.equals(14, item.kind)
    assert.matches("^SELECT", item.documentation)
    assert.is_true(item.data.snippet)
    assert.equals("sf", item.data.trigger)
    assert.truthy(item.data.body:find("SELECT * FROM", 1, true))
  end)

  it("matches custom snippets too", function()
    snippets.setup({ snippets = { foo = "SELECT 1" } })
    local items = snippets.get_completion_items("foo")
    assert.equals(1, #items)
    assert.equals("foo", items[1].insertText)
  end)
end)
end)