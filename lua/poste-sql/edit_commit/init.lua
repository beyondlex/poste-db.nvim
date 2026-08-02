--- Dataset edit commit — DML generation, commit, rollback, SQL logging.

local editor = require("poste-sql.editor")
local sql_format = require("poste-sql.format")
local sql_buffer = require("poste-sql.buffer")
local cli = require("poste.cli")
local const = require("poste-sql.constants")
local dml = require("poste-sql.dml")
local exec = require("poste-sql.edit_commit.exec")
local log = require("poste-sql.edit_commit.log")

local M = {}
M.generate_update = dml.generate_update
M.generate_insert = dml.generate_insert
M.generate_delete = dml.generate_delete
M.generate_dml = dml.generate_dml

---------------------------------------------------------------------------
-- SQL Log
---------------------------------------------------------------------------
function M.format_log_entry(entry) return log.format_log_entry(entry) end
function M.write_log(entry) return log.write_log(entry) end
function M.set_log_path(path) return log.set_log_path(path) end

---------------------------------------------------------------------------
-- Commit / Rollback
---------------------------------------------------------------------------

--- Generate combined DML and return as single SQL string.
--- @param es table edit_state
--- @param tab table Tab state
--- @param dialect string Dialect
--- @return string|nil combined SQL, table summary
function M.generate_combined_dml(es, tab, dialect)
  local stmts = dml.generate_dml(es, tab, dialect)
  if #stmts == 0 then
    return nil, { updates = 0, inserts = 0, deletes = 0 }
  end

  local sql_parts = {}
  local summary = { updates = 0, inserts = 0, deletes = 0 }
  for _, s in ipairs(stmts) do
    table.insert(sql_parts, s.sql)
    if s.type == "update" then summary.updates = summary.updates + 1
    elseif s.type == "insert" then summary.inserts = summary.inserts + 1
    elseif s.type == "delete" then summary.deletes = summary.deletes + 1
    end
  end

  return table.concat(sql_parts, "\n"), summary
end

