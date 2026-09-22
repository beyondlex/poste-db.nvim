--- What happens when the user confirms a completion item.
---
--- Both interfaces have an `execute`, and both are reached through a
--- `vim.schedule`, so every assertion here waits for the queued step. Only the
--- blink path expands snippets — `source:complete` never appends snippet
--- items, so the nvim-cmp path has nothing to expand.
local sql_comp = require("poste-db.completion")
local const = require("poste-db.constants")

local function wait_until(pred, why)
  assert.is_true(vim.wait(1000, pred, 10), "timed out: " .. why)
end

local function buffer_with(lines, cursor)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "filetype", "poste_sql")
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, cursor)
  return buf
end

local function directive_item(conn)
  return { label = conn, data = { directive_fallback = true, conn_name = conn } }
end

describe("completion execute: directive fallback", function()
  local db_directive = "-- @" .. const.DIRECTIVE_DATABASE

  it("writes the pair and parks the caret on the @database line", function()
    buffer_with({ "SELECT 1", "-- @", "" }, { 2, 1 })
    local done = false
    sql_comp.new():execute(nil, directive_item("alpha"), function() done = true end, nil)
    wait_until(function() return #vim.api.nvim_buf_get_lines(0, 0, -1, false) == 4 end,
      "the directive pair to be inserted")
    assert.is_true(done, "the callback should fire without waiting for the insert")

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.equals("-- @connection alpha", lines[2])
    -- The trailing space is fed as a keystroke (that is what reopens the menu),
    -- so the line itself is written without one — otherwise the screen ends up
    -- with "-- @database  ". Typeahead is not replayed under headless, so this
    -- is the written state, not the state after the fed space lands.
    assert.equals(db_directive, lines[3])
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert.equals(3, cursor[1])
    assert.equals(#db_directive, cursor[2])
  end)

  it("keeps the indentation of the line it was called on", function()
    buffer_with({ "  -- @" }, { 1, 5 })
    sql_comp.new():execute(nil, directive_item("beta"), function() end, nil)
    wait_until(function()
      return vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] ~= nil
    end, "the indented pair to be inserted")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.equals("  -- @connection beta", lines[1])
    assert.equals("  " .. db_directive, lines[2])
  end)

  it("runs the nvim-cmp path through the same insertion", function()
    for _, entry in ipairs({
      { completion_item = directive_item("gamma") },
      { get_completion_item = function() return directive_item("gamma") end },
    }) do
      buffer_with({ "-- @" }, { 1, 1 })
      local done = false
      sql_comp.source.new():execute(entry, function() done = true end)
      wait_until(function()
        return vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] ~= nil
      end, "cmp's directive pair to be inserted")
      assert.is_true(done)
      assert.equals("-- @connection gamma", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    end
  end)
end)

describe("completion execute: snippet items", function()
  local function snippet_item(body)
    return { label = "create database", data = { snippet = true, trigger = "createdb", body = body } }
  end

  it("replaces the word before the cursor with the expanded body", function()
    buffer_with({ "createdb" }, { 1, 7 })
    local done = false
    sql_comp.new():execute(nil, snippet_item("CREATE DATABASE ${1:db_name};"),
      function() done = true end, function() error("default_impl must not run") end)
    assert.is_true(done, "the callback fires before the expansion is scheduled")
    wait_until(function()
      return vim.api.nvim_get_current_line():find("CREATE DATABASE", 1, true) ~= nil
    end, "the snippet to expand")
    assert.is_nil(vim.api.nvim_get_current_line():find("createdb", 1, true))
    -- The placeholder text is what the first stop is seeded with.
    assert.is_true(vim.api.nvim_get_current_line():find("db_name", 1, true) ~= nil)
  end)

  it("defers to the default implementation when nothing is typed yet", function()
    -- The caret sits on the second space, so the word it just left is not a
    -- completion prefix and blink's own insertion has to take over.
    buffer_with({ "SELECT  " }, { 1, 7 })
    local defaulted = false
    sql_comp.new():execute(nil, snippet_item("CREATE DATABASE ${1:db_name};"),
      function() end, function() defaulted = true end)
    wait_until(function() return defaulted end, "the default implementation to run")
    assert.equals("SELECT  ", vim.api.nvim_get_current_line())
  end)
end)
