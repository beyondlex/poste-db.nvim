local cell = require("poste-sql.buffer_nav_cell")

describe("buffer_nav_cell", function()
  it("extracts the first resultset cell", function()
    local res, value = cell.get_resultset_cell({
      data = {
        results = {
          { rows = { { "a", "b" } } },
        },
      },
      meta = { type = "resultset" },
    }, 1, 2)

    assert.same({ rows = { { "a", "b" } } }, res)
    assert.equals("b", value)
  end)

  it("pretty prints json strings", function()
    local text, ft = cell.pretty_print('{"a":1}')
    assert.equals("json", ft)
    assert.truthy(text:find('"a"', 1, true))
  end)

  it("formats clipboard text", function()
    assert.equals("", cell.clipboard_text(vim.NIL))
    assert.equals("x", cell.clipboard_text("x"))
    assert.equals("1", cell.clipboard_text(1))
  end)

  it("truncates yank preview text", function()
    assert.equals("abcdefghijklmnopqrstuvwxyz", cell.yank_preview_text("abcdefghijklmnopqrstuvwxyz"))
  end)
end)
