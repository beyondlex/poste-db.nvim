local dialog = require("poste-db.dialog")
local layout = require("poste-db.layout")
local notify = require("poste-db.db_browser.notify")

local M = {}

local ns = vim.api.nvim_create_namespace("poste_db_adv_form")

require("poste-db.db_browser.theme").register({
  PosteDbFormShortcut = { fg = 0x98c379, bold = true },
  PosteDbFormDim = { fg = 0x5c6370 },
})
local active_form = nil

local function close_active()
  if not active_form then return end
  if active_form.dlg then
    active_form.dlg:close()
  end
  active_form = nil
end

--- Apply a `multi_select` pick to the current set, returning the new value as a
--- list in `choices` order (so generated SQL is deterministic).
local function apply_toggle(choices, current, picked)
  local selected = {}
  for _, c in ipairs(choices) do
    if c == picked then
      if not current[c] then table.insert(selected, c) end
    elseif current[c] then
      table.insert(selected, c)
    end
  end
  return selected
end

--- A fresh row for a `list` field: each sub-field starts from ITS declared
--- default (an empty-table default would otherwise throw away e.g.
--- `value = "grant"`), deep-copied so entries never share a table.
local function new_list_entry(sub_fields)
  local entry = {}
  for _, sf in ipairs(sub_fields or {}) do
    local v = sf.value
    if v == nil then
      if sf.kind == "bool" then
        v = false
      elseif sf.kind == "multi_select" then
        v = {}
      else
        v = ""
      end
    elseif type(v) == "table" then
      v = vim.deepcopy(v)
    end
    entry[sf.key] = v
  end
  entry._collapsed = false -- open on purpose: a new entry is there to be filled in
  return entry
end

--- Values for one `list` entry, read from the entry itself. Falling back to the
--- shared sub-field template only covers entries that predate a key — reading
--- the template first would make every entry report identical values.
local function entry_values(entry, sub_fields)
  local e = {}
  for _, sf in ipairs(sub_fields or {}) do
    local v = entry[sf.key]
    if v == nil then v = sf.value end
    e[sf.key] = v
  end
  return e
end

local function to_display(field)
  if field.kind == "bool" then
    return field.value and "✓" or "✗"
  end
  if field.kind == "multi_select" then
    if not field.value or #field.value == 0 then return "[]" end
    return "[" .. table.concat(field.value, " ") .. "]"
  end
  if field.kind == "list" then
    local count = field.value and #field.value or 0
    return count .. " entr" .. (count == 1 and "y" or "ies")
  end
  local v = field.value
  if v == nil or v == vim.NULL or type(v) == "userdata" then return "(not set)" end
  if v == "" then return "''" end
  return tostring(v)
end

--- One sub-field of an entry, shaped like a field so the existing editors (text,
--- select, multi_select, bool) work on it unchanged. The template is shared by
--- every entry, hence the copy; an edit lands back on the entry in `refresh`.
local function entry_subfield(entry, sf)
  local v = entry[sf.key]
  if v == nil then v = sf.value end
  return {
    key = sf.key,
    label = sf.label,
    kind = sf.kind,
    choices = sf.choices,
    value = type(v) == "table" and vim.deepcopy(v) or v,
  }
end

--- An entry's values on one line — all that a collapsed entry shows. Computed as
--- it renders, so an edit cannot leave it advertising the old values.
local function entry_summary(entry, sub_fields)
  local parts = {}
  for _, sf in ipairs(sub_fields or {}) do
    table.insert(parts, tostring(sf.label) .. "=" .. to_display(entry_subfield(entry, sf)))
  end
  return table.concat(parts, "  ")
end

