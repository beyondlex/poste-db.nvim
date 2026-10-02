--- insert_hint spec — the VALUES-column highlight: which column the cursor's
--- value position maps to. Driven through M.update on a real buffer (the
--- debounced autocmd path needs a live insert session; the mapping logic is
--- what is under test). Extmarks are read back from the plugin namespace.
local insert_hint = require("poste-db.insert_hint")
local ns = vim.api.nvim_create_namespace("poste_insert_hint")

describe("poste-db insert_hint", function()
  local buf

  local function set_sql(lines)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  local function cursor_at(row_1based, col_0based)
    vim.api.nvim_win_set_cursor(0, { row_1based, col_0based })
    insert_hint.update()
  end

  local function marks()
    return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  end

  --- The text the single hint extmark covers, or nil when none.
  local function hinted_text()
    local m = marks()
    if #m == 0 then return nil end
    assert.equals(1, #m, "expected exactly one hint extmark")
    return vim.api.nvim_buf_get_text(buf, m[1][2], m[1][3], m[1][2], m[1][4].end_col, {})[1]
  end

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("highlights the column under the cursor's value position", function()
    set_sql({ "INSERT INTO users (id, name, email) VALUES (1, 'bob', 'b@x');" })
    -- cursor inside the SECOND value ('|bob'): col 32 is within 'bob'
    local row = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    local col = row:find("'bob'")
    cursor_at(1, col)  -- on the opening quote of 'bob'
    assert.equals("name", hinted_text())
  end)

  it("handles backtick-quoted table names", function()
    set_sql({ "INSERT INTO `order items` (sku, qty) VALUES ('A-1', 2);" })
    local row = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    cursor_at(1, row:find("2)"))
    assert.equals("qty", hinted_text())
  end)

  it("a -- inside a string literal is data, not a comment", function()
    set_sql({ "INSERT INTO t (a, b) VALUES ('http://x--y', 7);" })
    local row = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    -- cursor inside the SECOND value region (after the literal with --)
    cursor_at(1, row:find("7)"))
    assert.equals("b", hinted_text())
  end)

  it("no hint before the VALUES list", function()
    set_sql({ "INSERT INTO users (id, name) VALUES (1, 'bob');",
              "SELECT 1;" })
    cursor_at(1, 5)  -- inside INSERT INTO head
    assert.is_nil(hinted_text())
  end)

  it("no hint past the closing VALUES paren", function()
    set_sql({ "INSERT INTO users (id, name) VALUES (1, 'bob');" })
    local row = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    cursor_at(1, #row - 1)  -- on the trailing `;`
    assert.is_nil(hinted_text())
  end)

  it("no hint without an INSERT INTO", function()
    set_sql({ "SELECT * FROM users;" })
    cursor_at(1, 3)
    assert.is_nil(hinted_text())
  end)

  it("multi-line statements still map the cursor", function()
    set_sql({
      "INSERT INTO users (",
      "  id, name, email",
      ") VALUES (",
      "  1, 'bob', 'b@x'",
      ");",
    })
    -- cursor on the value line, inside 'bob'
    local row = vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1]
    cursor_at(4, row:find("'bob'"))
    assert.equals("name", hinted_text())
  end)

  it("ignores an update for a buffer that is not the current one", function()
    -- CursorHold passes this buffer explicitly; if the user has meanwhile
    -- switched windows, the current window's cursor belongs to other text
    set_sql({ "INSERT INTO users (id, name) VALUES (1, 'bob');" })
    local row = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    cursor_at(1, row:find("'bob'"))
    assert.equals(1, #marks())

    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(other)
    insert_hint.update(buf)
    assert.equals(1, #marks(), "a foreign-cursor update must not touch this buffer's marks")
    insert_hint.clear(buf)

    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_delete(other, { force = true })
  end)

  it("clear removes the extmarks", function()
    set_sql({ "INSERT INTO users (id, name) VALUES (1, 'bob');" })
    local row = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    cursor_at(1, row:find("'bob'"))
    assert.equals(1, #marks())
    insert_hint.clear(buf)
    assert.equals(0, #marks())
  end)
end)
