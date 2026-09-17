--- session_conn pool keying: one session per (connection, database) pair.
--- The pool used to key on the bare connection URL, so two buffers using the
--- same connection with different @database directives shared the first
--- session — the second silently executed against the wrong database.

describe("poste-db.session_conn", function()
  local state = require("poste-db.state")
  local session_conn = require("poste-db.session_conn")

  local jobs
  local real_binary_lookup
  local real_jobstart, real_jobwait, real_chansend

  before_each(function()
    jobs = {}
    real_binary_lookup = state.find_poste_binary
    state.find_poste_binary = function() return "/fake/poste" end
    real_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, opts)
      local id = 1000 + vim.tbl_count(jobs)
      jobs[id] = { cmd = cmd, opts = opts }
      return id
    end
    real_jobwait = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    real_chansend = vim.fn.chansend
    vim.fn.chansend = function() return 10 end
  end)

  after_each(function()
    session_conn.stop_all()
    state.find_poste_binary = real_binary_lookup
    vim.fn.jobstart = real_jobstart
    vim.fn.jobwait = real_jobwait
    vim.fn.chansend = real_chansend
  end)

  it("pools one session per connection+database pair", function()
    local a = session_conn.get("postgres://h/app", nil, "db1")
    local b = session_conn.get("postgres://h/app", nil, "db2")
    local a_again = session_conn.get("postgres://h/app", nil, "db1")
    assert.are.equal(a, a_again, "same pair must reuse the pooled session")
    assert.are_not.equal(a, b, "a different database must get its own session")
    assert.are.equal(2, vim.tbl_count(jobs))
    assert.are.equal("db1", a.database)
    assert.are.equal("db2", b.database)
  end)

  it("stops every database-scoped session of a connection by bare URL", function()
    session_conn.get("postgres://h/app", nil, "db1")
    session_conn.get("postgres://h/app", nil, "db2")
    session_conn.get("postgres://h/other", nil, nil)
    session_conn.stop("postgres://h/app")
    assert.are.equal(1, vim.tbl_count(session_conn.list()))
  end)

  it("execute dispatches on the requested database's session", function()
    local status = session_conn.execute("postgres://h/app", "SELECT 1", {}, nil, "dbA")
    assert.are.equal("dispatched", status)
    status = session_conn.execute("postgres://h/app", "SELECT 1", {}, nil, "dbB")
    assert.are.equal("dispatched", status)
    assert.are.equal(2, vim.tbl_count(jobs))
  end)

  local function arg_value(cmd, flag)
    for i, v in ipairs(cmd) do
      if v == flag then return cmd[i + 1] end
    end
    return nil
  end

  it("passes opts.session_max_rows to the session command", function()
    local config = require("poste-db.config")
    local saved = config.config.session_max_rows
    config.config.session_max_rows = 500
    local ok, session = pcall(session_conn.get, "postgres://h/capped", nil, "db1")
    config.config.session_max_rows = saved
    assert.is_true(ok)
    assert.equals("500", arg_value(jobs[session.job_id].cmd, "--max-rows"))
  end)

  it("keeps --max-rows unlimited (0) by default and guards bad values", function()
    local config = require("poste-db.config")
    local saved = config.config.session_max_rows
    config.config.session_max_rows = -3
    local a = session_conn.get("postgres://h/guarded", nil, "db1")
    assert.equals("0", arg_value(jobs[a.job_id].cmd, "--max-rows"), "negative caps back to unlimited")
    config.config.session_max_rows = "lots"
    local b = session_conn.get("postgres://h/guarded", nil, "db2")
    assert.equals("0", arg_value(jobs[b.job_id].cmd, "--max-rows"), "non-number falls back to unlimited")
    config.config.session_max_rows = saved
  end)

  it("never passes the URL-inferred database as --database (sqlite file corrupt)", function()
    -- regression: the sqlite stem inferred from the URL was passed as
    -- --database, and the binary's replace_database_in_url swapped it for
    -- the URL's last path segment — `sqlite:///d/test.sqlite` re-opened as
    -- `sqlite:///d/test`, a fresh EMPTY database, silently.
    local a = session_conn.get("sqlite:///d/test.sqlite", nil, nil)
    assert.is_nil(arg_value(jobs[a.job_id].cmd, "--database"))
    -- an EXPLICIT database (an @database directive) still overrides
    local b = session_conn.get("postgres://h/app", nil, "override_db")
    assert.equals("override_db", arg_value(jobs[b.job_id].cmd, "--database"))
    -- pool keying keeps the inferred name for display purposes
    assert.equals("test", a.database)
  end)
end)

describe("session_conn database_from_url", function()
  local session_conn = require("poste-db.session_conn")
  local from_url = session_conn._test.database_from_url

  it("strips the query string from the database name", function()
    -- `db?schema=public` used to display (and pool-key) with the query riding
    -- along; the sqlite variant named a database "file.sqlite?mode=rwc"
    assert.equals("db", from_url("postgres://u:p@h:5432/db?schema=public"))
    assert.equals("file", from_url("sqlite:/tmp/x/file.sqlite?mode=rwc"))
  end)

  it("returns nil rather than password fragments for a db-less url", function()
    -- a `/` inside the password with no db path used to leak `p/ss@h:3306`
    assert.is_nil(from_url("mysql://u:p/ss@h:3306"))
    -- a real db path after a slash-y password still resolves
    assert.equals("blog", from_url("mysql://u:p/ss@h:3306/blog"))
  end)
end)