local function build_rows(sections, dialect)
  local rows = {}
  local focusable = {}
  for _, section in ipairs(sections) do
    if section.dialect and section.dialect ~= dialect then goto continue end
    table.insert(rows, { type = "section_header", section = section })
    if not section.collapsed then
      for _, field in ipairs(section.fields) do
        if field.dialect and field.dialect ~= dialect then goto skip_field end
        if field.kind == "preview" then
          table.insert(rows, { type = "preview", field = field, section = section })
        elseif field.kind == "list" then
          table.insert(rows, { type = "field", field = field, section = section })
          table.insert(focusable, #rows)
          for ei, entry in ipairs(field.value or {}) do
            local collapsed = entry._collapsed == true
            table.insert(rows, { type = "list_entry", field = field, entry = entry,
              entry_idx = ei, section = section, collapsed = collapsed })
            table.insert(focusable, #rows)
            -- An expanded entry shows its sub-fields as editable rows. Without
            -- them the entry is a line nobody can fill in or delete: `list` is
            -- the one field kind whose values the generated SQL depends on.
            if not collapsed then
              for _, sf in ipairs(field.sub_fields or {}) do
                if not (sf.dialect and sf.dialect ~= dialect) then
                  table.insert(rows, { type = "field", field = entry_subfield(entry, sf),
                    entry = entry, list_field = field, section = section, nested = true })
                  table.insert(focusable, #rows)
                end
              end
            end
          end
        else
          table.insert(rows, { type = "field", field = field, section = section })
          table.insert(focusable, #rows)
        end
        ::skip_field::
      end
    end
    ::continue::
  end
  return rows, focusable
end

local FOOTER = {
  { key = "q", label = "Cancel" },
  { key = "y", label = "Copy" },
  { key = "s", label = "Execute" },
  { key = "j/k", label = "move" },
  { key = "Enter", label = "edit" },
  { key = "Space", label = "toggle" },
}

--- Shown only by a form that actually renders a `list` field (a column list, an
--- index list): `d` has no other hint on screen at all, and on a form without a
--- list the two would advertise dead keys. Both were bound but never shown,
--- which is how the `list` kind stayed undiscoverable — the entry rows it paints
--- are the ones the generated SQL is built from.
local LIST_FOOTER = {
  { key = "a", label = "add item" },
  { key = "d", label = "del item" },
}

--- The shortcut bar, wrapped to the dialog width.
--- layout.keymaps emits a single unbroken line: at the default 80-column form
--- its 77 columns leave one to spare, and any narrower float simply cuts the
--- tail off — the `Space toggle` hint disappears with no signal. Each line here
--- holds as many entries as fit, so the bar wraps instead of truncating. Entries
--- are ASCII, so one byte width serves both the fit test and the columns.
---@param width number
---@param has_list? boolean advertise the list-entry keys, for a form that has one
---@return { lines: string[], highlights: table[] }
local function footer_lines(width, has_list)
  -- The common case is FOOTER itself: the copy only happens for a form with a
  -- list field, whose bar carries two more hints and wraps if they do not fit.
  local bar = FOOTER
  if has_list then
    bar = vim.list_extend({}, FOOTER)
    for _, e in ipairs(LIST_FOOTER) do table.insert(bar, e) end
  end
  local indent = "  "
  local sep = "  "
  local lines, highlights = {}, {}
  local chunk = {}

  local function emit(entries)
    local parts, pos = {}, #indent
    for i, e in ipairs(entries) do
      if i > 1 then pos = pos + #sep end
      local segment = "[" .. e.key .. " " .. e.label .. "]"
      table.insert(parts, segment)
      local key_start = pos + 1
      table.insert(highlights, { line = #lines, col_start = key_start, col_end = key_start + #e.key, hl_group = "PosteDbFormShortcut" })
      local label_start = key_start + #e.key + 1
      table.insert(highlights, { line = #lines, col_start = label_start, col_end = label_start + #e.label, hl_group = "PosteDbFormDim" })
      pos = pos + #segment
    end
    table.insert(lines, indent .. table.concat(parts, sep))
  end

  local used = #indent
  for _, e in ipairs(bar) do
    local w = #("[" .. e.key .. " " .. e.label .. "]")
    -- The first entry of a line is never dropped, even in a form too narrow for
    -- it: an empty line would hide the shortcut entirely.
    if #chunk > 0 and used + #sep + w > width then
      emit(chunk)
      chunk = {}
      used = #indent
    end
    table.insert(chunk, e)
    used = used + (#chunk > 1 and #sep or 0) + w
  end
  if #chunk > 0 then emit(chunk) end
  return { lines = lines, highlights = highlights }
end

--- Entry sub-fields sit one level under their entry line (which is itself
--- indented four columns), so the nesting reads the same at a glance.
local NESTED_INDENT = "      "
local function row_indent(row) return row.nested and NESTED_INDENT or "  " end

--- Whether the rendered rows contain a `list` field, which is what decides if the
--- `a`/`d` hints belong in the bar. Rows, not the section spec: `build_rows`
--- drops the fields of a collapsed section, so a list nobody can reach is not
--- advertised either.
local function has_list_field(rows)
  for _, r in ipairs(rows) do
    if r.type == "field" and r.field and r.field.kind == "list" then return true end
  end
  return false
end

--- @return lines, highlights, row_line  row_line[row index] = buffer line (1-based)
local function render(rows, width, sql_lines)
  local lines = {}
  local highlights = {}
  local row_line = {}
  local li = 0

  local function append(res)
    for _, l in ipairs(res.lines) do
      table.insert(lines, l)
    end
    for _, h in ipairs(res.highlights or {}) do
      table.insert(highlights, { line = h.line + li, col_start = h.col_start, col_end = h.col_end, hl_group = h.hl_group })
    end
    li = li + #res.lines
  end

  local label_width = 0
  for _, row in ipairs(rows) do
    if row.type == "field" and row.field then
      local dw = vim.fn.strdisplaywidth(row_indent(row) .. row.field.label .. ":")
      if dw > label_width then label_width = dw end
    end
  end

  local prev_was_content = false
  for ri, row in ipairs(rows) do
    -- The row's own line, recorded as it is emitted: a preview occupies as many
    -- lines as its wrap, and a section header can be preceded by a blank
    -- separator, so the row index is not a buffer line.
    row_line[ri] = li + 1
    if row.type == "section_header" then
      if prev_was_content then
        table.insert(lines, "")
        li = li + 1
        row_line[ri] = li + 1 -- the separator belongs to the gap, not the header
      end
      append(layout.section_title({ text = row.section.title, indent = 2 }))
    elseif row.type == "field" then
      local f = row.field
      local display = to_display(f)
      local label = row_indent(row) .. f.label .. ":"
      local pad = label_width - vim.fn.strdisplaywidth(label)
      if pad < 0 then pad = 0 end
      table.insert(lines, label .. string.rep(" ", pad) .. "  " .. display)
      li = li + 1
      prev_was_content = true
    elseif row.type == "preview" then
      append(layout.paragraph({
        text = sql_lines and #sql_lines > 0 and sql_lines or { "(no SQL generated)" },
        max_width = width,
        indent = 4,
      }))
      prev_was_content = true
    elseif row.type == "list_entry" then
      -- The marker is the entry's own state: rows are rebuilt whenever the
      -- structure changes, so a flag on the row would be lost on the next one.
      local marker = row.collapsed and "▶" or "▼"
      table.insert(lines, "    " .. marker .. " entry " .. tostring(row.entry_idx) .. "  "
        .. entry_summary(row.entry, row.field.sub_fields))
      li = li + 1
      prev_was_content = true
    else
      prev_was_content = false
    end
  end

  table.insert(lines, "")
  table.insert(lines, "")
  li = li + 2
  append(footer_lines(width, has_list_field(rows)))

  return lines, highlights, row_line
end

function M.open(opts)
  opts = opts or {}
  local title = opts.title or "Form"
  local width = opts.width or 80
  local dialect = opts.dialect or "postgres"
  local sections = opts.sections or {}
  local on_change = opts.on_change
  local on_submit = opts.on_submit
  local on_cancel = opts.on_cancel
  local on_validate = opts.on_validate
  local window_management = opts.window_management or "single"

  local sql_lines = {}

  if window_management == "single" and active_form then
    close_active()
  end

  local rows, focusable = build_rows(sections, dialect)
  local focus_idx = 1
  local editing = false
  local closed = false

  local function get_current_focus_row()
    if #focusable == 0 then return nil end
    return rows[focusable[focus_idx]]
  end

  local function get_sql_lines()
    if not on_change then return {} end
    local field_values = {}
    for _, section in ipairs(sections) do
      for _, field in ipairs(section.fields) do
        field_values[field.key] = field.value
      end
    end
    local ok, result = pcall(on_change, field_values)
    if ok and result then
      return type(result) == "table" and result or { tostring(result) }
    end
    return {}
  end

  -- dialog.open gives a bordered float exactly `width - 2` of content, and this
  -- form always opens one, so the first render can wrap the preview at the real
  -- width rather than a second, guessed-at one.
  local content_width = width - 2

  --- Render the current state: SQL preview included. on_change runs here and
  --- only here — the height used to be derived from a second call to it, so a
  --- preview that varied between the two made the window the wrong size.
  local function draw()
    sql_lines = get_sql_lines()
    return render(rows, content_width, sql_lines)
  end

  local function height_for(lines)
    return math.min(#lines, opts.height or 40) + 2 -- +2: the rounded border
  end

  local dlg = dialog.open({
    title = title,
    width = width,
    height = height_for(draw()),
    border = "rounded",
    backdrop = false,
    close_on_leave = false,
  })

  --- Redraw. `row` is the one just edited: an entry's sub-fields are edited on a
  --- copy of the shared template (see `entry_subfield`), so the new value has to
  --- reach the entry before anything reads it — the SQL preview included.
  local function refresh(row)
    if row and row.entry and row.field then row.entry[row.field.key] = row.field.value end

    local lines, highlights, row_line = draw()
    vim.api.nvim_win_set_config(dlg.win, { height = height_for(lines) })

    dlg:update(lines, highlights)

    if #focusable > 0 then
      local target_line = row_line[focusable[focus_idx]]
      if target_line then
        vim.api.nvim_buf_clear_namespace(dlg.buf, ns, 0, -1)
        vim.api.nvim_buf_add_highlight(dlg.buf, ns, "Visual", target_line - 1, 0, -1)
        pcall(vim.api.nvim_win_set_cursor, dlg.win, { target_line, 3 })
      end
    end
  end

  --- Rebuild the row list after the structure changed (an entry added, collapsed
  --- or removed) and keep the focus where it was: the rows before it are the same
  --- ones, so its index still names the same field.
  local function rebuild_rows()
    rows, focusable = build_rows(sections, dialect)
    if focus_idx > #focusable then focus_idx = math.max(1, #focusable) end
    refresh()
  end

  local function safe_close()
    if closed then return end
    closed = true
    dlg:close()
    active_form = nil
    if on_cancel then on_cancel() end
  end

  local function get_field_values()
    local vals = {}
    for _, section in ipairs(sections) do
      for _, field in ipairs(section.fields) do
        if field.kind == "list" then
          local entries = {}
          for _, entry in ipairs(field.value or {}) do
            table.insert(entries, entry_values(entry, field.sub_fields))
          end
          vals[field.key] = entries
        else
          vals[field.key] = field.value
        end
      end
    end
    return vals
  end

  local function move_cursor(delta)
    if #focusable == 0 then return end
    local new_idx = focus_idx + delta
    if new_idx < 1 or new_idx > #focusable then return end
    focus_idx = new_idx
    refresh()
  end

  --- Append a blank entry to a `list` field and put the cursor on it. Its own
  --- function because two keys reach it: `<CR>` on the list's own row, and `a`
  --- from anywhere inside that list (see the `a` keymap below).
  local function add_list_entry(f)
    if not f.sub_fields then return end
    local entry = new_list_entry(f.sub_fields)
    if not f.value then f.value = {} end
    table.insert(f.value, entry)
    rows, focusable = build_rows(sections, dialect)
    -- Land on the new entry rather than at the end of the form: it opens
    -- expanded because its default values are what the user came to change.
    focus_idx = #focusable
    for fi, ri in ipairs(focusable) do
      if rows[ri].entry == entry then
        focus_idx = fi
        break
      end
    end
    refresh()
  end

  local function edit_current()
    local row = get_current_focus_row()
    if not row then return end

    if row.type == "list_entry" then
      -- The state lives on the entry: the row it is drawn from is rebuilt from
      -- the entries on every structural change.
      row.entry._collapsed = not row.collapsed
      rebuild_rows()
      return
    end

    if row.type ~= "field" then return end

    local f = row.field
    if not f then return end

    if f.kind == "bool" then
      f.value = not f.value
      refresh(row)
      return
    end

    if f.kind == "multi_select" then
      if not f.choices or #f.choices == 0 then return end
      local choices = f.choices
      local current = {}
      if f.value then
        for _, v in ipairs(f.value) do current[v] = true end
      end
      local items = {}
      for _, c in ipairs(choices) do
        local selected = current[c] and "✓" or "✗"
        table.insert(items, { value = c, label = "[" .. selected .. "] " .. c })
      end
      editing = true
      vim.ui.select(items, {
        prompt = f.label .. " (pick an item to toggle it, repeat for more):",
        format_item = function(item) return item.label end,
      }, function(choice)
        editing = false
        if closed or not choice then return end
        -- `choice` is the picked item; some vim.ui.select backends hand back the
        -- formatted string instead of the table we built.
        local picked = type(choice) == "table" and choice.value or choice
        f.value = apply_toggle(choices, current, picked)
        if dlg.win and vim.api.nvim_win_is_valid(dlg.win) then
          vim.api.nvim_set_current_win(dlg.win)
          refresh(row)
        end
      end)
      return
    end

    if f.kind == "list" then
      add_list_entry(f)
      return
    end

    local v = f.value
    local current_val = (v == nil or v == vim.NULL or type(v) == "userdata") and "" or tostring(v)

    if f.kind == "select" and f.choices then
      editing = true
      vim.ui.select(f.choices, {
        prompt = f.label .. ":",
        format_item = function(item) return item end,
      }, function(choice)
        editing = false
        if closed then return end
        if choice then
          f.value = choice
        end
        if dlg.win and vim.api.nvim_win_is_valid(dlg.win) then
          vim.api.nvim_set_current_win(dlg.win)
          refresh(row)
        end
      end)
      return
    end

    editing = true
    vim.ui.input({
      prompt = f.label .. ": ",
      default = current_val,
    }, function(input)
      editing = false
      if closed then return end
      if input ~= nil then
        f.value = input
      end
      if dlg.win and vim.api.nvim_win_is_valid(dlg.win) then
        vim.api.nvim_set_current_win(dlg.win)
        refresh(row)
      end
    end)
  end

  local function submit()
    if on_validate then
      local vals = get_field_values()
      local err, err_key = on_validate(vals)
      if err then
        notify.warn(err)
        if err_key then
          for fi, ri in ipairs(focusable) do
            local r = rows[ri]
            if r and r.type == "field" and r.field and r.field.key == err_key then
              focus_idx = fi
              refresh()
              break
            end
          end
        end
        return
      end
    end

    local vals = get_field_values()
    local sql = table.concat(sql_lines, "\n")
    safe_close()
    vim.schedule(function()
      if on_submit then on_submit(vals, sql) end
    end)
  end

  local function copy_sql()
    local text = table.concat(sql_lines, "\n")
    if text == "" then
      notify.info("No SQL to copy")
      return
    end
    vim.fn.setreg("+", text)
    notify.info("SQL copied to clipboard")
  end

  local function delete_list_entry()
    local row = get_current_focus_row()
    -- Anywhere inside the entry, so that `d` means "this entry" whether the
    -- cursor is on its line or on one of its fields.
    if not row or not row.entry then return end
    local field = row.list_field or row.field
    local idx = row.entry_idx
    if not idx then
      for i, e in ipairs(field and field.value or {}) do
        if e == row.entry then
          idx = i
          break
        end
      end
    end
    if field and field.value and idx then
      table.remove(field.value, idx)
      rebuild_rows()
    end
  end

  active_form = { dlg = dlg, opts = opts }
  refresh()

  local km_opts = { buffer = dlg.buf, noremap = true, silent = true, nowait = true }

  vim.keymap.set("n", "j", function() move_cursor(1) end, km_opts)
  vim.keymap.set("n", "k", function() move_cursor(-1) end, km_opts)
  vim.keymap.set("n", "<Tab>", function()
    if #focusable == 0 then return end
    local new_idx = focus_idx + 1
    if new_idx > #focusable then new_idx = 1 end
    focus_idx = new_idx
    refresh()
  end, km_opts)
  vim.keymap.set("n", "<S-Tab>", function()
    if #focusable == 0 then return end
    local new_idx = focus_idx - 1
    if new_idx < 1 then new_idx = #focusable end
    focus_idx = new_idx
    refresh()
  end, km_opts)
  vim.keymap.set("n", "<CR>", edit_current, km_opts)
  vim.keymap.set("n", "<Space>", edit_current, km_opts)
  vim.keymap.set("n", "s", submit, km_opts)
  vim.keymap.set("n", "y", copy_sql, km_opts)
  vim.keymap.set("n", "q", safe_close, km_opts)
  vim.keymap.set("n", "<Esc>", safe_close, km_opts)
  vim.keymap.set("n", "a", function()
    local row = get_current_focus_row()
    if not row then return end
    -- Anywhere inside a list counts, mirroring `d`: an entry row's `field` and a
    -- nested sub-field row's `list_field` are the list itself. Requiring the
    -- cursor to be on the list's own row made the second `a` a silent no-op —
    -- the first one lands the cursor on the new entry, one line below.
    local field = row.list_field or row.field
    if field and field.kind == "list" then
      add_list_entry(field)
    end
  end, km_opts)
  vim.keymap.set("n", "d", delete_list_entry, km_opts)

  -- Not `once`: a `vim.ui.select` picker takes the focus, which fires WinLeave
  -- while `editing` is deliberately holding the close back. A one-shot
  -- autocmd spent itself on that leave, so the form stayed open forever after
  -- the first pick-list edit.
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = dlg.buf,
    callback = function()
      if not closed and not editing then
        safe_close()
      end
    end,
  })
end

--- Exposed for tests.
M._test = {
  apply_toggle = apply_toggle,
  new_list_entry = new_list_entry,
  entry_values = entry_values,
  entry_subfield = entry_subfield,
  entry_summary = entry_summary,
  build_rows = build_rows,
  render = render,
  footer_lines = footer_lines,
}

return M
