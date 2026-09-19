--- DB Browser UI lifecycle: multi-select markers surviving a re-render (15) and
--- the batch-drop progress dialog not leaking a global `q` (14).
local util = require("poste-db.db_browser.util")
local icons = require("poste-db.db_browser.icons")
local ops_drop = require("poste-db.db_browser.ops_drop")

local saved = {
  connections = package.loaded["poste-db.connections"],
  exec_run = package.loaded["poste-db.exec_run"],
}

local function floats()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
    if ok and cfg.relative and cfg.relative ~= "" then table.insert(out, win) end
  end
  return out
end

local function close_floats()
  for _, win in ipairs(floats()) do
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function fire_buffer_map(buf, lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if m.lhs == lhs and m.callback then
      m.callback()
      return true
    end
  end
  return false
end

local function global_normal(lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    if m.lhs == lhs then return true end
  end
  return false
end

--- Is `lhs` bound in the buffer of a live window (i.e. scoped to a dialog)?
local function bound_in_window(lhs)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
    if ok then
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if m.lhs == lhs then return true end
      end
    end
  end
  return false
end

describe("db_browser tree re-render", function()
  local buf

  before_each(function() buf = vim.api.nvim_create_buf(false, true) end)
  after_each(function()
    close_floats()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("keeps the multi-select markers when the tree is re-rendered", function()
    local picked = { node_type = "table", name = "t1" }
    local other = { node_type = "table", name = "t2" }
    local root = {
      node_type = "database",
      name = "blog",
      expanded = true,
      children = { picked, other },
    }
    local context = {
      browser_buf = buf,
      line_to_node = {},
      root_nodes = { root },
      conn_label = "local",
      multi_select = { active = true, selected = { [picked] = true } },
    }

    util.render_tree(context)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local function line_of(name)
      for _, line in ipairs(lines) do
        if line:find(name, 1, true) then return line end
      end
    end
    local picked_line, other_line = line_of("t1"), line_of("t2")
    assert.truthy(picked_line)
    assert.truthy(other_line)
    assert.truthy(picked_line:find(icons.MARKER_SELECTED, 1, true))
    assert.truthy(other_line:find(icons.MARKER_UNSELECTED, 1, true))
    assert.is_falsy(other_line:find(icons.MARKER_SELECTED, 1, true))
  end)
end)

describe("db_browser batch drop progress dialog", function()
  local node, context, started

  before_each(function()
    node = { node_type = "table", name = "t1", meta = { connection = "test-conn", database = "blog" } }
    context = { root_nodes = {}, source_buf = nil }
    started = 0
    package.loaded["poste-db.connections"] = {
      resolve_connection_url = function() return "postgres://u@h:5432/blog", nil end,
      name_for_url = function() return nil end,
    }
    package.loaded["poste-db.exec_run"] = {
      -- never calls back: the dialog stays open in the "dropping" state
      run_async = function()
        started = started + 1
        return 1
      end,
    }
  end)

  after_each(function()
    close_floats()
    package.loaded["poste-db.connections"] = saved.connections
    package.loaded["poste-db.exec_run"] = saved.exec_run
  end)

  it("binds q on its own buffer instead of globally", function()
    ops_drop.batch_drop_tables({ [node] = true }, context)
    local confirm_buf = vim.api.nvim_get_current_buf()
    assert.is_true(fire_buffer_map(confirm_buf, "y"))

    -- Wait for the drop itself to start, not merely for the focus to move:
    -- the confirm dialog closes before the scheduled batch runs, so a
    -- buffer-changed poll can win the race and assert on a half-built state.
    assert.is_true(vim.wait(2000, function() return started > 0 end, 10))

    -- the leak: a global `q` here outlives the dialog and swallows `q` in
    -- every later window (and macro recording)
    assert.is_false(global_normal("q"))
    assert.is_true(bound_in_window("q"))
  end)
end)
