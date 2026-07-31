local float_window = require("poste-sql.float_window")

describe("float_window centered_dimensions", function()
  local original_columns = vim.o.columns
  local original_lines = vim.o.lines

  after_each(function()
    vim.o.columns = original_columns
    vim.o.lines = original_lines
  end)

  it("centers a small window within editor bounds", function()
    vim.o.columns = 100
    vim.o.lines = 40

    local dims = float_window.centered_dimensions({ "hello", "wide text" }, {})

    assert.equals(11, dims.width)
    assert.equals(3, dims.height)
    assert.equals(44, dims.col)
    assert.equals(18, dims.row)
  end)

  it("clamps width and height to configured limits", function()
    vim.o.columns = 80
    vim.o.lines = 20

    local lines = {}
    for i = 1, 20 do
      lines[i] = string.rep("x", 200)
    end

    local dims = float_window.centered_dimensions(lines, {
      width_ratio = 0.7,
      max_width = 120,
      width_padding = 2,
      height_ratio = 0.6,
      min_height = 3,
      extra_height = 1,
    })

    assert.equals(56, dims.width)
    assert.equals(12, dims.height)
    assert.equals(12, dims.col)
    assert.equals(4, dims.row)
  end)
end)
