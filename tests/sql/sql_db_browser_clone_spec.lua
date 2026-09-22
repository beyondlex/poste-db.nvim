-- Tests for lua/poste-db/db_browser/copy.lua clone helpers and the envelope
-- readers they share with catalog.lua. Pure helper tests (no real DB / no UI).

local copy = require("poste-db.db_browser.copy")
local sql_conn = require("poste-db.db_browser.sql_conn")
local t = copy._test

describe("db_browser clone pick_clone_default", function()
  it("returns base when free", function()
    assert.equals("blog_copy", t.pick_clone_default("blog_copy", {}))
    assert.equals("blog_copy", t.pick_clone_default("blog_copy", { other = true }))
  end)

  it("bumps to base2 when base taken", function()
    local existing = { blog_copy = true }
    assert.equals("blog_copy2", t.pick_clone_default("blog_copy", existing))
  end)

  it("skips occupied suffixes", function()
    local existing = { blog_copy = true, blog_copy2 = true }
    assert.equals("blog_copy3", t.pick_clone_default("blog_copy", existing))
  end)

  it("continues past gaps when a later suffix is taken", function()
    local existing = { blog_copy = true, blog_copy3 = true }
    assert.equals("blog_copy2", t.pick_clone_default("blog_copy", existing))
  end)
end)
describe("db_browser resolve_conflict_names", function()
  local target = { conn = "t", db = "other", dialect = "postgres" }

  local function with_hooked_exists(taken, fn)
    local calls = {}
    _G.poste_db_copy_test_hooks = {
      exists = function(_t, name, _schema, cb)
        calls[#calls + 1] = name
        cb(taken(name, #calls))
      end,
    }
    local ok, err = pcall(fn, calls)
    _G.poste_db_copy_test_hooks = nil
    assert(ok, tostring(err))
    return calls
  end

  it("keeps a free name and suffixes a colliding one", function()
    local resolved
    with_hooked_exists(function(name)
      return name == "posts" or name == "posts_copy" or name == "posts_copy2"
    end, function()
      copy.resolve_conflict_names(target, {
        { name = "posts" }, { name = "users" },
      }, function(names) resolved = names end, function() error("must not cancel") end,
      { skip_dialogs = true })
    end)
    -- posts bumps past both taken candidates; users is free on the first probe
    assert.are.same({ "posts_copy3", "users" }, resolved)
  end)

  it("resolves everything in one pass when no item collides", function()
    local resolved
    local calls = with_hooked_exists(function() return false end, function()
      copy.resolve_conflict_names(target, { { name = "a" }, { name = "b" } },
        function(names) resolved = names end, function() error("must not cancel") end,
        { skip_dialogs = true })
    end)
    assert.are.same({ "a", "b" }, resolved)
    assert.are.same({ "a", "b" }, calls)
  end)

  -- The existence probe fails closed: a query that errors (lost connection,
  -- revoked information_schema grant) reports "taken". Without a ceiling the
  -- suffix search re-probes forever and the paste never starts.
  it("stops bumping suffixes at the cap when every name reports taken", function()
    local resolved
    local calls = with_hooked_exists(function() return true end, function()
      copy.resolve_conflict_names(target, { { name = "posts" } },
        function(names) resolved = names end, function() error("must not cancel") end,
        { skip_dialogs = true })
    end)
    assert.equals(t.MAX_NAME_BUMPS + 1, #calls, "probe count must stop at the cap")
    assert.are.same({ "posts_copy" .. (t.MAX_NAME_BUMPS + 1) }, resolved)
  end)
end)

describe("db_browser default existence probe", function()
  -- Exercises the real probe (no `exists` hook): resolve_conflict_names must
  -- ask about the schema the paste writes into, and `dialect_table_exists_sql`
  -- already supports the argument — only the caller can drop it. The SQL text
  -- is the observable, so the transport is stubbed one level below.
  local original_run

  before_each(function() original_run = sql_conn.run end)
  after_each(function() sql_conn.run = original_run end)

  local function respond_with(taken_for)
    local seen = {}
    sql_conn.run = function(_conn, _db, sql, on_result)
      seen[#seen + 1] = sql
      local rows = taken_for(#seen) and "[[true]]" or "[]"
      on_result(vim.json.encode({ body = '{"results":[{"columns":["r"],"rows":' .. rows .. "}]}" }))
    end
    return seen
  end

  local always_free = function() return false end

  local function resolve(target, items)
    local resolved
    copy.resolve_conflict_names(target, items, function(names) resolved = names end,
      function() error("must not cancel") end, { skip_dialogs = true })
    return resolved
  end

  it("probes the item's schema on postgres", function()
    local seen = respond_with(always_free)
    resolve({ conn = "t", db = "app", dialect = "postgres" }, { { name = "users", schema = "app" } })
    assert.equals(1, #seen)
    assert.matches("table_schema = 'app'", seen[1])
    assert.matches("table_name = 'users'", seen[1])
  end)

  it("falls back to public when the item carries no schema", function()
    local seen = respond_with(always_free)
    resolve({ conn = "t", db = "blog", dialect = "postgres" }, { { name = "users" } })
    assert.matches("table_schema = 'public'", seen[1])
  end)

  it("keeps the schema on the bumped candidate too", function()
    -- users and users_copy taken, users_copy2 free.
    local seen = respond_with(function(i) return i <= 2 end)
    local names = resolve({ conn = "t", db = "app", dialect = "postgres" },
      { { name = "users", schema = "app" } })
    assert.are.same({ "users_copy2" }, names)
    assert.equals(3, #seen)
    assert.matches("table_schema = 'app'", seen[1])
    assert.matches("table_name = 'users_copy'", seen[2])
    assert.matches("table_schema = 'app'", seen[2])
  end)

  -- MySQL's SHOW CREATE TABLE emits an unqualified name, so the paste lands in
  -- the connection's current database and DATABASE() is the matching probe even
  -- if an item happens to carry a schema.
  it("probes the current database on mysql", function()
    local seen = respond_with(always_free)
    resolve({ conn = "t", db = "shop", dialect = "mysql" }, { { name = "users", schema = "shop" } })
    assert.matches("TABLE_SCHEMA = DATABASE%(%)", seen[1])
    assert.matches("TABLE_NAME = 'users'", seen[1])
  end)
end)

describe("db_browser copy progress spinner", function()
  local function collect_dialog_lines()
    local lines = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(buf) then
        for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          table.insert(lines, l)
        end
      end
    end
    return lines
  end

  it("renders an animated spinner frame while a job is copying", function()
    local source = { conn = "s", db = "blog", dialect = "postgres" }
    local target = { conn = "t", db = "other", dialect = "postgres" }
    local jobs = {
      { label = "posts", work = function(cb)
          vim.defer_fn(function() cb(true, "100", "12ms") end, 400)
        end },
    }
    local start_fn = t.show_paste_progress(source, target, jobs, function() end)
    start_fn()

    local frames = require("poste-db.constants").SPINNER_FRAMES
    local observed = nil
    vim.wait(200, function()
      for _, l in ipairs(collect_dialog_lines()) do
        for _, ch in ipairs(frames) do
          if l:find(ch, 1, true) then observed = ch; return true end
        end
      end
      return false
    end)
    assert.is_not_nil(observed, "expected a spinner frame in the dialog while copying")

    -- After the job completes, the spinner is replaced by the success marker.
    vim.wait(600, function()
      for _, l in ipairs(collect_dialog_lines()) do
        if l:find("✓", 1, true) then return true end
      end
      return false
    end)
    local done = false
    for _, l in ipairs(collect_dialog_lines()) do
      if l:find("✓", 1, true) then done = true end
    end
    assert.is_true(done, "expected a ✓ success marker after job completion")

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      pcall(vim.api.nvim_win_close, win, true)
    end
  end)
end)

describe("db_browser copy progress cancel", function()
  local function collect_dialog_lines()
    local lines = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(buf) then
        for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          table.insert(lines, l)
        end
      end
    end
    return lines
  end

  local function close_all_floats()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win)
        and pcall(vim.api.nvim_win_get_config, win)
        and vim.api.nvim_win_get_config(win).relative ~= "" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end

  it("exposes a cancel handle and stops the queue without running later jobs", function()
    local source = { conn = "s", db = "blog", dialect = "postgres" }
    local target = { conn = "t", db = "other", dialect = "postgres" }
    local ran = {}
    local gate -- first job signals once it has STARTED, then we cancel
    local jobs = {
      { label = "first", work = function(cb)
          ran[#ran + 1] = "first"
          gate = true
          vim.defer_fn(function() cb(true, "1", "1ms") end, 50)
        end },
      { label = "second", work = function(cb)
          ran[#ran + 1] = "second"
          cb(true, "2", "2ms")
        end },
    }
    local on_close_called = false
    local start_fn, cancel_fn = t.show_paste_progress(source, target, jobs, function()
      on_close_called = true
    end)
    assert.is_function(start_fn)
    assert.is_function(cancel_fn, "show_paste_progress must return a cancel handle")
    start_fn()

    vim.wait(1000, function() return gate == true end)
    cancel_fn()  -- queue must stop after the in-flight job

    vim.wait(600, function() return on_close_called end)
    close_all_floats()
    assert.is_true(on_close_called, "cancel must close the dialog (firing on_close)")
    assert.are.same({ "first" }, ran, "jobs after cancel must not start")
  end)

  it("renders the cancel hint while jobs are pending", function()
    local source = { conn = "s", db = "blog", dialect = "postgres" }
    local target = { conn = "t", db = "other", dialect = "postgres" }
    local release
    local jobs = {
      { label = "hold", work = function(cb) release = cb end },
      { label = "next", work = function(cb) cb(true, "2", "2ms") end },
    }
    local start_fn = t.show_paste_progress(source, target, jobs, function() end)
    start_fn()

    local hinted = false
    vim.wait(500, function()
      for _, l in ipairs(collect_dialog_lines()) do
        if l:find("[c] cancel", 1, true) then hinted = true; return true end
      end
      return false
    end)
    assert.is_true(hinted, "pending copy must show the [c] cancel hint")
    if release then release(true, "1", "1ms") end
    close_all_floats()
  end)
end)

--- `check_response` is what stands between a rejected statement and clone
--- reporting "copied": the envelope it inspects is the JSON `exec_run` builds,
--- whose failure flag and per-statement text are separate fields.
describe("db_browser copy check_response", function()
  --- @param resp table an `exec_run` response, body already a JSON string
  local function envelope(resp) return vim.json.encode(resp) end

  local function body(results, extra)
    local obj = vim.tbl_extend("force", { type = "affected", results = results }, extra or {})
    return vim.json.encode(obj)
  end

  local function run(results, resp_extra, body_extra)
    local err
    local ok, decoded = t.check_response(
      envelope(vim.tbl_extend("force", {
        status = (resp_extra or {}).has_error and "error" or "ok",
        body = body(results, body_extra),
      }, resp_extra or {})), "INSERT", function(message) err = message end)
    return ok, err, decoded
  end

  it("accepts a clean statement and hands back the decoded body", function()
    local ok, err, decoded = run({ { affected_rows = 3 } })
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(3, decoded.results[1].affected_rows)
  end)

  it("surfaces the statement's own error text", function()
    local ok, err = run({ { error = "column \"b\" is of type integer" } })
    assert.is_false(ok)
    assert.equals('column "b" is of type integer', err)
  end)

  -- The flag without the text: a driver that marks the result failed without
  -- filling in `error` used to land on the caller's success path, because the
  -- only thing read was `results[1].error`.
  it("rejects a failure flag that carries no statement message", function()
    local ok, err = run({ { affected_rows = 0 } }, { has_error = true })
    assert.is_false(ok)
    assert.truthy(err:find("no message", 1, true))
  end)

  -- A multi-statement envelope flags the aggregate while an earlier result is
  -- clean; the first result is not the one that failed.
  it("rejects a batch that failed on a later statement", function()
    local ok, err = run({ { affected_rows = 1 }, { affected_rows = 0 } }, { has_error = true },
      { has_error = true })
    assert.is_false(ok)
    assert.is_truthy(err)
  end)

  it("reports an undecodable envelope instead of assuming success", function()
    local err
    local ok = t.check_response("not json at all", "DDL", function(message) err = message end)
    assert.is_false(ok)
    assert.equals("Failed to parse DDL response", err)
  end)
end)

--- The clone wizard's listing reads the same envelope as its writes, through
--- `sql_conn.decode_first_result`.
describe("db_browser sql_conn decode_first_result", function()
  local function envelope(results, resp_extra, body_extra)
    local body = vim.tbl_extend("force", { type = "resultset", results = results }, body_extra or {})
    return vim.json.encode(vim.tbl_extend("force", {
      status = (resp_extra or {}).has_error and "error" or "ok",
      body = vim.json.encode(body),
    }, resp_extra or {}))
  end

  it("returns the first result of a clean response", function()
    local ok, r = sql_conn.decode_first_result(envelope({ { columns = { { name = "a" } }, rows = { { 1 } } } }))
    assert.is_true(ok)
    assert.equals("a", r.columns[1].name)
  end)

  it("surfaces the statement's own error text", function()
    local ok, err = sql_conn.decode_first_result(envelope({ { error = "permission denied" } }))
    assert.is_false(ok)
    assert.equals("permission denied", err)
  end)

  it("rejects a failure flag that carries no statement message", function()
    local ok, err = sql_conn.decode_first_result(envelope({ { columns = {}, rows = {} } }, { has_error = true }))
    assert.is_false(ok)
    assert.truthy(err:find("no message", 1, true))
  end)
end)
