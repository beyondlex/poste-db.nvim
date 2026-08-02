local D = require("poste-sql.dataset")
local state = require("poste.state")
local raw = require("poste-sql.buffer_nav_raw")

describe("buffer_nav_raw", function()
  local saved_T = nil
  local saved_win_is_valid = nil
  local saved_enter = nil
  local saved_exit = nil
  local saved_buffer_page = nil

  before_each(function()
    saved_T = D.T
    saved_win_is_valid = vim.api.nvim_win_is_valid
    saved_enter = raw.enter
    saved_exit = raw.exit
    saved_buffer_page = package.loaded["poste-sql.buffer_page"]
    D.dataset_buffer = 11
    D.dataset_window = 22
    state.sql._raw_mode = false
    state.sql._hide_header_float = false
  end)

  after_each(function()
    D.T = saved_T
    vim.api.nvim_win_is_valid = saved_win_is_valid
    raw.enter = saved_enter
    raw.exit = saved_exit
    package.loaded["poste-sql.buffer_page"] = saved_buffer_page
  end)

  it("builds raw lines from the formatter", function()
    local saved_format = package.loaded["poste-sql.format"]
    package.loaded["poste-sql.format"] = {
      render_page = function()
        return { "one", "two" }, {}
      end,
    }

    local lines = raw.build_raw_lines({ layout = { rows = { 1, 2 } } })

    package.loaded["poste-sql.format"] = saved_format
    assert.same({ "one", "two" }, lines)
  end)

  it("enters and exits raw mode", function()
    local saved = {
      create_buf = vim.api.nvim_create_buf,
      set_option = vim.api.nvim_set_option_value,
      set_lines = vim.api.nvim_buf_set_lines,
      set_buf = vim.api.nvim_win_set_buf,
      set_name = vim.api.nvim_buf_set_name,
      buf_is_valid = vim.api.nvim_buf_is_valid,
      win_is_valid = vim.api.nvim_win_is_valid,
      buf_delete = vim.api.nvim_buf_delete,
      keymap_set = vim.keymap.set,
      close_header_float = D.close_header_float,
      get_keymap = state.get_keymap,
      format = package.loaded["poste-sql.format"],
    }

    local calls = {}
    local deleted_buf = nil
    local restored_buf = nil

    package.loaded["poste-sql.format"] = {
      render_page = function()
        return { "raw-1", "raw-2" }, {}
      end,
    }

    vim.api.nvim_create_buf = function()
      calls[#calls + 1] = "create_buf"
      return 77
    end
    vim.api.nvim_set_option_value = function(name, value, opts)
      calls[#calls + 1] = { name = name, value = value, opts = opts }
    end
    vim.api.nvim_buf_set_lines = function(buf, start, finish, strict, lines)
      calls[#calls + 1] = { kind = "set_lines", buf = buf, lines = lines }
    end
    vim.api.nvim_win_set_buf = function(win, buf)
      restored_buf = { win = win, buf = buf }
    end
    vim.api.nvim_buf_set_name = function(buf, name)
      calls[#calls + 1] = { kind = "set_name", buf = buf, name = name }
    end
    vim.api.nvim_buf_is_valid = function(buf)
      return buf == 11 or buf == 77
    end
    vim.api.nvim_win_is_valid = function(win)
      return win == 22
    end
    vim.api.nvim_buf_delete = function(buf, opts)
      deleted_buf = { buf = buf, opts = opts }
    end
    vim.keymap.set = function(mode, lhs, rhs, opts)
      calls[#calls + 1] = { kind = "keymap", lhs = lhs, opts = opts }
    end
    D.close_header_float = function()
      calls[#calls + 1] = "close_header_float"
    end
    state.get_keymap = function(_, _, default)
      return default
    end

    local ok, err = pcall(function()
      local buf = raw.enter({
        layout = { rows = { 1, 2 } },
      }, 22)
      assert.equals(77, buf)
      assert.is_true(state.sql._raw_mode)
      assert.is_true(state.sql._hide_header_float)
      assert.same({ win = 22, buf = 77 }, restored_buf)

      raw.exit()
      assert.is_false(state.sql._raw_mode)
      assert.is_false(state.sql._hide_header_float)
      assert.same({ win = 22, buf = 11 }, restored_buf)
      assert.same({ buf = 77, opts = { force = true } }, deleted_buf)
    end)

    vim.api.nvim_create_buf = saved.create_buf
    vim.api.nvim_set_option_value = saved.set_option
    vim.api.nvim_buf_set_lines = saved.set_lines
    vim.api.nvim_win_set_buf = saved.set_buf
    vim.api.nvim_buf_set_name = saved.set_name
    vim.api.nvim_buf_is_valid = saved.buf_is_valid
    vim.api.nvim_win_is_valid = saved.win_is_valid
    vim.api.nvim_buf_delete = saved.buf_delete
    vim.keymap.set = saved.keymap_set
    D.close_header_float = saved.close_header_float
    state.get_keymap = saved.get_keymap
    package.loaded["poste-sql.format"] = saved.format

    assert.is_true(ok, err)
    local saw_keymap = false
    for _, item in ipairs(calls) do
      if type(item) == "table" and item.kind == "keymap" then
        saw_keymap = true
        break
      end
    end
    assert.is_true(saw_keymap)
    assert.same({ buf = 77, opts = { force = true } }, deleted_buf)
  end)

  it("toggles raw mode on and off", function()
    local refresh_calls = 0
    local enter_calls = 0
    local exit_calls = 0

    package.loaded["poste-sql.buffer_page"] = {
      refresh_page = function()
        refresh_calls = refresh_calls + 1
      end,
    }
    raw.enter = function(tab, win)
      enter_calls = enter_calls + 1
      assert.truthy(tab)
      assert.equals(22, win)
      state.sql._raw_mode = true
      return 77
    end
    raw.exit = function()
      exit_calls = exit_calls + 1
      state.sql._raw_mode = false
    end
    D.T = function()
      return { layout = { rows = { 1 } } }
    end
    vim.api.nvim_win_is_valid = function(win)
      return win == 22
    end

    raw.toggle()
    assert.equals(1, enter_calls)
    assert.equals(0, exit_calls)
    assert.equals(0, refresh_calls)
    assert.is_true(state.sql._raw_mode)

    raw.toggle()
    assert.equals(1, enter_calls)
    assert.equals(1, exit_calls)
    assert.equals(1, refresh_calls)
    assert.is_false(state.sql._raw_mode)
  end)
end)
