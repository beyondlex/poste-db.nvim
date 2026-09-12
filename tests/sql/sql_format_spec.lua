--- Tests for format.lua helpers not covered elsewhere: timezone-aware
--- datetime rendering and the translated-SQL footnote.
---
--- Regression for the footnote: the raw original_sql was concatenated into a
--- buffer line, so a multi-line statement produced lines with embedded
--- newlines — nvim_buf_set_lines rejects those and the whole response render
--- aborted with "SQL execution error".

local sql_format = require("poste-db.format")
local width = require("poste-db.width")

--- Local UTC offset (seconds east of UTC), derived independently of the
--- module under test by comparing local and UTC renderings of one instant.
local function utc_offset()
  local now = os.time()
  return os.time(os.date("*t", now)) - os.time(os.date("!*t", now))
end

describe("format format_datetime_local", function()
  local dt = sql_format._test.format_datetime_local

  it("leaves strings without a timezone indicator unchanged", function()
    assert.equals("2026-01-01 12:00:00", dt("2026-01-01 12:00:00"))
    assert.equals("2026-01-01T12:00:00.123456", dt("2026-01-01T12:00:00.123456"))
    assert.equals("", dt(""))
    assert.equals("not a date", dt("not a date"))
  end)

  it("converts a Z (UTC) timestamp to the local wall clock", function()
    -- Regression: the old implementation dropped the offset entirely, so a
    -- `Z` timestamp rendered its UTC fields verbatim regardless of timezone.
    local fields = { year = 2026, month = 1, day = 1, hour = 12, min = 0, sec = 0 }
    local epoch_utc = os.time(fields) + utc_offset()
    local expected = os.date("%Y-%m-%d %H:%M:%S", epoch_utc)
    assert.equals(expected, dt("2026-01-01T12:00:00Z"))
  end)

  it("honors a +hh:mm offset", function()
    local fields = { year = 2026, month = 6, day = 15, hour = 12, min = 0, sec = 0 }
    -- `+05:30` means the fields are 5h30m ahead of UTC.
    local epoch_utc = os.time(fields) + utc_offset() - (5 * 3600 + 30 * 60)
    local expected = os.date("%Y-%m-%d %H:%M:%S", epoch_utc)
    assert.equals(expected, dt("2026-06-15T12:00:00+05:30"))
  end)

  it("honors a -hh:mm offset", function()
    local fields = { year = 2026, month = 6, day = 15, hour = 8, min = 30, sec = 0 }
    local epoch_utc = os.time(fields) + utc_offset() + (4 * 3600 + 30 * 60)
    local expected = os.date("%Y-%m-%d %H:%M:%S", epoch_utc)
    assert.equals(expected, dt("2026-06-15 08:30:00-04:30"))
  end)
end)

