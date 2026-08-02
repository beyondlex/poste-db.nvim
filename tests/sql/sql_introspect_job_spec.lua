local job = require("poste-sql.introspect.job")

describe("introspect job helpers", function()
  it("decodes json tables", function()
    local parsed = job.decode_json_table('{"items":[{"name":"authors"}]}', "bad")
    assert.same({ items = { { name = "authors" } } }, parsed)
  end)

  it("collects stderr lines and formats exit errors", function()
    local stderr = {}
    local logs = {}
    local notified = nil

    local state_mod = package.loaded["poste.state"]
    local saved_log = state_mod.log
    local saved_notify = vim.notify

    state_mod.log = function(level, msg)
      logs[#logs + 1] = { level = level, msg = msg }
    end
    vim.notify = function(msg, level, opts)
      notified = { msg = msg, level = level, opts = opts }
    end

    job.append_stderr(stderr, { "", "line1", "line2" }, "prefix: ")
    job.notify_exit_error("Thing", 7, stderr, "Title")

    vim.notify = saved_notify
    state_mod.log = saved_log

    assert.same({ "line1", "line2" }, stderr)
    assert.same({
      { level = "ERROR", msg = "prefix: line1" },
      { level = "ERROR", msg = "prefix: line2" },
    }, logs)
    assert.same({
      msg = "Thing exited with code 7\nline1\nline2",
      level = vim.log.levels.ERROR,
      opts = { title = "Title" },
    }, notified)
  end)
end)
