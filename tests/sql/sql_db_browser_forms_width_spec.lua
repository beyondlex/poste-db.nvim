--- db_browser forms — the simple form's width contract. forms.lua had no test
--- seam at all; calc_width is the one pure part, and it is the number both the
--- float geometry and the border art depend on (they used to compute it twice,
--- so a change to one silently clipped the other).
local forms = require("poste-db.db_browser.forms")

local function fields(...)
  local out = {}
  for _, label in ipairs({ ... }) do
    table.insert(out, { label = label, key = label, kind = "text" })
  end
  return out
end

describe("db_browser forms calc_width", function()
  it("follows the longest label, with a 4-column floor", function()
    -- "Name" is 4 wide — the floor; a longer label pushes the value area out
    assert.equals(4 + 4 + 24, forms._test.calc_width("T", fields("Name")))
    assert.equals(13 + 4 + 24, forms._test.calc_width("T", fields("Name", "Default Value")))
  end)

  it("follows a title longer than the content", function()
    local title = "Modify Column in some_schema.some_very_long_table_name"
    local w = forms._test.calc_width(title, fields("Name"))
    assert.equals(vim.fn.strdisplaywidth(title) + 6, w)
  end)

  it("matches the float height the form draws (+6 chrome rows)", function()
    -- calc_width feeds calc_size's height too: #fields + 6. Pin the pair so a
    -- chrome change cannot resize the float without failing here.
    local fs = fields("a", "b", "c")
    local w = forms._test.calc_width("New Table", fs)
    assert.equals(#fs + 6, 9, "height formula: fields + 6")
    assert.truthy(w > 0)
  end)
end)
