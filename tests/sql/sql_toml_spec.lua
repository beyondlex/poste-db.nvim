local toml = require("poste-db.toml")

describe("toml.parse", function()
  it("parses a simple key=value", function()
    local res, err = toml.parse('key = "value"')
    assert.is_nil(err)
    assert.equals("value", res.key)
  end)

  it("parses [section] with key=value", function()
    local res = toml.parse('[section]\nkey = "value"')
    assert.equals("value", res.section.key)
  end)

  it("parses numeric values", function()
    local res = toml.parse('port = 5432')
    assert.equals(5432, res.port)
  end)

  it("parses boolean values", function()
    local res = toml.parse('enabled = true')
    assert.is_true(res.enabled)
  end)

  it("strips inline comments from string values", function()
    local res = toml.parse('password = "abc123" # this is a comment')
    assert.equals("abc123", res.password)
  end)

  it("handles inline comments with # inside strings", function()
    local res = toml.parse('name = "str#value" # comment')
    assert.equals("str#value", res.name)
  end)

  it("parses single-quoted strings", function()
    local res = toml.parse("name = 'raw string'")
    assert.equals("raw string", res.name)
  end)

  it("handles escape sequences in double-quoted strings", function()
    local res = toml.parse('text = "line1\\nline2"')
    assert.equals("line1\nline2", res.text)
  end)

  it("does not re-process backslashes produced by an earlier unescape step", function()
    -- sequential gsubs turned the literal backslash + 'n' of \tables into a
    -- newline (the \\n → \n double-substitution), mangling Windows paths
    local res = toml.parse('path = "D:\\\\tables\\\\notes"')
    assert.equals("D:\\tables\\notes", res.path)
    local wal = toml.parse('mode = "\\\\new"') -- \\n must stay backslash + n
    assert.equals("\\new", wal.mode)
  end)

  it("keeps unknown escapes verbatim", function()
    local res = toml.parse('v = "a\\qb"')
    assert.equals("a\\qb", res.v)
  end)

  it("treats a backslash in a literal string as a plain character", function()
    -- literal strings ('…') have no escapes: 'a\' ends at that quote, so a
    -- trailing comment after it must still be stripped (the escape-skip used
    -- to swallow the closing quote and fail the parse)
    local res, err = toml.parse("password = 'a\\' # comment")
    assert.is_nil(err)
    assert.equals("a\\", res.password)
  end)

  it("parses content saved with a UTF-8 BOM", function()
    local res = toml.parse("\xEF\xBB\xBF[section]\nkey = \"value\"")
    assert.equals("value", res.section.key)
  end)

  it("skips comment lines", function()
    local res = toml.parse('# this is a comment\nkey = "value"')
    assert.equals("value", res.key)
  end)

  it("skips blank lines", function()
    local res = toml.parse('\n\nkey = "value"\n\n')
    assert.equals("value", res.key)
  end)

  it("errors on unclosed double-quoted string", function()
    local res, err = toml.parse('key = "unclosed')
    assert.is_nil(res)
    assert.matches("Unclosed", err or "")
  end)

  it("parses multiple sections", function()
    local content = '[pg]\nhost = "localhost"\n\n[mysql]\nhost = "127.0.0.1"\n'
    local res = toml.parse(content)
    assert.equals("localhost", res.pg.host)
    assert.equals("127.0.0.1", res.mysql.host)
  end)

  it("handles inline comment with # that looks like a value", function()
    local res = toml.parse('password = "abc#123" # comment')
    assert.equals("abc#123", res.password)
  end)

  it("handles real-world connections.toml snippet", function()
    local content = [[
[pg-dev]
dialect = "postgres"
host = "localhost"
port = 5432
database = "blog"
user = "{{DB_USER}}"
password = "{{DB_PASS}}"

[mysql-dev]
dialect = "mysql"
host = "127.0.0.1"
port = 3306
database = "inventory"
]]
    local res = toml.parse(content)
    assert.equals("postgres", res["pg-dev"].dialect)
    assert.equals("localhost", res["pg-dev"].host)
    assert.equals(5432, res["pg-dev"].port)
    assert.equals("mysql", res["mysql-dev"].dialect)
    assert.equals("inventory", res["mysql-dev"].database)
  end)
end)

describe("toml inline containers", function()
  it("parses an inline table into a real table", function()
    local res = toml.parse('[c]\ntunnel = { to = "jump@bastion", port = 2222, key = "~/.ssh/id" }')
    local tunnel = res.c.tunnel
    assert.is_table(tunnel)
    assert.equals("jump@bastion", tunnel.to)
    assert.equals(2222, tunnel.port)
    assert.equals("~/.ssh/id", tunnel.key)
  end)

  it("parses inline arrays and keeps commas inside strings", function()
    local res = toml.parse('[c]\nlist = ["a,b", "c"]\nempty = []\nnums = [1, 2, 3]')
    assert.same({ "a,b", "c" }, res.c.list)
    assert.same({}, res.c.empty)
    assert.same({ 1, 2, 3 }, res.c.nums)
  end)

  it("nests inline tables and arrays", function()
    local res = toml.parse('[c]\nx = { a = { b = 1 }, list = [ true ] }')
    assert.equals(1, res.c.x.a.b)
    assert.same({ true }, res.c.x.list)
  end)

  it("reports an unclosed inline container instead of stringifying it", function()
    local parsed, err = toml.parse('a = { to = "x"')
    assert.is_nil(parsed)
    assert.equals("Unclosed inline table", err)
    local p2, e2 = toml.parse('a = [1, 2')
    assert.is_nil(p2)
    assert.equals("Unclosed inline array", e2)
  end)

  it("feeds the documented tunnel shape to tunnel.normalize_cfg", function()
    local tunnel_mod = require("poste-db.tunnel")
    local res = toml.parse('[c]\ntunnel = { to = "jump@bastion", port = 2222 }')
    local cfg, err = tunnel_mod.normalize_cfg(res.c.tunnel)
    assert.is_nil(err)
    assert.equals("jump@bastion", cfg.dest)
    assert.equals(2222, cfg.port)
  end)

  it("rejects [[array-of-tables]] instead of making a \"[name\" section", function()
    local res, err = toml.parse('[[srv]]\nurl = "mysql://h/db"')
    assert.is_nil(res)
    assert.equals("Array-of-tables headers ([[name]]) are not supported", err)
  end)

  it("rejects dotted keys instead of storing a flat \"a.b\"", function()
    -- `tunnel.to = "h"` read as key "tunnel.to" never reached
    -- tunnel.normalize_cfg, so the connection looked fine and failed at use
    local res, err = toml.parse('[srv]\ntunnel.to = "h"')
    assert.is_nil(res)
    assert.equals("Dotted keys (a.b = …) are not supported: tunnel.to", err)
  end)

  it("keeps dotted section names: the header is the connection name", function()
    local res, err = toml.parse('[my-app.prod]\ndialect = "redis"')
    assert.is_nil(err)
    assert.equals("redis", res["my-app.prod"].dialect)
  end)

  it("does not echo the offending text for a malformed value line", function()
    -- the line may be a mistyped `password "s3cret"`; the old message
    -- printed it verbatim into :PosteDbHealth / the notify popup
    local res, err = toml.parse('password "s3cret-value"')
    assert.is_nil(res)
    assert.falsy(err:find("s3cret%-value", 1, false))
  end)
end)
