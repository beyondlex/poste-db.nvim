local util = require("poste-sql.util")

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
end)
