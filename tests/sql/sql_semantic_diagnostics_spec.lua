-- Tests for lua/poste-db/semantic_diagnostics.lua
-- Focus: schema cache invalidation after DDL so newly created tables are no
-- longer reported as "not found". context/connections/state/constants are
-- stubbed so the module loads deterministically without a database.

package.loaded["poste-db.context"] = { resolve_full_context = function() return {} end }
package.loaded["poste-db.connections"] = {
  resolve_connection_url = function() return nil end,
  get_connection_config = function() return nil end,
}
package.loaded["poste.state"] = { find_poste_binary = function() return nil end }
package.loaded["poste-db.constants"] = {
  SYSTEM_SCHEMAS = {},
  is_pg_catalog_name = function() return false end,
  is_sqlite_system_name = function() return false end,
}

local sem = require("poste-db.semantic_diagnostics")

local function has(keys, key)
  for _, k in ipairs(keys) do
    if k == key then return true end
  end
  return false
end

describe("semantic_diagnostics invalidate", function()
  before_each(function()
    sem._test.set_cache("connA/blog", { tables = { "old" } })
    sem._test.set_cache("connA/inventory", { tables = { "stock" } })
    sem._test.set_cache("connB/blog", { tables = { "users" } })
  end)

  after_each(function()
    sem.invalidate(nil)
  end)

  it("drops only the cache entry for the given connection/database", function()
    sem.invalidate("connA", "blog")
    local keys = sem._test.cache_keys()
    assert.is_false(has(keys, "connA/blog"))
    assert.is_true(has(keys, "connA/inventory"))
    assert.is_true(has(keys, "connB/blog"))
  end)

  it("drops every database of the connection when db is nil", function()
    sem.invalidate("connA", nil)
    local keys = sem._test.cache_keys()
    assert.is_false(has(keys, "connA/blog"))
    assert.is_false(has(keys, "connA/inventory"))
    assert.is_true(has(keys, "connB/blog"))
  end)

  it("clears the whole cache when connection is nil", function()
    sem.invalidate(nil, nil)
    assert.same({}, sem._test.cache_keys())
  end)
end)
