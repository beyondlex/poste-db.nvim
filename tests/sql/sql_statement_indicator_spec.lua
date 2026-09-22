local statement_indicator = require("poste-db.statement_indicator")

describe("statement_indicator toggle", function()
  after_each(function()
    statement_indicator.clear(vim.api.nvim_get_current_buf())
  end)

  it("toggles disabled state", function()
    statement_indicator.toggle()
    statement_indicator.toggle()
  end)

  it("clear does not error without buffer", function()
    statement_indicator.clear(nil)
  end)
end)

describe("statement_indicator update", function()
  it("handles nil buffer gracefully", function()
    statement_indicator.update(nil, 1)
  end)

  it("handles invalid buffer gracefully", function()
    statement_indicator.update(99999, 1)
  end)
end)

describe("statement_indicator boundary background", function()
  local buf

  before_each(function()
    statement_indicator.setup()
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "SELECT id,",
      "       name",
      "FROM users",
      "WHERE id = 1;",
    })
  end)

  after_each(function()
    statement_indicator.clear(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("paints the statement block with hl_eol extmarks", function()
    statement_indicator.update(buf, 1)  -- cursor inside the statement
    assert.is_true(vim.wait(500, function()
      return #vim.api.nvim_buf_get_extmarks(
        buf, statement_indicator._test.get_ns(), 0, -1, {}) > 0
    end), "boundary extmarks should appear after update")

    local eol_rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(
        buf, statement_indicator._test.get_ns(), 0, -1, { details = true })) do
      assert.are.equal("PosteDbSqlBoundary", m[4].hl_group)
      assert.is_truthy(m[4].hl_eol)
      eol_rows[m[2] + 1] = m[4].end_row
    end
    -- one extmark per statement row; end_row (0-based) = own row + 1
    assert.are.equal(1, eol_rows[1])
    assert.are.equal(2, eol_rows[2])
    assert.are.equal(3, eol_rows[3])
    assert.are.equal(4, eol_rows[4])
  end)

  it("does not repaint extmarks for moves inside the same statement", function()
    statement_indicator.update(buf, 1)
    assert.is_true(vim.wait(500, function()
      return #vim.api.nvim_buf_get_extmarks(
        buf, statement_indicator._test.get_ns(), 0, -1, {}) > 0
    end), "boundary extmarks should appear after update")

    local function extmark_ids()
      local ids = {}
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(
          buf, statement_indicator._test.get_ns(), 0, -1, {})) do
        ids[#ids + 1] = m[1]
      end
      return ids
    end

    local ids1 = extmark_ids()
    statement_indicator.update(buf, 3)  -- same statement, different line
    local ids2 = extmark_ids()
    assert.same(ids1, ids2, "same span must not clear/re-paint extmarks")
  end)

  it("repaints a new span after the statement set changes", function()
    statement_indicator.update(buf, 1)
    assert.is_true(vim.wait(500, function()
      return #vim.api.nvim_buf_get_extmarks(
        buf, statement_indicator._test.get_ns(), 0, -1, {}) > 0
    end), "boundary extmarks should appear after update")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "SELECT *",
      "FROM t;",
      "SELECT 1;",
    })
    statement_indicator.update(buf, 2)
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(
        buf, statement_indicator._test.get_ns(), 0, -1, { details = true })) do
      rows[#rows + 1] = m[2] + 1
    end
    table.sort(rows)
    assert.same({ 1, 2 }, rows)
  end)

  it("does not paint single-line statements", function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 1;" })
    statement_indicator.update(buf, 1)
    vim.wait(200)
    assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(
      buf, statement_indicator._test.get_ns(), 0, -1, {}))
  end)
end)

describe("statement_indicator boundary gutter", function()
  local config = require("poste-db.config")
  local buf

  local function marks()
    return vim.api.nvim_buf_get_extmarks(
      buf, statement_indicator._test.get_ns(), 0, -1, { details = true })
  end

  before_each(function()
    config.config.boundary_style = "gutter"
    statement_indicator.clear(vim.api.nvim_get_current_buf())
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "SELECT id,",
      "       name",
      "FROM users",
      "WHERE id = 1;",
    })
  end)

  after_each(function()
    config.config.boundary_style = "background"
    statement_indicator.clear(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("tints the number column instead of the text", function()
    statement_indicator.update(buf, 1)
    assert.is_true(vim.wait(500, function() return #marks() > 0 end),
      "boundary extmarks should appear after update")

    local rows = {}
    for _, m in ipairs(marks()) do
      assert.are.equal("PosteDbSqlBoundaryGutter", m[4].number_hl_group)
      assert.is_nil(m[4].hl_group, "gutter style must not tint the lines")
      assert.is_nil(m[4].hl_eol, "gutter style must not reach past EOL")
      rows[#rows + 1] = m[2] + 1
    end
    table.sort(rows)
    assert.same({ 1, 2, 3, 4 }, rows, "one mark per statement row")
  end)

  it("drops the marks when the cursor leaves the statement", function()
    statement_indicator.update(buf, 1)
    assert.is_true(vim.wait(500, function() return #marks() > 0 end))
    vim.api.nvim_buf_set_lines(buf, 4, 4, false, { "", "SELECT 2;", "" })
    statement_indicator.update(buf, 6)
    assert.are.equal(0, #marks())
  end)

  it("does not paint a single-line statement", function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 1;" })
    statement_indicator.update(buf, 1)
    vim.wait(200)
    assert.are.equal(0, #marks())
  end)
end)
