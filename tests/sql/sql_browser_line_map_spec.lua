--- Item 45: the browser's line→node map is shared by identity. Keymap handlers
--- build a context (`make_context`) and hand it to actions, some of which keep
--- it across an async jump and render through it. A render that replaced the
--- module's table instead of syncing it left the two copies drifting: the live
--- one described lines that were no longer on screen.
local browser = require("poste-db.db_browser.init")
local util = require("poste-db.db_browser.util")
local t = browser._test

local function connection(name)
  return { node_type = "connection", name = name, children = {}, expanded = false }
end

describe("db_browser line map identity", function()
  local buf, conn

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    conn = connection("pg-main")
    t.attach(buf, { conn })
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("a render describes the lines it just wrote", function()
    t.render_tree()
    assert.equals(1, #t.line_map())
    assert.equals(conn, t.line_map()[1])
  end)

  it("a context taken before a render still sees that render's rows", function()
    local ctx = t.make_context()
    t.render_tree()
    -- HEAD of this file: ctx.line_to_node was a different table by then, and a
    -- keymap resolving a line through it found nothing.
    assert.equals(t.line_map(), ctx.line_to_node, "the context must hold the live map")
    assert.equals(1, #ctx.line_to_node)
    assert.equals(conn, ctx.line_to_node[1])
  end)

  it("a render driven through a stored context updates the live map", function()
    -- The search path: actions keep a context and call util.render_tree on it
    -- after expanding ancestors.
    local ctx = t.make_context()
    t.render_tree()
    ctx.root_nodes[2] = connection("pg-second")
    util.render_tree(ctx)
    assert.equals(2, #t.line_map(), "the second connection must be visible to keymaps")
    assert.equals(t.line_map(), ctx.line_to_node)
  end)

  it("shrinking the tree drops the leftover tail instead of keeping dead rows", function()
    t.render_tree()
    local ctx = t.make_context()
    util.render_tree(ctx)
    assert.equals(1, #t.line_map())
    ctx.root_nodes[2] = nil
    util.render_tree(ctx)
    assert.equals(1, #t.line_map(), "the map must not keep a row that is no longer rendered")
    assert.equals(conn, t.line_map()[1])
  end)
end)
