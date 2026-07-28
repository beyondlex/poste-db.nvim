local state = require("poste.state")
local indicators = require("poste.indicators")
local dialog = require("poste.dialog")
local layout = require("poste.layout")

local M = {}

local S = {
  job_id = nil,
  dialog = nil,
  is_running = false,
  cancelled = false,
  n_succeeded = 0,
  n_failed = 0,
  total_rows = 0,
  total_affected = 0,
  total = 0,
  results = {},
  start_time = nil,
  filepath = nil,
  conn = nil,
  db = nil,
  mode = nil,
  rolled_back = false,
  stmt_counts = {
    create = 0, alter = 0, drop = 0,
    insert = 0, update = 0, delete = 0, select = 0, other = 0,
  },
}

local MAX_LOG_LINES = 5
local DIALOG_WIDTH = 70
local DIALOG_HEIGHT = 20

local function fmt_time(ms)
  if ms >= 1000 then
    return string.format("%.2fs", ms / 1000)
  end
  return string.format("%dms", ms)
end

local function fmt_elapsed()
  if not S.start_time then return "0s" end
  local elapsed = vim.loop.now() - S.start_time
  return fmt_time(elapsed)
end

local function fmt_sql(sql, max_len)
  local s = sql:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  max_len = max_len or 50
  if #s > max_len then
    s = s:sub(1, max_len - 3) .. "..."
  end
  return s
end

local function classify_stmt(sql)
  local s = sql:gsub("%s+", " "):gsub("^%s+", ""):upper()
  if s:find("^CREATE") then return "create" end
  if s:find("^ALTER") then return "alter" end
  if s:find("^DROP") then return "drop" end
  if s:find("^INSERT") then return "insert" end
  if s:find("^UPDATE") then return "update" end
  if s:find("^DELETE") then return "delete" end
  if s:find("^SELECT") then return "select" end
  return "other"
end

