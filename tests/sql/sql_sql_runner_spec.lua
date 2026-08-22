local saved_state = package.loaded["poste.state"]
local saved_util = package.loaded["poste.util"]
local saved_indicators = package.loaded["poste.indicators"]
local saved_statement = package.loaded["poste-db.statement"]
local saved_introspect = package.loaded["poste-db.introspect"]
local saved_format = package.loaded["poste-db.format"]
local saved_buffer = package.loaded["poste-db.buffer"]

local state_stub = {
  sql = { context = { connection = nil, database = nil } },
  current_env = "dev",
  find_poste_binary = function() return nil end,
  get_keymap = function() return nil end,
  log = function() end,
}

package.loaded["poste.state"] = state_stub
package.loaded["poste.util"] = {}
package.loaded["poste.indicators"] = { clear_all = function() end, set_indicator = function() end }
package.loaded["poste-db.statement"] = {
  extract_stmt_at_cursor = function() end,
  extract_visual_block = function() end,
  find_stmt_lines = function() end,
  get_stmt_sql = function() end,
  extract_table_name = function() end,
}
package.loaded["poste-db.introspect"] = { show_table_ddl = function() end }
package.loaded["poste-db.format"] = { format_dataset = function() end, format_error = function() end, plan_resultset_layout = function() end, render_page = function() end, format_resultset = function() end }
package.loaded["poste-db.buffer"] = { clear_panel = function() end, render_dataset = function() end }

local runner = require("poste-db.sql_runner")

describe("sql_runner ensure_sql_keymaps", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.b[buf] = {}
  end)

  it("installs keymaps on first call", function()
    state_stub.get_keymap = function(area, name, default)
      return default
    end
    runner.ensure_sql_keymaps(buf)
    assert.is_true(vim.b[buf].poste_db_keymaps_installed)
  end)

  it("skips if already installed", function()
    vim.b[buf].poste_db_keymaps_installed = true
    local get_keymap_calls = 0
    state_stub.get_keymap = function()
      get_keymap_calls = get_keymap_calls + 1
      return nil
    end
    runner.ensure_sql_keymaps(buf)
    assert.equals(0, get_keymap_calls)
  end)
end)

describe("sql_runner run_sql_request", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "select 1" })
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".sql")
    vim.api.nvim_set_current_buf(buf)
    vim.b[buf] = {}
    state_stub.sql = { context = { connection = nil, database = nil } }
  end)

  it("notifies when binary not found", function()
    state_stub.find_poste_binary = function() return nil end
    local notified
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end
    runner.run_sql_request()
    assert.is_not_nil(notified)
    assert.matches("not found", notified.msg)
  end)

  after_each(function()
    package.loaded["poste.state"] = saved_state
    package.loaded["poste.util"] = saved_util
    package.loaded["poste.indicators"] = saved_indicators
    package.loaded["poste-db.statement"] = saved_statement
    package.loaded["poste-db.introspect"] = saved_introspect
    package.loaded["poste-db.format"] = saved_format
    package.loaded["poste-db.buffer"] = saved_buffer
  end)
end)

