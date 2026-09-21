--- JSON `null` decodes to vim.NIL, which is truthy, so `item.comment or ""`
--- hands a browser node a value that every later string operation chokes on
--- (`" " .. meta.col_type` and `meta.extra:lower()` sit in the tree renderer,
--- so one uncommented column could leave the whole browser undrawable).
local tree = require("poste-db.db_browser.tree")
local actions = require("poste-db.db_browser.actions")
local HEADER_LINES = require("poste-db.db_browser.icons").HEADER_LINES

describe("db_browser.tree node builders", function()
  it("collapse a null column description to the placeholder it renders as", function()
    local node = tree.make_column_node({
      name = "note", type = vim.NIL, nullable = vim.NIL, default = vim.NIL,
      extra = vim.NIL, comment = vim.NIL, collation = vim.NIL,
    })
    assert.equals("?", node.meta.col_type)
    assert.equals("", node.meta.extra)
    assert.equals("", node.meta.comment)
    -- a NULL default is `DEFAULT NULL`, a fact worth keeping distinct from
    -- "the server said nothing"
    assert.equals(vim.NIL, node.meta.default)
  end)

  it("keep the values that are not null", function()
    local node = tree.make_column_node({ name = "id", type = "int8", extra = "auto_increment",
      comment = "primary key", default = 0 })
    assert.equals("int8", node.meta.col_type)
    assert.equals("auto_increment", node.meta.extra)
    assert.equals("primary key", node.meta.comment)
    assert.equals(0, node.meta.default)
  end)

  it("collapse a null table comment, which the statusline concatenates", function()
    assert.equals("", tree.make_table_node({ name = "users", comment = vim.NIL }, "public", "app", "c1").meta.comment)
    assert.equals("BASE TABLE", tree.make_table_node({ name = "v", type = vim.NIL }).meta.table_type)
  end)

  it("render a tree of null-described columns instead of erroring on it", function()
    local nodes = {
      tree.make_column_node({ name = "a", type = vim.NIL, extra = vim.NIL }),
      tree.make_column_node({ name = "b", type = "text", extra = "auto_increment" }),
    }
    local lines = tree.flatten_tree(nodes, 0, {})
    assert.equals(2, #lines)
    assert.equals("a ?", lines[1]:sub(-3), lines[1])
    assert.truthy(lines[2]:find("auto_increment", 1, true), lines[2])
  end)
end)

describe("db_browser.actions.show_column_info", function()
  local saved_introspect = package.loaded["poste-db.introspect"]
  local shown

  before_each(function()
    shown = nil
    package.loaded["poste-db.introspect"] = {
      show_float = function(lines) shown = lines end,
    }
  end)

  after_each(function()
    package.loaded["poste-db.introspect"] = saved_introspect
  end)

  local function info_for(item)
    shown = nil -- the schedule callback below is the only signal it is done
    local node = tree.make_column_node(item)
    actions.show_column_info(HEADER_LINES + 1, { line_to_node = { node } })
    vim.wait(1000, function() return shown ~= nil end)
    return shown or {}
  end

  local function row(lines, label)
    for _, l in ipairs(lines) do
      local t = vim.trim(l)
      if t:sub(1, #label) == label and t:sub(#label + 1, #label + 1):find("%s") then return t end
    end
  end

  it("says (null) for a NULL default and stays silent for an absent one", function()
    assert.equals("Default  (null)", row(info_for({ name = "a", type = "text", default = vim.NIL }), "Default"))
    -- the old tostring() turned the absent case into the word "nil"
    assert.equals(nil, row(info_for({ name = "a", type = "text" }), "Default"), "no default, no row")
    assert.equals("Default  0", row(info_for({ name = "a", type = "int", default = 0 }), "Default"))
  end)

  it("shows a comment without erroring when there is none", function()
    local lines = info_for({ name = "a", type = "text", comment = vim.NIL })
    assert.equals(nil, row(lines, "Comment"), "no comment, no row")
    lines = info_for({ name = "a", type = "text", comment = "the one" })
    assert.equals("Comment  'the one'", row(lines, "Comment"))
  end)

  it("lists the rest of the column", function()
    local lines = info_for({ name = "id", type = "int8", nullable = false,
      extra = "auto_increment", collation = "C" })
    assert.equals("Type  int8", row(lines, "Type"))
    assert.equals("Nullable  NO", row(lines, "Nullable"))
    assert.equals("Extra  auto_increment", row(lines, "Extra"))
    assert.equals("Collation  C", row(lines, "Collation"))
  end)
end)
