local state = require("poste.state")
local indicators = require("poste.indicators")

local M = {}

local NS = vim.api.nvim_create_namespace("poste_file_exec")

local S = {
  job_id = nil,
  buf = nil,
  win = nil,
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
}

local MAX_LOG_LINES = 5
local PROGRESS_WIDTH = 60
local PROGRESS_HEIGHT = 18

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

local function fmt_sql(sql)
  local s = sql:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #s > 50 then
    s = s:sub(1, 47) .. "..."
  end
  return s
end

local function cell(text, width)
  local s = tostring(text)
  if #s > width then
    return s:sub(1, width - 3) .. "..."
  end
  return string.format("%-" .. width .. "s", s)
end

local function render_bar(filled, total)
  local bar_width = 20
  local pct = total > 0 and math.floor((filled / total) * bar_width) or 0
  pct = math.min(pct, bar_width)
  local bar = string.rep("■", pct) .. string.rep("░", bar_width - pct)
  local pct_text = total > 0 and string.format("%d%%", math.floor(filled / total * 100)) or "0%"
  return string.format("[%s] %d/%d %s", bar, filled, total, pct_text)
end

local function build_progress_lines()
  local lines = {}
  local content_width = PROGRESS_WIDTH - 4
  local conn_label = S.conn or ""
  if S.db then conn_label = conn_label .. " / " .. S.db end

  table.insert(lines, "┌─ Execute SQL File " .. string.rep("─", PROGRESS_WIDTH - 21) .. "┐")
  table.insert(lines, "│ " .. cell("Connection: " .. conn_label, content_width) .. " │")
  table.insert(lines, "│ " .. cell("Mode: " .. (S.mode or "greedy"), content_width) .. " │")
  table.insert(lines, "│ " .. cell(render_bar(S.n_succeeded + S.n_failed, S.total), content_width) .. " │")
  table.insert(lines, "│ " .. cell("Elapsed: " .. fmt_elapsed(), content_width) .. " │")

  if S.current_sql and S.is_running then
    table.insert(lines, "│ " .. cell("→ " .. fmt_sql(S.current_sql), content_width) .. " │")
  else
    table.insert(lines, "│ " .. cell("", content_width) .. " │")
  end

  table.insert(lines, "│" .. string.rep("─", PROGRESS_WIDTH - 2) .. "│")

  local start = math.max(1, #S.results - MAX_LOG_LINES + 1)
  for i = start, #S.results do
    local r = S.results[i]
    local icon = r.status == "ok" and "✓" or "✘"
    local summary = r.summary or ""
    table.insert(lines, "│ " .. cell(icon .. " " .. summary, content_width) .. " │")
  end

  while #lines < PROGRESS_HEIGHT - 2 do
    table.insert(lines, "│ " .. cell("", content_width) .. " │")
  end

  if S.is_running then
    table.insert(lines, "│ " .. cell("[c] Cancel", content_width) .. " │")
  else
    table.insert(lines, "│ " .. cell("[q] Close", content_width) .. " │")
  end
  table.insert(lines, "└" .. string.rep("─", PROGRESS_WIDTH - 2) .. "┘")

  return lines
end

local function render_progress()
  if not S.buf or not vim.api.nvim_buf_is_valid(S.buf) then return end
  if not S.win or not vim.api.nvim_win_is_valid(S.win) then return end

  local lines = build_progress_lines()
  vim.bo[S.buf].modifiable = true
  local ok, err = pcall(vim.api.nvim_buf_set_lines, S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
  if not ok then
    state.log("ERROR", "ExecFile render failed: " .. tostring(err))
  end
  vim.cmd("redraw")
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

  if S.win and vim.api.nvim_win_is_valid(S.win) then
    vim.api.nvim_win_close(S.win, true)
  end
  S.win = nil
  S.buf = nil
end

local function create_progress_win()
  if S.buf and vim.api.nvim_buf_is_valid(S.buf) then
    vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, {})
    if S.win and vim.api.nvim_win_is_valid(S.win) then
      return
    end
  end

  S.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[S.buf].modifiable = false
  vim.bo[S.buf].bufhidden = "wipe"

  local width = PROGRESS_WIDTH
  local height = PROGRESS_HEIGHT
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  S.win = vim.api.nvim_open_win(S.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "none",
    focusable = false,
  })

  vim.wo[S.win].winhl = "Normal:NormalFloat"

  local km_opts = { buffer = S.buf, noremap = true, silent = true, nowait = true }
  vim.keymap.set("n", "c", function()
    M.cancel()
  end, km_opts)
  vim.keymap.set("n", "q", function()
    close_progress(false)
  end, km_opts)
  vim.keymap.set("n", "<Esc>", function()
    close_progress(false)
  end, km_opts)
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

    if status == "ok" then
      S.n_succeeded = S.n_succeeded + 1
      S.total_rows = S.total_rows + row_count
      local summary = string.format("(%d) %s", seq, fmt_sql(sql))
      if row_count > 0 then
        summary = summary .. string.format(" (%d rows, %s)", row_count, fmt_time(elapsed))
      else
        summary = summary .. string.format(" (%s)", fmt_time(elapsed))
      end
      table.insert(S.results, { status = "ok", summary = summary })
    else
      S.n_failed = S.n_failed + 1
      local error_msg = event.error or "unknown error"
      local summary = string.format("(%d) %s", seq, fmt_sql(sql))
      table.insert(S.results, { status = "error", summary = summary })
      vim.notify(string.format("[%d/%d] %s", seq, S.total, error_msg), vim.log.levels.ERROR, { title = "Poste Exec File" })
    end
    render_progress()

  elseif event_type == "summary" then
    S.total = event.total
    S.n_succeeded = event.succeeded or S.n_succeeded
    S.n_failed = event.failed or S.n_failed
    S.total_rows = event.total_rows or S.total_rows
    S.total_affected = event.total_affected or S.total_affected
    S.is_running = false
    S.current_sql = nil

    local lines = {
      string.format("Exec File: %s", S.filepath),
      string.format("Connection: %s", event.connection or S.conn or "?"),
      string.format("Database: %s", event.database or S.db or "?"),
      string.format("Mode: %s", event.mode or S.mode),
      "",
      string.format("Total: %d statements", event.total),
      string.format("Succeeded: %d", event.succeeded),
      string.format("Failed: %d", event.failed),
      string.format("Rows returned: %d", event.total_rows),
      string.format("Rows affected: %d", event.total_affected),
      string.format("Total time: %s", fmt_time(event.total_time_ms or 0)),
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Poste Exec File" })
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

  -- Reset state
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
  S.current_sql = nil

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