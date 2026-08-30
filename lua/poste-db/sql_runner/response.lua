--- Response handling for sql_runner — result routing, dataset rendering,
--- indicator placement and cache invalidation. Split from run_sql_request's
--- closures; every request-scoped value arrives explicitly via `deps`, so
--- nothing here closes over request locals:
---
---   entry, current_seq, get_exec_seq, src_buf, src_file, buf_lines,
---   buf_content, stmt_sql_raw, stmt_lines, stmt_end, first_line, is_visual,
---   visual_sel_end, vis_start, vis_end, set_lines, block_result_line
local state = require("poste.state")
local sql_state = require("poste-db.state")
local config = require("poste-db.config")
local indicators = require("poste.indicators")
local statement = require("poste-db.statement")
local sql_format = require("poste-db.format")
local sql_buffer = require("poste-db.buffer")

local M = {}

--- Compute the indicator line for a statement: `end_nr` exclusive, trimmed
--- past trailing blank lines AND `--` comment lines so the marker lands on the
--- statement itself, never on the section separator or the next statement's
--- comment (which would split pending/success icons across lines).
--- @param buf_lines string[]
--- @param line_nr number statement start line (inclusive)
--- @param next_start number|nil next statement start (exclusive bound)
--- @param max_end number fallback exclusive bound (visual selection end / buffer end)
--- @return number 0-based line index for indicators.set_indicator
function M.stmt_indicator_line(buf_lines, line_nr, next_start, max_end)
  local end_nr = next_start and (next_start - 1) or max_end
  while end_nr > line_nr do
    local trimmed = (buf_lines[end_nr] or ""):match("^%s*(.*)$")
    if trimmed ~= "" and not trimmed:match("^%-%-") then break end
    end_nr = end_nr - 1
  end
  return (end_nr - 1)
end

--- True when the first real statement of `sql` is DDL (CREATE/ALTER/DROP/
--- TRUNCATE/RENAME). Leading `-- @connection` directives, `###` section
--- markers, blank lines and comment lines are skipped before inspecting the
--- keyword, because buf_content (and visual blocks) carry that noise.
--- @param sql string|nil
--- @return boolean
function M.is_ddl(sql)
  if not sql then return false end
  for _, ln in ipairs(vim.split(sql, "\n", { plain = true })) do
    local t = ln:match("^%s*(.*)%s*$") or ""
    if t ~= "" and not t:match("^%-%-") and not t:match("^###") then
      return t:match("^CREATE%s") ~= nil
        or t:match("^ALTER%s") ~= nil
        or t:match("^DROP%s") ~= nil
        or t:match("^TRUNCATE%s") ~= nil
        or t:match("^RENAME%s") ~= nil
    end
  end
  return false
end

