--- SQL execution entry point — supports single-statement (normal mode)
--- and multi-statement (visual selection) execution.
--- Each statement result goes into its own dataset tab.
local state = require("poste.state")
local indicators = require("poste.indicators")
local statement = require("poste-sql.statement")
local sql_introspect = require("poste-sql.introspect")
local sql_format = require("poste-sql.format")
local sql_buffer = require("poste-sql.buffer")
local session_conn = require("poste-sql.session_conn")

local M = {}

-- Execution tracking for callback ordering
local exec_seq = 0
local _vis_active = false
local _vis_start = 0
local _vis_end = 0

-- CursorMoved debounce to avoid jitter from repeated context resolution
local _cursor_moved_timer = nil
local CURSOR_MOVED_DEBOUNCE_MS = 100


--- Install keymaps for this SQL buffer (one-time setup).
function M.ensure_sql_keymaps(buf)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if vim.b[buf].poste_sql_keymaps_installed then return end
  vim.b[buf].poste_sql_keymaps_installed = true

  local keymap_opts = { buffer = buf, noremap = true, silent = true }

  -- Normal mode: execute statement at cursor
  local k = state.get_keymap("sql_source", "run", "<CR>")
  if k then
    vim.keymap.set("n", k, function()
      M.run_sql_request()
    end, keymap_opts)
  end

  -- K: show DDL for table under cursor
  k = state.get_keymap("sql_source", "show_ddl", "K")
  if k then
    vim.keymap.set("n", k, function()
      sql_introspect.show_table_ddl()
    end, keymap_opts)
  end

  -- Visual mode: execute selected statements (uses same key as normal run)
  k = state.get_keymap("sql_source", "run", "<CR>")
  if k then
    vim.keymap.set("x", k, function()
      _vis_start = vim.fn.line("v")
      _vis_end = vim.fn.line(".")
      _vis_active = true
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
        "n", false
      )
      M.run_sql_request()
    end, keymap_opts)
  end

  -- g?: show keymap help
  k = state.get_keymap("sql_source", "help", "g?")
  if k then
    vim.keymap.set("n", k, function() require("poste-sql.help").open() end, keymap_opts)
  end

  -- <leader>l: toggle SQL execution log
  k = state.get_keymap("sql_source", "toggle_log", "<leader>l")
  if k then
    vim.keymap.set("n", k, function()
      require("poste-sql.log_viewer").toggle()
    end, keymap_opts)
  end

  -- Format SQL buffer/selection (default <leader>ff)
  k = state.get_keymap("sql_source", "format", "<leader>ff")
  if k then
    vim.keymap.set("n", k, function()
      local ok, source_format = pcall(require, "poste-sql.source_format")
      if ok then source_format.format() end
    end, keymap_opts)
    vim.keymap.set("x", k, function()
      local ok, source_format = pcall(require, "poste-sql.source_format")
      if ok then source_format.format() end
    end, keymap_opts)
  end

  -- Execute SQL file
  k = state.get_keymap("sql_source", "exec_file", "<leader>ef")
  if k then
    vim.keymap.set("n", k, function()
      local buf = vim.api.nvim_get_current_buf()
      local filepath = vim.api.nvim_buf_get_name(buf)
      if filepath == "" then
        vim.notify("Buffer must be saved to a file first", vim.log.levels.WARN)
        return
      end
      require("poste-sql.file_exec").run({
        filepath = filepath,
        mode = "greedy",
      })
    end, keymap_opts)
  end

  -- CursorMoved: update context indicator in statusline + statement highlight
  local augroup = "PosteSQLContext_" .. buf
  pcall(vim.api.nvim_del_augroup_by_name, augroup)
  local group = vim.api.nvim_create_augroup(augroup, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      if _cursor_moved_timer then
        _cursor_moved_timer:stop()
        _cursor_moved_timer:close()
      end
      _cursor_moved_timer = vim.defer_fn(function()
        _cursor_moved_timer = nil
        if vim.api.nvim_get_current_buf() ~= buf then return end
        local ok, ctx_mod = pcall(require, "poste-sql.context")
        if ok and ctx_mod then
          local ok2, text = pcall(ctx_mod.get_cursor_status_text, buf)
          if ok2 and text then
            vim.b[buf].poste_sql_context = text
            vim.cmd("redrawstatus")
          end
        end
        local stmt_indicator = require("poste-sql.statement_indicator")
        stmt_indicator.update(buf, vim.fn.line("."))
      end, CURSOR_MOVED_DEBOUNCE_MS)
    end,
  })

  -- Tree-sitter syntax diagnostics
  local ok_diag, diag = pcall(require, "poste-sql.diagnostics")
  if ok_diag then
    diag.setup(buf)
  end
