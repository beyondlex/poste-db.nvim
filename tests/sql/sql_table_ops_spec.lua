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
      assert.equals('"x"', t.quote("x", "mssql"))
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
      assert.equals('ALTER TABLE "t" MODIFY COLUMN "c" TEXT;',
        t.gen_alter_type("t", "c", "TEXT", "clickhouse"))
    end)
    it("mssql uses bare ALTER COLUMN (no TYPE keyword)", function()
      assert.equals('ALTER TABLE "t" ALTER COLUMN "c" TEXT;',
        t.gen_alter_type("t", "c", "TEXT", "mssql"))
    end)
    it("sqlite explains instead of emitting broken DDL", function()
      local ddl = t.gen_alter_type("t", "c", "TEXT", "sqlite")
      assert.match("does not support", ddl)
      assert.is_nil(ddl:find("ALTER TABLE", 1, true))
    end)
  end)
end)
