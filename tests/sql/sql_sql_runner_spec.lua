local saved_state = package.loaded["poste.state"]
local saved_sql_state = package.loaded["poste-db.state"]
local saved_config = package.loaded["poste-db.config"]
local saved_util = package.loaded["poste.util"]
local saved_indicators = package.loaded["poste.indicators"]
local saved_statement = package.loaded["poste-db.statement"]
local saved_introspect = package.loaded["poste-db.introspect"]
local saved_format = package.loaded["poste-db.format"]
local saved_buffer = package.loaded["poste-db.buffer"]

local poste_state_stub = {
  current_env = "dev",
  find_poste_binary = function() return nil end,
  log = function() end,
  last_response = nil,
}
local sql_state_stub = {
  context = { connection = nil, database = nil },
  _sql_session = nil,
}
local config_stub = {
  get_keymap = function() return nil end,
  config = {},
}

package.loaded["poste.state"] = poste_state_stub
package.loaded["poste-db.state"] = sql_state_stub
package.loaded["poste-db.config"] = config_stub
package.loaded["poste.util"] = {}
package.loaded["poste.indicators"] = { clear_all = function() end, set_indicator = function() end }
package.loaded["poste-db.statement"] = {
  extract_stmt_at_cursor = function() end,
  extract_visual_block = function() end,
  find_stmt_lines = function() end,
  get_stmt_sql = function() end,
  extract_table_name = function() end,
  _test = {},
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
    config_stub.get_keymap = function(area, name, default)
      return default
    end
    runner.ensure_sql_keymaps(buf)
    assert.is_true(vim.b[buf].poste_db_keymaps_installed)
  end)

  it("skips if already installed", function()
    vim.b[buf].poste_db_keymaps_installed = true
    local get_keymap_calls = 0
    config_stub.get_keymap = function()
      get_keymap_calls = get_keymap_calls + 1
      return nil
    end
    runner.ensure_sql_keymaps(buf)
    assert.equals(0, get_keymap_calls)
  end)
end)

describe("sql_runner is_ddl", function()
  it("detects DDL with leading @connection directive and ### marker", function()
    assert.is_true(runner._test.is_ddl("-- @connection blog\n###\nCREATE TABLE three_kingdoms_characters (id INT);"))
  end)

  it("detects CREATE/ALTER/DROP/TRUNCATE/RENAME", function()
    assert.is_true(runner._test.is_ddl("CREATE TABLE t (id INT);"))
    assert.is_true(runner._test.is_ddl("ALTER TABLE t ADD COLUMN c INT;"))
    assert.is_true(runner._test.is_ddl("DROP TABLE t;"))
    assert.is_true(runner._test.is_ddl("TRUNCATE TABLE t;"))
    assert.is_true(runner._test.is_ddl("RENAME TABLE a TO b;"))
  end)

  it("rejects DML and reads", function()
    assert.is_false(runner._test.is_ddl("SELECT * FROM t;"))
    assert.is_false(runner._test.is_ddl("INSERT INTO t VALUES (1);"))
    assert.is_false(runner._test.is_ddl("UPDATE t SET c = 1;"))
    assert.is_false(runner._test.is_ddl(nil))
  end)

  it("ignores leading comment and blank lines", function()
    assert.is_true(runner._test.is_ddl("-- note\n\n   DROP TABLE t;"))
    assert.is_false(runner._test.is_ddl("-- note\nSELECT 1;"))
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
    sql_state_stub.context = { connection = nil, database = nil }
  end)

  it("notifies when binary not found", function()
    poste_state_stub.find_poste_binary = function() return nil end
    local notified
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end
    runner.run_sql_request()
    assert.is_not_nil(notified)
    assert.matches("not found", notified.msg)
  end)

  it("visual multi-statement: running spinner lands on each statement's last line (not first)", function()
    local lines = {
      "-- 创建能力表",
      "CREATE TABLE abilities (",
      "    id INT AUTO_INCREMENT PRIMARY KEY,",
      "    FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE",
      ");",
      "",
      "-- 创建团队表",
      "CREATE TABLE teams (",
      "    id INT AUTO_INCREMENT PRIMARY KEY,",
      ");",
    }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    poste_state_stub.find_poste_binary = function() return "poste" end
    config_stub.get_keymap = function(area, name, default) return default end
    config_stub.config = { confirm_unfiltered_dml = false }

    local stub = package.loaded["poste-db.statement"]
    stub.extract_visual_block = function(src, start_line, end_line)
      return table.concat(lines, "\n"), { 2, 8 }, 0
    end
    stub.extract_label = function() return nil end
    stub.fallback_label = function() return "test_label" end
    stub.get_stmt_sql = function() return "" end

    local indicator_calls = {}
    -- The runner captured `poste.indicators` at require time (the stub set up
    -- at the top of this spec), so mutate that same object to spy on calls.
    local ind_stub = package.loaded["poste.indicators"]
    ind_stub.clear_all = function() end
    ind_stub.set_indicator = function(...)
      indicator_calls[#indicator_calls + 1] = { ... }
    end
    package.loaded["poste-db.executor"] = { execute = function() end }

    runner.ensure_sql_keymaps(buf)
    vim.api.nvim_set_current_buf(buf)
    vim.cmd("normal! ggVG")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)

    -- Running spinners must sit on the statements' last lines (0-indexed
    -- lines 4 = ");" and 9 = ");") — the same lines completion will touch —
    -- never on the CREATE TABLE first lines (1 and 7).
    local running_lines = {}
    for _, c in ipairs(indicator_calls) do
      if c[3] == "running" then running_lines[#running_lines + 1] = c[2] end
    end
    table.sort(running_lines)
    assert.same({ 4, 9 }, running_lines, "spinner must land on each statement's last line")
  end)

  after_each(function()
    package.loaded["poste.state"] = saved_state
    package.loaded["poste-db.state"] = saved_sql_state
    package.loaded["poste-db.config"] = saved_config
    package.loaded["poste.util"] = saved_util
    package.loaded["poste.indicators"] = saved_indicators
    package.loaded["poste-db.statement"] = saved_statement
    package.loaded["poste-db.introspect"] = saved_introspect
    package.loaded["poste-db.format"] = saved_format
    package.loaded["poste-db.buffer"] = saved_buffer
  end)
end)

