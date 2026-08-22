--- Persistent SQL session connection management.
---
--- Each session runs `poste session --connection <url>` as a long-lived
--- process that keeps a database connection open across requests. This lets
--- session variables (`SET @a=1; SELECT @a;`), temporary tables, and `USE db`
--- persist across separate `<CR>` executions.
---
--- Sessions are pooled keyed by `connection_url` and shared across buffers.

local state = require("poste.state")

local M = {}

-- pool[connection_url] = {
--   job_id  = number,
--   conn_url = string,
--   dialect = string,
--   database = string,
--   bufs    = { [bufnr] = true },
--   seq     = number,
--   pending = { [seq] = { on_response = fn, on_error = fn } },
--   buffer  = string,   -- partial stdout line buffer
--   alive   = boolean,
-- }
local pool = {}

-- Mapping connection URL prefix → dialect name
local function dialect_from_url(url)
  if url:match("^sqlite:") then return "sqlite" end
  if url:match("^mysql://") then return "mysql" end
  if url:match("^postgres://") or url:match("^postgresql://") then return "postgres" end
  return "unknown"
end

-- Extract database name from connection URL for display.
local function database_from_url(url)
  if url:match("^sqlite:") then
    local rest = url:gsub("^sqlite:", ""):gsub("^/+", "")
    if rest == ":memory:" or rest == "" then return nil end
    local stem = rest:match("([^/]+)%.sqlite$") or rest:match("([^/]+)$")
    return stem
  end
  local scheme_end = url:find("://")
  if scheme_end then
    local after = url:sub(scheme_end + 3)
    local last_slash = after:match(".*()/")
    if last_slash then
      local db = after:sub(last_slash + 1)
      if db ~= "" then return db end
    end
  end
  return nil
end

local function norm_affected(v)
  if v == nil or v == vim.NIL then return nil end
  return tonumber(v)
end

local function build_response(event, session)
  local has_err = event.status ~= "ok"
  local aff = norm_affected(event.affected_rows)
  local is_query = aff == nil
  local results = { {
    columns = event.columns or {},
    rows = event.rows or {},
    row_count = tonumber(event.row_count) or 0,
    affected_rows = aff,
    execution_time_ms = tonumber(event.execution_time_ms) or 0,
  } }
  if has_err then results[1].error = event.error or "unknown error" end
  if event.sql and event.sql ~= "" then results[1].sql = event.sql end

  local body_obj = {
    type = is_query and "resultset" or "affected",
    results = results,
    total_results = 1,
    total_rows = tonumber(event.row_count) or 0,
    total_affected = (not has_err and aff) or 0,
    total_execution_time_ms = tonumber(event.execution_time_ms) or 0,
    connection = session.conn_url,
    database = session.database or "",
    dialect = session.dialect,
  }
  if has_err then body_obj.has_error = true end

  return {
    status = has_err and "error" or "ok",
    latency_ms = tonumber(event.execution_time_ms) or 0,
    body = vim.json.encode(body_obj),
    connection = session.conn_url,
    database = session.database,
    dialect = session.dialect,
    results = results,
    has_error = has_err,
  }
end

local function process_event(session, event)
  local cb = session.pending[event.seq]
  if cb then
    session.pending[event.seq] = nil
    state.log("DEBUG", "SQL session callback found for seq=" .. tostring(event.seq))
    local resp = build_response(event, session)
    local ok_cb, err = pcall(function()
      if resp.has_error then
        if cb.on_sql_error then cb.on_sql_error(event.error or "unknown error", resp) end
      else
        if cb.on_response then cb.on_response(resp) end
      end
    end)
    if not ok_cb then
      state.log("ERROR", "SQL session callback error: " .. tostring(err))
    end
  end
end

local function process_line(session, line)
  local ok, event = pcall(vim.json.decode, line)
  if ok and type(event) == "table" and event.type == "result" then
    process_event(session, event)
  end
end