describe("format translated-SQL footnote", function()
  it("flattens multi-line original_sql so no rendered line contains a newline", function()
    local data = {
      type = "resultset",
      connection = "mysql://dev",
      database = "db",
      dialect = "mysql",
      total_rows = 1,
      results = { {
        columns = { { name = "id", type = "INT" } },
        rows = { { 1 } },
        row_count = 1,
        original_sql = "SELECT id\nFROM t\nWHERE id > 0",
        translated_sql = "SELECT id FROM t WHERE id > 0",
      } },
    }
    local lines, meta = sql_format.format_dataset({ body = vim.json.encode(data) })
    assert.equals("resultset", meta.type)
    assert.is_true(#lines > 1)
    for i, l in ipairs(lines) do
      assert.truthy(type(l) == "string" and not l:find("\n", 1, true),
        "line " .. i .. " contains a newline")
    end
    assert.truthy(vim.tbl_contains(lines, function(l)
      return l:find("SELECT id FROM t WHERE id > 0", 1, true) ~= nil
    end, { predicate = true }))
  end)
end)

describe("format wrap_text (error box)", function()
  it("wraps ASCII at the width boundary", function()
    local wrapped = sql_format._test.wrap_text(string.rep("a", 200), 78)
    assert.equals(3, #wrapped)
    assert.equals(78, #wrapped[1])
    assert.equals(78, #wrapped[2])
    assert.equals(string.rep("a", 44), wrapped[3])
  end)

  it("never splits a multibyte character (valid UTF-8 only)", function()
    -- CJK chars are 3 bytes / 2 display columns: a byte cut at width 78
    -- landed mid-character and put invalid UTF-8 into the buffer.
    local cjk = string.rep("数", 60) -- 120 display columns, 180 bytes
    local wrapped = sql_format._test.wrap_text(cjk, 78)
    assert.is_true(#wrapped >= 2)
    for _, l in ipairs(wrapped) do
      assert.equals(cjk:sub(1, 1), l:sub(1, #cjk:sub(1, 1)), "line kept its character")
      assert.equals(0, vim.fn.strchars(l) - vim.fn.strcharlen(l), "line is char-aligned")
    end
    local recombined = table.concat(wrapped)
    assert.equals(cjk, recombined)
  end)

  it("wraps a mixed ASCII/CJK error message without corrupting it", function()
    local err = "relation 「ユーザーマスタ」 does not exist 数" .. string.rep("x", 100)
    local wrapped = sql_format._test.wrap_text(err, 78)
    assert.equals(err, table.concat(wrapped))
    for _, l in ipairs(wrapped) do
      assert.is_true(vim.fn.strdisplaywidth(l) <= 78)
    end
  end)
end)

describe("format dataset default page size", function()
  local dataset = require("poste-db.dataset")

  local function body(rows)
    return vim.json.encode({
      type = "resultset",
      total_rows = rows,
      results = { {
        columns = { { name = "id", type = "INT" } },
        rows = vim.tbl_map(function(i) return { i } end, vim.fn.range(rows)),
        row_count = rows,
      } },
      connection = "",
      database = "",
      dialect = "postgres",
    })
  end

  before_each(function()
    dataset.set_page_size(50)
  end)

  it("renders the configured default page size for the first page", function()
    dataset.set_page_size(4)
    local _, meta = sql_format.format_dataset({ body = body(10) })
    assert.equals("resultset", meta.type)
    assert.equals(4, meta.row_count)
  end)

  it("falls back to 50 when unconfigured", function()
    local _, meta = sql_format.format_dataset({ body = body(70) })
    assert.equals(50, meta.row_count)
  end)
end)

describe("format bordered table width stability", function()
  local config = require("poste-db.config")
  before_each(function()
    -- The strictest invariant (rows exactly as wide as the border under the
    -- terminal oracle) is only guaranteed in "terminal" mode; pin it so the
    -- test does not float with the configured default.
    config.config.width_mode = "terminal"
  end)
  after_each(function()
    config.config.width_mode = nil
  end)

  -- Regression: rows containing Devanagari/Persian and CJK cells rendered
  -- past the border — strdisplaywidth() folds Indic Mc spacing marks (ि ा ी)
  -- to zero width while the terminal paints each into a real cell, so those
  -- rows were padded short and the trailing │ was overwritten. Line widths
  -- here are measured with width.display_width(), the terminal-consistent
  -- oracle (see lua/poste-db/width.lua and LEARNINGS #16).
  local function civilisations()
    return {
      type = "resultset",
      total_rows = 5,
      results = { {
        columns = {
          { name = "id" }, { name = "id2" }, { name = "id3" }, { name = "name" },
          { name = "native_name" }, { name = "chinese_name" }, { name = "start" },
          { name = "end" }, { name = "writing_system" }, { name = "capital" },
        },
        rows = {
          { 4, 4, 4, "Indus Valley civilization", "सिंधु घाटी", "印度河谷文明", -2600, -1900, "ideographic", "摩亨佐-达罗" },
          { 5, 5, 5, "Persian civilization", "تمدن ایران", "波斯文明", -550, 1979, "alphabet", "波斯波利斯" },
        },
      } },
    }
  end

  it("keeps every rendered line exactly as wide as the table border", function()
    local layout = sql_format.plan_resultset_layout(civilisations())
    local lines = sql_format.render_page(layout, 1, 50)
    -- Terminal-visible width (width.display_width), not strdisplaywidth:
    -- vim folds Indic spacing marks to 0 while the terminal paints them, so
    -- a row can be strdisplaywidth-equal to the border yet 3 cells over.
    local border_w = width.display_width(lines[1])
    for i, l in ipairs(lines) do
      assert.equals(border_w, width.display_width(l),
        "line " .. i .. " must be exactly the border width")
    end
  end)

  it("closes every data row with a right border beneath the border line", function()
    local layout = sql_format.plan_resultset_layout(civilisations())
    local lines, meta = sql_format.render_page(layout, 1, 50)
    local border_w = width.display_width(lines[1])
    assert.matches("┐$", lines[1])
    assert.matches("┘$", lines[#lines])
    for i = meta.data_start_line, meta.data_end_line do
      assert.equals(border_w, width.display_width(lines[i]),
        "data row " .. i .. " must match the border width")
      assert.matches("│$", lines[i], "data row " .. i .. " must end with the right border")
    end
  end)

  it("keeps last-column byte offsets consistent after rebalancing", function()
    local layout = sql_format.plan_resultset_layout(civilisations())
    local lines, meta = sql_format.render_page(layout, 1, 50)
    local last = #layout.col_widths
    for i, starts in ipairs(meta.col_starts) do
      local line = lines[meta.data_start_line + i - 1]
      -- The final separator is 3 bytes after the last cell's end.
      assert.equals(#line, starts[last].ext_end + 3,
        "last column byte end must sit right before the trailing │")
    end
  end)end)
