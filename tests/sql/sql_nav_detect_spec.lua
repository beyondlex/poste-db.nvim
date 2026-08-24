local detect = require("poste-db.nav.detect")

describe("nav_detect", function()
  it("builds a context detect command with optional dialect", function()
    local cmd = detect.build_context_detect_command("/tmp/poste", 12, "postgres")
    assert.equals(vim.fn.shellescape("/tmp/poste") .. " context detect 12 --dialect postgres", cmd)
  end)

  it("extracts the SQL block around the current line", function()
    local info = detect.extract_sql_block({
      "### query",
      "select",
      "from authors",
      "### other",
    }, 2, "select", 6)

    assert.same({
      block_start = 2,
      block_end = 3,
      offset = 5,
      sql_text = "select\nfrom authors",
    }, info)
  end)

  it("resolves dot_column aliases to a table target", function()
    local target = detect.resolve_detected_table_target({
      ctx_type = "dot_column",
      ctx_data = "p",
      tables = {
        { name = "posts", alias = "p" },
      },
    }, "p.title", 1, "title", {
      connection = "conn",
      database = "blog",
    })

    assert.same({
      action = "navigate_to_table",
      database = "blog",
      table_name = "posts",
      column_name = "title",
    }, target)
  end)
end)
