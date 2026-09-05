--- Tests for format.lua helpers not covered elsewhere: timezone-aware
--- datetime rendering and the translated-SQL footnote.
---
--- Regression for the footnote: the raw original_sql was concatenated into a
--- buffer line, so a multi-line statement produced lines with embedded
--- newlines — nvim_buf_set_lines rejects those and the whole response render
--- aborted with "SQL execution error".

local sql_format = require("poste-db.format")

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
