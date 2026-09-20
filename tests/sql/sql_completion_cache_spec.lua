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

--- Item 22 follow-up: the connection-name cache had the same authority
--- problem one level up — it cached "we have looked at connections.toml"
--- forever, so a connection added mid-session never reached `USE <tab>`.
describe("completion connection names", function()
  local tmpdir
  local saved_conn_mod, saved_toml_mod, saved_search_dir
  local parse_calls

  local function write_config(text, mtime)
    local path = tmpdir .. "/connections.toml"
    vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
    -- getftime has one-second granularity: pin explicit values so the second
    -- write cannot look like "unchanged" just because both landed now
    vim.loop.fs_utime(path, mtime, mtime)
    return path
  end

  local function collect()
    local names
    data.ensure_conn_names(function(n) names = n end)
    vim.wait(1000, function() return names ~= nil end)
    return names or {}
  end

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    parse_calls = 0
    saved_conn_mod = package.loaded["poste-db.connections"]
    saved_toml_mod = package.loaded["poste-db.toml"]
    saved_search_dir = data.search_dir
    package.loaded["poste-db.connections"] = {
      find_connections_toml = function(dir)
        local p = dir .. "/connections.toml"
        return vim.fn.filereadable(p) == 1 and p or nil
      end,
    }
    package.loaded["poste-db.toml"] = {
      parse_file = function(path)
        parse_calls = parse_calls + 1
        local out = {}
        for _, line in ipairs(vim.fn.readfile(path)) do
          local name = line:match("^%[([%w%-_]+)%]$")
          if name then out[name] = { dialect = "postgres" } end
        end
        return out
      end,
    }
    data.search_dir = function() return tmpdir end
  end)

  after_each(function()
    package.loaded["poste-db.connections"] = saved_conn_mod
    package.loaded["poste-db.toml"] = saved_toml_mod
    data.search_dir = saved_search_dir
    pcall(vim.fn.delete, tmpdir, "rf")
  end)

  it("re-reads when connections.toml changes", function()
    write_config("[alpha]\ndialect = \"postgres\"\n", 1700000000)
    assert.same({ "alpha" }, collect())
    assert.equals(1, parse_calls)
    write_config("[alpha]\ndialect = \"postgres\"\n[beta]\ndialect = \"mysql\"\n", 1700000600)
    assert.same({ "alpha", "beta" }, collect())
    assert.equals(2, parse_calls, "a touched file must not serve the old names")
  end)

  it("serves the cache while the file is untouched", function()
    write_config("[alpha]\ndialect = \"postgres\"\n", 1700000000)
    assert.same({ "alpha" }, collect())
    assert.same({ "alpha" }, collect())
    assert.equals(1, parse_calls, "the same path + mtime is a cache hit")
  end)
end)
