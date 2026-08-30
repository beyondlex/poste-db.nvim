--- SQL execution entry point — supports single-statement (normal mode)
--- and multi-statement (visual selection) execution.
--- Each statement result goes into its own dataset tab.
local state = require("poste.state")
local sql_state = require("poste-db.state")
local config = require("poste-db.config")
local indicators = require("poste.indicators")
local statement = require("poste-db.statement")
local sql_introspect = require("poste-db.introspect")
local sql_buffer = require("poste-db.buffer")
local dml_guard = require("poste-db.dml_guard")
local D = require("poste-db.dataset")
local response = require("poste-db.sql_runner.response")

local stmt_indicator_line = response.stmt_indicator_line

local M = {}

-- Execution tracking for callback ordering
local exec_seq = 0
local _vis_active = false
local _vis_start = 0
local _vis_end = 0

-- CursorMoved debounce to avoid jitter from repeated context resolution
-- Pending statusline/indicator debounce, keyed per SQL buffer. A single
-- shared timer would let one buffer's cursor move cancel another buffer's
-- scheduled update.
local _cursor_moved_timers = {}
local CURSOR_MOVED_DEBOUNCE_MS = 100





--- Install keymaps for this SQL buffer (one-time setup).
function M.ensure_sql_keymaps(buf)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if vim.b[buf].poste_db_keymaps_installed then return end
  vim.b[buf].poste_db_keymaps_installed = true

  local keymap_opts = { buffer = buf, noremap = true, silent = true }

  -- Normal mode: execute statement at cursor
  local k = config.get_keymap("sql_source", "run", "<CR>")
  if k then
    vim.keymap.set("n", k, function()
      M.run_sql_request()
    end, keymap_opts)
  end

  -- K: show DDL for table under cursor
  k = config.get_keymap("sql_source", "show_ddl", "K")
  if k then
    vim.keymap.set("n", k, function()
      sql_introspect.show_table_ddl()
    end, keymap_opts)
  end

  -- Visual mode: execute selected statements (uses same key as normal run)
  k = config.get_keymap("sql_source", "run", "<CR>")
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
  k = config.get_keymap("sql_source", "help", "g?")
  if k then
    vim.keymap.set("n", k, function() require("poste-db.help").open() end, keymap_opts)
  end

  -- <leader>l: toggle SQL execution log
  k = config.get_keymap("sql_source", "toggle_log", "<leader>l")
  if k then
    vim.keymap.set("n", k, function()
      require("poste-db.log_viewer").toggle()
    end, keymap_opts)
  end

  -- Format SQL buffer/selection (default <leader>ff)
  k = config.get_keymap("sql_source", "format", "<leader>ff")
  if k then
    vim.keymap.set("n", k, function()
      local ok, source_format = pcall(require, "poste-db.source_format")
      if ok then source_format.format() end
    end, keymap_opts)
    vim.keymap.set("x", k, function()
      local ok, source_format = pcall(require, "poste-db.source_format")
      if ok then source_format.format() end
    end, keymap_opts)
  end

  -- CursorMoved: update context indicator in statusline + statement highlight
  local augroup = "PosteDbCursorMoved_" .. buf
  pcall(vim.api.nvim_del_augroup_by_name, augroup)
  local group = vim.api.nvim_create_augroup(augroup, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      local pending = _cursor_moved_timers[buf]
      if pending then
        pending:stop()
        pending:close()
      end
      _cursor_moved_timers[buf] = vim.defer_fn(function()
        _cursor_moved_timers[buf] = nil
        if vim.api.nvim_get_current_buf() ~= buf then return end
        local ok, ctx_mod = pcall(require, "poste-db.context")
        if ok and ctx_mod then
          local ok2, text = pcall(ctx_mod.get_cursor_status_text, buf)
          if ok2 and text then
            vim.b[buf].poste_db_context = text
            vim.cmd("redrawstatus")
          end
        end
        local stmt_indicator = require("poste-db.statement_indicator")
        stmt_indicator.update(buf, vim.fn.line("."))
      end, CURSOR_MOVED_DEBOUNCE_MS)
    end,
  })

  -- Tree-sitter syntax diagnostics
  local ok_diag, diag = pcall(require, "poste-db.diagnostics")
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
  require("poste-db.session").begin({
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
    vim.notify("You have unsaved edits. Commit or discard them first.", vim.log.levels.WARN, { title = "PosteDb" })
    return
  end
  exec_seq = exec_seq + 1
  local current_seq = exec_seq
  indicators.clear_all(src_buf)

  -- Request history entry (JetBrains-style sidebar): one entry per request.
  -- Created here so the label is captured at request time; elapsed/error are
  -- filled in by on_response/on_error via the captured entry reference.
  local dataset = require("poste-db.dataset")
  local label_start = stmt_start
    or (is_visual and math.max(1, math.min(_vis_start, _vis_end)) or nil) or 1
  local label = statement.extract_label(buf_lines, label_start)
  if not label then
    -- Fallback: <basename>_<per-buffer counter> (e.g. test_1, test_2)
    label = statement.fallback_label(file, src_buf)
  end
  local ts = dataset.now_wall()
  local entry = dataset.new_entry({
    label = label,
    ts_sec = ts.sec,
    ts_nsec = ts.nsec,
    src_buf = src_buf,
    src_file = file,
    stmt_line = stmt_start,
  })
  sql_buffer.clear_panel()

  -- Set running indicators
  local first_line = stmt_lines[1]
  if not first_line then
    first_line = (is_visual and math.max(_vis_start or 0, _vis_end or 0) > 0)
      and math.min(_vis_start, _vis_end) or 1
  end
  first_line = math.max(1, math.min(first_line, #buf_lines))

  -- Place the running spinner on the same line each statement's completion
  -- indicator will land (`stmt_indicator_line` for visual blocks, `stmt_end`
  -- for cursor runs) so ✓/✘ replaces the spinner in place — otherwise the
  -- spinner freezes on the statement's first line while the result lands on
  -- its last line, splitting loading/completion across two lines.
  if is_visual then
    local max_end = visual_sel_end or #buf_lines
    if #stmt_lines > 0 then
      for i, ln in ipairs(stmt_lines) do
        indicators.set_indicator(src_buf,
          stmt_indicator_line(buf_lines, ln, stmt_lines[i + 1], max_end), "running")
      end
    else
      indicators.set_indicator(src_buf, first_line - 1, "running")
    end
  else
    indicators.set_indicator(src_buf, (stmt_end and (stmt_end - 1)) or (first_line - 1), "running")
  end

  -- Line a whole-block failure lands on (the last statement's ending line for
  -- visual runs), matching where its running spinner sits.
  local block_result_line
  if is_visual then
    local last_start = stmt_lines[#stmt_lines] or first_line
    block_result_line = stmt_indicator_line(buf_lines, last_start, nil, visual_sel_end or #buf_lines)
  else
    block_result_line = (stmt_end and (stmt_end - 1)) or (first_line - 1)
  end

  local sql_context = require("poste-db.context")
  local ctx
  if is_visual then
    local sel_start = math.min(_vis_start, _vis_end)
    ctx = sql_context.resolve_full_context(src_buf, math.max(1, sel_start - 1))
  else
    ctx = sql_context.resolve_full_context(src_buf)
  end
  -- Persist resolved context so it's available for dataset editing (PK introspection etc.)
  if ctx.connection then sql_state.context.connection = ctx.connection end
  if ctx.database then sql_state.context.database = ctx.database end

  -- Resolve connection name to URL and pass directly (bypasses Rust connections.json lookup)
  local conn_url = nil
  if ctx.connection and ctx.connection ~= "" then
    local connections = require("poste-db.connections")
    local url, err = connections.resolve_connection_url(ctx.connection)
    if url then
      conn_url = url
    else
      indicators.clear_all(src_buf)
      vim.notify("Connection '" .. ctx.connection .. "' not found: " .. (err or "create a connections.toml in your project root"), vim.log.levels.ERROR, { title = "PosteDb" })
      return
    end
  end

  local db = ctx.database
  if db == vim.NIL then db = nil end
  if db and db == "" then db = nil end

  local exec_run = require("poste-db.exec_run")

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
  entry.sql = stmt_sql_raw or buf_content

  -- Unfiltered DML guard: a DELETE/UPDATE without a WHERE clause would hit
  -- every row. Confirm once (before any executor side effects) so a stray
  -- `<CR>` cannot wipe a table without an explicit yes.
  if config.config.confirm_unfiltered_dml ~= false then
    local risky = dml_guard.scan_text(stmt_sql_raw or buf_content or "")
    if #risky > 0 then
      local choice = vim.fn.confirm(
        dml_guard.confirm_message(risky),
        "&Yes, execute\n&No, cancel", 2, "Warning")
      if choice ~= 1 then
        vim.notify("Cancelled — statement(s) without a WHERE clause were not executed.",
          vim.log.levels.WARN, { title = "PosteDb" })
        return
      end
    end
  end

  -- Route: single non-USE statement with a resolved connection → session
  --         visual selection, USE, or no connection → exec-file
  local use_session = not is_visual and conn_url and stmt_sql_raw and not is_use_stmt(stmt_sql_raw)

  -- Response handling lives in sql_runner/response.lua; every request-scoped
  -- value is passed explicitly so nothing closes over request locals.
  local response_deps = {
    entry = entry,
    current_seq = current_seq,
    get_exec_seq = function() return exec_seq end,
    src_buf = src_buf,
    src_file = file,
    buf_lines = buf_lines,
    buf_content = buf_content,
    stmt_sql_raw = stmt_sql_raw,
    stmt_lines = stmt_lines,
    stmt_end = stmt_end,
    first_line = first_line,
    is_visual = is_visual,
    visual_sel_end = visual_sel_end,
    vis_start = _vis_start,
    vis_end = _vis_end,
    set_lines = set_lines,
    block_result_line = block_result_line,
  }

  local on_response = function(parsed)
    response.handle(response_deps, parsed)
  end

  local on_error = function(message, parsed)
    response.handle_error(response_deps, message, parsed)
  end

  local executor = require("poste-db.executor")
  executor.execute({
    sql = stmt_sql_raw or buf_content,
    conn_url = conn_url,
    database = db,
    mode = "greedy",
    prefer_session = use_session,
    src_buf = src_buf,
    src_file = file,
    on_response = on_response,
    on_error = function(message, parsed)
      indicators.set_indicator(src_buf, block_result_line, "error")
      on_error(message, parsed)
    end,
  })
end

function M.get_exec_seq()
  return exec_seq
end

M._test = vim.tbl_extend("force", statement._test, { is_ddl = response.is_ddl })

return M
