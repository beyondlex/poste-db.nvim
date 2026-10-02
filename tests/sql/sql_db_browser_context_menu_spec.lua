describe("db_browser context_menu shortcuts", function()
  local context_menu = require("poste-db.db_browser.context_menu")
  local shortcut_keys = context_menu._test.shortcut_keys

  it("binds every item letter", function()
    local keys = shortcut_keys({
      { letter = "r" }, { letter = "e" }, { letter = "N" },
    })
    local bound = {}
    for _, s in ipairs(keys) do bound[s.key] = s.letter end
    assert.are.equal("r", bound.r)
    assert.are.equal("e", bound.e)
    assert.are.equal("N", bound.N)
  end)

  it("aliases a free lowercase key to its uppercase item", function()
    -- connection menu: [N] Create Database, and "n" is free — typing "n"
    -- used to be a silent no-op because the alias looked up "n", which no
    -- item has
    local keys = shortcut_keys({ { letter = "r" }, { letter = "e" }, { letter = "N" } })
    local n
    for _, s in ipairs(keys) do
      if s.key == "n" then n = s end
    end
    assert.is_truthy(n, "free lowercase key should be aliased")
    assert.are.equal("N", n.letter)
  end)

  it("does not alias a lowercase key another item already uses", function()
    -- table menu has both "i" (INSERT template) and "I" (Import Data); the
    -- alias for "I" must not clobber "i"'s own binding
    local keys = shortcut_keys({
      { letter = "i" }, { letter = "u" }, { letter = "I" }, { letter = "n" }, { letter = "d" },
    })
    for _, s in ipairs(keys) do
      if s.key == "i" then
        assert.are.equal("i", s.letter, "'i' must keep running the 'i' item")
      end
    end
    local seen_i = {}
    for _, s in ipairs(keys) do
      if s.key == "i" then seen_i[#seen_i + 1] = s.letter end
    end
    assert.are.equal(1, #seen_i, "'i' must be bound exactly once")
  end)

  it("keeps the real keymap table's shape stable", function()
    local keys = shortcut_keys({ { letter = "D" } })
    assert.same({ { key = "D", letter = "D" }, { key = "d", letter = "D" } }, keys)
  end)
end)
