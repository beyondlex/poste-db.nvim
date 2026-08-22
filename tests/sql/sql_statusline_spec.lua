-- Tests for lua/poste-db/statusline.lua
-- Context text/conn resolution from the buffer-local poste_db_* variables.

package.loaded["poste-db.connections"] = {
  get_connection_config = function(conn)
    if conn == "prod" then return { color = "red" } end
    return nil
  end,
}

local statusline = require("poste-db.statusline")

describe("statusline context text", function()
  before_each(function()
    vim.b.poste_db_context = nil
    vim.b.poste_db_conn = nil
  end)

  it("returns empty string when no context is stored", function()
    assert.equals("", statusline.get_context_text())
    assert.equals("", statusline.get_context())
  end)

  it("returns the stored context text", function()
    vim.b.poste_db_context = "prod  🗄  blog"
    assert.equals("prod  🗄  blog", statusline.get_context_text())
  end)

  it("returns plain context when the connection has no color config", function()
    vim.b.poste_db_context = "anon/blog"
    assert.equals("anon/blog", statusline.get_context())
  end)

  it("wraps the context in a per-connection highlight when color is configured", function()
    vim.b.poste_db_context = "prod/blog"
    vim.b.poste_db_conn = "prod"
    local out = statusline.get_context()
    assert.matches("^%%#PosteDbSqlCtxprod#", out)
    assert.matches("# prod/blog $", out)
  end)

  it("context highlight uses the connection name from the context string", function()
    vim.b.poste_db_context = "prod/blog"
    local hl = statusline.get_context_hl()
    assert.equals("PosteDbSqlCtxprod", hl)
  end)
end)