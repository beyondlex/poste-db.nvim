--- sql_runner/response.lua is the screen the user reads after pressing <CR>:
--- it places the ✓/✘ sign, fills `state.last_error` for the AI "ask about this
--- error" action, and hands the dataset panel its content. Its contract with the
--- transport is a verdict (`failed`/`has_error`) plus optional text, so these
--- specs drive it with every combination of the two — the shape that used to
--- paint a green ✓ beside a statement nobody executed.

local saved = {
  state = package.loaded["poste-db.state"],
  config = package.loaded["poste-db.config"],
  indicators = package.loaded["poste-db.indicators"],
  statement = package.loaded["poste-db.statement"],
  format = package.loaded["poste-db.format"],
  dataset = package.loaded["poste-db.dataset"],
  buffer = package.loaded["poste-db.buffer"],
  context = package.loaded["poste-db.context"],
  completion = package.loaded["poste-db.completion.data"],
  semantic = package.loaded["poste-db.semantic_diagnostics"],
  db_browser = package.loaded["poste-db.db_browser.init"],
}

local state_stub = {
  log = function() end,
  last_response = nil,
  last_error = nil,
  context = { connection = "pg://h/app", database = "app" },
}
local indicator_calls = {}
local rendered = {}
local notified = {}

package.loaded["poste-db.state"] = state_stub
package.loaded["poste-db.config"] = { config = {}, get_keymap = function() return nil end }
package.loaded["poste-db.indicators"] = {
  set_indicator = function(_, line, kind, ms)
    indicator_calls[#indicator_calls + 1] = { line = line, kind = kind, ms = ms }
  end,
  clear_all = function() end,
}
package.loaded["poste-db.statement"] = {
  get_stmt_sql = function() return "SELECT 1" end,
  extract_table_name = function() return nil end,
}
package.loaded["poste-db.format"] = {
  format_dataset = function() return { "rendered" }, { type = "affected" } end,
  format_error = function(msg) return { "E: " .. tostring(msg) } end,
  format_resultset = function() return { "rs" }, { type = "resultset" } end,
  plan_resultset_layout = function() return nil end,
  render_page = function() return { "page" }, { type = "resultset" } end,
}
package.loaded["poste-db.dataset"] = { default_page_size = 200 }
package.loaded["poste-db.buffer"] = {
  render_dataset = function(lines, meta) rendered[#rendered + 1] = meta end,
}
package.loaded["poste-db.context"] = {
  handle_use_statement = function() end,
  resolve_full_context = function() return { connection = "pg://h/app", database = "app" } end,
}
package.loaded["poste-db.completion.data"] = { clear_cache = function() end }
package.loaded["poste-db.semantic_diagnostics"] = { invalidate = function() end, update = function() end }
package.loaded["poste-db.db_browser.init"] = { is_open = function() return false end }

local response = require("poste-db.sql_runner.response")
local verdict = require("poste-db.verdict")

--- One request's worth of `deps`, as run_sql_request builds them.
local function make_deps(over)
  local deps = {
    entry = {},
    current_seq = 1,
    get_exec_seq = function() return 1 end,
    src_buf = 1,
    src_file = "/tmp/one.sql",
    buf_lines = { "SELECT 1" },
    buf_content = "SELECT 1",
    stmt_sql_raw = "SELECT 1",
    stmt_lines = { 1 },
    first_line = 1,
    set_lines = nil,
    is_visual = false,
    block_result_line = 0,
  }
  return vim.tbl_extend("force", deps, over or {})
end

local function single(parsed_over)
  return vim.tbl_extend("force", {
    latency_ms = 12,
    connection = "pg://h/app",
    database = "app",
    dialect = "postgres",
    body = "{}",
    results = { { row_count = 1, execution_time_ms = 3 } },
  }, parsed_over or {})
end

describe("sql_runner response.handle single result", function()
  before_each(function()
    indicator_calls = {}
    rendered = {}
    notified = {}
    state_stub.last_response = nil
    state_stub.last_error = nil
    vim.notify = function(msg, level) notified[#notified + 1] = { msg = msg, level = level } end
  end)

  after_each(function()
    for k, v in pairs(saved) do package.loaded[k] = v end
  end)

  local function kinds()
    local out = {}
    for _, c in ipairs(indicator_calls) do out[#out + 1] = c.kind end
    return table.concat(out, ",")
  end

  it("marks a clean run success", function()
    local deps = make_deps()
    response.handle(deps, single())
    assert.equals("success", kinds())
    assert.is_nil(deps.entry.error)
    assert.is_nil(state_stub.last_error)
    assert.equals(12, deps.entry.elapsed_ms)
  end)

  it("marks a failed statement with text as an error and keeps the message", function()
    local deps = make_deps()
    response.handle(deps, single({
      has_error = true,
      results = { { error = "column x does not exist", failed = true } },
    }))
    assert.equals("error", kinds())
    assert.is_true(deps.entry.error)
    assert.equals("column x does not exist", state_stub.last_error.message)
  end)

  it("marks a failed statement that carried no text as an error", function()
    -- The regression this whole path is about: `error` was the only field read,
    -- so a silent rejection got a green ✓ and an empty `state.last_error`.
    local deps = make_deps()
    response.handle(deps, single({ has_error = true, results = { { failed = true } } }))
    assert.equals("error", kinds())
    assert.is_true(deps.entry.error)
    assert.equals(verdict.UNEXPLAINED_FAILURE, state_stub.last_error.message)
    assert.equals("string", type(state_stub.last_error.message))
  end)

  it("honours the envelope verdict when the result carries neither flag nor text", function()
    local deps = make_deps()
    response.handle(deps, single({ has_error = true, results = { { row_count = 0 } } }))
    assert.equals("error", kinds())
    assert.is_true(deps.entry.error)
  end)

  it("treats a response with no results at all as failed when the envelope says so", function()
    local deps = make_deps()
    response.handle(deps, single({ has_error = true, results = {} }))
    assert.equals("error", kinds())
    assert.equals(verdict.UNEXPLAINED_FAILURE, state_stub.last_error.message)
  end)

  it("does not read a null error field as a failure", function()
    -- `vim.NIL` is truthy, and it was the only shape of "no message" the old code
    -- treated as an error — so a session result that merely carried null looked
    -- rejected while the panel stayed silent about it.
    local deps = make_deps()
    response.handle(deps, single({ results = { { error = vim.NIL, row_count = 2 } } }))
    assert.equals("success", kinds())
    assert.is_nil(state_stub.last_error)
  end)

  it("puts the sign on the statement's own line", function()
    response.handle(make_deps({ first_line = 7, stmt_lines = { 7 } }),
      single({ has_error = true, results = { { failed = true } } }))
    assert.equals(6, indicator_calls[1].line, "0-based first line of the statement")
  end)

  it("renders through the dataset buffer without notifying", function()
    response.handle(make_deps(), single({ has_error = true, results = { { failed = true } } }))
    assert.equals(1, #rendered)
    local handled = 0
    for _, n in ipairs(notified) do
      if n.msg:find("SQL execution error", 1, true) then handled = handled + 1 end
    end
    assert.equals(0, handled, "a statement failure is data, not a handler crash")
  end)
end)

describe("sql_runner response.handle multi result", function()
  before_each(function()
    indicator_calls = {}
    rendered = {}
    state_stub.last_error = nil
  end)

  after_each(function()
    for k, v in pairs(saved) do package.loaded[k] = v end
  end)

  it("places an error sign per failed statement and a success sign per clean one", function()
    local deps = make_deps({
      stmt_lines = { 1, 4 },
      buf_lines = { "SELECT 1", "", "", "SELECT 2" },
      first_line = 1,
    })
    response.handle(deps, single({
      has_error = true,
      results = {
        { failed = true },
        { row_count = 1, columns = { { name = "x" } }, execution_time_ms = 2 },
      },
    }))
    local by_line = {}
    for _, c in ipairs(indicator_calls) do by_line[c.line] = c.kind end
    assert.equals("error", by_line[0], "the silently rejected first statement")
    assert.equals("success", by_line[3], "the statement that did run")
    assert.is_true(deps.entry.error)
    assert.equals(verdict.UNEXPLAINED_FAILURE, state_stub.last_error.message)
  end)
end)
