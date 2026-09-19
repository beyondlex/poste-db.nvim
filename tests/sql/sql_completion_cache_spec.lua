--- Item 22: the completion schema cache must actually be purgeable, and an
--- empty column list must not become authoritative.
local data = require("poste-db.completion.data")

local saved = {
  connections = package.loaded["poste-db.connections"],
  jobstart = vim.fn.jobstart,
  resolve_current_context = data.resolve_current_context,
}

local function cache() return data.get_cache() end

describe("completion schema cache", function()
  before_each(function()
    package.loaded["poste-db.connections"] = {
      resolve_connection_url = function() return "postgres://h:5432/blog" end,
      get_connection_config = function() return { dialect = "postgres" } end,
    }
    data.resolve_current_context = function()
      return { connection = "prod", database = "blog" }
    end
    cache()["prod/blog"] = { tables = { "orders" }, columns = { orders = { "id" } } }
    cache()["prod/blog/db:inventory"] = { tables = { "parts" }, columns = {} }
    cache()["prod/__databases__"] = { tables = { "blog", "inventory" } }
    cache()["dev/blog"] = { tables = { "keepme" }, columns = {} }
  end)

  after_each(function()
    for _, k in ipairs({ "prod/blog", "prod/blog/db:inventory", "prod/__databases__", "dev/blog" }) do
      cache()[k] = nil
    end
    package.loaded["poste-db.connections"] = saved.connections
    vim.fn.jobstart = saved.jobstart
    data.resolve_current_context = saved.resolve_current_context
  end)

  it("purges every entry of the current connection", function()
    data.clear_cache()
    assert.is_nil(cache()["prod/blog"])
    -- the per-database list is keyed `<conn>/<db>/db:<name>`; the old purge
    -- looked for keys starting with `db:` and matched none of them
    assert.is_nil(cache()["prod/blog/db:inventory"])
    assert.is_nil(cache()["prod/__databases__"])
    assert.truthy(cache()["dev/blog"])
  end)

  it("is a no-op without a connection context", function()
    data.resolve_current_context = function() return {} end
    data.clear_cache()
    assert.truthy(cache()["prod/blog"])
  end)

  local function fetch_columns(items)
    vim.fn.jobstart = function(_, opts)
      if opts.on_stdout then
        opts.on_stdout(1, { vim.json.encode({ items = items }) }, "")
      end
      if opts.on_exit then opts.on_exit(1, 0) end
      return 1
    end
    local finished = false
    data.ensure_columns("metrics", function() finished = true end)
    vim.wait(500, function() return finished end)
    return finished
  end

  it("does not cache an empty column list as authoritative", function()
    assert.is_true(fetch_columns({}))
    assert.is_nil(cache()["prod/blog"].columns["metrics"])
  end)

  it("caches a non-empty column list", function()
    assert.is_true(fetch_columns({ { name = "id" }, { name = "value" } }))
    assert.same({ "id", "value" }, cache()["prod/blog"].columns["metrics"])
  end)
end)
