-- Tests for lua/poste-db/db_browser/copy.lua clone helpers.
-- Pure helper tests (no real DB / no UI).

local copy = require("poste-db.db_browser.copy")
local t = copy._test

describe("db_browser clone pick_clone_default", function()
  it("returns base when free", function()
    assert.equals("blog_copy", t.pick_clone_default("blog_copy", {}))
    assert.equals("blog_copy", t.pick_clone_default("blog_copy", { other = true }))
  end)

  it("bumps to base2 when base taken", function()
    local existing = { blog_copy = true }
    assert.equals("blog_copy2", t.pick_clone_default("blog_copy", existing))
  end)

  it("skips occupied suffixes", function()
    local existing = { blog_copy = true, blog_copy2 = true }
    assert.equals("blog_copy3", t.pick_clone_default("blog_copy", existing))
  end)

  it("continues past gaps when a later suffix is taken", function()
    local existing = { blog_copy = true, blog_copy3 = true }
    assert.equals("blog_copy2", t.pick_clone_default("blog_copy", existing))
  end)
end)
describe("db_browser copy progress spinner", function()
  local function collect_dialog_lines()
    local lines = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(buf) then
        for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          table.insert(lines, l)
        end
      end
    end
    return lines
  end

  it("renders an animated spinner frame while a job is copying", function()
    local copy = require("poste-db.db_browser.copy")
    local t = copy._test
    local source = { conn = "s", db = "blog", dialect = "postgres" }
    local target = { conn = "t", db = "other", dialect = "postgres" }
    local jobs = {
      { label = "posts", work = function(cb)
          vim.defer_fn(function() cb(true, "100", "12ms") end, 400)
        end },
    }
    local start_fn = t.show_paste_progress(source, target, jobs, function() end)
    start_fn()

    local frames = require("poste.constants").SPINNER_FRAMES
    local observed = nil
    vim.wait(200, function()
      for _, l in ipairs(collect_dialog_lines()) do
        for _, ch in ipairs(frames) do
          if l:find(ch, 1, true) then observed = ch; return true end
        end
      end
      return false
    end)
    assert.is_not_nil(observed, "expected a spinner frame in the dialog while copying")

    -- After the job completes, the spinner is replaced by the success marker.
    vim.wait(600, function()
      for _, l in ipairs(collect_dialog_lines()) do
        if l:find("✓", 1, true) then return true end
      end
      return false
    end)
    local done = false
    for _, l in ipairs(collect_dialog_lines()) do
      if l:find("✓", 1, true) then done = true end
    end
    assert.is_true(done, "expected a ✓ success marker after job completion")

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      pcall(vim.api.nvim_win_close, win, true)
    end
  end)
end)
