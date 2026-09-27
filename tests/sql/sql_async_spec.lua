--- async.run delivery contract: a run reports its outcome exactly once —
--- on_error OR on_exit, never both. The binary-missing path used to deliver
--- twice (cli.run_async's synthesized on_exit(-1) plus async's own
--- "Failed to start job" on_error), and the introspect caller journaled two
--- rows and notified twice per failure.
local saved_cli = package.loaded["poste-db.cli"]
local cli_run -- active stub, reassigned per test

package.loaded["poste-db.cli"] = {
  run_async = function(cmd, cbs) return cli_run(cmd, cbs) end,
}
package.loaded["poste-db.async"] = nil
local async = require("poste-db.async")

describe("async.run", function()
  after_each(function()
    package.loaded["poste-db.cli"] = saved_cli
  end)

  it("delivers on_error exactly once when the job never started", function()
    cli_run = function(_cmd, cbs)
      cbs.on_exit(-1) -- cli.run_async's synchronous synthesized exit
      return nil
    end
    local errors, exits = {}, {}
    local task = async.run({ "x" }, {
      on_error = function(msg) errors[#errors + 1] = msg end,
      on_exit = function(code) exits[#exits + 1] = code end,
    })
    assert.is_nil(task)
    assert.equals(1, #errors, "one failure, one delivery")
    assert.equals(0, #exits, "the synthesized -1 must not reach on_exit")
  end)

  it("delivers on_exit once on normal completion", function()
    cli_run = function(_cmd, cbs) return 42 end
    -- Keep a handle to the callbacks so the test plays the job's side.
    local job_cbs
    cli_run = function(_cmd, cbs)
      job_cbs = cbs
      return 42
    end
    local errors, exits = {}, {}
    local task = async.run({ "x" }, {
      timeout = 60000,
      on_error = function(msg) errors[#errors + 1] = msg end,
      on_exit = function(code) exits[#exits + 1] = code end,
    })
    assert.truthy(task)
    job_cbs.on_exit(0)
    assert.same({ 0 }, exits)
    assert.equals(0, #errors)
    assert.falsy(task:is_alive())
  end)

  it("cancel stops the task and swallows the late on_exit", function()
    local job_cbs
    cli_run = function(_cmd, cbs)
      job_cbs = cbs
      return 42
    end
    local cancelled, exits = 0, 0
    local task = async.run({ "x" }, {
      timeout = 60000,
      on_cancel = function() cancelled = cancelled + 1 end,
      on_exit = function() exits = exits + 1 end,
    })
    task:cancel()
    job_cbs.on_exit(0) -- the real job's exit after jobstop
    assert.equals(1, cancelled)
    assert.equals(0, exits)
  end)

  it("timeout delivers on_error and a later exit stays swallowed", function()
    local job_cbs
    cli_run = function(_cmd, cbs)
      job_cbs = cbs
      return 42
    end
    local errors, exits = {}, 0
    async.run({ "x" }, {
      timeout = 10,
      on_error = function(msg) errors[#errors + 1] = msg end,
      on_exit = function() exits = exits + 1 end,
    })
    vim.wait(300, function() return #errors > 0 end)
    job_cbs.on_exit(0) -- jobstop's exit lands after the timeout delivery
    assert.equals(1, #errors)
    assert.truthy(errors[1]:find("Timeout", 1, true))
    assert.equals(0, exits)
  end)
end)
