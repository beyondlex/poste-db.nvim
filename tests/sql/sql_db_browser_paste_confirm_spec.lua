--- show_paste_confirm's settle contract: y confirms, and EVERY other way the
--- dialog can go away (n, q, <Esc>, WinLeave) counts as cancel.
describe("db_browser paste confirm", function()
  local copy_progress = require("poste-db.db_browser.copy_progress")

  local source = { conn = "a", db = "blog", dialect = "mysql" }
  local target = { conn = "b", db = "blog", dialect = "mysql" }
  local plan = { { kind = "table", orig = "users", final = "users" } }

  --- Open the confirm dialog and return its buffer (the new buffer that has
  --- the y/n/q keymaps — the backdrop float has none).
  local function open_confirm(on_confirm, on_cancel)
    local before = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do before[b] = true end
    copy_progress.show_paste_confirm(source, target, plan, nil, on_confirm, on_cancel)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if not before[b] and vim.fn.maparg("q", "n", false, true) ~= "" then
        -- maparg is buffer-local sensitive only via the current buffer; check
        -- this buffer directly instead
        local m = vim.api.nvim_buf_get_keymap(b, "n")
        for _, km in ipairs(m) do
          if km.lhs == "q" and km.callback then return b, km.callback end
        end
      end
    end
    error("paste-confirm dialog buffer not found")
  end

  it("runs on_confirm exactly once on y", function()
    local confirmed, cancelled = 0, 0
    local buf = open_confirm(function() confirmed = confirmed + 1 end,
      function() cancelled = cancelled + 1 end)
    local y_cb
    for _, km in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if km.lhs == "y" then y_cb = km.callback end
    end
    y_cb()
    assert.equals(1, confirmed, "y must confirm exactly once")
    assert.equals(0, cancelled, "confirm must not also cancel")
    assert.is_false(vim.api.nvim_buf_is_valid(buf), "the dialog closes after answering")
  end)

  it("runs on_cancel when the dialog is closed with q", function()
    local confirmed, cancelled = 0, 0
    local buf, q_cb = open_confirm(function() confirmed = confirmed + 1 end,
      function() cancelled = cancelled + 1 end)
    q_cb()
    assert.equals(1, cancelled, "q counts as cancel — exactly once")
    assert.equals(0, confirmed)
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)

  it("does not double-fire when n closes the dialog", function()
    local cancelled = 0
    local buf = open_confirm(nil, function() cancelled = cancelled + 1 end)
    for _, km in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if km.lhs == "n" then km.callback() end
    end
    assert.equals(1, cancelled, "n must cancel exactly once (close+answer must not stack)")
  end)
end)
