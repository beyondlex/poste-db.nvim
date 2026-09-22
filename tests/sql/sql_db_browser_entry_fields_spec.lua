--- Item 50: a `list` field's entries are editable. The advanced form rendered an
--- entry as one summary line with a ▶/▼ marker, but the marker flipped a flag on
--- the row (rebuilt from the entry on every change), no sub-field was ever shown,
--- and entries were not even in `focusable` — so Enter, Space and `d` could not
--- reach them at all. The one field kind the generated SQL depends on was stuck
--- at its defaults: CREATE SCHEMA's GRANT entries could never name a grantee.
local forms = require("poste-db.db_browser.forms_advanced")
local t = forms._test

local WIDTH = 70

local function sub_fields()
  return {
    { key = "type", label = "Type", kind = "select", value = "grant", choices = { "grant", "grant_usage" } },
    { key = "grantee", label = "Grantee", kind = "text", value = "" },
    { key = "privileges", label = "Privileges", kind = "multi_select", value = { "SELECT" },
      choices = { "SELECT", "INSERT" } },
    { key = "grantee_option", label = "Grant Option", kind = "bool", value = false, dialect = "postgres" },
  }
end

local function list_field(entries)
  return { key = "grants", label = "Grants", kind = "list", value = entries or {}, sub_fields = sub_fields() }
end

local function sections(entries)
  return { { title = "Grants", fields = { list_field(entries), { key = "p", label = "SQL", kind = "preview" } } } }
end

local function nested(rows)
  local out = {}
  for ri, row in ipairs(rows) do
    if row.nested then table.insert(out, ri) end
  end
  return out
end

