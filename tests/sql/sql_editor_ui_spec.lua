--- Regression: the three dedicated cell editors in `editor/nav.lua` are driven
--- through `vim.ui.select`, and two of them then ask for a typed value —
--- datetime's "Custom…" entry and, for every other column, `cell_editors.text`.
--- The text editor parses and validates what was typed before it reaches
--- `apply_cell_edit`; the datetime one called `apply_cell_edit` straight with
--- the prompt's own text, so its input skipped both. `enum`'s "<default>"
--- choice passed Lua `nil`, which means "no value" to the row table and NULL
--- to the generated UPDATE, while the label promises the column's default.
---
--- These specs stub the two `vim.ui` entry points and go through
--- `nav.edit_cell()`, so the column metadata and the guard order are exercised
--- too — a direct call to the editor function would not notice a handler that
--- is never reached.

local fmt = require("poste-db.format")
local dml = require("poste-db.dml")
local state = require("poste-db.state")

local STAMP = "2026-01-02 03:04:05"

local function make_layout()
  return {
    columns = {
      { name = "id", type = "int", ctype = "integer", primary_key = true },
      { name = "status", type = "enum", ctype = "enum('draft','done')",
        enum_values = { "draft", "done" }, default = "draft" },
      { name = "created_at", type = "timestamp", ctype = "timestamp" },
      { name = "flag", type = "bool", ctype = "boolean" },
    },
    rows = { { 1, "draft", STAMP, false } },
    col_widths = { 4, 4, 12, 21, 7 },
    numeric_cols = { false, true, false, false, false },
    total_rows = 1,
    table_name = "orders",
    schema = "",
  }
end