--- Handle one executor response: stale-seq guard, DDL cache invalidation,
--- USE handling, SET-prelude filtering, then multi-tab or single-result
--- rendering with per-statement indicator placement.
function M.handle(deps, parsed)
  state.log("DEBUG", "SQL on_response called: latency=" .. tostring(parsed.latency_ms or "?") .. " type=" .. (parsed.dialect or "?"))
  local ok_cb, err_cb = pcall(function()
    local exec_seq_now = deps.get_exec_seq()
    if deps.current_seq < exec_seq_now then
      state.log("DEBUG", "SQL on_response stale: current=" .. tostring(deps.current_seq) .. " exec=" .. tostring(exec_seq_now))
      return
    end
    state.last_response = parsed
    deps.entry.elapsed_ms = tonumber(parsed.latency_ms) or 0

    -- DDL detection: buf_content (and visual blocks) may carry leading
    -- directives (`-- @connection`), `###` section markers, blank and
    -- comment lines, so inspect the first real statement's keyword instead
    -- of anchoring the regex at the start of the whole blob.
    if M.is_ddl(deps.stmt_sql_raw or deps.buf_content) then
      require("poste-db.completion.data").clear_cache()
      -- Semantic diagnostics cache the introspected schema; a DDL may have
      -- created/renamed/dropped tables, so invalidate and re-check so the
      -- new tables are no longer reported as "not found".
      local ok_sem, sem = pcall(require, "poste-db.semantic_diagnostics")
      if ok_sem then
        sem.invalidate(sql_state.context.connection, sql_state.context.database)
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(deps.src_buf) then
            sem.update(deps.src_buf)
          end
        end)
      end
    end

    require("poste-db.context").handle_use_statement(parsed)

    local results = parsed.results or {}
    -- When preceding SET @var statements were pulled in, the first #set_lines
    -- results are SET (affected-rows) responses — skip them since they're
    -- dependencies, not the user-selected statement.
    local prelude_count = (not deps.is_visual and deps.set_lines and #deps.set_lines > 0) and #deps.set_lines or 0
    if prelude_count > 0 and #results > 1 then
      local n = math.min(prelude_count, #results - 1)
      local filtered = {}
      for i = n + 1, #results do filtered[#filtered + 1] = results[i] end
      results = filtered
      parsed.results = results
      -- Re-encode body for consumers that rely on parsed.body
      local ok_body, decoded = pcall(vim.json.decode, parsed.body)
      if ok_body and type(decoded) == "table" then
        decoded.results = results
        decoded.total_results = #results
        parsed.body = vim.json.encode(decoded)
      end
    end
    local is_multi = #results > 1

    if is_multi then
      local tab_idx = 0
      local hide_empty = config.config.hide_empty_result_tabs ~= false
      for i, result in ipairs(results) do
        if result.error then
          deps.entry.error = true
          local err_text = type(result.error) == "string" and result.error or vim.inspect(result.error)
          sql_state.last_error = {
            message = err_text,
            sql = statement.get_stmt_sql(deps.buf_lines, deps.stmt_lines, i, deps.visual_sel_end or #deps.buf_lines) or deps.buf_content,
            connection = parsed.connection,
            database = parsed.database,
            at = os.time(),
          }
          tab_idx = tab_idx + 1
          local err_line = deps.stmt_lines[i] or deps.first_line
          local next_start = deps.stmt_lines[i + 1]
          indicators.set_indicator(deps.src_buf,
            M.stmt_indicator_line(deps.buf_lines, err_line, next_start, deps.visual_sel_end or #deps.buf_lines),
            "error")
          local lines = sql_format.format_error(err_text, parsed.connection or "")
          sql_buffer.render_dataset(lines, { type = "error" }, { tab_index = tab_idx, exec_seq = deps.current_seq })
        else
          local sql_text = statement.get_stmt_sql(deps.buf_lines, deps.stmt_lines, i, deps.visual_sel_end)
          local table_name = statement.extract_table_name(sql_text)
          local single_data = {
            type = "resultset",
            results = { result },
            total_rows = tonumber(result.row_count) or 0,
            total_affected = tonumber(result.affected_rows) or 0,
            total_execution_time_ms = tonumber(result.execution_time_ms) or 0,
            connection = result.connection or parsed.connection,
            database = parsed.database,
            dialect = parsed.dialect,
            table_name = table_name,
          }
          local layout = sql_format.plan_resultset_layout(single_data)
          local lines, meta
          if layout then
            tab_idx = tab_idx + 1
            lines, meta = sql_format.render_page(layout, 1, 50)
            meta.table_name = table_name
          elseif hide_empty then
            -- Skip statements with no result set (SET, USE, etc.) — they
            -- would otherwise clutter the dataset with empty tabs.
            local line_nr = deps.stmt_lines[i] or deps.first_line
            local next_start = deps.stmt_lines[i + 1]
            indicators.set_indicator(deps.src_buf,
              M.stmt_indicator_line(deps.buf_lines, line_nr, next_start, deps.visual_sel_end or #deps.buf_lines),
              "success", result.execution_time_ms)
            goto continue
          else
            tab_idx = tab_idx + 1
            lines, meta = sql_format.format_resultset(single_data)
          end
          sql_buffer.render_dataset(lines, meta, {
            tab_index = tab_idx,
            exec_seq = deps.current_seq,
            data = single_data,
            layout = layout,
            original_sql = deps.buf_content,
            src_file = deps.src_file,
            src_buf = deps.src_buf,
          })

          local line_nr = deps.stmt_lines[i] or deps.first_line
          local next_start = deps.stmt_lines[i + 1]
          indicators.set_indicator(deps.src_buf,
            M.stmt_indicator_line(deps.buf_lines, line_nr, next_start, deps.visual_sel_end or #deps.buf_lines),
            "success", result.execution_time_ms)
        end
        ::continue::
      end
    else
      -- Single result
      local table_name
      if deps.is_visual then
        local start_ln = math.min(deps.vis_start, deps.vis_end)
        local end_ln = math.max(deps.vis_start, deps.vis_end)
        local vis_lines = {}
        for i = start_ln, end_ln do
          local ln = deps.buf_lines[i]
          if ln then vis_lines[#vis_lines + 1] = ln end
        end
        table_name = statement.extract_table_name(table.concat(vis_lines, " "))
      else
        table_name = statement.extract_table_name(deps.buf_content)
      end
      local lines, meta, layout = sql_format.format_dataset(parsed)
      if table_name then meta.table_name = table_name end
      sql_buffer.render_dataset(lines, meta, {
        exec_seq = deps.current_seq,
        layout = layout,
        original_sql = deps.buf_content,
        src_file = deps.src_file,
        src_buf = deps.src_buf,
      })

      local has_err = results[1] and results[1].error
      if has_err then
        deps.entry.error = true
        local err_text = type(results[1].error) == "string" and results[1].error or vim.inspect(results[1].error)
        sql_state.last_error = {
          message = err_text,
          sql = deps.buf_content or "",
          connection = parsed.connection,
          database = parsed.database,
          at = os.time(),
        }
      end
      local result_line = deps.stmt_end
        or (deps.is_visual and M.stmt_indicator_line(deps.buf_lines, deps.first_line, deps.stmt_lines[2], deps.visual_sel_end or #deps.buf_lines) or nil)
        or deps.first_line
      if has_err then
        indicators.set_indicator(deps.src_buf, result_line - 1, "error")
      else
        indicators.set_indicator(deps.src_buf, result_line - 1, "success", parsed.latency_ms)
        -- Log successful manual execution
        local edit_commit = require("poste-db.edit_commit")
        local context = require("poste-db.context").resolve_full_context(deps.src_buf, deps.first_line)
        edit_commit.write_log({
          source = "manual_exec",
          connection = context.connection or "",
          dialect = parsed.dialect or "",
          database = context.database or "",
          sql = deps.buf_content or "",
          status = "success",
          elapsed_ms = tonumber(parsed.latency_ms) or 0,
        })
      end
    end

    -- Refresh DB browser tree for the connection/database used
    local db_browser = require("poste-db.db_browser.init")
    if db_browser.is_open() and parsed.connection then
      db_browser.refresh_by_conn(parsed.connection, parsed.database)
    end
  end)
  if not ok_cb then
    state.log("ERROR", "SQL on_response error: " .. tostring(err_cb))
    vim.notify("SQL execution error: " .. tostring(err_cb), vim.log.levels.ERROR, { title = "PosteDb" })
  end
end

--- Handle an executor-level failure (transport errors, dead sessions):
--- record for the AI chat's "ask about this error", surface, log.
function M.handle_error(deps, message, _parsed)
  state.log("ERROR", "SQL execution failed: " .. message)
  vim.schedule(function()
    if deps.current_seq < deps.get_exec_seq() then return end
    deps.entry.error = true
    -- retained for the AI chat's "ask about this error" action
    local err_ctx = require("poste-db.context").resolve_full_context(deps.src_buf, #deps.buf_lines)
    sql_state.last_error = {
      message = tostring(message),
      sql = deps.stmt_sql_raw or deps.buf_content,
      connection = err_ctx.connection,
      database = err_ctx.database,
      at = os.time(),
    }
    indicators.set_indicator(deps.src_buf, deps.block_result_line, "error")
    vim.notify(message, vim.log.levels.ERROR, { title = "PosteDb" })
    local lines = sql_format.format_error(message, sql_state.context.connection or "")
    sql_buffer.render_dataset(lines, { type = "error" })
    -- Log failed execution
    local edit_commit = require("poste-db.edit_commit")
    local context = require("poste-db.context").resolve_full_context(deps.src_buf, #deps.buf_lines)
    edit_commit.write_log({
      source = "manual_exec",
      connection = context.connection or "",
      dialect = sql_state.context.dialect or "",
      database = context.database or "",
      sql = deps.buf_content or "",
      status = "error",
      elapsed_ms = 0,
      error_msg = message:sub(1, 500),
    })
  end)
end

return M
