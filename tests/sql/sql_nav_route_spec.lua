local route = require("poste-sql.nav.route")

describe("nav_route", function()
  it("routes connection directives", function()
    local target = route.resolve_definition_route(1, 1, "-- @connection analytics", { 1, 0 }, {})
    assert.same({ kind = "connection", conn_name = "analytics" }, target)
  end)

  it("routes database directives", function()
    local target = route.resolve_definition_route(1, 1, "-- @database blog", { 1, 0 }, { connection = "conn" })
    assert.same({ kind = "database", db_name = "blog" }, target)
  end)

  it("routes table words when a connection context exists", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "authors" })
    vim.api.nvim_set_current_buf(buf)

    local target = route.resolve_definition_route(buf, 1, "authors", { 1, 0 }, { connection = "conn" })
    assert.same({ kind = "table", table_name = "authors" }, target)
  end)
end)