end

--------------------------------------------------------------------------------
-- Main entry point
--------------------------------------------------------------------------------

function M.run_sql_request()
  local src_buf = vim.api.nvim_get_current_buf()

  local binary = state.find_poste_binary()
  if not binary then
    vim.notify("Poste binary not found.", vim.log.levels.ERROR)
    return
  end

  M.ensure_sql_keymaps(src_buf)

  local buf_lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
  local file = vim.api.nvim_buf_get_name(src_buf)
  if file == "" then
    file = vim.fn.getcwd() .. "/untitled.sql"
  end

  -- Fresh SQL session: clears request-scoped dataset/response state (Phase 2b)
  require("poste-sql.session").begin({
    buf = src_buf,
    line = vim.fn.line("."),
    file = file,
  })

  local is_visual = _vis_active
  _vis_active = false

  local buf_content
  local adjusted_line
  local visual_sel_end
  local stmt_start  -- used for session raw SQL extraction
  local stmt_end  -- used in callbacks for indicator placement on last line
  local stmt_lines
  local set_lines  -- preceding SET @var statements found by extract_stmt_at_cursor

  if is_visual then
    local sel_start = math.min(_vis_start, _vis_end)
    local sel_end = math.max(_vis_start, _vis_end)
    sel_start = math.max(1, sel_start)
    sel_end = math.min(#buf_lines, sel_end)
    visual_sel_end = sel_end
    local directive_count
    buf_content, stmt_lines, directive_count = statement.extract_visual_block(buf_lines, sel_start, sel_end)

    -- Find adjusted_line: first non-blank/non-comment line after ### in buf_content
    local content_lines = vim.split(buf_content, "\n")
    adjusted_line = 0
    for j, ln in ipairs(content_lines) do
      local trimmed = ln:match("^%s*(.*)$")
      if trimmed ~= "" and not trimmed:match("^%-%-") and not trimmed:match("^###") then
        adjusted_line = j
        break
      end
    end
    if adjusted_line == 0 then
      adjusted_line = directive_count + 2
    end
    adjusted_line = math.max(1, adjusted_line)
  else
    local line = vim.fn.line(".")
    buf_content, adjusted_line, stmt_start, stmt_end, set_lines = statement.extract_stmt_at_cursor(buf_lines, line, src_buf)
    if not buf_content then return end
    stmt_lines = { stmt_start or 1 }
    stmt_end = stmt_end or stmt_start
  end

  -- Only clear after we confirm there's something to execute
  local tab = D.T()
  if tab and tab.edit_state and tab.edit_state.dirty then
    vim.notify("You have unsaved edits. Commit or discard them first.", vim.log.levels.WARN, { title = "Poste SQL" })
    return
  end
  exec_seq = exec_seq + 1
  local current_seq = exec_seq
  indicators.clear_all(src_buf)
  sql_buffer.clear_panel(current_seq)

  -- Set running indicators
  local first_line = stmt_lines[1]
  if not first_line then
    first_line = (is_visual and math.max(_vis_start or 0, _vis_end or 0) > 0)
      and math.min(_vis_start, _vis_end) or 1
  end
  first_line = math.max(1, math.min(first_line, #buf_lines))

  if #stmt_lines > 0 then
    for _, ln in ipairs(stmt_lines) do
      indicators.set_indicator(src_buf, ln - 1, "running")
    end
  else
    indicators.set_indicator(src_buf, first_line - 1, "running")
  end
  -- Override running spinner to last line (same position as success indicator)
  if stmt_end then
    indicators.clear_all(src_buf)
    indicators.set_indicator(src_buf, stmt_end - 1, "running")
  end

  local sql_context = require("poste-sql.context")
  local ctx
  if is_visual then
    local sel_start = math.min(_vis_start, _vis_end)
    ctx = sql_context.resolve_full_context(src_buf, math.max(1, sel_start - 1))
  else
    ctx = sql_context.resolve_full_context(src_buf)
  end
  -- Persist resolved context so it's available for dataset editing (PK introspection etc.)
  if ctx.connection then state.sql.context.connection = ctx.connection end
  if ctx.database then state.sql.context.database = ctx.database end

  -- Resolve connection name to URL and pass directly (bypasses Rust connections.json lookup)
  local conn_url = nil
  if ctx.connection and ctx.connection ~= "" then
    local connections = require("poste-sql.connections")
    local url, err = connections.resolve_connection_url(ctx.connection)
    if url then
      conn_url = url
    else
      indicators.clear_all(src_buf)
      vim.notify("Connection '" .. ctx.connection .. "' not found: " .. (err or "create a connections.toml in your project root"), vim.log.levels.ERROR, { title = "Poste SQL" })
      return
    end
  end

  local db = ctx.database
  if db == vim.NIL then db = nil end
  if db and db == "" then db = nil end

  local exec_run = require("poste-sql.exec_run")

  -- Detect lone USE statement (handled locally by exec_run, not via session)
  local function is_use_stmt(s)
    if not s then return false end
    local trimmed = s:match("^%s*(.*)%s*$") or ""
    return trimmed:match("^USE%s+([%w_]+)%s*;?%s*$") ~= nil
  end

  -- Extract raw SQL text for a single statement (without directives/###)
  local stmt_sql_raw
  if not is_visual and stmt_start and stmt_end then
    local raw_lines = {}
    if set_lines then
      for _, l in ipairs(set_lines) do raw_lines[#raw_lines + 1] = l end
    end
    for i = stmt_start, stmt_end do
      raw_lines[#raw_lines + 1] = buf_lines[i] or ""
    end
    stmt_sql_raw = table.concat(raw_lines, "\n")
  end

  -- Route: single non-USE statement with a resolved connection → session
  --         visual selection, USE, or no connection → exec-file
  local use_session = not is_visual and conn_url and stmt_sql_raw and not is_use_stmt(stmt_sql_raw)

  local on_response = function(parsed)
    state.log("DEBUG", "SQL on_response called: latency=" .. tostring(parsed.latency_ms or "?") .. " type=" .. (parsed.dialect or "?"))
    local ok_cb, err_cb = pcall(function()
      if current_seq < exec_seq then
        state.log("DEBUG", "SQL on_response stale: current=" .. tostring(current_seq) .. " exec=" .. tostring(exec_seq))
        return
      end
      state.last_response = parsed

      -- Clear completion cache to pick up schema changes from DDL
      require("poste-sql.completion.data").clear_cache()

      -- If raw mode was active, restore dataset buffer before rendering new results
      require("poste-sql.buffer.nav").restore_from_raw_mode()

      sql_context.handle_use_statement(parsed)

      -- Decode body to get actual SQL results
      local ok_body, decoded = pcall(vim.json.decode, parsed.body)
      if not ok_body or type(decoded) ~= "table" then
        decoded = nil
      end

      local results = decoded and decoded.results or {}
      -- When preceding SET @var statements were pulled in, the first #set_lines
      -- results are SET (affected-rows) responses — skip them since they're
      -- dependencies, not the user-selected statement.
      local prelude_count = (not is_visual and set_lines and #set_lines > 0) and #set_lines or 0
      if prelude_count > 0 and #results > 1 then
        local n = math.min(prelude_count, #results - 1)
        local filtered = {}
        for i = n + 1, #results do filtered[#filtered + 1] = results[i] end
        results = filtered
        if decoded then
          decoded.results = results
          decoded.total_results = #results
          parsed.body = vim.json.encode(decoded)
        end
        parsed.results = results
      end
      local is_multi = #results > 1

    if is_multi then
      local tab_idx = 0
      local hide_empty = state.config.hide_empty_result_tabs ~= false
      for i, result in ipairs(results) do
        if result.error then
          tab_idx = tab_idx + 1
          local err_line = stmt_lines[i] or first_line
          local next_start = stmt_lines[i + 1]
          local end_nr = next_start and (next_start - 1) or visual_sel_end or #buf_lines
          while end_nr > err_line and (buf_lines[end_nr] or ""):match("^%s*$") do end_nr = end_nr - 1 end
          indicators.set_indicator(src_buf, end_nr - 1, "error")
          local err_text = type(result.error) == "string" and result.error or vim.inspect(result.error)
          local lines = sql_format.format_error(err_text, parsed.connection or "")
          sql_buffer.render_dataset(lines, { type = "error" }, { tab_index = tab_idx, exec_seq = current_seq })
        else
          local sql_text = statement.get_stmt_sql(buf_lines, stmt_lines, i, visual_sel_end)
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
            local line_nr = stmt_lines[i] or first_line
            local next_start = stmt_lines[i + 1]
            local end_nr = next_start and (next_start - 1) or visual_sel_end or #buf_lines
            while end_nr > line_nr and (buf_lines[end_nr] or ""):match("^%s*$") do end_nr = end_nr - 1 end
            indicators.set_indicator(src_buf, end_nr - 1, "success", result.execution_time_ms)
            goto continue
          else
            tab_idx = tab_idx + 1
            lines, meta = sql_format.format_resultset(single_data)
          end
          sql_buffer.render_dataset(lines, meta, {
            tab_index = tab_idx,
            exec_seq = current_seq,
            data = single_data,
            layout = layout,
            original_sql = buf_content,
            src_file = file,
            src_buf = src_buf,
          })

          local line_nr = stmt_lines[i] or first_line
          local next_start = stmt_lines[i + 1]
          local end_nr = next_start and (next_start - 1) or visual_sel_end or #buf_lines
          while end_nr > line_nr and (buf_lines[end_nr] or ""):match("^%s*$") do end_nr = end_nr - 1 end
          indicators.set_indicator(src_buf, end_nr - 1, "success", result.execution_time_ms)
        end
        ::continue::
      end
    else
      -- Single result
      local table_name
      if is_visual then
        local start_ln = math.min(_vis_start, _vis_end)
        local end_ln = math.max(_vis_start, _vis_end)
        local vis_lines = {}
        for i = start_ln, end_ln do
          local ln = buf_lines[i]
          if ln then vis_lines[#vis_lines + 1] = ln end
        end
        table_name = statement.extract_table_name(table.concat(vis_lines, " "))
      else
        table_name = statement.extract_table_name(buf_content)
      end
      local lines, meta, layout = sql_format.format_dataset(parsed)
      if table_name then meta.table_name = table_name end
      sql_buffer.render_dataset(lines, meta, {
        exec_seq = current_seq,
        layout = layout,
        original_sql = buf_content,
        src_file = file,
        src_buf = src_buf,
      })

      local has_err = results[1] and results[1].error
      local result_line = stmt_end or first_line
      if has_err then
        indicators.set_indicator(src_buf, result_line - 1, "error")
      else
        indicators.set_indicator(src_buf, result_line - 1, "success", parsed.latency_ms)
        -- Log successful manual execution
        local edit_commit = require("poste-sql.edit_commit")
        local context = require("poste-sql.context").resolve_full_context(src_buf, first_line)
        edit_commit.write_log({
          source = "manual_exec",
          connection = context.connection or "",
          dialect = parsed.dialect or "",
          database = context.database or "",
          sql = buf_content or "",
          status = "success",
          elapsed_ms = tonumber(parsed.latency_ms) or 0,
        })
      end
    end

      -- Refresh DB browser tree for the connection/database used
      local db_browser = require("poste-sql.db_browser.init")
      if db_browser.is_open() and parsed.connection then
        db_browser.refresh_by_conn(parsed.connection, parsed.database)
      end
  end)
  if not ok_cb then
    state.log("ERROR", "SQL on_response error: " .. tostring(err_cb))
    vim.notify("SQL execution error: " .. tostring(err_cb), vim.log.levels.ERROR, { title = "Poste SQL" })
  end
end

  local on_error = function(message)
    state.log("ERROR", "SQL execution failed: " .. message)
    vim.schedule(function()
      if current_seq < exec_seq then return end
      indicators.set_indicator(src_buf, (stmt_end or first_line) - 1, "error")
      vim.notify(message, vim.log.levels.ERROR, { title = "Poste SQL" })
      local lines = sql_format.format_error(message, state.sql.context.connection or "")
      sql_buffer.render_dataset(lines, { type = "error" })
      -- Log failed execution
      local edit_commit = require("poste-sql.edit_commit")
      local context = require("poste-sql.context").resolve_full_context(src_buf, #buf_lines)
      edit_commit.write_log({
        source = "manual_exec",
        connection = context.connection or "",
        dialect = state.sql.context.dialect or "",
        database = context.database or "",
        sql = buf_content or "",
        status = "error",
        elapsed_ms = 0,
        error_msg = message:sub(1, 500),
      })
    end)
  end

  local fallback_used = false
  local function exec_file_fallback(msg)
    if fallback_used then return end
    fallback_used = true
    local log = require("poste-sql.log")
    log.warn("SQL session failed, falling back to exec-file: " .. msg)
    local job_id = exec_run.run_async(buf_content, {
      src_file = file,
      conn_url = conn_url,
      database = db,
      mode = "greedy",
      max_rows = 0,
    }, {
      on_response = on_response,
      on_error = on_error,
    })
    if not job_id or job_id <= 0 then
      indicators.set_indicator(src_buf, (stmt_end or first_line) - 1, "error")
      vim.notify("Failed to start poste exec-file job (session fallback): " .. msg, vim.log.levels.ERROR, { title = "Poste SQL" })
    end
  end

  if use_session then
    local log = require("poste-sql.log")
    log.info_fmt("SQL run via session: conn=%s db=%s", tostring(conn_url), tostring(db))
    local ok = session_conn.execute(conn_url, stmt_sql_raw, {
      on_response = on_response,
      on_error = exec_file_fallback,
      on_sql_error = function(message, parsed)
        indicators.set_indicator(src_buf, (stmt_end or first_line) - 1, "error")
        on_error(message, parsed)
      end,
    }, src_buf, db)  -- 5th arg: database context from @database directive
    if ok ~= "dispatched" then
      exec_file_fallback("session " .. ok)
    end
  else
    log.info_fmt("SQL run via exec-file: conn=%s db=%s", tostring(conn_url), tostring(db))
    local job_id = exec_run.run_async(buf_content, {
      src_file = file,
      conn_url = conn_url,
      database = db,
      mode = "greedy",
      max_rows = 0,
    }, {
      on_response = on_response,
      on_error = on_error,
    })
    if not job_id or job_id <= 0 then
      indicators.set_indicator(src_buf, (stmt_end or first_line) - 1, "error")
      vim.notify("Failed to start poste exec-file job", vim.log.levels.ERROR, { title = "Poste SQL" })
    end
  end
end

function M.get_exec_seq()
  return exec_seq
end

M._test = statement._test

return M