--- Re-execute original SELECT and refresh the dataset in-place.
--- Bypasses run_sql_request() to avoid cursor-position-dependent buffer parsing.
--- @param tab table Tab state with original_sql, src_file, src_buf
function M.refresh_dataset(tab)
  local state = require("poste.state")
  local statement = require("poste-sql.statement")

  local sql = tab.original_sql
  if not sql or sql == "" then
    vim.notify("No original SQL to re-execute", vim.log.levels.WARN)
    return
  end

  local binary = state.find_poste_binary()
  if not binary then
    vim.notify("Poste binary not found", vim.log.levels.ERROR)
    return
  end

  local conn = (tab.layout and tab.layout._conn_name) or state.sql.context.connection or ""
  local db = ""
  if tab.layout then
    local layout_db = tab.layout._database or tab.layout.database
    if layout_db and layout_db ~= "" then db = layout_db end
  end
  if db == "" then db = state.sql.context.database or "" end

  local conn_url = nil
  if conn and conn ~= "" then
    local connections = require("poste-sql.connections")
    conn_url, _ = connections.resolve_connection_url(conn)
  end

  -- Strip directives and ### markers from SQL, since original_sql
  -- may contain the full buffer content (-- @connection, ###, etc.)
  local sql_lines = vim.split(sql, "\n", { plain = true })
  local clean_sql_lines = {}
  for _, line in ipairs(sql_lines) do
    local trimmed = line:match("^%s*(.*)$")
    if trimmed ~= "" and not trimmed:match("^%-%-") and not const.is_section_marker(trimmed) then
      table.insert(clean_sql_lines, line)
    end
  end

  local content_lines = {}
  if conn_url then
    table.insert(content_lines, "-- @" .. const.DIRECTIVE_CONNECTION .. " " .. conn_url)
  end
  if db and db ~= "" then
    table.insert(content_lines, "-- @" .. const.DIRECTIVE_DATABASE .. " " .. db)
  end
  table.insert(content_lines, "")
  table.insert(content_lines, const.SECTION_MARKER .. " refresh")
  local sql_start_line = #content_lines + 1
  for _, line in ipairs(clean_sql_lines) do
    table.insert(content_lines, line)
  end
  table.insert(content_lines, "")

  -- Write temp file alongside source for connections.json discovery
  local src_dir = tab.src_file and vim.fn.fnamemodify(tab.src_file, ":h") or ""
  local tmpfile
  if src_dir ~= "" and vim.fn.isdirectory(src_dir) == 1 then
    tmpfile = src_dir .. "/.poste_refresh_" .. vim.fn.strftime("%Y%m%d%H%M%S") .. ".sql"
  else
    tmpfile = vim.fn.tempname() .. ".sql"
  end
  vim.fn.writefile(content_lines, tmpfile)

  local cmd_parts = { binary, "run", tmpfile, "--line", tostring(sql_start_line), "--env", state.current_env, "--json" }
  if conn_url then
    table.insert(cmd_parts, "--connection-url")
    table.insert(cmd_parts, conn_url)
  end
  if db and db ~= "" then
    local db_clean = vim.split(db, "/")
    table.insert(cmd_parts, "--database")
    table.insert(cmd_parts, db_clean[#db_clean])
  end

  -- Clear PK cache so the new layout gets primary_key info re-introspected
  editor.clear_pk_cache()

  local stderr_buf = {}

  local job_id = cli.run_async(cmd_parts, {
    on_stdout = function(data)
      if not data or #data == 0 then return end
      local output = table.concat(data, "\n")
      vim.schedule(function()
        local ok, parsed = pcall(vim.json.decode, output)
        if not ok or not parsed then
          local stderr_text = table.concat(stderr_buf, "\n")
          vim.notify("Refresh failed: JSON parse error\n" .. stderr_text:sub(1, 300), vim.log.levels.ERROR)
          return
        end

        local lines, meta, layout = sql_format.format_dataset(parsed)
        if layout then
          local table_name = statement.extract_table_name(sql)
          if table_name then meta.table_name = table_name end
        end

        sql_buffer.render_dataset(lines, meta, {
          exec_seq = 0,
          layout = layout,
          original_sql = tab.original_sql,
          src_file = tab.src_file,
          src_buf = tab.src_buf,
        })
      end)
    end,
    on_stderr = function(data)
      if not data then return end
      for _, l in ipairs(data) do
        if l ~= "" then table.insert(stderr_buf, l) end
      end
    end,
    on_exit = function(code)
      pcall(vim.fn.delete, tmpfile)
      if code ~= 0 then
        vim.schedule(function()
          local stderr_text = table.concat(stderr_buf, "\n")
          vim.notify("Refresh failed (exit " .. code .. ")\n" .. stderr_text:sub(1, 300), vim.log.levels.ERROR)
        end)
      end
    end,
  })

  if job_id <= 0 then
    vim.notify("Failed to start refresh job", vim.log.levels.ERROR)
  end
end

---------------------------------------------------------------------------
-- Commit / Rollback execution
---------------------------------------------------------------------------

--- Commit all pending edits by generating and executing DML.
function M.commit_edits()
  local D = require("poste-sql.dataset")
  local state = require("poste.state")
  local tab = D.T()
  if not tab or not tab.edit_state or not tab.edit_state.dirty then
    vim.notify("No changes to commit", vim.log.levels.INFO)
    return
  end

  -- Guard: warn if no primary key for UPDATE/DELETE (but don't block — use all-column WHERE)
  local es = tab.edit_state
  local has_updates = not vim.tbl_isempty(es.modified_cells)
  local has_deletes = not vim.tbl_isempty(es.deleted_rows)
  if (has_updates or has_deletes) and tab.layout then
    local pk_cols = {}
    for _, col in ipairs(tab.layout.columns) do
      if col.primary_key then table.insert(pk_cols, col.name) end
    end
    if #pk_cols == 0 then
      vim.notify("No primary key info — WHERE will use all column values", vim.log.levels.WARN)
    end
  end

  local dialect = tab.layout and tab.layout.dialect or "postgres"
  local sql, summary = M.generate_combined_dml(es, tab, dialect)
  if not sql then
    vim.notify("No changes to commit", vim.log.levels.INFO)
    return
  end

  -- Execute via poste CLI
  local binary = state.find_poste_binary()
  if not binary then
    vim.notify("Poste binary not found", vim.log.levels.ERROR)
    return
  end

  local connection = tab.layout and tab.layout._conn_name or state.sql.context.connection or ""
  local table_name = tab.layout and tab.layout.table_name or ""

  -- Resolve database: layout._database → layout.database → context → connections.json default
  local database = ""
  if tab.layout then
    local layout_db = tab.layout._database or tab.layout.database
    if layout_db and layout_db ~= "" then database = layout_db end
  end
  if database == "" then
    database = state.sql.context.database or ""
  end
  if database == "" and connection ~= "" then
    local config = require("poste-sql.connections").get_connection_config(connection)
    if config and config.database and config.database ~= "" then
      database = config.database
    end
  end
  local src_file = tab.src_file or ""

  -- poste run needs a FILE for env.json discovery
  if src_file == "" then
    src_file = vim.fn.tempname() .. ".sql"
  end

  local conn_url = nil
  if connection and connection ~= "" then
    local connections = require("poste-sql.connections")
    conn_url, _ = connections.resolve_connection_url(connection)
  end

  local sql_content = sql
  local cmd = { binary, "run", "--stdin", "--line", "2", "--json", src_file }
  if conn_url then
    table.insert(cmd, "--connection-url")
    table.insert(cmd, conn_url)
  end
  if database and database ~= "" then
    table.insert(cmd, "--database")
    table.insert(cmd, database)
  end

  local stderr_buf = {}
  local start_time = vim.uv.now()
  local job_id = cli.run_async(cmd, {
    stdin = sql_content,
    on_stdout = function(data)
      if not data or #data == 0 then return end
      vim.schedule(function()
        local elapsed = vim.uv.now() - start_time
        local output = table.concat(data, "\n")

        local resp, resp_err = exec.decode_json(output)
        if not resp then
          local stderr_text = table.concat(stderr_buf, "\n")
          vim.notify("Commit: failed to parse poste response\n" .. stderr_text:sub(1, 300), vim.log.levels.ERROR)
          log.write_log({
            source = "dataset_commit",
            table_name = table_name,
            connection = connection,
            dialect = dialect,
            database = database,
            sql = sql,
            status = "error",
            elapsed_ms = elapsed,
            edit_summary = summary,
            error_msg = "JSON parse error: " .. (resp_err or stderr_text:sub(1, 200)),
          })
          return
        end

        -- Decode inner body to get per-statement errors
        local body = exec.decode_body(resp)
        local errors = exec.collect_statement_errors(body)

        if body.has_error or #errors > 0 then
          local err_msg = exec.build_commit_error_message(body, errors)
          vim.notify("Commit failed:\n" .. err_msg:sub(1, 500), vim.log.levels.ERROR)
          log.write_log({
            source = "dataset_commit",
            table_name = table_name,
            connection = connection,
            dialect = dialect,
            database = database,
            sql = sql,
            status = "error",
            elapsed_ms = elapsed,
            edit_summary = summary,
            error_msg = err_msg:sub(1, 500),
          })
          return
        end

        -- Success
        local affected = exec.count_affected_rows(body)

        vim.notify(string.format("Committed: %d update(s), %d insert(s), %d delete(s) (%d row(s) affected)",
          summary.updates, summary.inserts, summary.deletes, affected), vim.log.levels.INFO)
        log.write_log({
          source = "dataset_commit",
          table_name = table_name,
          connection = connection,
          dialect = dialect,
          database = database,
          sql = sql,
          status = "success",
          elapsed_ms = elapsed,
          edit_summary = summary,
          affected_rows = affected,
        })
        -- Clear edit state and refresh dataset in-place
        require("poste-sql.editor").reset_edit_state(tab.edit_state)
        tab.edit_state = nil
        M.refresh_dataset(tab)
      end)
    end,
    on_stderr = function(data)
      if not data then return end
      for _, l in ipairs(data) do
        if l ~= "" then table.insert(stderr_buf, l) end
      end
    end,
    on_exit = function(code)
      if code ~= 0 then
        vim.schedule(function()
          local stderr_text = table.concat(stderr_buf, "\n")
          -- Only notify if on_stdout didn't already handle it
          vim.notify("Commit process exited with code " .. code .. "\n" .. stderr_text:sub(1, 300), vim.log.levels.WARN)
        end)
      end
    end,
  })

  if not job_id or job_id <= 0 then
    vim.notify("Failed to start poste job", vim.log.levels.ERROR)
  end
end

return M
