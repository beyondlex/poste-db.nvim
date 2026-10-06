local handlers = require("poste-db.nav.handlers")

describe("nav_handlers", function()
  it("finds the matching connection line", function()
    local line = handlers.find_connection_target_line({
      "[other]",
      "dialect = \"sqlite\"",
      "",
      "[analytics]",
      "dialect = \"postgres\"",
    }, "analytics")

    assert.equals(4, line)
  end)

  -- The TOML parser accepts whitespace-padded quoted headers, so the
  -- goto-definition finder must read them the same way.
  it("finds a whitespace-padded quoted header", function()
    local line = handlers.find_connection_target_line({
      "[ 'my db' ]",
      "dialect = \"postgres\"",
    }, "my db")

    assert.equals(1, line)
  end)

  it("keeps names whose ends merely look like quotes", function()
    -- [a"] is a legal TOML header whose name really is `a"`: the quote is
    -- only stripped as a MATCHING pair.
    assert.equals(1, handlers.find_connection_target_line({
      "[a\"]",
    }, "a\""))
    -- and the name must match exactly, not modulo whitespace
    assert.equals(2, handlers.find_connection_target_line({
      "[a\"]",
      "[plain]",
    }, "plain"))
  end)

  it("builds a search dir from the current buffer path", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "/tmp/example/query.sql")
    assert.equals("/tmp/example", handlers.build_connection_search_dir(buf))
  end)
end)
