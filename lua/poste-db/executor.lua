local state = require("poste.state")
local config = require("poste-db.config")
local session_conn = require("poste-db.session_conn")
local exec_run = require("poste-db.exec_run")
local log = require("poste-db.log")

local M = {}

local function default_max_rows()
  return config.config.default_max_rows or 0
end

function M.execute(opts)
  opts = opts or {}
  local sql = opts.sql
  local conn_url = opts.conn_url
  local database = opts.database
  local mode = opts.mode or "greedy"
  local max_rows = opts.max_rows
  if max_rows == nil then max_rows = default_max_rows() end
  local on_response = opts.on_response
  local on_error = opts.on_error
  local prefer_session = opts.prefer_session
  if prefer_session == nil then prefer_session = true end
  local src_buf = opts.src_buf
  local src_file = opts.src_file

  local fallback_used = false
  local function exec_file_fallback(msg)
    if fallback_used then return end
    fallback_used = true
    log.warn("SQL session failed, falling back to exec-file: " .. msg)
    log.debug("SQL via exec-file (fallback): " .. (sql and sql:sub(1, 200):gsub("\n", "\\n") or "nil"))
    local job_id = exec_run.run_async(sql, {
      src_file = src_file,
      conn_url = conn_url,
      database = database,
      mode = mode,
      max_rows = max_rows,
    }, {
      on_response = on_response,
      on_error = on_error,
    })
    if not job_id or job_id <= 0 then
      if on_error then on_error("Failed to start exec-file job: " .. msg) end
    end
  end

  if prefer_session and conn_url then
    log.info_fmt("SQL run via session: conn=%s db=%s", tostring(conn_url), tostring(database))
    log.debug("SQL via session: " .. (sql and sql:sub(1, 200):gsub("\n", "\\n") or "nil"))
    local ok = session_conn.execute(conn_url, sql, {
      on_response = on_response,
      on_error = exec_file_fallback,
      on_sql_error = function(message, parsed)
        if on_error then on_error(message, parsed) end
      end,
    }, src_buf, database)
    if ok ~= "dispatched" then
      exec_file_fallback("session " .. ok)
    end
  else
    log.info_fmt("SQL run via exec-file: conn=%s db=%s", tostring(conn_url), tostring(database))
    log.debug("SQL via exec-file: " .. (sql and sql:sub(1, 200):gsub("\n", "\\n") or "nil"))
    local job_id = exec_run.run_async(sql, {
      src_file = src_file,
      conn_url = conn_url,
      database = database,
      mode = mode,
      max_rows = max_rows,
    }, {
      on_response = on_response,
      on_error = on_error,
    })
    if not job_id or job_id <= 0 then
      if on_error then on_error("Failed to start exec-file job") end
    end
  end
end

return M