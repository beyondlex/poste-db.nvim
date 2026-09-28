--- The copy/drop error summaries: UTF-8-safe wrapping, stable error order,
--- and a progress render that survives an empty job list. The summaries used
--- to chunk error text on raw bytes — a CJK message split mid-glyph and put
--- U+FFFD replacement characters on the dialog — and listed errors in
--- pairs() order, which reshuffles between runs.
local util = require("poste-db.db_browser.util")

--- Pure-Lua UTF-8 structure check: every lead byte is followed by exactly
--- the right number of continuation bytes.
local function valid_utf8(s)
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    local len
    if b < 0x80 then len = 1
    elseif b >= 0xC2 and b < 0xE0 then len = 2
    elseif b >= 0xE0 and b < 0xF0 then len = 3
    elseif b >= 0xF0 and b < 0xF5 then len = 4
    else return false, i end
    if i + len - 1 > n then return false, i end
    for j = 2, len do
      local cb = s:byte(i + j - 1)
      if not cb or cb < 0x80 or cb >= 0xC0 then return false, i end
    end
    i = i + len
  end
  return true
end

describe("db_browser.util.wrap_utf8", function()
  it("splits ASCII at the exact byte budget", function()
    local chunks = util.wrap_utf8(string.rep("a", 120), 50)
    assert.equals(3, #chunks)
    assert.equals(50, #chunks[1])
    assert.equals(50, #chunks[2])
    assert.equals(20, #chunks[3])
    assert.equals(string.rep("a", 120), table.concat(chunks))
  end)

  it("backs the cut up instead of splitting a CJK glyph", function()
    -- 50 bytes lands inside the 17th 3-byte character; the cut must back up
    -- so every chunk is well-formed UTF-8.
    local text = string.rep("表", 40) -- 120 bytes
    local chunks = util.wrap_utf8(text, 50)
    assert.is_true(#chunks >= 3)
    for i, chunk in ipairs(chunks) do
      assert.is_true(valid_utf8(chunk), "chunk " .. i .. " must be valid UTF-8")
      assert.truthy(#chunk <= 50)
    end
    assert.equals(text, table.concat(chunks))
  end)

  it("keeps mixed ASCII/CJK round and lossless", function()
    local text = "Duplicate entry '中文值' for key 'uk_user_name'"
    local chunks = util.wrap_utf8(text, 20)
    assert.equals(text, table.concat(chunks))
    for _, chunk in ipairs(chunks) do
      assert.is_true(valid_utf8(chunk))
    end
  end)

  it("returns no chunks for empty text", function()
    assert.same({}, util.wrap_utf8("", 50))
  end)

  it("does not loop forever when the budget is smaller than one glyph", function()
    -- utf8_safe_cut backs up to zero for a 3-byte char under a 2-byte
    -- budget; the wrapper must keep the character whole instead.
    local chunks = util.wrap_utf8("中文", 2)
    assert.equals(2, #chunks)
    assert.equals("中", chunks[1])
    assert.equals("文", chunks[2])
  end)
end)

describe("copy_progress.show_summary_dialog", function()
  local saved_dialog = package.loaded["poste-db.dialog"]
  local saved_copy_progress = package.loaded["poste-db.db_browser.copy_progress"]
  local captured

  after_each(function()
    package.loaded["poste-db.dialog"] = saved_dialog
    if saved_copy_progress then
      package.loaded["poste-db.db_browser.copy_progress"] = saved_copy_progress
    else
      package.loaded["poste-db.db_browser.copy_progress"] = nil
    end
  end)

  local function load_with_fake_dialog()
    captured = {}
    package.loaded["poste-db.dialog"] = {
      open = function(_opts)
        return {
          buf = -1,
          win = -1,
          update = function(_self, lines, highlights)
            captured[#captured + 1] = { lines = lines, highlights = highlights }
          end,
          close = function() end,
        }
      end,
    }
    package.loaded["poste-db.db_browser.copy_progress"] = nil
    return require("poste-db.db_browser.copy_progress")
  end

  it("renders a CJK error without splitting a glyph", function()
    local cp = load_with_fake_dialog()
    local err = table.concat({ "失败：表 ", string.rep("用户", 30), " 不存在" }) -- ~190 bytes of CJK
    cp.show_summary_dialog(1, 1, { users = err })
    assert.equals(1, #captured)
    for i, line in ipairs(captured[1].lines) do
      assert.is_true(valid_utf8(line), "summary line " .. i .. " must be valid UTF-8")
    end
  end)

  it("lists errors in a stable, sorted order", function()
    local cp = load_with_fake_dialog()
    cp.show_summary_dialog(0, 2, { beta = "x", alpha = "y" })
    local lines = captured[1].lines
    local a_pos, b_pos
    for i, line in ipairs(lines) do
      if line:find("alpha", 1, true) then a_pos = i end
      if line:find("beta", 1, true) then b_pos = i end
    end
    assert.truthy(a_pos, "alpha listed")
    assert.truthy(b_pos, "beta listed")
    assert.is_true(a_pos < b_pos, "errors are sorted, not pairs() order")
  end)

  it("survives a non-string error message", function()
    local cp = load_with_fake_dialog()
    -- The err argument crosses several modules before it lands here; a table
    -- must render as text, not raise on :gsub.
    assert.has_no_error(function() cp.show_summary_dialog(0, 1, { t = { code = 7 } }) end)
  end)
end)

describe("copy_progress.show_paste_progress", function()
  local saved_dialog = package.loaded["poste-db.dialog"]
  local saved_copy_progress = package.loaded["poste-db.db_browser.copy_progress"]
  local captured

  after_each(function()
    package.loaded["poste-db.dialog"] = saved_dialog
    if saved_copy_progress then
      package.loaded["poste-db.db_browser.copy_progress"] = saved_copy_progress
    else
      package.loaded["poste-db.db_browser.copy_progress"] = nil
    end
  end)

  local function load_with_fake_dialog()
    captured = {}
    package.loaded["poste-db.dialog"] = {
      open = function(_opts)
        return {
          buf = -1,
          win = -1,
          update = function(_self, lines, highlights)
            captured[#captured + 1] = { lines = lines, highlights = highlights }
          end,
          close = function() end,
        }
      end,
    }
    package.loaded["poste-db.db_browser.copy_progress"] = nil
    return require("poste-db.db_browser.copy_progress")
  end

  it("renders once with zero jobs without hitting a 0/0 progress bar", function()
    -- paste_objects refuses an empty plan upstream, but the progress view is
    -- a public surface: with no jobs the old render fed string.rep a NaN
    -- from the unguarded done/total (its pct twin had the guard already).
    local cp = load_with_fake_dialog()
    local start = cp.show_paste_progress(
      { conn = "a", db = "db", dialect = "sqlite" },
      { conn = "b", db = "db2", dialect = "sqlite" },
      {},
      function() end)
    assert.is_function(start)
    assert.equals(1, #captured, "the initial render ran")
    local joined = table.concat(captured[1].lines, "\n")
    assert.truthy(joined:find("0/0", 1, true), "the bar line renders as 0/0")
  end)
end)
