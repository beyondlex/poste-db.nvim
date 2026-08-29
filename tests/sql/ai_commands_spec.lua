describe("poste-db.ai.commands", function()
  local commands = require("poste-db.ai.commands")
  local connections = require("poste-db.connections")
  local async = require("poste-db.db_browser.async")

  local real_list, real_introspect

  before_each(function()
    real_list = connections.list_connections
    real_introspect = async.run_introspect
  end)

  after_each(function()
    connections.list_connections = real_list
    async.run_introspect = real_introspect
  end)

  it("exposes /connections and /databases for the palette", function()
    local list = commands.list()
    assert.are.equal(2, #list)
    assert.are.equal("connections", list[1].name)
    assert.are.equal("databases", list[2].name)
    for _, c in ipairs(list) do
      assert.is_function(c.complete)
      assert.is_function(c.run)
      assert.truthy(c.desc and c.desc ~= "")
    end
  end)

  it("builds connection candidates from connections.toml", function()
    connections.list_connections = function(cb)
      cb({
        { name = "my-blog", dialect = "mysql", host = "h1" },
        { name = "sqlite-dev", dialect = "sqlite", path = "./x.db" },
      })
    end
    local got = nil
    commands._test.complete_connections("", nil, function(items) got = items end)
    assert.are.equal(2, #got)
    assert.are.equal("my-blog", got[1].label)
    assert.truthy(got[1].description:find("mysql"))
    assert.truthy(got[2].description:find("sqlite"))

    -- prefix filtering
    commands._test.complete_connections("my", nil, function(items) got = items end)
    assert.are.equal(1, #got)
    assert.are.equal("my-blog", got[1].label)
  end)

  it("builds database candidates for the scoped connection", function()
    local seen = {}
    async.run_introspect = function(conn, kind, _s, _t, _db, cb)
      seen.conn, seen.kind = conn, kind
      cb({ items = {
        { name = "shop" },
        { name = "mysql" },            -- system db, skipped
        { name = "information_schema" }, -- skipped
        { name = "analytics" },
      } })
    end
    local got = nil
    commands._test.complete_databases("", { connection = "my-blog" }, function(items) got = items end)
    assert.are.equal("my-blog", seen.conn)
    assert.are.equal("databases", seen.kind)
    assert.are.same({ "shop", "analytics" },
      vim.tbl_map(function(i) return i.label end, got))

    commands._test.complete_databases("sh", { connection = "my-blog" }, function(items) got = items end)
    assert.are.equal(1, #got)
    assert.are.equal("shop", got[1].label)
  end)

  it("requires a connection before listing databases", function()
    local got = "unset"
    commands._test.complete_databases("", {}, function(items) got = items end)
    assert.are.same({}, got)
  end)

  it("run() binds the scope via the api", function()
    local bound = {}
    local api = { set_scope = function(k, v) bound[k] = v end }
    for _, c in ipairs(commands.list()) do
      c.run({ label = "pg" }, api)
    end
    assert.are.equal("pg", bound.connection)
    assert.are.equal("pg", bound.database)
  end)
end)

describe("poste-db.ai.commands registered on poste-ai", function()
  local ai = require("poste-db.ai")

  it("registers the commands with the db context", function()
    if not ai.available() then
      pending("poste-ai.nvim not on rtp")
      return
    end
    assert.is_true(ai.register())
    local spec = require("poste-ai.context_api").get("db")
    assert.is_not_nil(spec.commands)
    local names = {}
    for _, c in ipairs(spec.commands) do names[#names + 1] = c.name end
    assert.are.same({ "connections", "databases" }, names)
  end)
end)
