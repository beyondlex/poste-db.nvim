-- Tests for lua/poste-db/diagnostics.lua
-- Error-node → diagnostic mapping, dialect resolution, and update wiring.
-- ts_stmt / context / connections / semantic_diagnostics are stubbed so the
-- module is deterministic without a real tree-sitter parser or database.

package.loaded["poste-db.ts_stmt"] = {
  find_error_nodes = function() return {} end,
}
package.loaded["poste-db.context"] = {
  resolve_context = function() return { connection = "prod" } end,
}
package.loaded["poste-db.connections"] = {
  get_connection_config = function(conn)
    if conn == "prod" then return { dialect = "POSTGRES" } end
    return nil
  end,
}
package.loaded["poste-db.semantic_diagnostics"] = {
  update = function() end,
  clear = function() end,
}
package.loaded["poste.state"] = { sql = { context = { connection = nil } } }

local diag = require("poste-db.diagnostics")
local t = diag._test

describe("diagnostics to_diag_entries", function()
  it("converts 1-based error nodes to 0-based diagnostic entries", function()
    local entries = t.to_diag_entries({
      { lnum = 2,  col = 1,  end_lnum = 3, end_col = 5,  text = "syntax error" },
      { lnum = 10, col = 20, end_lnum = 10, end_col = 25, text = "unexpected token" },
    })
    assert.same({
      {
        lnum = 1, col = 0, end_lnum = 2, end_col = 4,
        severity = vim.diagnostic.severity.ERROR,
        source = "poste-db",
        message = "syntax error",
      },
      {
        lnum = 9, col = 19, end_lnum = 9, end_col = 24,
        severity = vim.diagnostic.severity.ERROR,
        source = "poste-db",
        message = "unexpected token",
      },
    }, entries)
  end)

  it("returns an empty table for no errors", function()
    assert.same({}, t.to_diag_entries({}))
  end)
end)

describe("diagnostics get_dialect", function()
  it("lowercases the dialect from the connection config", function()
    assert.equals("postgres", t.get_dialect(0))
  end)
end)

describe("diagnostics update_diagnostics", function()
  local captures

  before_each(function()
    captures = { set = nil }
    vim.diagnostic.set = function(ns_in, buf, entries, opts)
      captures.set = { ns = ns_in, buf = buf, entries = entries, opts = opts }
    end
  end)

  after_each(function()
    vim.diagnostic.set = nil
  end)

  it("only runs on sql filetypes", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "markdown"
    diag.update_diagnostics(buf)
    assert.is_nil(captures.set)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("sets 0-based diagnostics for SQL filetypes", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "poste_sql"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 1" })
    package.loaded["poste-db.ts_stmt"].find_error_nodes = function()
      return { { lnum = 1, col = 1, end_lnum = 1, end_col = 7, text = "unexpected SELECT" } }
    end
    diag.update_diagnostics(buf)
    assert.is_not_nil(captures.set)
    assert.same(
      { 0, 0, 0, 6 },
      { captures.set.entries[1].lnum, captures.set.entries[1].col, captures.set.entries[1].end_lnum, captures.set.entries[1].end_col }
    )
    assert.equals("unexpected SELECT", captures.set.entries[1].message)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)