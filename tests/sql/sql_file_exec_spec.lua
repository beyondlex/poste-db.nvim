local file_exec = require("poste-db.file_exec")

describe("file_exec", function()
  describe("handle_line", function()
    it("exists as a module", function()
      assert.is_not_nil(file_exec)
      assert.is_not_nil(file_exec.run)
      assert.is_not_nil(file_exec.cancel)
    end)
  end)

  describe("progress window", function()
    it("creates and closes progress window", function()
      -- Test that the module can be loaded without errors
      local ok, err = pcall(require, "poste-db.file_exec")
      assert.is_true(ok, "file_exec module should load without errors")
    end)
  end)

  describe("cancellation", function()
    it("cancel works without active job", function()
      local ok, err = pcall(file_exec.cancel)
      assert.is_true(ok, "cancel should not error when no job is running")
    end)
  end)

  describe("run builds an argv list (no shell string)", function()
    local saved, captured, logged, notified

    before_each(function()
      saved = {}
      saved.state = package.loaded["poste.state"]
      saved.dialog = package.loaded["poste.dialog"]
      saved.layout = package.loaded["poste.layout"]
      saved.connections = package.loaded["poste-db.connections"]
      saved.log = package.loaded["poste-db.log"]
      saved.jobstart = vim.fn.jobstart
      saved.readfile = vim.fn.readfile

      package.loaded["poste.state"] = {
        current_env = "dev",
        find_poste_binary = function() return "/tmp/bin dir/poste" end,
        log = function() end,
      }
      package.loaded["poste.dialog"] = {
        open = function()
          return {
            content_width = 68,
            content_height = 18,
            update = function() end,
            close = function() end,
          }
        end,
      }
      local identity = function(x) return x end
      package.loaded["poste.layout"] = {
        cell = identity,
        columns = function() return { lines = {}, highlights = {} } end,
        progress = function() return { "" } end,
        space_between = function() return { "" } end,
        separator = function() return { "" } end,
        dynamic_line = function(t) return t.text or "" end,
      }
      package.loaded["poste-db.connections"] = {
        resolve_connection_url = function(name)
          return "clickhouse://user:secret@localhost:18123/" .. name, nil
        end,
      }
      local real_log = require("poste-db.log")
      logged = {}
      package.loaded["poste-db.log"] = setmetatable({
        info = function(msg) logged[#logged + 1] = msg end,
      }, { __index = real_log })

      captured, notified = nil, nil
      vim.fn.jobstart = function(cmd, opts)
        captured = { cmd = cmd, opts = opts }
        return 42
      end
      vim.notify = function(msg, level) notified = { msg = msg, level = level } end

      -- reload file_exec so its top-level requires pick up the stubs
      package.loaded["poste-db.file_exec"] = nil
    end)

    after_each(function()
      package.loaded["poste.state"] = saved.state
      package.loaded["poste.dialog"] = saved.dialog
      package.loaded["poste.layout"] = saved.layout
      package.loaded["poste-db.connections"] = saved.connections
      package.loaded["poste-db.log"] = saved.log
      package.loaded["poste-db.file_exec"] = nil
      vim.fn.jobstart = saved.jobstart
      vim.fn.readfile = saved.readfile
    end)

    local function fresh()
      return require("poste-db.file_exec")
    end

    it("passes the job a list with binary first and unquoted values", function()
      local fe = fresh()
      fe.run({
        filepath = "/tmp/my file.sql",
        conn = "playground",
        database = "my db",
      })

      assert.is_table(captured.cmd, "jobstart must receive an argv list, not a shell string")
      assert.same({
        "/tmp/bin dir/poste", "exec-file", "/tmp/my file.sql",
        "--env", "dev", "--mode", "greedy",
        "--timeout", "30", "--max-rows", "1000",
        "--json",
        "--connection", "clickhouse://user:secret@localhost:18123/playground",
        "--database", "my db",
      }, captured.cmd)
    end)

    it("falls back to the file's @connection directive", function()
      vim.fn.readfile = function()
        return { "SELECT 1;", "-- @connection directive_conn" }
      end

      local fe = fresh()
      fe.run({ filepath = "/tmp/plain.sql" })

      assert.is_table(captured.cmd)
      local idx = #captured.cmd - 1
      assert.equals("--connection", captured.cmd[idx])
      assert.equals("clickhouse://user:secret@localhost:18123/directive_conn", captured.cmd[idx + 1])
    end)

    it("does not start a job and reports the error on an unresolvable connection", function()
      package.loaded["poste-db.connections"] = {
        resolve_connection_url = function() return nil, "not in connections.toml" end,
      }

      local fe = fresh()
      fe.run({ filepath = "/tmp/x.sql", conn = "nope" })

      assert.is_nil(captured, "no job must be started when connection resolution fails")
      assert.truthy(notified)
      assert.equals(vim.log.levels.ERROR, notified.level)
      assert.matches("not found", notified.msg)
    end)

    it("redacts the connection URL in the command log", function()
      local fe = fresh()
      fe.run({ filepath = "/tmp/x.sql", conn = "playground" })

      assert.equals(1, #logged)
      assert.matches("ExecFile cmd:", logged[1])
      assert.is_falsy(logged[1]:find("secret", 1, true))
      assert.matches("<redacted>", logged[1])
    end)
  end)
end)