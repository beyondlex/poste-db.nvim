local saved_state = package.loaded["poste.state"]
local saved_select = package.loaded["poste.select"]
local saved_const = package.loaded["poste-sql.constants"]
local saved_connections = package.loaded["poste-sql.connections"]

local state_stub = { sql = { context = { connection = nil, database = nil } }, log = function() end }
local const_stub = package.loaded["poste-sql.constants"] or require("poste-sql.constants")

package.loaded["poste-sql.connections"] = {
  get_connection_config = function(name)
    return { database = "default_db" }
  end,
}
package.loaded["poste.state"] = state_stub
package.loaded["poste.select"] = { select = function() end }

local context = require("poste-sql.context")

describe("context resolve_context", function()
  local function make_buf(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  after_each(function()
    package.loaded["poste.state"] = state_stub
    state_stub.sql = { context = { connection = nil, database = nil } }
  end)

  it("returns nil for empty buffer", function()
    local buf = make_buf({})
    local ctx = context.resolve_context(buf, 1)
    assert.same({ connection = nil, database = nil }, ctx)
  end)

  it("reads @connection from file header", function()
    local buf = make_buf({ "-- @connection analytics", "select 1" })
    local ctx = context.resolve_context(buf, 2)
    assert.equals("analytics", ctx.connection)
    assert.is_nil(ctx.database)
  end)

  it("reads @database from file header", function()
    local buf = make_buf({ "-- @connection analytics", "-- @database blog", "select 1" })
    local ctx = context.resolve_context(buf, 3)
    assert.equals("analytics", ctx.connection)
    assert.equals("blog", ctx.database)
  end)

  it("header scan stops at ### marker but block-level scan still reads overrides", function()
    local buf = make_buf({ "-- @connection analytics", "###", "-- @connection other", "select 1" })
    local ctx = context.resolve_context(buf, 4)
    assert.equals("other", ctx.connection)
  end)

  it("reads USE statement before cursor", function()
    local buf = make_buf({ "use blog", "select 1" })
    local ctx = context.resolve_context(buf, 1)
    assert.equals("blog", ctx.database)
  end)

  it("reads USE statement with quotes", function()
    local buf = make_buf({ "use `my-db`", "select 1" })
    local ctx = context.resolve_context(buf, 1)
    assert.equals("my-db", ctx.database)
  end)

  it("last USE statement before cursor wins", function()
    local buf = make_buf({ "use blog", "select 1", "use analytics", "select 2" })
    local ctx = context.resolve_context(buf, 3)
    assert.equals("analytics", ctx.database)
  end)

  it("block-level @connection overrides file header", function()
    local buf = make_buf({ "-- @connection analytics", "###", "-- @connection blog", "select 1" })
    local ctx = context.resolve_context(buf, 4)
    assert.equals("blog", ctx.connection)
  end)
end)

describe("context get_status_text", function()
  before_each(function()
    package.loaded["poste.state"] = state_stub
    state_stub.sql = { context = { connection = nil, database = nil } }
  end)

  after_each(function()
    package.loaded["poste.state"] = state_stub
  end)

  it("returns empty string when no conn or db", function()
    assert.equals("", context.get_status_text())
  end)

  it("returns [db: conn/db] when both present", function()
    state_stub.sql.context.connection = "analytics"
    state_stub.sql.context.database = "blog"
    assert.equals("[db: analytics/blog]", context.get_status_text())
  end)

  it("returns [db: conn] when only connection", function()
    state_stub.sql.context.connection = "analytics"
    assert.equals("[db: analytics]", context.get_status_text())
  end)

  it("returns [db: ?/db] when only database", function()
    state_stub.sql.context.database = "blog"
    assert.equals("[db: ?/blog]", context.get_status_text())
  end)
end)

describe("context get_cursor_status_text", function()
  local function make_buf(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  before_each(function()
    package.loaded["poste.state"] = state_stub
    package.loaded["poste-sql.connections"] = {
      get_connection_config = function(name)
        return { database = "default_db" }
      end,
    }
  end)

  it("returns empty string when no connection", function()
    local buf = make_buf({ "select 1" })
    assert.equals("", context.get_cursor_status_text(buf))
  end)

  it("returns connection/db from resolve_full_context", function()
    local buf = make_buf({ "-- @connection analytics", "-- @database blog", "select 1" })
    assert.equals("analytics/blog", context.get_cursor_status_text(buf))
  end)

  it("falls back to connections config database when no @database directive", function()
    local buf = make_buf({ "-- @connection analytics", "select 1" })
    local text = context.get_cursor_status_text(buf)
    assert.matches("analytics", text)
  end)
end)

describe("context handle_use_statement", function()
  before_each(function()
    state_stub.sql = { context = { connection = nil, database = nil } }
  end)

  it("does nothing for nil response", function()
    context.handle_use_statement(nil)
    assert.is_nil(state_stub.sql.context.database)
  end)

  it("does nothing for response without body", function()
    context.handle_use_statement({})
    assert.is_nil(state_stub.sql.context.database)
  end)

  it("updates database from USE response", function()
    context.handle_use_statement({
      body = vim.json.encode({ type = "use", database_name = "blog" }),
    })
    assert.equals("blog", state_stub.sql.context.database)
  end)
end)

