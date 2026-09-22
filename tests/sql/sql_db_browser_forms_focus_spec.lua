--- Item 47: the form's focus highlight and cursor are positioned through a
--- row→line map built during rendering, and the window is sized from the same
--- render. Both used to be derived independently, so the selection landed on the
--- wrong line and the shortcut bar was cut off — vertically and horizontally.
local forms = require("poste-db.db_browser.forms_advanced")
local t = forms._test

local WIDTH = 60

local function sections()
  return {
    {
      title = "Owner",
      fields = {
        { key = "name", label = "Role", kind = "text", value = "analyst" },
        { key = "preview", label = "SQL", kind = "preview" },
      },
    },
    {
      title = "Grants",
      fields = {
        { key = "grantee", label = "Grantee", kind = "text", value = "app" },
      },
    },
  }
end

local SQL = {
  "GRANT SELECT, INSERT",
  "ON ALL TABLES IN SCHEMA analytics",
  "TO analyst",
}

describe("forms_advanced row → line mapping", function()
  local rows, focusable, lines, row_line

  before_each(function()
    rows, focusable = t.build_rows(sections(), "postgres")
    local rendered, _, mapping = t.render(rows, WIDTH, SQL)
    lines, row_line = rendered, mapping
  end)

  it("every focusable row maps to the line that shows its own label", function()
    -- The regression: the row index was used as a buffer line, so the blank
    -- separator before "Grants" and the preview's extra lines shifted every
    -- later row onto the line above it.
    assert.equals(2, #focusable, "preview rows are not focusable")
    for _, ri in ipairs(focusable) do
      local row = rows[ri]
      local line = lines[row_line[ri]] or ""
      assert.is_truthy(line:find(row.field.label, 1, true),
        ("expected %q on line %s, got %q"):format(row.field.label, tostring(row_line[ri]), line))
    end
  end)

  it("maps every row, in strictly increasing buffer order", function()
    local prev = 0
    for ri = 1, #rows do
      local line = row_line[ri]
      assert.is_truthy(line, "row " .. ri .. " is unmapped")
      assert.is_truthy(line > prev, "row " .. ri .. " maps before the previous row")
      assert.is_truthy(line <= #lines, "row " .. ri .. " maps past the end of the buffer")
      prev = line
    end
  end)

  it("the last row still resolves inside the buffer next to a wrapped preview", function()
    assert.equals("  Grantee:  app", lines[row_line[#rows]] or "")
  end)

  it("ends on the shortcut bar, which the window height must therefore cover", function()
    -- The tail hint is the one the old single-line bar lost to the border.
    assert.equals("  [Enter edit]  [Space toggle]", lines[#lines] or "")
  end)
end)

describe("forms_advanced shortcut bar", function()
  it("stays one line while the whole bar fits, as at the default width", function()
    -- 80-column form → 78 columns of content, and the bar is 77 wide. Wrapping
    -- must not start early and waste a line on the shape every caller uses.
    local res = t.footer_lines(78)
    assert.equals(1, #res.lines)
    assert.equals("  [q Cancel]  [y Copy]  [s Execute]  [j/k move]  [Enter edit]  [Space toggle]",
      res.lines[1])
  end)

  it("keeps every entry inside the width it is drawn for", function()
    -- The bar is 77 columns wide, so any float narrower than 79 cut its tail
    -- off: the `Space toggle` hint was simply never on screen.
    local res = t.footer_lines(58)
    assert.is_true(#res.lines > 1, "the bar must wrap instead of overflowing")
    for _, line in ipairs(res.lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= 58, "too wide: " .. line)
    end
    local text = table.concat(res.lines, "\n")
    for _, entry in ipairs({ "Cancel", "Copy", "Execute", "move", "edit", "toggle" }) do
      assert.is_truthy(text:find(entry, 1, true), "lost the " .. entry .. " hint")
    end
  end)

  it("highlights each key and label on the line that actually carries it", function()
    local res = t.footer_lines(58)
    local keys = { q = true, y = true, s = true, ["j/k"] = true, Enter = true, Space = true }
    local labels = { Cancel = true, Copy = true, Execute = true, move = true, edit = true, toggle = true }
    assert.equals(12, #res.highlights, "one key and one label highlight per entry")
    for _, h in ipairs(res.highlights) do
      local expected = h.hl_group == "PosteDbFormShortcut" and keys or labels
      local snippet = (res.lines[h.line + 1] or ""):sub(h.col_start + 1, h.col_end)
      assert.is_true(expected[snippet] == true,
        ("%q on line %d is not a %s"):format(snippet, h.line + 1, h.hl_group))
      expected[snippet] = nil
    end
    assert.equals(0, vim.tbl_count(keys), "some key was never highlighted")
    assert.equals(0, vim.tbl_count(labels), "some label was never highlighted")
  end)
end)

describe("forms_advanced dialog geometry", function()
  local win, buf

  local function adv_ns()
    for name, id in pairs(vim.api.nvim_get_namespaces()) do
      if name == "poste_db_adv_form" then return id end
    end
  end

  --- 0-based row of the single mark the form paints for the focused row.
  local function marked_row()
    local marks = vim.api.nvim_buf_get_extmarks(buf, adv_ns(), 0, -1, { details = true })
    return marks[1] and marks[1][2] or nil -- items are {id, row, col, details}
  end

  local function line_at(row)
    return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  end

  local function open(secs)
    forms.open({
      title = "Grants",
      width = WIDTH,
      sections = secs,
      on_change = function() return SQL end,
    })
    win = vim.api.nvim_get_current_win()
    buf = vim.api.nvim_win_get_buf(win)
    assert.is_true(vim.api.nvim_win_is_valid(win))
  end

  after_each(function()
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    win, buf = nil, nil
  end)

  it("the window is tall enough for the whole buffer", function()
    -- Height used to be guessed from a row count that ignored the trailing
    -- blank lines and the shortcut bar, cutting the shortcuts off.
    open(sections())
    local n_lines = vim.api.nvim_buf_line_count(buf)
    local content_height = vim.api.nvim_win_get_height(win) - 2 -- rounded border
    assert.equals(n_lines, content_height, "window content height must fit the buffer")
    assert.is_truthy(line_at(n_lines - 1):find("toggle", 1, true),
      "last line is the shortcut bar: " .. line_at(n_lines - 1))
  end)

  it("no shortcut line is wider than the float's content", function()
    open(sections())
    local content_width = vim.api.nvim_win_get_width(win) - 2
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= content_width,
        ("line wider than the float, so its tail is cut off: %q"):format(line))
    end
  end)

  it("the selection highlight and the cursor agree on the focused row", function()
    open(sections())
    local marks = vim.api.nvim_buf_get_extmarks(buf, adv_ns(), 0, -1, { details = true })
    assert.equals(1, #marks, "one highlight mark for the focused row")
    local row = marks[1][2]
    assert.is_truthy(line_at(row):find("Role", 1, true), "focused row is Role, got " .. line_at(row))
    assert.equals(row + 1, vim.api.nvim_win_get_cursor(win)[1], "cursor must sit on the highlight")
  end)

  it("focus past a section separator lands on the field, not the preview above it", function()
    -- The first focusable row is in the second section, so the row→line map has
    -- to get across both the separator blank and the preview's extra lines.
    open({
      { title = "SQL", fields = { { key = "preview", label = "Preview", kind = "preview" } } },
      { title = "Grants", fields = { { key = "g", label = "Grantee", kind = "text", value = "app" } } },
    })
    local row = marked_row()
    assert.is_truthy(row, "the form painted no selection")
    assert.equals("  Grantee:  app", line_at(row))
    assert.equals(row + 1, vim.api.nvim_win_get_cursor(win)[1])
  end)
end)

describe("forms_advanced close on WinLeave", function()
  local win, buf, maps, picker_shown, ui_select

  local function open()
    forms.open({
      title = "Owner",
      width = WIDTH,
      dialect = "postgres",
      sections = { { title = "Owner", fields = {
        { key = "owner", label = "Owner", kind = "select", value = "a", choices = { "a", "b" } },
      } } },
      on_change = function() return { "SELECT 1" } end,
    })
    win = vim.api.nvim_get_current_win()
    buf = vim.api.nvim_win_get_buf(win)
    maps = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do maps[m.lhs] = m.callback end
  end

  after_each(function()
    vim.ui.select = ui_select
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    win, buf, maps = nil, nil, nil
  end)

  before_each(function()
    ui_select, picker_shown = vim.ui.select, false
  end)

  --- Answer a pick list the way the default UI does it: from its own window, so
  --- answering one is itself a WinLeave from the form.
  local function picker(items, _, cb)
    picker_shown = true
    vim.cmd("vsplit /tmp/poste-db-picker.txt")
    local picker_win = vim.api.nvim_get_current_win()
    cb(items[2])
    if vim.api.nvim_win_is_valid(picker_win) then vim.api.nvim_win_close(picker_win, true) end
  end

  local function leave()
    vim.cmd("vsplit /tmp/poste-db-other.txt")
    local other = vim.api.nvim_get_current_win()
    vim.wait(100, function() return not vim.api.nvim_win_is_valid(win) end)
    if vim.api.nvim_win_is_valid(other) then vim.api.nvim_win_close(other, true) end
  end

  it("leaving the form closes it", function()
    open()
    leave()
    assert.is_false(vim.api.nvim_win_is_valid(win))
  end)

  it("a pick list does not close the form while it is up", function()
    vim.ui.select = picker
    open()
    maps["<CR>"]()
    assert.is_true(picker_shown)
    assert.is_true(vim.api.nvim_win_is_valid(win), "answering the prompt is not the same as leaving")
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    assert.is_truthy(text:find("Owner:  b", 1, true), "the pick applied:\n" .. text)
  end)

  it("still closes on the next leave after a pick list edit", function()
    vim.ui.select = picker
    open()
    maps["<CR>"]()
    leave()
    assert.is_false(vim.api.nvim_win_is_valid(win),
      "the one-shot autocmd spent itself on the picker's focus change")
  end)
end)
