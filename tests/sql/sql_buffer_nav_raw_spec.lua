local raw = require("poste-db.buffer.nav_raw")

describe("buffer_nav_raw", function()
  local saved = {}

  local function stub_api()
    saved.create_buf = vim.api.nvim_create_buf
    saved.set_option = vim.api.nvim_set_option_value
    saved.set_lines = vim.api.nvim_buf_set_lines
    saved.open_win = vim.api.nvim_open_win
    saved.win_is_valid = vim.api.nvim_win_is_valid
    saved.win_close = vim.api.nvim_win_close
    saved.keymap = vim.keymap.set
    saved.nav_state = package.loaded["poste-db.buffer.nav_state"]
    saved.format = package.loaded["poste-db.format"]
  end

  local function unstub_api()
    vim.api.nvim_create_buf = saved.create_buf
    vim.api.nvim_set_option_value = saved.set_option
    vim.api.nvim_buf_set_lines = saved.set_lines
    vim.api.nvim_open_win = saved.open_win
    vim.api.nvim_win_is_valid = saved.win_is_valid
    vim.api.nvim_win_close = saved.win_close
    vim.keymap.set = saved.keymap
    package.loaded["poste-db.buffer.nav_state"] = saved.nav_state
    package.loaded["poste-db.format"] = saved.format
  end

  before_each(stub_api)
  after_each(unstub_api)

  it("warns when no tab is available", function()
    package.loaded["poste-db.buffer.nav_state"] = {
      get_tab = function() return nil end,
      has_layout = function() return false end,
    }

    local notified
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end

    raw.show()

    assert.truthy(notified)
    assert.equals(vim.log.levels.WARN, notified.level)
  end)

  it("warns when the tab has no layout", function()
    package.loaded["poste-db.buffer.nav_state"] = {
      get_tab = function() return {} end,
      has_layout = function() return false end,
    }

    local notified
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end

    raw.show()

    assert.truthy(notified)
    assert.equals(vim.log.levels.WARN, notified.level)
  end)

  it("opens a float window carrying the rendered table in a buffer", function()
    package.loaded["poste-db.buffer.nav_state"] = {
      get_tab = function()
        return { layout = { rows = { 1, 2 }, table_name = "users" } }
      end,
      has_layout = function() return true end,
    }
    package.loaded["poste-db.format"] = {
      render_page = function()
        return { "header", "row1" }
      end,
    }

    local set_lines_calls = {}
    local set_option_calls = {}
    local open_win_calls = {}
    local keymap_calls = {}

    vim.api.nvim_create_buf = function()
      return 77
    end
    vim.api.nvim_set_option_value = function(name, value, opts)
      set_option_calls[#set_option_calls + 1] = { name = name, value = value, opts = opts }
    end
    vim.api.nvim_buf_set_lines = function(buf, start, finish, strict, lines)
      set_lines_calls[#set_lines_calls + 1] = { buf = buf, lines = lines }
    end
    vim.api.nvim_open_win = function(buf, enter, opts)
      open_win_calls[#open_win_calls + 1] = { buf = buf, opts = opts }
      return 88
    end
    vim.api.nvim_win_is_valid = function() return true end
    vim.api.nvim_win_close = function(win, force)
      set_option_calls[#set_option_calls + 1] = { kind = "close", win = win, force = force }
    end
    vim.keymap.set = function(mode, lhs, rhs, opts)
      keymap_calls[#keymap_calls + 1] = { mode = mode, lhs = lhs, opts = opts }
    end

    local ok, err = pcall(raw.show)

    assert.is_true(ok, err)
    assert.equals(1, #set_lines_calls)
    assert.same({ "header", "row1" }, set_lines_calls[1].lines)
    assert.equals(77, set_lines_calls[1].buf)
    assert.equals(1, #open_win_calls)
    assert.equals(77, open_win_calls[1].buf)
    local titled = open_win_calls[1].opts.title or ""
    assert.matches("Raw Mode", titled)
    assert.matches("users", titled)

    local saw_close = false
    for _, item in ipairs(keymap_calls) do
      if item.mode == "n" and item.lhs == "q" then
        saw_close = true
      end
    end
    assert.is_true(saw_close)
  end)

  it("appends an omitted-rows footer and caps page size", function()
    local render_args
    package.loaded["poste-db.buffer.nav_state"] = {
      get_tab = function()
        return { layout = { rows = { 1 }, total_rows = 600 } }
      end,
      has_layout = function() return true end,
    }
    package.loaded["poste-db.format"] = {
      render_page = function(layout, page, page_size)
        render_args = { page = page, page_size = page_size }
        return { "header" }
      end,
    }

    local set_lines_calls = {}
    vim.api.nvim_create_buf = function() return 77 end
    vim.api.nvim_set_option_value = function() end
    vim.api.nvim_buf_set_lines = function(buf, start, finish, strict, lines)
      set_lines_calls[#set_lines_calls + 1] = lines
    end
    vim.api.nvim_open_win = function() return 88 end
    vim.api.nvim_win_is_valid = function() return true end
    vim.api.nvim_win_close = function() end
    vim.keymap.set = function() end

    raw.show()

    assert.equals(1, render_args.page)
    assert.is_true(render_args.page_size <= 500)
    local lines = set_lines_calls[1]
    local joined = table.concat(lines, " ")
    assert.matches("more row%(s%) omitted", joined)
  end)

  it("toggle aliases show", function()
    assert.equals(raw.show, raw.toggle)
  end)
end)