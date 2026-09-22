-- Tests for `import/execute.lua` — the chunk loop and what each chunk reports
-- about itself.
--
-- This is the only part of the import path that talks to the database, and the
-- only one whose failure mode is a hang instead of a message: the chunk index
-- arithmetic decides when to stop, so a chunk that never advances re-sends
-- itself forever. Everything the loop touches externally is stubbed, and the
-- stub answers synchronously so each case ends inside the spec's own call
-- stack.

local config = require("poste-db.config")
local real_state = require("poste-db.state")

local execute_import
local sent, logged, dialogs, done, result
local respond

--- Install the stubs and re-require the module under test. `poste-db.state`
--- keeps its real shape through a delegating metatable — `dml` and friends
--- reach the same module — and only `log` is silenced, so nothing is written
--- under `stdpath("state")`.
local function load_module()
  sent, logged, dialogs, done, result = {}, {}, {}, false, nil
  package.loaded["poste-db.exec_run"] = {
    run_async = function(sql, opts, handlers)
      if #sent > 30 then
        error("import did not terminate: more than 30 chunks were sent", 0)
      end
      sent[#sent + 1] = { sql = sql, opts = opts }
      handlers.on_response(respond(#sent, sql))
    end,
  }
  package.loaded["poste-db.edit_commit"] = {
    write_log = function(entry) logged[#logged + 1] = entry end,
  }
  package.loaded["poste-db.dialog"] = {
    open = function(spec)
      dialogs[#dialogs + 1] = spec
      return { update = function() end }
    end,
  }
  package.loaded["poste-db.state"] = setmetatable({ log = function() end }, { __index = real_state })
  package.loaded["poste-db.import.execute"] = nil
  execute_import = require("poste-db.import.execute").execute_import
end

local original_chunk

--- Each generated statement carries exactly one `INSERT INTO`, and the payload
--- here is a single integer column, so counting that counts statements.
local function statements(sql)
  local n = 0
  for _ in sql:gmatch("INSERT INTO ") do n = n + 1 end
  return n
end

local function table_info()
  return { name = "t", database = nil, connection = nil, dialect = "postgres", search_dir = "/tmp" }
end

local TABLE_COLS = { { name = "n", col_type = "int", is_pk = false } }

--- Rows are already coerced at this point, so plain single-column values do.
local function rows(count)
  local out = {}
  for i = 1, count do out[i] = { i } end
  return out
end

--- `affected_rows = 1` for every statement, which is what the "imported" count
--- sums.
local function all_ok()
  return function(_, sql)
    local results = {}
    for _ = 1, statements(sql) do results[#results + 1] = { affected_rows = 1 } end
    return { has_error = false, body = vim.json.encode({ results = results }) }
  end
end

--- Run an import and wait for its callback, which the module defers with
--- `vim.schedule`.
local function run(chunk_size, count)
  config.config.import_chunk_size = chunk_size
  execute_import(table_info(), rows(count), nil, TABLE_COLS, function(res)
    result = res
    done = true
  end)
  assert.is_true(vim.wait(2000, function() return done end, 5), "the import callback never ran")
  return result
end

describe("import execute chunking", function()
  -- plenary's busted shim only supports these inside a describe.
  before_each(function()
    load_module()
    original_chunk = config.config.import_chunk_size
  end)

  after_each(function()
    config.config.import_chunk_size = original_chunk
  end)

  it("sends one chunk per configured size and sums the affected rows", function()
    respond = all_ok()
    local res = run(2, 5)
    assert.equals(5, res.imported)
    assert.equals(3, #sent)
    assert.same({ 2, 2, 1 }, { statements(sent[1].sql), statements(sent[2].sql), statements(sent[3].sql) })
    assert.same({}, res.errors)
    -- One log entry per chunk, so a partial import is reconstructable.
    assert.equals(3, #logged)
    assert.same({ "success", "success", "success" }, { logged[1].status, logged[2].status, logged[3].status })
  end)

  -- `import_chunk_size` is documented user config with no validator, and a
  -- value below 1 made the end index precede the start: the chunk held no
  -- statement, `end_idx + 1` was `start_idx` again, and the loop re-sent the
  -- same empty chunk until Neovim was killed.
  it("clamps a zero chunk size to one statement per chunk", function()
    respond = all_ok()
    local res = run(0, 5)
    assert.equals(5, #sent)
    assert.equals(5, res.imported)
    assert.equals(1, statements(sent[1].sql))
  end)

  it("clamps a negative chunk size the same way", function()
    respond = all_ok()
    local res = run(-3, 2)
    assert.equals(2, #sent)
    assert.equals(2, res.imported)
  end)

  -- A non-numeric value used to reach `start_idx + chunk_size - 1` and throw
  -- mid-import, after earlier chunks had already been written to the database.
  it("falls back to the default when the size is not a number", function()
    respond = all_ok()
    local res = run("wide", 5)
    assert.equals(1, #sent)
    assert.equals(5, statements(sent[1].sql))
    assert.equals(5, res.imported)
  end)

  it("accepts a numeric string", function()
    respond = all_ok()
    local res = run("2", 5)
    assert.equals(3, #sent)
    assert.equals(5, res.imported)
  end)

  it("maps a per-statement error back to its absolute row number", function()
    respond = function(chunk_no, sql)
      local results = {}
      for _ = 1, statements(sql) do results[#results + 1] = { affected_rows = 1 } end
      -- Chunk 2 carries rows 3 and 4; flag its first statement.
      if chunk_no == 2 then
        results[1] = { error = "duplicate key value violates unique constraint" }
      end
      return { has_error = chunk_no == 2, body = vim.json.encode({ results = results }) }
    end
    local res = run(2, 5)
    assert.equals(1, #res.errors)
    assert.equals(3, res.errors[1].row)
    assert.equals(3, res.errors[1].chunk_start)
    assert.equals(4, res.errors[1].chunk_end)
    -- The failing statement reports no affected rows, so 4 of 5 landed.
    assert.equals(4, res.imported)
    assert.equals(1, #dialogs, "the grouped error dialog is what the user sees")
    assert.equals("Import Errors", dialogs[1].title)
    local statuses = {}
    for _, entry in ipairs(logged) do statuses[#statuses + 1] = entry.status end
    assert.same({ "success", "error", "success" }, statuses)
  end)
end)

--- What each chunk *says about itself* in the journal, and what the summary
--- claims. The chunk loop above decides when the import stops; these decide
--- whether a user who comes back an hour later can tell which rows landed.
describe("import chunk outcomes", function()
  local notices, notice_saved

  before_each(function()
    load_module()
    original_chunk = config.config.import_chunk_size
    notices = {}
    notice_saved = vim.notify
    vim.notify = function(msg, level) notices[#notices + 1] = { msg = msg, level = level } end
  end)

  after_each(function()
    vim.notify = notice_saved
    config.config.import_chunk_size = original_chunk
  end)

  it("names the failing statements in the chunk's journal entry", function()
    respond = function(chunk_no, sql)
      local results = {}
      for _ = 1, statements(sql) do results[#results + 1] = { affected_rows = 1 } end
      if chunk_no == 2 then
        results[1] = { error = "duplicate key value violates unique constraint \"t_pkey\"" }
        results[2] = { error = "null value in column \"n\" violates not-null constraint" }
      end
      return { has_error = chunk_no == 2, body = vim.json.encode({ results = results }) }
    end
    run(2, 4)
    assert.equals("success", logged[1].status)
    assert.equals("error", logged[2].status)
    -- The count is the chunk's own; the text is the first real server message,
    -- not a placeholder that says only "something here failed".
    assert.truthy(logged[2].error_msg)
    assert.equals("2 statement(s) in this chunk failed: duplicate key value violates unique constraint \"t_pkey\"",
      logged[2].error_msg)
    assert.is_nil(logged[1].error_msg)
  end)

  it("journals a failure it cannot read as an error, and still reports it", function()
    -- A response that arrived as a failure with a body that will not decode:
    -- nothing per-statement is knowable, but the chunk was rejected.
    respond = function() return { has_error = true, body = "{ not json" } end
    local res = run(2, 4)
    for i, entry in ipairs(logged) do
      assert.equals("error", entry.status, "chunk " .. i .. " was journaled as success")
      assert.equals("The chunk's response reported a failure and its results could not be read",
        entry.error_msg)
    end
    assert.equals(2, #res.errors, "one reported error per chunk")
    assert.equals(1, #dialogs)
    local last = notices[#notices]
    assert.equals(vim.log.levels.WARN, last.level)
    assert.truthy(last.msg:find("%(2 chunk%(s%) with errors%)"), last.msg)
  end)

  it("treats a statement error as a failure even without the aggregate flag", function()
    respond = function(chunk_no, sql)
      local results = {}
      for _ = 1, statements(sql) do results[#results + 1] = { affected_rows = 1 } end
      if chunk_no == 1 then results[1] = { error = "relation \"public.t\" does not exist" } end
      -- has_error deliberately false: the results are the evidence here.
      return { has_error = false, body = vim.json.encode({ results = results }) }
    end
    run(2, 2)
    assert.equals("error", logged[1].status)
    assert.truthy(logged[1].error_msg:find('relation "public.t" does not exist'))
  end)

  it("counts one chunk with several failures as one chunk in the summary", function()
    respond = function(chunk_no, sql)
      local results = {}
      for _ = 1, statements(sql) do results[#results + 1] = { affected_rows = 1 } end
      -- One chunk holding both rows, and both of them rejected.
      if chunk_no == 1 then
        for i = 1, #results do
          results[i] = { error = "check constraint \"ck_n\" is violated" }
        end
      end
      return { has_error = chunk_no == 1, body = vim.json.encode({ results = results }) }
    end
    local res = run(2, 2)
    assert.equals(2, #res.errors, "the two rejected statements")
    assert.equals(1, #logged)
    local last = notices[#notices]
    assert.truthy(last.msg:find("%(1 chunk%(s%) with errors%)"), last.msg)
    assert.is_nil(last.msg:find("%(2 chunk%(s%)"), nil, true)
  end)
end)
