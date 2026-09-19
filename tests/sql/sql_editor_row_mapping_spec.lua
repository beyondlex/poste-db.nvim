--- Regression: the dataset buffer shows one PAGE of the result set, so the row
--- under the cursor (visible 1..meta.row_count) and the row the edit
--- bookkeeping addresses (an index into layout.rows / rows_source) are only the
--- same number on page 1 of an unfiltered, unsorted view. Editor edits, DML
--- generation and edit highlights all speak SOURCE rows, and `meta.row_sources`
--- / `meta.row_numbers` are what translate between the two spaces.

local fmt = require("poste-db.format")
local dml = require("poste-db.dml")
local state = require("poste-db.state")

local function make_layout(n)
  local rows = {}
  for i = 1, n do rows[i] = { i, "v" .. i } end
  return {
    columns = {
      { name = "id", type = "int", ctype = "integer", primary_key = true },
      { name = "name", type = "text", ctype = "varchar" },
    },
    rows = rows,
    -- cell 1 is the row-number column, so widths and numeric flags are
    -- offset by one from `columns` (see plan_resultset_layout)
    col_widths = { 4, 6, 10 },
    numeric_cols = { false, true, false },
    total_rows = n,
    table_name = "users",
    schema = "",
  }
end

--- Split a rendered line into its trimmed cell texts, so the `#` column can be
--- told apart from a data column that happens to hold the same digits.
local function cells_of(line)
  local out = {}
  local sep = line:find("│")
  for cell in line:sub(sep):gmatch("([^│]+)") do
    out[#out + 1] = (cell:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  return out
end

local function identity(n)
  local v = {}
  for i = 1, n do v[i] = i end
  return v
end

describe("format row-index mapping", function()
  local layout, view

  before_each(function()
    layout = make_layout(60)
    view = identity(60)
  end)

  it("maps a paged page-2 row to its source index", function()
    local _, meta = fmt.render_page(layout, 2, 50)
    assert.equals(4, meta.data_start_line)
    assert.equals(10, meta.row_count)
    assert.equals(51, fmt.source_row_of(meta, 1))
    assert.equals(60, fmt.source_row_of(meta, 10))
    assert.equals(1, fmt.visible_row_of(meta, 51))
    assert.is_nil(fmt.visible_row_of(meta, 5), "a row on page 1 is off this page")
    assert.equals(51, fmt.row_number_of(meta, 1))
  end)

  it("maps a sorted view through view_indices", function()
    local sorted = {}
    for i = 1, 60 do sorted[i] = 61 - i end -- descending
    local _, meta = fmt.render_view(layout, sorted, 1, 50)
    assert.equals(60, fmt.source_row_of(meta, 1))
    assert.equals(11, fmt.source_row_of(meta, 50))
    assert.equals(1, fmt.visible_row_of(meta, 60))
    assert.is_nil(fmt.visible_row_of(meta, 10), "not rendered on page 1")
  end)

  it("keeps the displayed # column and the source index separate", function()
    local _, src_meta = fmt.render_view(layout, view, 1, 50, { row_number_mode = "source" })
    assert.equals(1, fmt.source_row_of(src_meta, 1))
    assert.equals(1, fmt.row_number_of(src_meta, 1))

    local _, view_meta = fmt.render_view(layout, { 60, 59 }, 1, 50,
      { row_number_mode = "view" })
    assert.equals(60, fmt.source_row_of(view_meta, 1), "data still comes from row 60")
    assert.equals(1, fmt.row_number_of(view_meta, 1), "but the # column shows its screen position")
  end)

  it("maps identity when the meta carries no bookkeeping", function()
    local meta = { type = "resultset", row_count = 5 }
    assert.equals(3, fmt.source_row_of(meta, 3))
    assert.equals(3, fmt.visible_row_of(meta, 3))
    assert.equals(3, fmt.row_number_of(meta, 3))
  end)
end)

describe("editor edits address source rows", function()
  local dataset, nav
  local buf, tab

  local function install_tab(page, view_indices, row_number_mode)
    local layout = make_layout(60)
    local lines, meta = fmt.render_view(layout, view_indices, page, 50,
      { row_number_mode = row_number_mode })
    local padded = {}
    for i, line in ipairs(lines) do padded[i] = "  " .. line end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
    tab = {
      data = { type = "resultset", results = { {
        columns = layout.columns, rows = layout.rows, row_count = #layout.rows,
      } } },
      layout = layout,
      rows_source = layout.rows,
      view_indices = view_indices,
      page = page,
      page_size = 50,
      num_pages = 2,
      padded = padded,
      meta = meta,
      original_sql = "select * from users",
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
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
    dataset.dataset_buffer = nil
    dataset.dataset_window = nil
    dataset.tabs = {}
    dataset.active_tab_idx = 1
    state.cell.row, state.cell.col = 1, 1
    vim.ui.input = nil
  end)

  it("records a cell edit against the source row and re-renders its line", function()
    install_tab(2, identity(60))
    local seen
    vim.ui.input = function(_, cb) seen = cb; end
    state.cell.row, state.cell.col = 1, 2 -- visible row 1 of page 2 = source 51
    nav.edit_cell()
    -- the text editor prompts asynchronously; drive the callback
    seen("edited")

    local es = tab.edit_state
    assert.is_true(es.modified_cells["51:2"] ~= nil,
      "edit_state is keyed by source row, which is what dml.generate_dml reads")
    assert.equals("edited", tab.layout.rows[51][2])
    assert.equals("edited", tab.rows_source[51][2])
    assert.equals("v50", tab.layout.rows[50][2], "the row that visible index 1 names on page 1")

    -- the buffer line for the edited row is page 2 / visible 1
    local line = vim.api.nvim_buf_get_lines(buf, tab.meta.data_start_line - 1,
      tab.meta.data_start_line, false)[1]
    local cells = cells_of(line)
    assert.equals("edited", cells[3])
    assert.equals("51", cells[1], "the # column keeps the row number it displayed")

    local stmts = dml.generate_dml(es, tab, "postgres")
    assert.equals(1, #stmts)
    assert.equals('UPDATE "users" SET "name" = \'edited\' WHERE "id" = 51;', stmts[1].sql)
  end)

  it("deletes the row on screen, not the row its page position names", function()
    install_tab(2, identity(60))
    state.cell.row, state.cell.col = 1, 1
    nav.delete_row()

    local es = tab.edit_state
    assert.is_true(es.deleted_rows[51])
    assert.is_nil(es.deleted_rows[1])

    local stmts = dml.generate_dml(es, tab, "postgres")
    assert.equals(1, #stmts)
    assert.equals('DELETE FROM "users" WHERE "id" = 51;', stmts[1].sql)
  end)

  it("deletes the right row through a sorted view", function()
    local sorted = {}
    for i = 1, 60 do sorted[i] = 61 - i end
    install_tab(2, sorted)
    state.cell.row, state.cell.col = 1, 1
    nav.delete_row()

    -- page 2 of a descending view holds view positions 51..60, i.e. source
    -- rows 10..1, so the top row on screen is source row 10
    assert.is_true(tab.edit_state.deleted_rows[10])
    local stmts = dml.generate_dml(tab.edit_state, tab, "postgres")
    assert.equals('DELETE FROM "users" WHERE "id" = 10;', stmts[1].sql)
  end)

  it("highlights edited lines by source row", function()
    local ns_edit = vim.api.nvim_create_namespace("poste_db_dataset_edit")
    install_tab(2, identity(60))
    local es = require("poste-db.editor.cell").create_edit_state()
    es.dirty = true
    es.deleted_rows[51] = true
    es.modified_cells["52:2"] = { col = 2, old_val = "v52", new_val = "x" }
    es.deleted_rows[7] = true -- source row off this page: no line to mark
    tab.edit_state = es

    require("poste-db.highlights").apply_edit_highlights(buf, tab)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns_edit, 0, -1, {})
    local lines = {}
    for _, mark in ipairs(marks) do lines[mark[2] + 1] = true end
    assert.is_true(lines[tab.meta.data_start_line], "deleted source row 51 is page 2 line 1")
    assert.is_true(lines[tab.meta.data_start_line + 1], "modified source row 52")
    assert.equals(2, #marks, "the off-page source row 7 marks nothing")
  end)

  it("queues an inserted row without touching the sql namespace", function()
    -- the cursor-move block read `state.sql.cell`, a nesting left over from the
    -- old shared state shim; state.cell is the real one, so this used to error
    install_tab(2, identity(60))
    local ok, err = pcall(nav.insert_row)
    assert.is_true(ok, err)
    assert.equals(61, #tab.layout.rows)
    local added = tab.edit_state.added_rows[1]
    assert.equals(61, added.row_idx, "tracked by source index")
    assert.equals(11, state.cell.row, "the new row is visible 11 of page 2")
  end)
end)
