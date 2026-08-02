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

  it("collects column yank values from resultsets", function()
    local values, col_name = cell.collect_column_values({
      data = {
        results = {
          {
            rows = {
              { "a", vim.NIL },
              { { b = 2 }, 3 },
            },
            columns = {
              [2] = { name = "status" },
            },
          },
        },
      },
      meta = { type = "resultset" },
    }, 2)

    assert.same({ "NULL", "3" }, values)
    assert.equals("status", col_name)
  end)

  it("builds column yank text", function()
    local text, count, col_name = cell.build_column_yank_text({
      data = {
        results = {
          {
            rows = {
              { "a", "x" },
              { "b", "y" },
            },
            columns = {
              [2] = { name = "status" },
            },
          },
        },
      },
      meta = { type = "resultset" },
    }, 2)

    assert.equals("x, y", text)
    assert.equals(2, count)
    assert.equals("status", col_name)
  end)

  it("applies or clears cell highlights", function()
    local highlights = package.loaded["poste-sql.highlights"]
    local saved_highlight = highlights.highlight_cell
    local saved_clear = highlights.clear_cell_highlight
    local calls = {}

    highlights.highlight_cell = function(...)
      calls[#calls + 1] = { fn = "highlight", args = { ... } }
    end
    highlights.clear_cell_highlight = function(...)
      calls[#calls + 1] = { fn = "clear", args = { ... } }
    end

    cell.apply_cell_highlight(true, "buf", 3, 4, { kind = "meta" }, { 1, 2 })
    cell.apply_cell_highlight(false, "buf", 3, 4, { kind = "meta" }, { 1, 2 })

    highlights.highlight_cell = saved_highlight
    highlights.clear_cell_highlight = saved_clear

    assert.same({
      { fn = "highlight", args = { "buf", 3, 4, { kind = "meta" }, nil, { 1, 2 } } },
      { fn = "clear", args = { "buf" } },
    }, calls)
  end)
end)