local function build_content()
  local d = S.dialog
  if not d then return {}, {} end
  local cw = d.content_width
  local lines = {}
  local highlights = {}
  local conn_label = S.conn or ""
  if S.db then conn_label = conn_label .. " / " .. S.db end

  table.insert(lines, layout.cell("Connection: " .. conn_label, cw))

  local mode_label = S.mode == "transaction" and "Transaction" or "Greedy"
  local stats_text
  if S.rolled_back then
    stats_text = string.format("Mode: %s   Failed: %d   (rolled back: %d)", mode_label, S.n_failed, S.n_succeeded)
  else
    stats_text = string.format("Mode: %s   Succeeded: %d   Failed: %d", mode_label, S.n_succeeded, S.n_failed)
  end
  table.insert(lines, stats_text)

  local succeeded_start = stats_text:find("Succeeded:", 1, true)
  if succeeded_start then
    local num_end = stats_text:find("   ", succeeded_start + 11, true) or #stats_text + 1
    table.insert(highlights, { line = #lines - 1, col_start = succeeded_start - 1, col_end = num_end - 1, hl_group = "PosteSqlSucceeded" })
  end
  local failed_start = stats_text:find("Failed:", 1, true)
  if failed_start then
    local num_end = stats_text:find("   ", failed_start + 8, true) or #stats_text + 1
    table.insert(highlights, { line = #lines - 1, col_start = failed_start - 1, col_end = num_end - 1, hl_group = "PosteSqlFailed" })
  end

  table.insert(lines, "")

  local c = S.stmt_counts
  local cols = layout.columns({
    { title = "DDL", items = {
      string.format("create: %d", c.create),
      string.format("modify: %d", c.alter),
      string.format("drop: %d", c.drop),
    }},
    { title = "DML", items = {
      string.format("insert: %d", c.insert),
      string.format("update: %d", c.update),
      string.format("delete: %d", c.delete),
      string.format("select: %d", c.select),
    }},
  }, { width = cw, title_hl = "Title" })
  for _, l in ipairs(cols.lines) do table.insert(lines, l) end
  for _, h in ipairs(cols.highlights) do table.insert(highlights, h) end

  table.insert(lines, "")

  local bar = layout.progress(S.n_succeeded + S.n_failed, S.total, { bar_width = 20 })[1]
  local elapsed = "Elapsed: " .. fmt_elapsed()
  table.insert(lines, layout.space_between(bar, elapsed, { width = cw })[1])
  table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = cw, hl_group = "PosteProgressBar" })

  local elapsed_start = (#lines[#lines] or 0) > 0 and lines[#lines]:find("Elapsed:", 1, true)
  if elapsed_start then
    table.insert(highlights, { line = #lines - 1, col_start = elapsed_start - 1, col_end = #lines[#lines], hl_group = "PosteSqlConstant" })
  end

  table.insert(lines, layout.dynamic_line({
    text = "File: " .. S.filepath,
    container_width = cw,
    truncate_at = "mid",
  }))
  local file_line = #lines
  local file_label_end = ("File: "):len()
  table.insert(highlights, { line = file_line - 1, col_start = file_label_end, col_end = cw, hl_group = "PosteSqlFilepath" })

  table.insert(lines, layout.separator({ width = cw })[1])

  local start = math.max(1, #S.results - MAX_LOG_LINES + 1)
  for i = start, #S.results do
    local r = S.results[i]
    local icon = r.status == "ok" and "✓" or "✘"
    local prefix = icon .. " (" .. r.seq .. ") "
    local suffix = ""
    if r.status == "ok" and r.row_count > 0 then
      suffix = string.format(" (%d rows, %s)", r.row_count, fmt_time(r.elapsed))
    elseif r.status == "ok" then
      suffix = string.format(" (%s)", fmt_time(r.elapsed))
    end
    local prefix_dw = vim.fn.strdisplaywidth(prefix)
    local suffix_dw = vim.fn.strdisplaywidth(suffix)
    local max_sql_dw = math.max(10, cw - prefix_dw - suffix_dw - 1)
    local sql_display = fmt_sql(r.sql, max_sql_dw)
    local line = prefix .. sql_display .. suffix
    table.insert(lines, layout.cell(line, cw))
    local hl = r.status == "ok" and "PosteLogSuccess" or "PosteLogError"
    local prefix_bytes = #prefix
    table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = prefix_bytes, hl_group = hl })
    local sql_start = prefix_bytes
    local sql_end = prefix_bytes + #sql_display
    if sql_end > sql_start then
      table.insert(highlights, { line = #lines - 1, col_start = prefix_bytes, col_end = sql_end, hl_group = "PosteLogSQL" })
    end
  end

  while #lines < d.content_height do
    table.insert(lines, "")
  end

  return lines, highlights
end

local function render_progress()
  if not S.dialog then return end
  local lines, highlights = build_content()
  S.dialog:update(lines, highlights)
end

local function close_progress(force)
  if not force and S.is_running then
    vim.ui.input({ prompt = "Close anyway? (y/N): " }, function(input)
      if input and input:lower() == "y" then
        close_progress(true)
      end
    end)
    return
  end
  if S.dialog then
    S.dialog:close()
  end
  S.dialog = nil
end

local function create_progress_win()
  if S.dialog then
    S.dialog:update({}, {})
    return
  end
  S.dialog = dialog.open({
    title = "Execute SQL File",
    width = DIALOG_WIDTH,
    height = DIALOG_HEIGHT,
    keymaps = {
      c = function()
        M.cancel()
      end,
    },
    on_close = function()
      S.dialog = nil
    end,
  })
end

function M.cancel()
  if not S.is_running or not S.job_id then return end
  S.cancelled = true
  vim.fn.jobstop(S.job_id)
  S.is_running = false
  render_progress()
end

local function handle_line(line)
  local ok, event = pcall(vim.json.decode, line)
  if not ok or type(event) ~= "table" then return end

  local event_type = event.type
  if event_type == "progress" then
    S.current_sql = event.sql
    S.total = event.total
    render_progress()

  elseif event_type == "result" then
    local seq = event.seq
    local status = event.status
    local row_count = event.row_count or 0
    local elapsed = event.execution_time_ms or 0
    local sql = event.sql or ""
    local stmt_type = classify_stmt(sql)
    S.stmt_counts[stmt_type] = S.stmt_counts[stmt_type] + 1

    if status == "ok" then
      S.n_succeeded = S.n_succeeded + 1
      S.total_rows = S.total_rows + row_count
      table.insert(S.results, {
        status = "ok",
        seq = seq,
        sql = sql,
        row_count = row_count,
        elapsed = elapsed,
      })
    else
      S.n_failed = S.n_failed + 1
      local error_msg = event.error or "unknown error"
      table.insert(S.results, {
        status = "error",
        seq = seq,
        sql = sql,
        row_count = 0,
        elapsed = elapsed,
        error = error_msg,
      })
      vim.notify(string.format("[%d/%d] %s", seq, S.total, error_msg), vim.log.levels.ERROR, { title = "Poste Exec File" })
    end
    render_progress()

  elseif event_type == "summary" then
    S.total = event.total
    S.n_succeeded = event.succeeded or S.n_succeeded
    S.n_failed = event.failed or S.n_failed
    S.total_rows = event.total_rows or S.total_rows
    S.total_affected = event.total_affected or S.total_affected
    S.rolled_back = event.rolled_back or false
    S.is_running = false
    S.current_sql = nil
    render_progress()
  end
end

function M.run(opts)
  opts = opts or {}
  local filepath = opts.filepath
  local conn = opts.conn
  local db = opts.database
  local mode = opts.mode or "greedy"
  local timeout = opts.timeout or 30
  local max_rows = opts.max_rows or 1000

  if not filepath or filepath == "" then
    vim.notify("No file specified", vim.log.levels.ERROR)
    return
  end

  S.job_id = nil
  S.is_running = true
  S.cancelled = false
  S.n_succeeded = 0
  S.n_failed = 0
  S.total_rows = 0
  S.total_affected = 0
  S.total = 0
  S.results = {}
  S.start_time = vim.loop.now()
  S.filepath = filepath
  S.conn = conn
  S.db = db
  S.mode = mode
  S.rolled_back = false
  S.current_sql = nil
  S.stmt_counts = { create = 0, alter = 0, drop = 0, insert = 0, update = 0, delete = 0, select = 0, other = 0 }

  create_progress_win()
  render_progress()

  local binary = state.find_poste_binary()
  if not binary then
    vim.notify("Poste binary not found", vim.log.levels.ERROR)
    S.is_running = false
    render_progress()
    return
  end

  local cmd = string.format("%s exec-file %s --env %s --mode %s --timeout %d --max-rows %d --json",
    vim.fn.shellescape(binary),
    vim.fn.shellescape(filepath),
    vim.fn.shellescape(state.current_env),
    vim.fn.shellescape(mode),
    timeout,
    max_rows
  )

  if conn then
    cmd = cmd .. " --connection " .. vim.fn.shellescape(conn)
  end

  if db then
    cmd = cmd .. " --database " .. vim.fn.shellescape(db)
  end

  state.log("INFO", "ExecFile cmd: " .. cmd)

  local partial = ""
  S.job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data or S.cancelled then return end
      for _, chunk in ipairs(data) do
        if chunk == "" then
          if partial ~= "" then
            handle_line(partial)
            partial = ""
          end
        else
          local combined = partial .. chunk
          local lines = vim.split(combined, "\n")
          partial = table.remove(lines) or ""
          for _, line in ipairs(lines) do
            if line ~= "" then
              handle_line(line)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then return end
      for _, l in ipairs(data) do
        if l ~= "" then
          state.log("WARN", "ExecFile stderr: " .. l)
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 and not S.cancelled then
          state.log("ERROR", "ExecFile exit code " .. code)
        end
        S.is_running = false
        render_progress()
      end)
    end,
  })

  if S.job_id <= 0 then
    vim.notify("Failed to start poste exec-file job", vim.log.levels.ERROR)
    S.is_running = false
    render_progress()
  end
end

return M
