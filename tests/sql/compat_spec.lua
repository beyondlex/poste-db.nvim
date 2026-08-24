local compat = require("poste-db.compat")

describe("poste-db.compat global migration", function()
  local saved = {}

  before_each(function()
    saved = {}
    for _, name in ipairs({ "config", "debug", "legacy_completion", "dialect", "autoformat" }) do
      saved[name] = {
        new = vim.g["poste_db_" .. name],
        old = vim.g["poste_sql_" .. name],
      }
      vim.g["poste_db_" .. name] = nil
      vim.g["poste_sql_" .. name] = nil
    end
  end)

  after_each(function()
    for _, name in ipairs({ "config", "debug", "legacy_completion", "dialect", "autoformat" }) do
      vim.g["poste_db_" .. name] = saved[name].new
      vim.g["poste_sql_" .. name] = saved[name].old
    end
  end)

  it("reads the new poste_db_* key when set", function()
    vim.g.poste_db_debug = true
    assert.is_true(compat.opt("debug"))
  end)

  it("falls back to the deprecated poste_sql_* key", function()
    vim.g.poste_sql_dialect = "mysql"
    assert.equals("mysql", compat.opt("dialect"))
  end)

  it("prefers the new key over the deprecated one", function()
    vim.g.poste_sql_legacy_completion = true
    vim.g.poste_db_legacy_completion = "rust"
    assert.equals("rust", compat.opt("legacy_completion"))
  end)

  it("returns nil when neither key is set", function()
    assert.is_nil(compat.opt("autoformat"))
  end)

  it("set() writes the new poste_db_* key only", function()
    compat.set("dialect", "sqlite")
    assert.equals("sqlite", vim.g.poste_db_dialect)
    assert.is_nil(vim.g.poste_sql_dialect)
  end)

  it("set() with nil clears the new key", function()
    vim.g.poste_db_debug = true
    compat.set("debug", nil)
    assert.is_nil(vim.g.poste_db_debug)
  end)

  it("errors on unsupported key names", function()
    assert.has.errors(function() compat.opt("nope") end)
    assert.has.errors(function() compat.set("nope", 1) end)
  end)
end)