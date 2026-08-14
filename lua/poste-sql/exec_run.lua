--- SQL execution via `poste exec-file`.
---
--- The Rust CLI replaced the `run` subcommand with `exec-file` (streaming
--- `progress`/`result`/`summary` events, file-based, no `--stdin`). This
--- module wraps `exec-file` — writing the SQL to a temp file, streaming the
--- events — and reconstructs the legacy single-JSON "response" shape that the
--- rest of the SQL plugin consumes (`resp.body` decodes to
--- `{ type, results, has_error, ... }`).
---
--- Depends on poste.nvim shared infra: `poste.cli`, `poste.state`.

local cli = require("poste.cli")
local state = require("poste.state")

local M = {}

----------------------------------------------------------------------------
-- Temp file
----------------------------------------------------------------------------

--- Remove the `###` section markers that sql_runner's synthetic-block wrapping
--- inserts (the Rust CLI cannot parse them as SQL). `-- @` directives are kept:
--- exec-file strips those itself.
local function strip_section_markers(sql)
  local filtered = {}
  for _, l in ipairs(vim.split(sql, "\n", { plain = true })) do
    if not l:match("^%s*###%s*$") then filtered[#filtered + 1] = l end
  end
  return table.concat(filtered, "\n")
end

--- Write SQL content to a temp `.sql` file. Prefers the source file's
--- directory so `connections.json` discovery works for bare `@connection`
--- names (echoes the `.poste_refresh_*.sql` pattern). Returns the path.
---
--- `###` section markers (from statement.lua's synthetic-block wrapping) are
--- stripped before exec-file parses the file; the Rust CLI only strips `-- @`
--- directives, and a statement left starting with `###` would be misclassified
--- as a non-query (DML) and rendered as "Query OK".
local function write_temp_file(sql, src_file)
  local lines = vim.split(strip_section_markers(sql), "\n", { plain = true })
  local tmp = vim.fn.tempname() .. ".sql"
  vim.fn.writefile(lines, tmp)
  return tmp
end

----------------------------------------------------------------------------
-- USE statement detection
----------------------------------------------------------------------------

--- Detect a lone `USE <db>;` statement (exec-file skips USE statements, so we
--- handle context switching without hitting the database).
--- @param sql string
--- @return string|nil database_name
local function detect_use(sql)
  local trimmed = sql:match("^%s*(.*)%s*$") or ""
  local name = trimmed:match("^USE%s+([%w_]+)%s*;?%s*$")
  if not name then
    name = trimmed:match("^USE%s+[\"`]([%w_]+)[\"`]%s*;?%s*$")
  end
  if not name then
    name = trimmed:match("^USE%s+[%w_]+%s*%-%-.*$")
  end
  return name
end

----------------------------------------------------------------------------
-- Command construction
----------------------------------------------------------------------------

--- Build `exec-file` args (binary is prepended by cli.run_async).
local function build_cmd(tmpfile, opts)
  local cmd = {
    "exec-file", tmpfile,
    "--env", state.current_env or "dev",
    "--mode", opts.mode or "greedy",
    "--json",
  }
  local timeout = opts.timeout
  if timeout then
    table.insert(cmd, "--timeout"); table.insert(cmd, tostring(timeout))
  end
  -- 0 = unlimited, so client-side dataset pagination keeps working.
  local max_rows = opts.max_rows
  if max_rows == nil then max_rows = 0 end
  table.insert(cmd, "--max-rows"); table.insert(cmd, tostring(max_rows))
  if opts.conn_url and opts.conn_url ~= "" then
    table.insert(cmd, "--connection"); table.insert(cmd, opts.conn_url)
  end
  if opts.database and opts.database ~= "" then
    table.insert(cmd, "--database"); table.insert(cmd, opts.database)
  end
  return cmd
end

-- Normalize an `affected_rows` value from the event stream (number → number,
-- JSON null → nil).
local function norm_affected(v)
  if v == nil or v == vim.NIL then return nil end
  return tonumber(v)
end

-- The `exec-file` result event carries the SQL text; use its leading keyword to
-- tell a query apart from a DML even when the binary/driver reports
-- `affected_rows` as a number (not null) and omits columns/rows for a SELECT.
local QUERY_PREFIXES = {
  "SELECT", "WITH", "EXPLAIN", "SHOW", "VALUES", "PRAGMA", "DESCRIBE",
  "TABLE", "DESC", "RETURNING", "CALL", "EXEC",
}
local function is_query_sql(sql)
  if not sql or sql == "" then return false end
  local head = sql:gsub("^%s*([A-Za-z]+).*", "%1"):upper()
  for _, p in ipairs(QUERY_PREFIXES) do
    if head == p or sql:find("RETURNING", 1, true) then return true end
  end
  return false
end

----------------------------------------------------------------------------
-- Response reconstruction
----------------------------------------------------------------------------

--- Accumulate `result`/`summary` events into a legacy-shaped resp object.
--- @param conn string resolved connection URL (fallback label)
--- @param shown_db string
local function build_response(events, conn, shown_db)
  local results = {}
  local total_ms = 0
  local dialect = ""
  local connection = conn or ""
  local database = shown_db or ""
  local failed = 0
  local total_rows = 0
  local total_affected = 0

  for _, ev in ipairs(events) do
    if ev.type == "result" then
      local res = {
        columns = ev.columns or {},
        rows = ev.rows or {},
        row_count = tonumber(ev.row_count) or 0,
        affected_rows = norm_affected(ev.affected_rows),
        execution_time_ms = tonumber(ev.execution_time_ms) or 0,
      }
      if ev.error and ev.error ~= "" then res.error = ev.error end
      if ev.sql and ev.sql ~= "" then res.sql = ev.sql end
      table.insert(results, res)
      if ev.status ~= "ok" then failed = failed + 1 end
      if res.affected_rows then total_affected = total_affected + res.affected_rows end
    elseif ev.type == "summary" then
      total_ms = tonumber(ev.total_time_ms) or 0
      dialect = ev.dialect or dialect
      connection = ev.connection or connection
      database = ev.database or database
    end
  end

  -- Match legacy classification: a resultset if any result is a query (has
  -- columns, or returned rows, or no affected_rows), else an affected-rows
  -- response. Keying off column presence (not just affected_rows == nil)
  -- guards against a driver/binary reporting affected_rows as 0 for a SELECT,
  -- which would otherwise be misclassified as an affected/Query OK response.
  local is_query = false
  for _, r in ipairs(results) do
    if r.error then
      failed = failed + 1
    elseif r.affected_rows == nil or (r.row_count or 0) > 0 or #(r.columns or {}) > 0
      or is_query_sql(r.sql or "") then
      is_query = true
    end
    total_rows = total_rows + (r.row_count or 0)
  end
  local has_error = failed > 0

  local body_obj = {
    type = is_query and "resultset" or "affected",
    results = results,
    total_results = #results,
    total_rows = total_rows,
    total_affected = total_affected,
    total_execution_time_ms = total_ms,
    connection = connection,
    database = database,
    dialect = dialect,
  }
  if has_error then body_obj.has_error = true end

  return {
    status = has_error and "error" or "ok",
    latency_ms = total_ms,
    body = vim.json.encode(body_obj),
    connection = connection,
    database = database,
    dialect = dialect,
    results = results,
    has_error = has_error,
  }
end

---------------------------------------------------------------------------
-- Event decoding
---------------------------------------------------------------------------

--- `jobstart` with buffered stdout delivers each JSON event as its own element
--- of the `data` array (newlines already stripped, with a trailing `""`), so we
--- parse each non-empty element directly rather than reassembling lines.
local function for_each_event(data, on_event)
  if not data then return end
  for _, line in ipairs(data) do
    if line ~= "" then
      local ok, event = pcall(vim.json.decode, line)
      if ok and type(event) == "table" then on_event(event) end
    end
  end
end

---------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------

--- Parse a full stdout blob (newline-separated JSON events) into events.
local function parse_lines(output)
  local events = {}
  if not output or output == "" then return events end
  for _, line in ipairs(vim.split(output, "\n", { plain = true })) do
    if line ~= "" then
      local ok, event = pcall(vim.json.decode, line)
      if ok and type(event) == "table" then events[#events + 1] = event end
    end
  end
  return events
end

--- Build the legacy-shaped response for a lone USE statement.
local function make_use_response(use_db)
  return {
    status = "ok",
    latency_ms = 0,
    body = vim.json.encode({
      type = "use",
      database_name = use_db,
      is_use_statement = true,
      connection = "",
      dialect = "",
    }),
    connection = "",
    database = use_db,
    dialect = "",
  }
end

--- Run SQL synchronously via `exec-file`, returning a legacy-shaped response
--- (or nil on failure). Calls are blocking — for non-interactive/introspection
--- queries where the caller needs the result inline.
--- @param sql string
--- @param opts table  same as run_async (src_file, conn_url, database, mode, timeout, max_rows)
local function run_sql(sql, opts)
  opts = opts or {}
  local use_db = detect_use(sql)
  if use_db and not opts.conn_url and not opts.database then
    return make_use_response(use_db)
  end
  local binary = state.find_poste_binary()
  if not binary then return nil end
  local tmpfile = write_temp_file(sql, opts.src_file or (opts.conn_url and vim.fn.tempname() .. ".sql" or nil))
  local cmd = vim.list_extend({ binary }, build_cmd(tmpfile, opts))
  local ok_sys, result_obj = pcall(vim.system, cmd, { timeout = 30000 })
  if not ok_sys then pcall(vim.fn.delete, tmpfile); return nil end
  local result = result_obj:wait()
  pcall(vim.fn.delete, tmpfile)
  if result.code ~= 0 then return nil end
  local events = parse_lines(result.stdout)
  if #events == 0 then return nil end
  return build_response(events, opts.conn_url, opts.database)
end

--- Run SQL asynchronously via `exec-file`.
--- @param sql string SQL content to execute
--- @param opts table
---   - src_file: string|nil  source buffer path (for temp-file placement/discovery)
---   - conn_url: string|nil  resolved connection URL ("--connection")
---   - database: string|nil  database override
---   - mode: "greedy"|"transaction"
---   - timeout, max_rows: number|nil
---   - on_response: function(resp)
---   - on_progress: function(seq, total)|nil
---   - on_error: function(message, stderr)|nil   called when the process itself fails
local function run_async(sql, opts, callbacks)
  opts = opts or {}
  callbacks = callbacks or {}
  local on_response = callbacks.on_response
  local on_error = callbacks.on_error

  -- Lone USE statement: handled locally (exec-file skips USE).
  local use_db = detect_use(sql)
  if use_db and not opts.conn_url and not opts.database then
    local resp = {
      status = "ok",
      latency_ms = 0,
      body = vim.json.encode({
        type = "use",
        database_name = use_db,
        is_use_statement = true,
        connection = opts.conn_url or "",
        dialect = "",
      }),
      connection = opts.conn_url or "",
      database = use_db,
      dialect = "",
    }
    if on_response then on_response(resp) end
    return 1
  end

  local binary = state.find_poste_binary()
  if not binary then
    if on_error then on_error("Poste binary not found", "") end
    return nil
  end

  local src_file = opts.src_file
  local tmpfile = write_temp_file(sql, src_file)

  local cmd = build_cmd(tmpfile, opts)
  local log = require("poste-sql.log")
  log.info("exec-run cmd: " .. log.redact_cmd(cmd))

  local events = {}
  local stderr_buf = {}
  local summary_seen = false

  local job_id

  local function flush_and_deliver()
    local resp = build_response(events, opts.conn_url, opts.database)
    if on_response then on_response(resp) end
  end

  job_id = cli.run_async(cmd, {
    on_stdout = function(data)
      if not data or #data == 0 then return end
      for_each_event(data, function(event)
        if event.type == "result" then
          events[#events + 1] = event
          if callbacks.on_progress then callbacks.on_progress(event.seq, event.total) end
        elseif event.type == "summary" then
          events[#events + 1] = event
          summary_seen = true
          vim.schedule(function()
            pcall(vim.fn.delete, tmpfile)
            flush_and_deliver()
          end)
        end
      end)
    end,
    on_stderr = function(data)
      if not data then return end
      for _, l in ipairs(data) do
        if l ~= "" then table.insert(stderr_buf, l) end
      end
    end,
    on_exit = function(code)
      vim.schedule(function()
        pcall(vim.fn.delete, tmpfile)
        if not summary_seen and on_error then
          local text = table.concat(stderr_buf, "\n")
          on_error(text ~= "" and text or ("exit code " .. code), text)
        end
      end)
    end,
  })

  return job_id
end

return {
  run_async = run_async,
  run_sql = run_sql,
  detect_use = detect_use,
  build_response = build_response,
  for_each_event = for_each_event,
  is_query_sql = is_query_sql,
  strip_section_markers = strip_section_markers,
}