--- Answer the select prompt with the entry whose text matches `pick`, then the
--- input prompt (if the handler opens one) with `typed`. Records what the input
--- was pre-filled with, which is what the "Custom…" prompt is judged on.
local function drive_ui(pick, typed)
  local prompt_defaults = {}
  vim.ui.select = function(items, _, cb)
    for _, item in ipairs(items) do
      local text = (type(item) == "table") and item.display or item
      if text == pick then
        cb(item)
        return
      end
    end
    error("no " .. pick .. " entry in the picker")
  end
  vim.ui.input = function(opts, cb)
    prompt_defaults[#prompt_defaults + 1] = opts.default
    cb(typed)
  end
  return prompt_defaults
end

describe("cell editors that prompt for typed text", function()
  local dataset, nav
  local buf, tab

  local function install_tab()
    local layout = make_layout()
    local lines, meta = fmt.render_page(layout, 1, 50)
    local padded = {}
    for i, line in ipairs(lines) do padded[i] = "  " .. line end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
    tab = {
      data = { type = "resultset", results = { {
        columns = layout.columns, rows = layout.rows, row_count = #layout.rows,
      } } },
      layout = layout,
      rows_source = layout.rows,
      page = 1,
      page_size = 50,
      num_pages = 1,
      padded = padded,
      meta = meta,
      original_sql = "select * from orders",
    }
    dataset.tabs = { [1] = tab }
    dataset.active_tab_idx = 1
    return tab
  end

  before_each(function()
    package.loaded["poste-db.editor.column"] = {
      ensure_primary_key = function() return true end,
    }
    dataset = require("poste-db.dataset")
    nav = require("poste-db.editor.nav")
    buf = vim.api.nvim_create_buf(false, true)
    dataset.dataset_buffer = buf
    dataset.dataset_window = nil
    install_tab()
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
    dataset.dataset_buffer = nil
    dataset.dataset_window = nil
    dataset.tabs = {}
    dataset.active_tab_idx = 1
    state.cell.row, state.cell.col = 1, 1
    vim.ui.input = nil
    vim.ui.select = nil
  end)

  local function edit(col, pick, typed)
    state.cell.row, state.cell.col = 1, col
    local defaults = drive_ui(pick, typed)
    nav.edit_cell()
    return defaults
  end

  local function sql_for_row()
    local stmts = dml.generate_dml(tab.edit_state, tab, "mysql")
    assert.equals(1, #stmts)
    return stmts[1].sql
  end

  it("turns a cleared datetime prompt into NULL, as the text editor does", function()
    edit(3, "Custom…", "")
    -- the old handler tested only for a cancelled prompt, and clearing the
    -- command line answers with "" rather than nil, so the empty text landed in
    -- the cell: `SET created_at = ''`, which postgres rejects and MySQL answers
    -- by storing a zero date when it is not running strictly
    assert.equals(vim.NIL, tab.layout.rows[1][3])
    assert.equals("UPDATE `orders` SET `created_at` = NULL WHERE `id` = 1;", sql_for_row())
  end)

  it("reads a typed NULL in the datetime prompt as NULL", function()
    edit(3, "Custom…", "(NULL)")
    assert.equals(vim.NIL, tab.layout.rows[1][3])
    assert.equals("UPDATE `orders` SET `created_at` = NULL WHERE `id` = 1;", sql_for_row())
  end)

  it("refuses datetime text the column cannot hold instead of committing it", function()
    edit(3, "Custom…", "soon")
    assert.equals(STAMP, tab.layout.rows[1][3], "the cell keeps the value it had")
    assert.is_nil(tab.edit_state.modified_cells["1:3"])
    assert.equals("Invalid date format", tab.edit_state.cell_errors["1:3"])
  end)

  it("offers the value already in the cell as the datetime prompt's text", function()
    local defaults = edit(3, "Custom…", STAMP)
    assert.equals(1, #defaults)
    -- the prompt used to pre-fill the current time, which is a new value rather
    -- than the one being corrected, and typing over it lost the rest of it
    assert.equals(STAMP, defaults[1])
  end)

  it("still accepts the datetime picker's own candidates", function()
    edit(3, "CURRENT_TIMESTAMP", nil)
    assert.equals("__expr:CURRENT_TIMESTAMP", tab.layout.rows[1][3])
    assert.equals("UPDATE `orders` SET `created_at` = CURRENT_TIMESTAMP WHERE `id` = 1;",
      sql_for_row())
  end)

  it("means the same thing when the candidate's word is typed instead of picked", function()
    -- the word is the entry directly above "Custom…" in the list, and the prompt
    -- refused it: `validate_value` saw a string with no leading digit and answered
    -- "Invalid date format", so the one spelling that means *the server's now*
    -- worked only one of the two ways it was offered
    edit(3, "Custom…", "CURRENT_TIMESTAMP")
    assert.equals("__expr:CURRENT_TIMESTAMP", tab.layout.rows[1][3])
    assert.equals("UPDATE `orders` SET `created_at` = CURRENT_TIMESTAMP WHERE `id` = 1;",
      sql_for_row())
  end)

  it("reads a typed expression regardless of case, like the server does", function()
    edit(3, "Custom…", "current_timestamp")
    assert.equals("__expr:CURRENT_TIMESTAMP", tab.layout.rows[1][3])
  end)

  it("restores the column default instead of writing NULL", function()
    edit(2, "<default>", nil)
    -- `nil` reads as "no value" further down: the row table lost the slot and
    -- the statement said `SET status = NULL`, a write the label never promised
    assert.equals("__expr:DEFAULT", tab.layout.rows[1][2])
    assert.equals("UPDATE `orders` SET `status` = DEFAULT WHERE `id` = 1;", sql_for_row())
  end)

  it("picks an enum value from the list", function()
    edit(2, "done", nil)
    assert.equals("done", tab.layout.rows[1][2])
    assert.equals("UPDATE `orders` SET `status` = 'done' WHERE `id` = 1;", sql_for_row())
  end)

  it("sets a boolean cell from its three choices", function()
    edit(4, "(NULL)", nil)
    assert.equals(vim.NIL, tab.layout.rows[1][4])
    assert.equals("UPDATE `orders` SET `flag` = NULL WHERE `id` = 1;", sql_for_row())
  end)
end)

describe("a cleared prompt on an already-NULL cell", function()
  local dataset, nav
  local buf, tab

  before_each(function()
    package.loaded["poste-db.editor.column"] = {
      ensure_primary_key = function() return true end,
    }
    dataset = require("poste-db.dataset")
    nav = require("poste-db.editor.nav")
    buf = vim.api.nvim_create_buf(false, true)
    dataset.dataset_buffer = buf
    dataset.dataset_window = nil

    local layout = make_layout()
    layout.rows[1][3] = vim.NIL
    local lines, meta = fmt.render_page(layout, 1, 50)
    local padded = {}
    for i, line in ipairs(lines) do padded[i] = "  " .. line end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
    tab = {
      data = { type = "resultset", results = { {
        columns = layout.columns, rows = layout.rows, row_count = #layout.rows,
      } } },
      layout = layout,
      rows_source = layout.rows,
      page = 1,
      page_size = 50,
      num_pages = 1,
      padded = padded,
      meta = meta,
      original_sql = "select * from orders",
    }
    dataset.tabs = { [1] = tab }
    dataset.active_tab_idx = 1
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
    dataset.dataset_buffer = nil
    dataset.dataset_window = nil
    dataset.tabs = {}
    dataset.active_tab_idx = 1
    state.cell.row, state.cell.col = 1, 1
    vim.ui.input = nil
    vim.ui.select = nil
  end)

  it("changes nothing rather than writing an empty string", function()
    -- `parse_value` answers nil for that, which means "the edit was not taken",
    -- and the datetime handler now goes through it too
    state.cell.row, state.cell.col = 1, 3
    drive_ui("Custom…", "")
    nav.edit_cell()
    assert.equals(vim.NIL, tab.layout.rows[1][3])
    assert.is_nil(tab.edit_state and next(tab.edit_state.modified_cells))
  end)
end)
