--- Integration spec for apply_search_highlights' extmark byte columns: the
--- substring mark must start ON the match's first character. Extmark cols are
--- 0-based; this spec pins the convention with a real buffer (the off-by-one
--- that dropped the first matched character is invisible to a pure helper).
local saved_dataset = package.loaded["poste-db.dataset"]
local saved_search = package.loaded["poste-db.buffer.search"]

describe("apply_search_highlights extmark columns", function()
  local ns = vim.api.nvim_create_namespace("poste_db_search_spec")
  local search
  local buf
  local tab

  local line = "│ alice │ bob │" -- 2 data columns: "alice", "bob"

  before_each(function()
    package.loaded["poste-db.dataset"] = {
      dataset_buffer = nil, -- set after the buffer exists
      search_ns = ns,
      T = function() return tab end,
    }
    package.loaded["poste-db.buffer.search"] = nil
    search = require("poste-db.buffer.search")

    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    package.loaded["poste-db.dataset"].dataset_buffer = buf

    tab = {
      search_text = "ob",
      search_matches = { { row = 1, col = 1, global_match_idx = 1 } },
      search_matches_by_page = { [1] = { { row = 1, col = 1, global_match_idx = 1 } } },
      search_total_matches = 1,
      search_idx = 0, -- != global_match_idx: a non-current match
      meta = { data_start_line = 1 },
      page = 1,
      page_size = 10,
    }
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
    package.loaded["poste-db.dataset"] = saved_dataset
    package.loaded["poste-db.buffer.search"] = saved_search
  end)

  local function marks()
    return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  end

  it("covers the whole cell plus the matched substring", function()
    search.apply_search_highlights()
    local m = marks()
    assert.equals(2, #m, "whole-cell mark + substring mark")
    -- substring: "ob" in "bob" of data col 1. cell_text starts at
    -- ext_start = 13 (`<sep-tail><space>bob<space>`), so "ob" is at 0-based
    -- bytes 15..16, end exclusive 17.
    local sub = m[2]
    assert.equals(15, sub[3]) -- extmark items are {id, row, col, details}
    assert.equals(17, sub[4].end_col)
    assert.equals("PosteDbDatasetSearchMatchText", sub[4].hl_group)
  end)

  it("the substring mark starts on the match's first character", function()
    -- the regression: a +1 column error made the highlight begin one byte
    -- into the match, dropping its first character
    search.apply_search_highlights()
    local sub = marks()[2]
    local first_byte = line:sub(sub[3] + 1, sub[3] + 1)
    assert.equals("o", first_byte)
    local last_byte = line:sub(sub[4].end_col, sub[4].end_col)
    assert.equals("b", last_byte)
  end)

  it("a match at the start of the cell content starts on its first char", function()
    tab.search_text = "bob"
    search.apply_search_highlights()
    local sub = marks()[2]
    assert.equals("b", line:sub(sub[3] + 1, sub[3] + 1))
    assert.equals("b", line:sub(sub[4].end_col, sub[4].end_col))
  end)

  it("the current match's substring uses CurrentText", function()
    tab.search_idx = 1 -- == global_match_idx
    search.apply_search_highlights()
    local sub = marks()[2]
    assert.equals("PosteDbDatasetSearchCurrentText", sub[4].hl_group)
    assert.equals(15, sub[3])
  end)

  it("a query matching the cell's padding stays inside the cell", function()
    -- The text spanned for the substring mark is exactly the region the
    -- whole-cell mark covers, so a bare space can only land on the cell's own
    -- padding — never on the │ byte in front of it. Asserted by content, not
    -- just by column, because the span is 1-based inside a slice whose start
    -- is 0-based and the two can cancel out an error in either one.
    tab.search_text = " "
    search.apply_search_highlights()
    local m = marks()
    local cell, sub = m[1], m[2]
    assert.equals(13, cell[3], "whole-cell mark starts at the cell")
    assert.is_true(sub[3] >= cell[3], "substring mark never starts left of its cell")
    assert.equals(" ", line:sub(sub[3] + 1, sub[3] + 1))
    assert.equals(14, sub[4].end_col)
  end)
end)

describe("apply_search_highlights page slicing", function()
  -- Which rows get highlighted is a separate question from where the marks
  -- land: `search_matches_by_page` is built so a jump knows which page to open,
  -- and paging is a toggle the user can flip while a search is live.
  local ns = vim.api.nvim_create_namespace("poste_db_search_page_spec")
  local search, buf, tab

  before_each(function()
    package.loaded["poste-db.dataset"] = {
      dataset_buffer = nil,
      search_ns = ns,
      T = function() return tab end,
    }
    package.loaded["poste-db.buffer.search"] = nil
    search = require("poste-db.buffer.search")
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "│ alice │ a │",
      "│ bob   │ b │",
      "│ carol │ c │",
    })
    package.loaded["poste-db.dataset"].dataset_buffer = buf
    tab = {
      search_text = "a",
      search_matches = {
        { row = 1, col = 1, global_match_idx = 1 },
        { row = 3, col = 1, global_match_idx = 2 },
      },
      search_matches_by_page = {
        [1] = { { row = 1, col = 1, global_match_idx = 1 } },
        [2] = { { row = 3, col = 1, global_match_idx = 2 } },
      },
      search_total_matches = 2,
      search_idx = 1,
      meta = { data_start_line = 1 },
      page = 1,
      page_size = 2,
      layout = {}, -- the third half of the "is this tab paged" conjunction
      num_pages = 2,
    }
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
    package.loaded["poste-db.dataset"] = saved_dataset
    package.loaded["poste-db.buffer.search"] = saved_search
  end)

  --- buffer rows (0-based) carrying a whole-cell search mark
  local function marked_rows()
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      if m[4].hl_group:find("Text", 1, true) == nil then rows[#rows + 1] = m[2] end
    end
    return rows
  end

  it("highlights every match when the tab is not paged", function()
    -- `num_pages` keeps its pre-toggle value once paging is switched off, and
    -- all three rows are on screen: slicing by bucket would highlight row 1
    -- while n/N walked both matches
    tab.pagination_enabled = false
    search.apply_search_highlights()
    assert.same({ 0, 2 }, marked_rows())
  end)

  it("and only the open page's matches when it is", function()
    tab.pagination_enabled = true
    search.apply_search_highlights()
    assert.same({ 0 }, marked_rows(), "row 3 is on page 2")

    tab.page = 2 -- buffer now shows view rows 3..4, so match row 3 is screen row 1
    search.apply_search_highlights()
    assert.same({ 0 }, marked_rows(), "the same screen row, re-based")
  end)
end)
