--- table_ops DDL generation: dialect-correct ALTER forms. The generated SQL
--- lands in the user's buffer for review — a wrong dialect form wastes the
--- flow (mssql got Postgres `RENAME COLUMN`, which that engine does not
--- support; clickhouse/mssql got `ALTER COLUMN c TYPE t`, invalid in both).

describe("poste-db table_ops DDL generation", function()
  local t = require("poste-db.table_ops")._test

  describe("quote", function()
    it("backticks and doubles embedded backticks for mysql/mariadb", function()
      assert.equals("`we``rd`", t.quote("we`rd", "mysql"))
      assert.equals("`x`", t.quote("x", "mariadb"))
    end)
    it("double quotes and doubles embedded quotes elsewhere", function()
      assert.equals('"we""rd"', t.quote('we"rd', "postgres"))
      assert.equals('"x"', t.quote("x", "sqlite"))
    end)
    -- The generator used to carry its own two-line quoting helper, which
    -- predated these dialects and rendered a clickhouse name as "t" (invalid
    -- there) and an mssql one as "t" (only legal with QUOTED_IDENTIFIER on).
    it("shares poste-db.ident's clickhouse and mssql spellings", function()
      assert.equals("`t`", t.quote("t", "clickhouse"))
      assert.equals("[t]", t.quote("t", "mssql"))
    end)
  end)

  describe("add column", function()
    it("carries NOT NULL and DEFAULT", function()
      assert.equals('ALTER TABLE "t" ADD COLUMN "c" INT NOT NULL DEFAULT 0;',
        t.gen_add_column("t", "c", "INT", false, "0", "postgres"))
    end)
    it("omits both when nullable and no default", function()
      assert.equals('ALTER TABLE "t" ADD COLUMN "c" TEXT;',
        t.gen_add_column("t", "c", "TEXT", true, nil, "postgres"))
    end)
    it("annotates sqlite NOT NULL without a DEFAULT (server rejects it)", function()
      local ddl = t.gen_add_column("t", "c", "TEXT", false, "", "sqlite")
      assert.match("^ALTER TABLE", ddl)
      assert.match("requires a DEFAULT", ddl)
      -- a DEFAULT makes it legal: no note
      assert.equals('ALTER TABLE "t" ADD COLUMN "c" TEXT NOT NULL DEFAULT 0;',
        t.gen_add_column("t", "c", "TEXT", false, "0", "sqlite"))
    end)
  end)

  describe("rename column", function()
    it("uses sp_rename on mssql (no RENAME COLUMN there)", function()
      assert.equals("EXEC sp_rename 't.old', 'new', 'COLUMN';",
        t.gen_rename_column("t", "old", "new", "mssql"))
    end)
    it("uses the standard form elsewhere", function()
      assert.equals('ALTER TABLE "t" RENAME COLUMN "old" TO "new";',
        t.gen_rename_column("t", "old", "new", "postgres"))
    end)
    it("quotes on mysql", function()
      assert.equals("ALTER TABLE `t` RENAME COLUMN `old` TO `new`;",
        t.gen_rename_column("t", "old", "new", "mysql"))
    end)
    it("doubles an apostrophe inside sp_rename's literal arguments", function()
      assert.equals("EXEC sp_rename 'dbo.o''brien.old', 'new', 'COLUMN';",
        t.gen_rename_column("dbo.o'brien", "old", "new", "mssql"))
    end)
  end)

  describe("drop column", function()
    it("quotes per dialect", function()
      assert.equals('ALTER TABLE "t" DROP COLUMN "c";', t.gen_drop_column("t", "c", "postgres"))
      assert.equals("ALTER TABLE `t` DROP COLUMN `c`;", t.gen_drop_column("t", "c", "mysql"))
    end)
  end)

  describe("alter column type", function()
    it("postgres keeps ALTER COLUMN ... TYPE", function()
      assert.equals('ALTER TABLE "t" ALTER COLUMN "c" TYPE TEXT;',
        t.gen_alter_type("t", "c", "TEXT", "postgres"))
    end)
    it("mysql/mariadb/clickhouse use MODIFY COLUMN", function()
      assert.equals("ALTER TABLE `t` MODIFY COLUMN `c` TEXT;",
        t.gen_alter_type("t", "c", "TEXT", "mysql"))
      assert.equals('ALTER TABLE `t` MODIFY COLUMN `c` TEXT;',
        t.gen_alter_type("t", "c", "TEXT", "clickhouse"))
    end)
    it("mssql uses bare ALTER COLUMN (no TYPE keyword)", function()
      assert.equals('ALTER TABLE [t] ALTER COLUMN [c] TEXT;',
        t.gen_alter_type("t", "c", "TEXT", "mssql"))
    end)
    it("sqlite explains instead of emitting broken DDL", function()
      local ddl = t.gen_alter_type("t", "c", "TEXT", "sqlite")
      assert.match("does not support", ddl)
      assert.is_nil(ddl:find("ALTER TABLE", 1, true))
    end)
  end)
end)

--- The generators answer with a comment *block* for SQLite. nvim_buf_set_lines
--- rejects any item containing a newline, so an unsplitted multi-line string
--- aborted the insert and left the source buffer untouched: `mt` on SQLite
--- looked like a command that does nothing.
describe("poste-db table_ops DDL insertion", function()
  local ops = require("poste-db.table_ops")

  --- Feed the sequential vim.ui.input prompts of a table_ops flow.
  local function feed(inputs)
    local i = 0
    local orig = vim.ui.input
    vim.ui.input = function(_, cb)
      i = i + 1
      cb(inputs[i])
    end
    return function() vim.ui.input = orig end
  end

  local function run(fn, inputs, dialect)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "select 1;" })
    local restore = feed(inputs)
    local ok, err = pcall(fn, "t", dialect, buf)
    restore()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert(ok, tostring(err))
    return lines
  end

  it("writes every line of a multi-line answer into the buffer", function()
    local lines = run(ops.alter_type, { "c", "TEXT" }, "sqlite")
    assert.equals("select 1;", lines[1])
    assert.match("^%-%- Alter type", lines[3])
    assert.match("does not support", lines[4])
    assert.match("^%-%- Recreate", lines[5])
    assert.equals(6, #lines, "blank, label, two comment lines, blank")
  end)

  it("keeps the DDL and its SQLite caveat as separate lines", function()
    local lines = run(ops.add_column, { "c", "INT", "n", "" }, "sqlite")
    assert.equals('ALTER TABLE "t" ADD COLUMN "c" INT NOT NULL;', lines[4])
    assert.match("requires a DEFAULT", lines[5])
  end)

  it("still inserts a plain one-line statement unchanged", function()
    local lines = run(ops.add_column, { "c", "INT", "y", "" }, "postgres")
    assert.equals('ALTER TABLE "t" ADD COLUMN "c" INT;', lines[4])
    assert.equals(5, #lines)
  end)
end)