describe("forms_advanced entry rows", function()
  it("an expanded entry contributes one row per sub-field this dialect has", function()
    local entry = t.new_list_entry(sub_fields())
    local rows = t.build_rows(sections({ entry }), "postgres")
    assert.equals(4, #nested(rows))
    local mysql_rows = t.build_rows(sections({ entry }), "mysql")
    assert.equals(3, #nested(mysql_rows), "the `dialect = postgres` sub-field is skipped")
  end)

  it("each row carries its own entry's value, not the shared template's", function()
    local subs = sub_fields()
    local field = list_field({ { grantee = "app", type = "grant_usage" }, { grantee = "batch" } })
    field.sub_fields = subs
    local rows = t.build_rows({ { title = "G", fields = { field } } }, "postgres")
    local seen = {}
    for _, ri in ipairs(nested(rows)) do
      local row = rows[ri]
      seen[row.entry.grantee .. "/" .. row.field.key] = row.field.value
    end
    assert.equals("grant_usage", seen["app/type"], "the first entry's own choice")
    assert.equals("app", seen["app/grantee"])
    assert.equals("batch", seen["batch/grantee"])
    assert.equals("grant", seen["batch/type"], "the second entry keeps the template's default")
    assert.equals("", subs[2].value, "the template is a fallback, never a value store")
  end)

  it("a collapsed entry keeps its own row focusable and shows no sub-fields", function()
    local entry = t.new_list_entry(sub_fields())
    entry._collapsed = true
    local rows, focusable = t.build_rows(sections({ entry }), "postgres")
    assert.equals(0, #nested(rows))
    local entry_row
    for ri, row in ipairs(rows) do
      if row.type == "list_entry" then entry_row = ri end
    end
    assert.is_truthy(vim.tbl_contains(focusable, entry_row),
      "`d` and the marker toggle need the entry line to be reachable")
  end)

  it("the entry line reports its values as they are now", function()
    local entry = t.new_list_entry(sub_fields())
    entry.grantee = "app"
    local rows = t.build_rows(sections({ entry }), "postgres")
    local lines = t.render(rows, WIDTH, { "sql" })
    local entry_line
    for _, line in ipairs(lines) do
      if line:find("entry 1", 1, true) then entry_line = line end
    end
    assert.is_truthy(entry_line:find("Grantee=app", 1, true), entry_line)
    assert.is_truthy(entry_line:find("Privileges=[SELECT]", 1, true), entry_line)
  end)

  it("nested rows sit under their entry line and align with each other", function()
    local entry = t.new_list_entry(sub_fields())
    local rows = t.build_rows(sections({ entry }), "postgres")
    local lines, _, row_line = t.render(rows, WIDTH, { "sql" })
    local entry_line
    for ri, row in ipairs(rows) do
      if row.type == "list_entry" then entry_line = lines[row_line[ri]] end
    end
    assert.is_truthy(entry_line:find("^    ▼ "), entry_line)
    local value_col
    for _, ri in ipairs(nested(rows)) do
      local line = lines[row_line[ri]] or ""
      local indent = line:match("^(%s+)")
      assert.is_true(#indent > 4, "a sub-field must sit deeper than its entry: " .. line)
      local col = line:find("%S", #indent + 1)
      value_col = value_col or col
      assert.equals(value_col, col, ("labels disagree on the value column: %q"):format(line))
    end
  end)

  it("a table value is copied per entry, so two entries cannot share one list", function()
    local subs = sub_fields()
    local a = t.entry_subfield({ privileges = { "SELECT" } }, subs[3])
    local b = t.entry_subfield({}, subs[3])
    -- `is_not.same` compares deeply, and two equal-looking privilege lists are
    -- exactly the bug here: identity is what the assertion needs.
    assert.is_true(a.value ~= b.value, "each entry owns its list")
    assert.is_true(b.value ~= subs[3].value, "the copy must not alias the template's default")
    assert.same({ "SELECT" }, b.value, "an entry without its own value falls back to the template")

    table.insert(a.value, "INSERT")
    assert.equals(1, #b.value, "toggling one entry's privileges must not touch the other's")
  end)
end)

describe("forms_advanced entry editing", function()
  local win, buf, maps, seen

  local function line_at(row)
    return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  end

  local function marked_row()
    for name, id in pairs(vim.api.nvim_get_namespaces()) do
      if name == "poste_db_adv_form" then
        local marks = vim.api.nvim_buf_get_extmarks(buf, id, 0, -1, { details = true })
        return marks[1] and marks[1][2] or nil
      end
    end
  end

  local function press(lhs)
    maps[lhs]()
  end

  --- Tab down to the line whose text matches `pattern`, failing if none does.
  local function focus(pattern)
    for _ = 1, 12 do
      if line_at(marked_row()):find(pattern) then return line_at(marked_row()) end
      press("j")
    end
    error("no focused line matches " .. pattern)
  end

  local ui_input, ui_select
  before_each(function()
    ui_input, ui_select = vim.ui.input, vim.ui.select
    seen = {}
    forms.open({
      title = "Create Schema",
      width = WIDTH,
      dialect = "postgres",
      sections = sections({}),
      on_change = function(vals)
        table.insert(seen, vim.deepcopy(vals.grants))
        local grantee = (vals.grants[1] or {}).grantee or "(none)"
        return { "GRANT USAGE ON SCHEMA analytics TO " .. grantee .. ";" }
      end,
    })
    win = vim.api.nvim_get_current_win()
    buf = vim.api.nvim_win_get_buf(win)
    maps = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do maps[m.lhs] = m.callback end
    press("a") -- the focus starts on the Grants field row
  end)

  after_each(function()
    vim.ui.input, vim.ui.select = ui_input, ui_select
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    win, buf, maps = nil, nil, nil
  end)

  it("editing a sub-field writes through to the entry and into the SQL", function()
    local answer = "app"
    vim.ui.input = function(_, cb) cb(answer) end
    focus("^%s+Grantee:")
    press("<CR>")
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    assert.is_truthy(text:find("Grantee=app", 1, true), "the entry line re-reads the entry:\n" .. text)
    assert.is_truthy(text:find("TO app;", 1, true), "the preview came from the entry:\n" .. text)
    assert.equals("app", seen[#seen][1].grantee)
  end)

  it("cancelling the prompt leaves the value standing", function()
    vim.ui.input = function(_, cb) cb(nil) end
    focus("^%s+Grantee:")
    press("<CR>")
    assert.equals("", seen[#seen][1].grantee)
  end)

  it("a select sub-field goes through the choice list", function()
    vim.ui.select = function(_, _, cb) cb("grant_usage") end
    focus("^%s+Type:")
    press("<CR>")
    assert.equals("grant_usage", seen[#seen][1].type)
  end)

  it("a multi_select sub-field toggles one choice at a time", function()
    vim.ui.select = function(_, _, cb) cb({ value = "INSERT", label = "[✗] INSERT" }) end
    focus("^%s+Privileges:")
    press("<CR>")
    assert.same({ "SELECT", "INSERT" }, seen[#seen][1].privileges)
  end)

  it("a bool sub-field flips with no prompt", function()
    focus("^%s+Grant Option:")
    press("<CR>")
    assert.is_true(seen[#seen][1].grantee_option)
  end)

  it("Enter on the entry line folds its fields away and back", function()
    --- How many lines name the grantee: the entry's summary, plus the field row
    --- while the entry is open.
    local function grantee_lines()
      local n = 0
      for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:find("Grantee") then n = n + 1 end
      end
      return n
    end
    -- The entry line opens with indent and the fold marker, so anchor on the
    -- label rather than the start of the line.
    focus("entry 1")
    assert.equals(2, grantee_lines())
    press("<CR>")
    assert.equals(1, grantee_lines(), "a collapsed entry shows only its summary")
    press("<CR>")
    assert.equals(2, grantee_lines(), "and the marker is not a lie: it opens again")
  end)

  it("`d` on any line of the entry removes that entry", function()
    focus("^%s+Privileges:")
    press("d")
    assert.equals(0, #seen[#seen], "the preview saw the list empty out")
  end)

  -- The first `a` (in before_each) lands the cursor on the entry it created, one
  -- line below the list's own row. `a` used to act only on that row, so the
  -- second press did nothing at all and gave no sign it had not.
  it("`a` again from inside the entry adds a second entry", function()
    press("a")
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    assert.is_truthy(text:find("entry 2", 1, true), "the second `a` was a silent no-op:\n" .. text)
    assert.equals(2, #seen[#seen], "the preview saw both entries")
  end)

  it("`a` puts the cursor on the entry it added", function()
    press("a")
    local row = marked_row()
    assert.is_truthy(line_at(row):find("entry 2", 1, true),
      "the new entry should be the focused line, got: " .. line_at(row))
  end)

  it("`d` removes the entry under the cursor, not the first one", function()
    -- Names the first entry, adds a second from a sub-field row (the third
    -- place `a` has to work, and the one its `list_field` lookup is for), then
    -- deletes from the entry the cursor is on.
    vim.ui.input = function(_, cb) cb("app") end
    focus("^%s+Grantee:")
    press("<CR>")
    press("a")
    press("d")
    assert.equals(1, #seen[#seen], "one of the two entries is left")
    assert.equals("app", seen[#seen][1].grantee, "the named entry survived, the new one went")
  end)
end)
