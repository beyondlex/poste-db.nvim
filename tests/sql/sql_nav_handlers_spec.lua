local handlers = require("poste-sql.nav.handlers")

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

  it("builds a search dir from the current buffer path", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "/tmp/example/query.sql")
    assert.equals("/tmp/example", handlers.build_connection_search_dir(buf))
  end)
end)
