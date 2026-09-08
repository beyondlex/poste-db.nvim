local saved_cli = package.loaded["poste.cli"]
local saved_state = package.loaded["poste-db.state"]
local saved_util = package.loaded["poste.util"]
local saved_select = package.loaded["poste.select"]
local saved_const = package.loaded["poste-db.constants"]
local saved_toml = package.loaded["poste-db.toml"]

local cli_stub = {}
local state_stub = { context = { connection = nil, database = nil } }
local util_stub = { find_file_upwards = function() return nil end }
local select_stub = { select = function() end }

package.loaded["poste.cli"] = cli_stub
package.loaded["poste-db.state"] = state_stub
package.loaded["poste.util"] = util_stub
package.loaded["poste.select"] = select_stub
package.loaded["poste-db.constants"] = require("poste-db.constants")

local toml_parse_calls = {}
package.loaded["poste-db.toml"] = {
  parse_file = function(path)
    table.insert(toml_parse_calls, path)
    if path:match("found") then
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice" } }
    end
    return nil, "parse error"
  end,
}

local connections = require("poste-db.connections")

describe("connections find_connections_toml", function()
  local tmpdir

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
  end)

  after_each(function()
    pcall(vim.fn.delete, tmpdir, "rf")
  end)

  it("returns nil when no connections.toml found", function()
    util_stub.find_file_upwards = function() return nil end
    assert.is_nil(connections.find_connections_toml(tmpdir))
  end)

  it("returns path when connections.toml found", function()
    local config_path = tmpdir .. "/connections.toml"
    vim.fn.writefile({ "[test]", "dialect = \"sqlite\"" }, config_path)
    util_stub.find_file_upwards = function() return config_path end
    assert.equals(config_path, connections.find_connections_toml(tmpdir))
  end)

  it("caches results", function()
    local config_path = tmpdir .. "/connections.toml"
    util_stub.find_file_upwards = function() return config_path end
    local first = connections.find_connections_toml(tmpdir)
    util_stub.find_file_upwards = function() return nil end
    assert.equals(first, connections.find_connections_toml(tmpdir))
  end)
end)

