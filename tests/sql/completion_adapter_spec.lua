--- completion.adapter — the blink.cmp seam. The adapter lazy-loads
--- blink.cmp, so specs plant a fake module in package.loaded (require
--- returns it before any real searcher runs) and drive the pass-through
--- behavior without a real blink install.
local function plant_blink(name, module)
  package.loaded[name] = module
end

describe("completion adapter", function()
  after_each(function()
    package.loaded["blink.cmp"] = nil
    package.loaded["blink.cmp.completion.trigger"] = nil
    package.loaded["poste-db.completion.adapter"] = nil
  end)

  local function fresh_adapter()
    package.loaded["poste-db.completion.adapter"] = nil
    return require("poste-db.completion.adapter")
  end

  it("show() forwards opts to blink.cmp's top-level show", function()
    local seen = {}
    -- adapter calls the planted module with a DOT call (b.show(opts)):
    -- no self, opts is the first and only argument.
    plant_blink("blink.cmp", { show = function(opts) seen[#seen + 1] = opts end })
    local adapter = fresh_adapter()
    adapter.show({ force = true, trigger_kind = "manual" })
    adapter.show()
    assert.same({ { force = true, trigger_kind = "manual" }, nil }, seen)
  end)

  it("show() falls back to completion.trigger when blink has no show", function()
    local seen
    plant_blink("blink.cmp", {})
    plant_blink("blink.cmp.completion.trigger", { show = function(opts) seen = opts end })
    local adapter = fresh_adapter()
    adapter.show() -- no opts: the fallback supplies its force-show default
    assert.same({ force = true }, seen)
  end)

  it("is_available / has_provider reflect the stubbed blink", function()
    plant_blink("blink.cmp", {})
    local adapter = fresh_adapter()
    assert.is_true(adapter.is_available())
    assert.is_false(adapter.has_provider("poste_db"))
    package.loaded["blink.cmp"] = nil
    adapter = fresh_adapter()
    assert.is_false(adapter.is_available())
  end)

  it("register_source / register_filetype are no-ops without blink", function()
    local adapter = fresh_adapter()
    assert.has_no_error(function()
      adapter.register_source({ name = "poste_db", module = "poste-db.completion" })
      adapter.register_filetype("poste_sql", "poste_db")
    end)
  end)
end)
