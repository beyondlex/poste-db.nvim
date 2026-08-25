-- Tests for lua/poste-db/source_format.lua
-- Formatter detection, priority, dialect resolution, and CLI arg building.
-- Detection is made deterministic by stubbing vim.fn.executable (nothing
-- installed) and overriding the cache for specific formatters via
-- M._test.set_detected().

local state = require("poste-db.state")
local sf = require("poste-db.source_format")
local t = sf._test

local orig_executable = vim.fn.executable
local function stub_executable(result)
  vim.fn.executable = function() return result or 0 end
end

local function restore_detection()
  t.rediscover()
end

describe("source_format build_formatter_args", function()
  it("replaces __DIALECT__ with the mapped dialect", function()
    local args = t.build_formatter_args({ args = { "format", "--dialect", "__DIALECT__", "-" } }, "mysql")
    assert.same({ "format", "--dialect", "mysql", "-" }, args)
  end)

  it("maps dialect names per formatter", function()
    local fmt = { args = { "--language", "__DIALECT__" }, dialect_map = { postgres = "postgresql" } }
    assert.same({ "--language", "postgresql" }, t.build_formatter_args(fmt, "postgres"))
    assert.same({ "--language", "foo" }, t.build_formatter_args(fmt, "foo"))
  end)

  it("falls back to the formatter default dialect when none resolved", function()
    local fmt = { args = { "--dialect", "__DIALECT__" }, default_dialect = "ansi" }
    assert.same({ "--dialect", "ansi" }, t.build_formatter_args(fmt, ""))
  end)

  it("leaves literal args untouched", function()
    local fmt = { args = { "-" } }
    assert.same({ "-" }, t.build_formatter_args(fmt, "postgres"))
  end)
end)

describe("source_format _get_priority", function()
  local saved

  before_each(function()
    saved = state.config and state.config.sql_formatters
  end)

  after_each(function()
    state.config.sql_formatters = saved
  end)

  it("returns the built-in default order when unconfigured", function()
    state.config.sql_formatters = nil
    assert.same({ "sqlfluff", "sqlfmt", "sql-formatter", "pg_format" }, t._get_priority())
  end)

  it("honors the configured priority order", function()
    state.config.sql_formatters = { "sqlfmt", "pg_format" }
    assert.same({ "sqlfmt", "pg_format" }, t._get_priority())
  end)

  it("filters out unknown formatter names", function()
    state.config.sql_formatters = { "nope", "sqlfluff", "wat" }
    assert.same({ "sqlfluff" }, t._get_priority())
  end)

  it("falls back to the default when the configured list is empty", function()
    state.config.sql_formatters = {}
    assert.same({ "sqlfluff", "sqlfmt", "sql-formatter", "pg_format" }, t._get_priority())
  end)
end)

describe("source_format best", function()
  before_each(function() stub_executable(0) end)
  after_each(restore_detection)

  it("returns nil when no formatter detected", function()
    assert.is_nil(t.best("postgres"))
    assert.is_nil(t.best())
  end)

  it("returns the first detected formatter in priority order", function()
    t.set_detected({ sqlfmt = true })
    assert.equals("sqlfmt", t.best("postgres"))
  end)

  it("prefers higher-priority installed formatters", function()
    t.set_detected({ sqlfluff = true, sqlfmt = true })
    assert.equals("sqlfluff", t.best("postgres"))
  end)

  it("uses a dialect-mapped formatter for a known dialect", function()
    t.set_detected({ ["sql-formatter"] = true })
    assert.equals("sql-formatter", t.best("postgres"))
  end)
end)

describe("source_format resolve_dialect", function()
  it("reads the ### dialect header from the buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local ok = pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, {
      "### dialect MySQL",
      "select 1",
    })
    assert.is_true(ok)
    assert.equals("mysql", t.resolve_dialect(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("falls back to sqlite for poste_sqlite filetype", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "poste_sqlite"
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { "select 1" })
    assert.equals("sqlite", t.resolve_dialect(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns empty string when nothing applies", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "poste_sql"
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { "select 1" })
    assert.equals("", t.resolve_dialect(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("source_format format_text", function()
  before_each(function() stub_executable(0) end)
  after_each(restore_detection)

  it("returns an error when forced to an unknown formatter", function()
    local result, err = t.format_text("select 1", { formatter = "wat" })
    assert.is_nil(result)
    assert.matches("Unknown formatter", err or "")
  end)

  it("returns an error when no formatter is installed", function()
    local result, err = t.format_text("select 1")
    assert.is_nil(result)
    assert.matches("No SQL formatter found", err or "")
  end)
end)