describe("connections resolve_connection_url", function()
  local tmpdir
  local saved_cwd

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    saved_cwd = vim.fn.getcwd()
    vim.fn.chdir(tmpdir)
    util_stub.find_file_upwards = function() return tmpdir .. "/connections.toml" end
  end)

  after_each(function()
    vim.fn.chdir(saved_cwd)
    pcall(vim.fn.delete, tmpdir, "rf")
  end)

  it("returns nil when no connections.toml found", function()
    util_stub.find_file_upwards = function() return nil end
    local url, err = connections.resolve_connection_url("primary")
    assert.is_nil(url)
    assert.matches("not found", err or "")
  end)

  it("returns nil when connection not in config", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { other = { dialect = "sqlite" } }
    end
    local url, err = connections.resolve_connection_url("missing")
    assert.is_nil(url)
    assert.matches("not found", err or "")
  end)

  it("rejects unsupported dialect (shared connections.toml)", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { cache = { dialect = "elasticsearch", host = "127.0.0.1", port = 9200 } }
    end
    local url, err = connections.resolve_connection_url("cache")
    assert.is_nil(url)
    assert.matches("unsupported dialect", err or "")
  end)

  it("builds postgres URL from fields", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "pg.example.com", port = 5432, database = "blog", user = "alice" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("postgres://alice@pg.example.com:5432/blog", url)
  end)

  it("builds postgres URL with password", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice", password = "secret" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("postgres://alice:secret@localhost:5432/blog", url)
  end)

  it("percent-encodes special chars in user and password", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice", password = "p@ss:w/rd%" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("postgres://alice:p%40ss%3Aw%2Frd%25@localhost:5432/blog", url)
  end)

  it("percent-encodes user when it contains special chars", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "user@example.com", password = "pw" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("postgres://user%40example.com:pw@localhost:5432/blog", url)
  end)

  it("builds mysql URL", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "mysql", host = "db.example.com", port = 3306, database = "shop", user = "root" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("mysql://root@db.example.com:3306/shop", url)
  end)

  it("builds sqlite URL from path", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { localdb = { dialect = "sqlite", path = "/data/test.db" } }
    end
    local url = connections.resolve_connection_url("localdb")
    assert.equals("sqlite:/data/test.db?mode=rwc", url)
  end)

  it("builds sqlite :memory: URL", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { mem = { dialect = "sqlite" } }
    end
    local url = connections.resolve_connection_url("mem")
    assert.equals("sqlite::memory:", url)
  end)

  it("builds mssql URL from fields with default port", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return {
        m1 = { dialect = "mssql", host = "sql.example.com", database = "shop", user = "sa" },
        m2 = { dialect = "mssql", host = "localhost", port = 11433, database = "shop", user = "sa", password = "p@ss" },
      }
    end
    assert.equals("mssql://sa@sql.example.com:1433/shop", connections.resolve_connection_url("m1"))
    assert.equals("mssql://sa:p%40ss@localhost:11433/shop", connections.resolve_connection_url("m2"))
  end)

  it("accepts the postgresql spelling as postgres", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgresql", host = "pg.example.com", database = "blog", user = "alice" } }
    end
    assert.equals("postgres://alice@pg.example.com:5432/blog", connections.resolve_connection_url("primary"))
  end)

  it("builds clickhouse URL with default port", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { ch = { dialect = "clickhouse", host = "ch.example.com", database = "playground", user = "default" } }
    end
    assert.equals("clickhouse://default@ch.example.com:8123/playground", connections.resolve_connection_url("ch"))
  end)

  it("normalizes compat aliases to their base protocol URL", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return {
        crdb = { dialect = "cockroachdb", host = "crdb.example.com", database = "blog", user = "alice" },
        yb = { dialect = "yugabyte", host = "yb.example.com", database = "blog", user = "alice", password = "pw" },
        ps = { dialect = "planetscale", host = "aws.connect.psdb.cloud", database = "shop", user = "root" },
        maria = { dialect = "mariadb", host = "localhost", database = "shop", user = "root" },
      }
    end
    -- Aliases must land on their base protocol URL, never the binary
    -- fallback scheme (the old `postgres or mysql` default).
    assert.equals("postgres://alice@crdb.example.com:5432/blog", connections.resolve_connection_url("crdb"))
    assert.equals("postgres://alice:pw@yb.example.com:5432/blog", connections.resolve_connection_url("yb"))
    assert.equals("mysql://root@aws.connect.psdb.cloud:3306/shop", connections.resolve_connection_url("ps"))
    assert.equals("mysql://root@localhost:3306/shop", connections.resolve_connection_url("maria"))
  end)

  it("uses url field directly when present", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { custom = { dialect = "postgres", url = "postgres://custom@localhost/mydb" } }
    end
    local url = connections.resolve_connection_url("custom")
    assert.equals("postgres://custom@localhost/mydb", url)
  end)

  describe("with a tunnel section", function()
    local saved_parse, saved_tunnel

    before_each(function()
      saved_parse = package.loaded["poste-db.toml"].parse_file
      saved_tunnel = package.loaded["poste-db.tunnel"]
      package.loaded["poste-db.tunnel"] = {
        ensure = function(name, cfg, host, port)
          return 15432
        end,
      }
    end)

    after_each(function()
      package.loaded["poste-db.toml"].parse_file = saved_parse
      package.loaded["poste-db.tunnel"] = saved_tunnel
    end)

    it("rewrites host/port to the tunnel's local end", function()
      package.loaded["poste-db.toml"].parse_file = function()
        return { primary = {
          dialect = "postgres", host = "db.internal", port = 5432,
          database = "blog", user = "alice", tunnel = "jump@bastion",
        } }
      end
      assert.equals("postgres://alice@127.0.0.1:15432/blog",
        connections.resolve_connection_url("primary"))
    end)

    it("passes the connection host/port to tunnel.ensure", function()
      local seen
      package.loaded["poste-db.tunnel"] = {
        ensure = function(name, cfg, host, port)
          seen = { name = name, cfg = cfg, host = host, port = port }
          return 16000
        end,
      }
      package.loaded["poste-db.toml"].parse_file = function()
        return { primary = {
          dialect = "mysql", host = "db.internal", port = 3306,
          database = "shop", user = "root", tunnel = { to = "jump@bastion", port = 2222 },
        } }
      end
      connections.resolve_connection_url("primary")
      assert.same({ name = "primary", cfg = { to = "jump@bastion", port = 2222 },
        host = "db.internal", port = 3306 }, seen)
    end)

    it("propagates tunnel failures", function()
      package.loaded["poste-db.tunnel"] = {
        ensure = function() return nil, "ssh tunnel failed" end,
      }
      package.loaded["poste-db.toml"].parse_file = function()
        return { primary = {
          dialect = "postgres", host = "db.internal", port = 5432,
          database = "blog", tunnel = "jump@bastion",
        } }
      end
      local url, err = connections.resolve_connection_url("primary")
      assert.is_nil(url)
      assert.matches("ssh tunnel failed", err or "")
    end)

    it("rejects tunnel combined with a raw url field", function()
      package.loaded["poste-db.toml"].parse_file = function()
        return { custom = {
          dialect = "postgres", url = "postgres://custom@localhost/mydb",
          tunnel = "jump@bastion",
        } }
      end
      local url, err = connections.resolve_connection_url("custom")
      assert.is_nil(url)
      assert.matches("host/port form", err or "")
    end)

    it("ignores tunnel for sqlite file connections", function()
      package.loaded["poste-db.toml"].parse_file = function()
        return { localdb = { dialect = "sqlite", path = "/data/test.db", tunnel = "jump@bastion" } }
      end
      assert.equals("sqlite:/data/test.db?mode=rwc",
        connections.resolve_connection_url("localdb"))
    end)
  end)
