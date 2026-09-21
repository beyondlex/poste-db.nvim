-- Tests for lua/poste-db/semantic_diagnostics.lua
-- Focus: schema cache invalidation after DDL so newly created tables are no
-- longer reported as "not found". context/connections/state/constants are
-- stubbed so the module loads deterministically without a database.

-- `fake_binary` and `fake_ctx` are read through closures so a test can swap
-- the binary the fetch helpers launch, and the context every statement
-- resolves to, without reloading the module under test.
local fake_binary
local fake_ctx = {}
package.loaded["poste-db.context"] = { resolve_full_context = function() return fake_ctx end }
package.loaded["poste-db.connections"] = {
  resolve_connection_url = function() return "postgres://user@localhost:5432/spec" end,
  get_connection_config = function() return nil end,
}
package.loaded["poste-db.state"] = {
  find_poste_binary = function() return fake_binary end,
  log = function() end,
}
package.loaded["poste-db.constants"] = {
  SYSTEM_SCHEMAS = {},
  is_pg_catalog_name = function() return false end,
  is_sqlite_system_name = function() return false end,
  dialect_from_url = function() return nil end,
}

local sem = require("poste-db.semantic_diagnostics")

local function has(keys, key)
  for _, k in ipairs(keys) do
    if k == key then return true end
  end
  return false
end

-- The cold-cache scenarios below drive `M.update`, which needs the tree-sitter
-- SQL grammar to find any statement at all. `tests/run_one.sh` redirects the
-- XDG dirs, so the grammar is missing there; the same guard the other
-- tree-sitter specs use turns those runs into visible `pending` instead of
-- silently green tests that never fetched.
local has_sql_parser = require("poste-db.ts_stmt").check_parser()

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

-- The cold-cache fetch is the only thing that can turn a "no squiggles" buffer
-- into a checked one, and it is gated by a per-buffer in-flight flag. Two
-- measured Neovim behaviours used to leave that flag set forever:
--   * `jobstart()` *throws* E475 ("... is not executable") for a path that is
--     missing or not runnable -- it does not return 0, and no callback fires;
--   * a job that exits 0 without writing to stdout still fires `on_stdout`,
--     but with the single empty line the guards used to `return` on.
-- A stuck flag is silent and permanent: every later update() skips the fetch,
-- so the buffer stays unchecked for the rest of the session even after the
-- binary is restored. Each case below starts broken on purpose and then
-- asserts that a working binary is actually reached. The last three are
  -- controls: they settled correctly even before the fix, and they pin the
-- rule that a failed fetch re-arms the next attempt rather than muting it.
describe("semantic_diagnostics fetch failure recovery", function()
  if not has_sql_parser then
    it("is skipped when the parser is unavailable", function()
      pending("Tree-sitter SQL parser unavailable in this Neovim environment")
    end)
    return
  end

  local created = {}

  local function sh(body)
    local path = vim.fn.tempname()
    vim.fn.writefile({ "#!/bin/sh", body }, path)
    local uv = vim.uv or vim.loop
    uv.fs_chmod(path, 493) -- 0o755, the same requirement minimal_init notes
    created[#created + 1] = path
    return path
  end

  local function sql_buf(sql)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(sql, "\n"))
    vim.api.nvim_set_option_value("filetype", "sql", { buf = buf })
    return buf
  end

  local function cached(key)
    return vim.wait(3000, function() return has(sem._test.cache_keys(), key) end)
  end

  before_each(function()
    sem.invalidate(nil)
    fake_ctx = { connection = "connA", database = "blog" }
  end)

  -- Every script is made inside an `it` body, so the list only ever holds
  -- files the current test still needs.
  after_each(function()
    sem.invalidate(nil)
    fake_binary = nil
    fake_ctx = {}
    for _, path in ipairs(created) do os.remove(path) end
    created = {}
  end)

  -- One buffer per scenario: the flag under test is keyed by buffer, so a
  -- fresh buffer would hide a leak instead of showing it.
  local cases = {
    {
      name = "the binary path is rejected by jobstart",
      broken = function() return "/nonexistent/poste-spec-binary" end,
    },
    {
      name = "the binary exits 0 without any stdout",
      broken = function() return sh("true") end,
    },
    {
      name = "the binary prints something that is not JSON",
      broken = function() return sh("echo 'not json at all'") end,
    },
    {
      name = "the binary exits non-zero without stdout",
      broken = function() return sh("exit 7") end,
    },
  }

  for _, case in ipairs(cases) do
    it("reaches a working binary again when " .. case.name, function()
      fake_binary = case.broken()
      local buf = sql_buf("SELECT id FROM widget;")
      sem.update(buf)
      assert.is_false(cached("connA/blog"))

      fake_binary = sh("echo '{\"items\":[{\"name\":\"widget\"}]}'")
      sem.update(buf)
      assert.is_true(cached("connA/blog"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end
end)
