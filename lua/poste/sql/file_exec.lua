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
  rolled_back = false,
  stmt_counts = {
    create = 0, alter = 0, drop = 0,
    insert = 0, update = 0, delete = 0, select = 0, other = 0,
  },
}

local MAX_LOG_LINES = 5
local PROGRESS_WIDTH = 60
local PROGRESS_HEIGHT = 20

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
  local dw = vim.fn.strdisplaywidth(s)
  if dw > width then
    return vim.fn.strcharpart(s, 0, width - 3) .. "..."
  end
  local pad = width - dw
  return s .. string.rep(" ", pad)
end

local function render_bar(filled, total)
  local bar_width = 20
  local pct = total > 0 and math.floor((filled / total) * bar_width) or 0
  pct = math.min(pct, bar_width)
  local bar = string.rep("■", pct) .. string.rep("░", bar_width - pct)
  local pct_text = total > 0 and string.format("%d%%", math.floor(filled / total * 100)) or "0%"
  return string.format("[%s] %d/%d %s", bar, filled, total, pct_text)
end

local function fmt_filepath(path, max_len)
  if not path or path == "" then return "" end
  max_len = max_len or 48
  if #path <= max_len then return path end
  local half = math.floor((max_len - 3) / 2)
  return path:sub(1, half) .. "..." .. path:sub(#path - half + 1)
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

local function build_progress_lines()
  local lines = {}
  local content_width = PROGRESS_WIDTH - 4
  local conn_label = S.conn or ""
  if S.db then conn_label = conn_label .. " / " .. S.db end

  local close_tag = S.is_running and "[c] Cancel" or "[q] Close"
  local title_left = "┌─ Execute SQL File "
  local title_right = " " .. close_tag .. " ─┐"
  local left_dw = vim.fn.strdisplaywidth(title_left)
  local right_dw = vim.fn.strdisplaywidth(title_right)
  local fill = math.max(0, PROGRESS_WIDTH - left_dw - right_dw)
  table.insert(lines, title_left .. string.rep("─", fill) .. title_right)

  local half = 27
  local half2 = content_width - 1 - half

  table.insert(lines, "│ " .. cell("Connection: " .. conn_label, content_width) .. " │")

  local mode_label = S.mode == "transaction" and "Transaction" or "Greedy"
  local stats
  if S.rolled_back then
    stats = string.format("Mode: %s   Failed: %d   (rolled back: %d)", mode_label, S.n_failed, S.n_succeeded)
  else
    stats = string.format("Mode: %s   Succeeded: %d   Failed: %d", mode_label, S.n_succeeded, S.n_failed)
  end
  table.insert(lines, "│ " .. cell(stats, content_width) .. " │")

  table.insert(lines, "│ " .. cell("", content_width) .. " │")

  local c = S.stmt_counts
  local ddl_rows = {
    { "create", c.create },
    { "modify", c.alter },
    { "drop", c.drop },
  }
  local dml_rows = {
    { "insert", c.insert },
    { "update", c.update },
    { "delete", c.delete },
    { "select", c.select },
  }

  table.insert(lines, "│ " .. cell("DDL", half) .. " " .. cell("DML", half2) .. " │")
  for i = 1, 4 do
    local ddl = ddl_rows[i]
    local dml = dml_rows[i]
    local left = ddl and string.format("%s: %d", ddl[1], ddl[2]) or ""
    local right = dml and string.format("%s: %d", dml[1], dml[2]) or ""
    table.insert(lines, "│ " .. cell(left, half) .. " " .. cell(right, half2) .. " │")
  end

  table.insert(lines, "│ " .. cell("", content_width) .. " │")

  local bar = render_bar(S.n_succeeded + S.n_failed, S.total)
  local elapsed = "Elapsed: " .. fmt_elapsed()
  local bar_dw = vim.fn.strdisplaywidth(bar)
  local elapsed_dw = vim.fn.strdisplaywidth(elapsed)
  local pad = math.max(1, content_width - bar_dw - elapsed_dw)
  table.insert(lines, "│ " .. bar .. string.rep(" ", pad) .. elapsed .. " │")
  table.insert(lines, "│ " .. cell("File: " .. fmt_filepath(S.filepath), content_width) .. " │")

  table.insert(lines, "│" .. string.rep("─", PROGRESS_WIDTH - 2) .. "│")

  local start = math.max(1, #S.results - MAX_LOG_LINES + 1)
  for i = start, #S.results do
    local r = S.results[i]
    local icon = r.status == "ok" and "✓" or "✘"
    local summary = r.summary or ""
    table.insert(lines, "│ " .. cell(icon .. " " .. summary, content_width) .. " │")
  end

  while #lines < PROGRESS_HEIGHT - 1 do
    table.insert(lines, "│ " .. cell("", content_width) .. " │")
  end

  table.insert(lines, "└" .. string.rep("─", PROGRESS_WIDTH - 2) .. "┘")

  return lines
end

local function apply_highlights()
  vim.api.nvim_buf_clear_namespace(S.buf, NS, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(S.buf, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:sub(1, 6) == "│ Mo" then
      local s = line:find("Succeeded:", 1, true)
      if s then
        local e = line:find("   ", s + 11, true)
        if e then
          vim.api.nvim_buf_set_extmark(S.buf, NS, i - 1, s - 1, { end_col = e - 1, hl_group = "PosteSqlSucceeded" })
        end
      end
      s = line:find("Failed:", 1, true)
      if s then
        local e = line:find(" │", s + 8, true)
        if e then
          vim.api.nvim_buf_set_extmark(S.buf, NS, i - 1, s - 1, { end_col = e - 1, hl_group = "PosteSqlFailed" })
        end
      end
    end

    if line:sub(1, 5) == "│ [" then
      local s = line:find("Elapsed:", 1, true)
      if s then
        local e = line:find("s", s + 8, true)
        if e then
          vim.api.nvim_buf_set_extmark(S.buf, NS, i - 1, s - 1, { end_col = e, hl_group = "PosteSqlConstant" })
        end
      end
    end

    if line:sub(1, 6) == "│ Fi" then
      local s = line:find("File: ", 1, true)
      if s then
        local path_start = s + 5
        local pipe = line:find("│", s + 6, true)
        if pipe and pipe > path_start then
          vim.api.nvim_buf_set_extmark(S.buf, NS, i - 1, path_start, {
            end_row = i - 1,
            end_col = pipe - 3,
            hl_group = "PosteSqlFilepath",
          })
        end
      end
    end

    if line:sub(1, 5) == "│ \226" then
      local check = line:find("\226\156\147", 1, true)
      if check then
        vim.api.nvim_buf_set_extmark(S.buf, NS, i - 1, check - 1, { end_col = check + 2, hl_group = "PosteLogSuccess" })
        local sql_start = check + 3
        local pipe = line:find("│", sql_start, true)
        if pipe then
          vim.api.nvim_buf_set_extmark(S.buf, NS, i - 1, sql_start, {
            end_row = i - 1,
            end_col = pipe - 3,
            hl_group = "PosteLogSQL",
          })
        end
      end
      local cross = line:find("\226\156\152", 1, true)
      if cross then
        vim.api.nvim_buf_set_extmark(S.buf, NS, i - 1, cross - 1, { end_col = cross + 2, hl_group = "PosteLogError" })
        local sql_start = cross + 3
        local pipe = line:find("│", sql_start, true)
        if pipe then
          vim.api.nvim_buf_set_extmark(S.buf, NS, i - 1, sql_start, {
            end_row = i - 1,
            end_col = pipe - 3,
            hl_group = "PosteLogSQL",
          })
        end
      end
    end
  end
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
  pcall(apply_highlights)
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
    local stmt_type = classify_stmt(sql)
    S.stmt_counts[stmt_type] = S.stmt_counts[stmt_type] + 1

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