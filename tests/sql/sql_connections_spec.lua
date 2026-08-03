local saved_cli = package.loaded["poste.cli"]
local saved_state = package.loaded["poste.state"]
local saved_util = package.loaded["poste.util"]
local saved_select = package.loaded["poste.select"]
local saved_const = package.loaded["poste-sql.constants"]
local saved_toml = package.loaded["poste-sql.toml"]

local cli_stub = {}
local state_stub = { sql = { context = { connection = nil, database = nil } } }
local util_stub = { find_file_upwards = function() return nil end }
local select_stub = { select = function() end }

package.loaded["poste.cli"] = cli_stub
package.loaded["poste.state"] = state_stub
package.loaded["poste.util"] = util_stub
package.loaded["poste.select"] = select_stub
package.loaded["poste-sql.constants"] = require("poste-sql.constants")

local toml_parse_calls = {}
package.loaded["poste-sql.toml"] = {
  parse_file = function(path)
    table.insert(toml_parse_calls, path)
    if path:match("found") then
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice" } }
    end
    return nil, "parse error"
  end,
}

local connections = require("poste-sql.connections")

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
    package.loaded["poste-sql.toml"].parse_file = function()
      return { other = { dialect = "sqlite" } }
    end
    local url, err = connections.resolve_connection_url("missing")
    assert.is_nil(url)
    assert.matches("not found", err or "")
  end)

  it("builds postgres URL from fields", function()
    package.loaded["poste-sql.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "pg.example.com", port = 5432, database = "blog", user = "alice" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("postgres://alice@pg.example.com:5432/blog", url)
  end)

  it("builds postgres URL with password", function()
    package.loaded["poste-sql.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice", password = "secret" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("postgres://alice:secret@localhost:5432/blog", url)
  end)

  it("builds mysql URL", function()
    package.loaded["poste-sql.toml"].parse_file = function()
      return { primary = { dialect = "mysql", host = "db.example.com", port = 3306, database = "shop", user = "root" } }
    end
    local url = connections.resolve_connection_url("primary")
    assert.equals("mysql://root@db.example.com:3306/shop", url)
  end)

  it("builds sqlite URL from path", function()
    package.loaded["poste-sql.toml"].parse_file = function()
      return { localdb = { dialect = "sqlite", path = "/data/test.db" } }
    end
    local url = connections.resolve_connection_url("localdb")
    assert.equals("sqlite:/data/test.db?mode=rwc", url)
  end)

  it("builds sqlite :memory: URL", function()
    package.loaded["poste-sql.toml"].parse_file = function()
      return { mem = { dialect = "sqlite" } }
    end
    local url = connections.resolve_connection_url("mem")
    assert.equals("sqlite::memory:", url)
  end)

  it("uses url field directly when present", function()
    package.loaded["poste-sql.toml"].parse_file = function()
      return { custom = { dialect = "postgres", url = "postgres://custom@localhost/mydb" } }
    end
    local url = connections.resolve_connection_url("custom")
    assert.equals("postgres://custom@localhost/mydb", url)
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
    package.loaded["poste-sql.toml"].parse_file = function()
      return nil, "parse error"
    end
    assert.is_nil(connections.get_connection_config("missing"))
  end)

  it("returns connection config when found", function()
    package.loaded["poste-sql.toml"].parse_file = function()
      return { primary = { dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice" } }
    end
    local config = connections.get_connection_config("primary")
    assert.same({ dialect = "postgres", host = "localhost", port = 5432, database = "blog", user = "alice" }, config)
  end)

  it("converts mariadb to mysql dialect", function()
    package.loaded["poste-sql.toml"].parse_file = function()
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
    package.loaded["poste-sql.toml"].parse_file = function()
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
end)

describe("connections apply_connection", function()
  local function make_buf(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  before_each(function()
    state_stub.sql = { context = { connection = nil, database = nil } }
  end)

  it("updates state.sql.context.connection", function()
    connections.apply_connection({ name = "analytics" })
    assert.equals("analytics", state_stub.sql.context.connection)
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

