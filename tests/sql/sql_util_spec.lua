local util = require("poste-db.util")

describe("util utf8 helpers", function()
  it("utf8_char_bytes returns correct byte widths", function()
    assert.equals(1, util.utf8_char_bytes(0x24))
    assert.equals(2, util.utf8_char_bytes(0xC2))
    assert.equals(3, util.utf8_char_bytes(0xE2))
    assert.equals(4, util.utf8_char_bytes(0xF0))
  end)

  it("truncate_displaywidth preserves ASCII strings under limit", function()
    assert.equals("hello", util.truncate_displaywidth("hello", 10))
  end)

  it("truncate_displaywidth stops before multibyte overflow", function()
    local s = "a│b"
    assert.equals("a│", util.truncate_displaywidth(s, 2))
  end)

  it("truncate_displaywidth handles empty strings", function()
    assert.equals("", util.truncate_displaywidth("", 5))
    assert.equals("", util.truncate_displaywidth(nil, 5))
  end)

  it("utf8_safe_cut keeps short strings unchanged", function()
    assert.equals("abc", util.utf8_safe_cut("abc", 10))
    assert.equals("", util.utf8_safe_cut(nil, 10))
  end)

  it("utf8_safe_cut cuts ASCII exactly at the budget", function()
    assert.equals(string.rep("x", 10), util.utf8_safe_cut(string.rep("x", 20), 10))
  end)

  it("utf8_safe_cut backs the cut off a multibyte character", function()
    -- 数 = 3 bytes: budget 10 would split the 4th character
    local s = string.rep("\u{6570}", 5)
    assert.equals(string.rep("\u{6570}", 3), util.utf8_safe_cut(s, 10))
  end)
end)
