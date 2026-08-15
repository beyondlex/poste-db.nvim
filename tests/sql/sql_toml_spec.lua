local toml = require("poste-sql.toml")

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