end)

describe("connections get_connection_config", function()
  local tmpdir
  local saved_cwd

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    saved_cwd = vim.fn.getcwd()
    vim.fn.chdir(tmpdir)
    util_stub.find_file_upwards = function() return tmpdir .. "/connections.toml" end
  end)

  after_each(function()
    vim.fn.chdir(saved_cwd)
    pcall(vim.fn.delete, tmpdir, "rf")
  end)

  it("returns nil when no connections.toml found", function()
    util_stub.find_file_upwards = function() return nil end
    assert.is_nil(connections.get_connection_config("primary"))
  end)

  it("returns nil when toml parse fails", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return nil, "parse error"
    end
    assert.is_nil(connections.get_connection_config("missing"))
  end)

  it("returns connection config when found", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice" } }
    end
    local config = connections.get_connection_config("primary")
    assert.same({ dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice" }, config)
  end)

  it("converts mariadb to mysql dialect", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "mariadb" } }
    end
    local config = connections.get_connection_config("primary")
    assert.equals("mysql", config.dialect)
  end)
end)

describe("connections list_connections", function()
  local tmpdir
  local saved_cwd

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    saved_cwd = vim.fn.getcwd()
    vim.fn.chdir(tmpdir)
    util_stub.find_file_upwards = function() return nil end
  end)

  after_each(function()
    vim.fn.chdir(saved_cwd)
    pcall(vim.fn.delete, tmpdir, "rf")
  end)

  it("calls callback with empty list when no toml found", function()
    local captured
    connections.list_connections(function(list) captured = list end)
    vim.wait(100, function() return captured ~= nil end)
    assert.same({}, captured)
  end)

  it("calls callback with parsed connections", function()
    local config_path = tmpdir .. "/connections.toml"
    vim.fn.writefile({ "[primary]", "dialect = \"postgres\"" }, config_path)
    util_stub.find_file_upwards = function() return config_path end
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgres" } }
    end
    local captured
    connections.list_connections(function(list) captured = list end)
    vim.wait(100, function() return captured ~= nil end)
    assert.is_not_nil(captured)
    assert.equals(1, #captured)
    assert.equals("primary", captured[1].name)
    assert.equals("postgres", captured[1].dialect)
  end)

  it("skips unsupported dialects from a shared connections.toml", function()
    local config_path = tmpdir .. "/connections.toml"
    util_stub.find_file_upwards = function() return config_path end
    package.loaded["poste-db.toml"].parse_file = function()
      return {
        primary = { dialect = "postgres", host = "localhost" },
        cache = { dialect = "elasticsearch", host = "127.0.0.1" },
      }
    end
    local captured
    connections.list_connections(function(list) captured = list end)
    vim.wait(100, function() return captured ~= nil end)
    assert.is_not_nil(captured)
    assert.equals(1, #captured)
    assert.equals("primary", captured[1].name)
  end)
end)

describe("connections env var resolution", function()
  local tmpdir
  local saved_cwd

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    saved_cwd = vim.fn.getcwd()
    vim.fn.chdir(tmpdir)
    util_stub.find_file_upwards = function(filename)
      if filename == ".env" then
        return tmpdir .. "/.env"
      end
      if filename == "env.json" then
        return tmpdir .. "/env.json"
      end
      return tmpdir .. "/connections.toml"
    end
  end)

  after_each(function()
    vim.env.POSTE_TEST_DB_PASS = nil
    vim.fn.chdir(saved_cwd)
    pcall(vim.fn.delete, tmpdir, "rf")
  end)

  it("substitutes known vars and keeps unknown ones literal", function()
    local vars = { DB_USER = "alice" }
    assert.equals("alice", connections.substitute_vars("{{DB_USER}}", vars))
    assert.equals("alice:secret", connections.substitute_vars("{{DB_USER}}:secret", vars))
    assert.equals("{{DB_PASS}}", connections.substitute_vars("{{DB_PASS}}", vars))
    assert.equals(5432, connections.substitute_vars(5432, vars))
  end)

  it("resolves {{VAR}} from .env in connection config", function()
    vim.fn.writefile({ "POSTE_TEST_DB_PASS=supersecret" }, tmpdir .. "/.env")
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice", password = "{{POSTE_TEST_DB_PASS}}" } }
    end
    local config = connections.get_connection_config("primary")
    assert.equals("supersecret", config.password)
  end)

  it("resolves {{VAR}} from .env in resolved URL", function()
    vim.fn.writefile({ "POSTE_TEST_DB_PASS=supersecret" }, tmpdir .. "/.env")
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice", password = "{{POSTE_TEST_DB_PASS}}" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("postgres://alice:supersecret@localhost:5432/blog", url)
  end)

  it("keeps unresolved {{VAR}} literal when .env is missing", function()
    package.loaded["poste-db.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice", password = "{{DB_PASS}}" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("postgres://alice:%7B%7BDB_PASS%7D%7D@localhost:5432/blog", url)
  end)

  it("prefers OS env over .env over env.json", function()
    vim.fn.writefile({ '{"dev": {"POSTE_TEST_DB_PASS": "from-envjson"}}' }, tmpdir .. "/env.json")
    vim.fn.writefile({ "POSTE_TEST_DB_PASS=from-dotenv" }, tmpdir .. "/.env")

    vim.env.POSTE_TEST_DB_PASS = "from-os"
    assert.equals("from-os", connections.get_env_vars(tmpdir).POSTE_TEST_DB_PASS)

    vim.env.POSTE_TEST_DB_PASS = nil
    assert.equals("from-dotenv", connections.get_env_vars(tmpdir).POSTE_TEST_DB_PASS)

    vim.fn.delete(tmpdir .. "/.env")
    -- _dotenv_cache still holds the parsed .env; bypass it with a fresh dir
    local other_dir = tmpdir .. "/nested"
    vim.fn.mkdir(other_dir, "p")
    util_stub.find_file_upwards = function(filename)
      if filename == ".env" then return nil end
      if filename == "env.json" then return tmpdir .. "/env.json" end
      return tmpdir .. "/connections.toml"
    end
    assert.equals("from-envjson", connections.get_env_vars(other_dir).POSTE_TEST_DB_PASS)
  end)
end)

describe("connections apply_connection", function()
  local function make_buf(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  before_each(function()
    state_stub.context = { connection = nil, database = nil }
  end)

  it("updates state.context.connection", function()
    connections.apply_connection({ name = "analytics" })
    assert.equals("analytics", state_stub.context.connection)
  end)

  it("updates existing @connection directive", function()
    local buf = make_buf({ "-- @connection old", "select 1" })
    connections.apply_connection({ name = "newconn" })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("-- @connection newconn", lines[1])
  end)

  it("inserts @connection directive at end when none exists and no ### marker", function()
    local buf = make_buf({ "select 1" })
    connections.apply_connection({ name = "newconn" })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("select 1", lines[1])
    assert.equals("-- @connection newconn", lines[2])
  end)

  it("inserts @connection before first ### marker", function()
    local buf = make_buf({ "### query", "select 1" })
    connections.apply_connection({ name = "newconn" })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("-- @connection newconn", lines[1])
    assert.equals("", lines[2])
    assert.equals("### query", lines[3])
  end)
end)

describe("connections format_connection", function()
  it("renders the host/port/database line for host connections", function()
    local line = connections._test.format_connection({
      name = "pg-dev", dialect = "postgres", host = "db.internal", port = 5432, database = "app",
    })
    assert.equals("🐘 pg-dev — db.internal:5432/app", line)
  end)

  it("coerces a quoted (string) port instead of throwing on %d", function()
    -- a connections.toml `port = "5433"` used to error inside string.format,
    -- killing the whole connection picker
    local line = connections._test.format_connection({
      name = "pg-q", dialect = "postgres", host = "h", port = "5433", database = "app",
    })
    assert.equals("🐘 pg-q — h:5433/app", line)
  end)

  it("renders sqlite paths and the tunnel mark", function()
    local line = connections._test.format_connection({
      name = "lite", dialect = "sqlite", path = "data.db", tunnel = "jump@bastion",
    })
    assert.equals("📦 lite — data.db 🔒", line)
  end)
end)

describe("connections percent_encode", function()
  it("encodes reserved bytes but keeps unreserved characters", function()
    local enc = connections._test.percent_encode
    assert.equals("p%40ss%3Aw%2Frd", enc("p@ss:w/rd"))
    assert.equals("keep_-~.12", enc("keep_-~.12"))
    assert.equals("caf%C3%A9", enc("café"))
  end)
end)
