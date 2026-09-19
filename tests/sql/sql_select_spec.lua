--- Item 19: the built-in select float must render item descriptions itself.
local selector = require("poste-db.select")

local saved_ui_select = vim.ui.select
local ui_select_called = false

local function float_wins()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
    if ok and cfg.relative and cfg.relative ~= "" then table.insert(out, win) end
  end
  return out
end

describe("select built-in float", function()
  before_each(function()
    ui_select_called = false
    -- a hit means the float bailed out and the picker silently degraded
    vim.ui.select = function() ui_select_called = true end
  end)

  after_each(function()
    vim.ui.select = saved_ui_select
    for _, win in ipairs(float_wins()) do pcall(vim.api.nvim_win_close, win, true) end
  end)

  it("renders descriptions inline without falling back to vim.ui.select", function()
    selector.select({
      { key = "k1", name = "alpha", description = "the first one" },
      "beta",
    }, "Pick", function() end)

    assert.is_false(ui_select_called)
    local wins = float_wins()
    assert.equals(1, #wins)

    local buf = vim.api.nvim_win_get_buf(wins[1])
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    assert.truthy(text:find("alpha", 1, true))
    assert.truthy(text:find("the first one", 1, true))
    assert.truthy(text:find("beta", 1, true))

    -- the description tint is an extmark, and nvim_buf_set_extmark rejects the
    -- `-1` that add/clear_namespace accept: the render used to abort here
    local ns = vim.api.nvim_get_namespaces()["poste-db-select"]
    assert.truthy(ns)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert.equals(1, #marks)
  end)
end)
