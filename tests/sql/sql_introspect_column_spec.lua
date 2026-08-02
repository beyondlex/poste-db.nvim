local saved_connections = package.loaded["poste-sql.connections"]
local saved_exec = package.loaded["poste-sql.introspect.exec"]
local saved_ui = package.loaded["poste-sql.introspect.ui"]

local connections_stub = {}
local exec_stub = {}
local ui_stub = {}

package.loaded["poste-sql.connections"] = connections_stub
package.loaded["poste-sql.introspect.exec"] = exec_stub
package.loaded["poste-sql.introspect.ui"] = ui_stub

local column = require("poste-sql.introspect.column")

describe("introspect column helper", function()
  local saved_schedule = vim.schedule

  before_each(function()
    package.loaded["poste-sql.connections"] = connections_stub
    package.loaded["poste-sql.introspect.exec"] = exec_stub
    package.loaded["poste-sql.introspect.ui"] = ui_stub
    vim.schedule = function(fn)
      fn()
    end
  end)

  after_each(function()
    vim.schedule = saved_schedule
    package.loaded["poste-sql.connections"] = saved_connections
    package.loaded["poste-sql.introspect.exec"] = saved_exec
    package.loaded["poste-sql.introspect.ui"] = saved_ui
  end)

  it("builds column introspection args and forwards items", function()
    local captured = nil
    local seen = nil
    connections_stub.resolve_connection_url = function(conn)
      assert.equals("primary", conn)
      return "postgres://user@localhost/blog", nil
    end
    connections_stub.get_connection_config = function()
      return { dialect = "mysql" }
    end
    exec_stub.run_json_items_job = function(args, opts)
      captured = { args = args, opts = opts }
      opts.on_items({ { name = "id", type = "int" } })
    end
    ui_stub.show_column_info = function(items, table_name, col_name, show_float)
      seen = { items = items, table_name = table_name, col_name = col_name, show_float = show_float }
    end

    local show_float = function() end
    column.show_column_info("primary", "blog", "\"authors\"", "\"id\"", "analytics", show_float)

    assert.same({
      "introspect",
      "--connection-url",
      "postgres://user@localhost/blog",
      "--type",
      "columns",
      "--table",
      "authors",
      "--database",
      "analytics",
    }, captured.args)
    assert.equals("Column introspection", captured.opts.exit_kind)
    assert.same({
      items = { { name = "id", type = "int" } },
      table_name = "authors",
      col_name = "id",
      show_float = show_float,
    }, seen)
  end)

  it("uses schema as database for mysql", function()
    local captured = nil
    connections_stub.resolve_connection_url = function()
      return "postgres://user@localhost/blog", nil
    end
    connections_stub.get_connection_config = function()
      return { dialect = "mysql" }
    end
    exec_stub.run_json_items_job = function(args)
      captured = args
    end
    ui_stub.show_column_info = function()
      error("should not be called")
    end

    column.show_column_info("primary", "blog", "authors", "id", "analytics", function() end)

    assert.same({
      "introspect",
      "--connection-url",
      "postgres://user@localhost/blog",
      "--type",
      "columns",
      "--table",
      "authors",
      "--database",
      "analytics",
    }, captured)
  end)
end)
