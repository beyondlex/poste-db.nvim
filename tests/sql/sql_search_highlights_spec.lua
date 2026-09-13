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

  it("the current match's substring uses IncSearch", function()
    tab.search_idx = 1 -- == global_match_idx
    search.apply_search_highlights()
    local sub = marks()[2]
    assert.equals("PosteDbDatasetSearchCurrent", sub[4].hl_group)
    assert.equals(15, sub[3])
  end)
end)
