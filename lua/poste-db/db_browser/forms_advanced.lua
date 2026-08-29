local state = require("poste.state")
local dialog = require("poste.dialog")
local layout = require("poste.layout")
local notify = require("poste-db.db_browser.notify")

local M = {}

local ns = vim.api.nvim_create_namespace("poste_db_adv_form")

local function setup_hl()
  vim.api.nvim_set_hl(0, "PosteDbFormShortcut", { fg = 0x98c379, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbFormDim",      { fg = 0x5c6370 })
  state.apply_highlight_overrides({
    "PosteDbFormShortcut", "PosteDbFormDim",
  })
end
setup_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = setup_hl })
local active_form = nil

local function close_active()
  if not active_form then return end
  if active_form.dlg then
    active_form.dlg:close()
  end
  active_form = nil
end

local word_wrap = layout.word_wrap

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
            table.insert(rows, { type = "list_entry", field = field, entry = entry, entry_idx = ei, section = section, collapsed = entry._collapsed or false })
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

local function render(rows, title, width, sql_lines)
  local lines = {}
  local highlights = {}
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
      local dw = vim.fn.strdisplaywidth("  " .. row.field.label .. ":")
      if dw > label_width then label_width = dw end
    end
  end

  local prev_was_content = false
  for _, row in ipairs(rows) do
    if row.type == "section_header" then
      if prev_was_content then
        table.insert(lines, "")
        li = li + 1
      end
      append(layout.section_title({ text = row.section.title, indent = 2 }))
    elseif row.type == "field" then
      local f = row.field
      local display = to_display(f)
      local label = "  " .. f.label .. ":"
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
      local marker = row.collapsed and "▶" or "▼"
      local summary = "entry " .. row.entry_idx
      if row.entry and row.entry._summary then
        summary = row.entry._summary
      end
      table.insert(lines, "    " .. marker .. " " .. summary)
      li = li + 1
      prev_was_content = true
    else
      prev_was_content = false
    end
  end

  table.insert(lines, "")
  table.insert(lines, "")
  li = li + 2
  append(layout.keymaps({
    mapping = {
      { key = "q", label = "Cancel" },
      { key = "y", label = "Copy" },
      { key = "s", label = "Execute" },
      { key = "j/k", label = "move" },
      { key = "Enter", label = "edit" },
      { key = "Space", label = "toggle" },
    },
    key_hl = "PosteDbFormShortcut",
    value_hl = "PosteDbFormDim",
    indent = 2,
  }))

  return lines, highlights
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
  local height = 20

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

  local function calc_height()
    local h = 2
    for _, row in ipairs(rows) do
      if row.type == "preview" then
        local sl = get_sql_lines()
        local indent = "    "
        local max_line = width - #indent
        local line_count = 0
        if sl and #sl > 0 then
          for _, sl_line in ipairs(sl) do
            line_count = line_count + #word_wrap(sl_line, max_line)
          end
        else
          line_count = 1
        end
        h = h + line_count
      else
        h = h + 1
      end
    end
    return math.min(h, opts.height or 40) + 2
  end

  local dlg = dialog.open({
    title = title,
    width = width,
    height = calc_height(),
    border = "rounded",
    backdrop = false,
    close_on_leave = false,
  })

  local function refresh()
    sql_lines = get_sql_lines()
    height = calc_height()
    vim.api.nvim_win_set_config(dlg.win, { height = height })

    local lines, highlights = render(rows, title, dlg.content_width, sql_lines)
    dlg:update(lines, highlights)

    if #focusable > 0 then
      local ri = focusable[focus_idx]
      local target_line = ri
      for i = 1, ri - 1 do
        local r = rows[i]
        if r.type == "preview" then
          local indent = "    "
          local max_line = dlg.content_width - #indent
          if sql_lines and #sql_lines > 0 then
            for _, sl in ipairs(sql_lines) do
              target_line = target_line + #word_wrap(sl, max_line) - 1
            end
          end
        end
      end
      vim.api.nvim_buf_clear_namespace(dlg.buf, ns, 0, -1)
      vim.api.nvim_buf_add_highlight(dlg.buf, ns, "Visual", target_line - 1, 0, -1)
      pcall(vim.api.nvim_win_set_cursor, dlg.win, { target_line, 3 })
    end
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
            local e = {}
            for _, sf in ipairs(field.sub_fields or {}) do
              e[sf.key] = sf.value
            end
            table.insert(entries, e)
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

  local function edit_current()
    local row = get_current_focus_row()
    if not row then return end

    if row.type == "list_entry" then
      row.collapsed = not row.collapsed
      refresh()
      return
    end

    if row.type ~= "field" then return end

    local f = row.field
    if not f then return end

    if f.kind == "bool" then
      f.value = not f.value
      refresh()
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
        prompt = f.label .. " (Space to toggle, Enter to confirm):",
        format_item = function(item) return item.label end,
      }, function(choice)
        editing = false
        if closed or not choice then return end
        local selected = {}
        for _, c in ipairs(choices) do
          if current[c] then
            table.insert(selected, c)
          end
        end
        f.value = selected
        if dlg.win and vim.api.nvim_win_is_valid(dlg.win) then
          vim.api.nvim_set_current_win(dlg.win)
          refresh()
        end
      end)
      return
    end

    if f.kind == "list" then
      if not f.sub_fields then return end
      local entry = {}
      for _, sf in ipairs(f.sub_fields) do
        entry[sf.key] = (sf.kind == "bool" and false) or (sf.kind == "multi_select" and {}) or ""
      end
      entry._collapsed = true
      entry._summary = "new entry"
      if not f.value then f.value = {} end
      table.insert(f.value, entry)
      rows, focusable = build_rows(sections, dialect)
      focus_idx = #focusable
      refresh()
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
          refresh()
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
        refresh()
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
    if not row or row.type ~= "list_entry" then return end
    local field = row.field
    local idx = row.entry_idx
    if field and field.value then
      table.remove(field.value, idx)
      rows, focusable = build_rows(sections, dialect)
      if focus_idx > #focusable then focus_idx = #focusable end
      refresh()
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
    if row and row.type == "field" and row.field and row.field.kind == "list" then
      edit_current()
    end
  end, km_opts)
  vim.keymap.set("n", "d", delete_list_entry, km_opts)

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = dlg.buf,
    once = true,
    callback = function()
      if not closed and not editing then
        safe_close()
      end
    end,
  })
end

return M