local function on_session_stdout(session, chunks)
  local combined = table.concat(chunks, "")
  state.log("DEBUG", "SQL session stdout (" .. #combined .. " bytes)")
  session.buffer = session.buffer .. combined
  -- Each response from the Rust session is a single JSON line, but Neovim may
  -- deliver it with or without the trailing newline (or split across chunks).
  local pos = 1
  while true do
    -- Try newline-based parsing first
    local nl = session.buffer:find("\n", pos, true)
    if nl then
      local line = session.buffer:sub(pos, nl - 1)
      pos = nl + 1
      if line ~= "" then
        process_line(session, line)
      end
    else
      -- No newline found. Try to parse the remaining buffer as a complete JSON
      -- object (in case Neovim stripped the newline).
      local remaining = session.buffer:sub(pos)
      if remaining ~= "" then
        local ok, event = pcall(vim.json.decode, remaining)
        if ok and type(event) == "table" and event.type == "result" then
          process_event(session, event)
          session.buffer = ""
        else
          -- Incomplete data, keep the buffer for the next chunk
          session.buffer = remaining
        end
      else
        session.buffer = ""
      end
      break
    end
  end
end

local function on_session_exit(session, code)
  session.alive = false
  -- Fail all pending requests
  for seq, cb in pairs(session.pending) do
    session.pending[seq] = nil
    if cb.on_error then cb.on_error("SQL session exited (code " .. code .. ")") end
  end
  -- Remove from pool if still referenced
  if pool[session.conn_url] == session then
    pool[session.conn_url] = nil
  end
end

local function start(conn_url, database)
  local binary = state.find_poste_binary()
  if not binary then return nil end

  local db = database or database_from_url(conn_url)
  local session = {
    job_id = nil,
    conn_url = conn_url,
    dialect = dialect_from_url(conn_url),
    database = db,
    bufs = {},
    seq = 0,
    pending = {},
    buffer  = "",
    alive = true,
  }

  local cmd = { binary, "session", "--connection", conn_url, "--max-rows", "0", "--timeout", "0" }
  if db then
    table.insert(cmd, "--database"); table.insert(cmd, db)
  end
  local job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    stdout_buffered = false,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then on_session_stdout(session, data) end
    end,
    on_stderr = function(_, data)
      if data then
        for _, l in ipairs(data) do
          if l ~= "" then state.log("WARN", "SQL session stderr: " .. l) end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function() on_session_exit(session, code) end)
    end,
  })

  if job_id <= 0 then return nil end
  session.job_id = job_id
  pool[conn_url] = session
  return session
end

--- Get the session for a connection_url, starting one if needed.
--- @param conn_url string
--- @param bufnr number|nil buffer that will use this session
--- @param database string|nil database context to connect to (default: from URL)
--- @return table|nil session
function M.get(conn_url, bufnr, database)
  local session = pool[conn_url]
  if not session or not session.alive then
    session = start(conn_url, database)
    if not session then return nil end
  end
  if bufnr then session.bufs[bufnr] = true end
  return session
end

--- Send SQL to the session for a connection, executing it on the persistent
--- connection. Starts a session if none exists.
--- @param conn_url string
--- @param sql string
--- @param callbacks table { on_response = fn(parsed), on_error = fn(msg), on_sql_error = fn(msg, parsed?) }
--- @param bufnr number|nil
--- @param database string|nil database context (e.g. from `@database` directive)
--- @return string  "dispatched", "start_failed", or "not_running"
function M.execute(conn_url, sql, callbacks, bufnr, database)
  callbacks = callbacks or {}
  local session = M.get(conn_url, bufnr, database)
  if not session then
    return "start_failed"
  end
  if not session.alive then
    return "not_running"
  end

  session.seq = session.seq + 1
  local seq = session.seq
  session.pending[seq] = {
    on_response = callbacks.on_response,
    on_error = callbacks.on_error,
    on_sql_error = callbacks.on_sql_error,
  }
  local payload = vim.json.encode({ seq = seq, sql = sql }) .. "\n"
  local sent = vim.fn.chansend(session.job_id, payload)
  state.log("DEBUG", string.format("SQL session send seq=%d job=%d chansend=%d", seq, session.job_id, sent))
  state.log("DEBUG", "SQL session payload: " .. (sql and sql:sub(1, 300):gsub("\n", "\\n") or "nil"))
  if sent <= 0 then
    session.pending[seq] = nil
    if callbacks.on_error then callbacks.on_error("SQL session chansend failed") end
    return "not_running"
  end
  state.log("DEBUG", string.format("SQL session send seq=%d job=%d chansend=%d", seq, session.job_id, sent))
  return "dispatched"
end

--- Close a session for a connection_url.
--- @param conn_url string
function M.stop(conn_url)
  local session = pool[conn_url]
  if not session then return end
  session.alive = false
  pool[conn_url] = nil
  if session.job_id and vim.fn.jobwait({ session.job_id }, 0)[1] == -1 then
    pcall(vim.fn.chansend, session.job_id, "")
    pcall(vim.fn.chanclose, session.job_id, "stdin")
  end
end

--- Close all sessions.
function M.stop_all()
  for conn_url in pairs(pool) do
    M.stop(conn_url)
  end
end

--- Remove a buffer from all sessions; close sessions with no remaining buffers.
--- @param bufnr number
function M.cleanup_buf(bufnr)
  for conn_url, session in pairs(pool) do
    session.bufs[bufnr] = nil
    if not next(session.bufs) then
      M.stop(conn_url)
    end
  end
end

--- List active sessions (for debugging / :PosteDbSessionList).
--- @return { [conn_url] = { job_id, dialect } }
function M.list()
  local out = {}
  for conn_url, session in pairs(pool) do
    out[conn_url] = { job_id = session.job_id, dialect = session.dialect }
  end
  return out
end

M._test = {
  dialect_from_url = dialect_from_url,
  database_from_url = database_from_url,
  build_response = build_response,
}

return M