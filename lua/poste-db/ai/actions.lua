--- SQL code-block execution for the "db" AI context — takes a ```sql block
--- from an AI reply, resolves the target connection, runs it through the
--- regular executor and renders results into the dataset view.
--- Safety: only clearly read-only statements run without confirmation.

local M = {}

--- Read-only statement keywords (Lua patterns have no alternation, hence the
--- lookup table).
local READONLY_KINDS = {
  select = true, with = true, show = true, explain = true, describe = true,
  desc = true, analyze = true, pragma = true, table = true,
}

--- Heuristic read-only check for the confirm gate.
--- @param sql string
--- @return boolean
function M.is_readonly(sql)
  local kind = (sql:lower()):match("^%s*(%a+)")
  return kind ~= nil and READONLY_KINDS[kind] == true
end

--- Confirm gate used by poste-ai's codeblock action. Read-only statements
--- pass; everything else asks (mirrors the family's destructive-op dialogs).
--- @param sql string
--- @return boolean proceed
function M.confirm_sql(sql)
  if M.is_readonly(sql) then return true end
  local kind = (sql:match("^%s*(%S+)") or "statement"):upper()
  local choice = vim.fn.confirm(
    ("AI wants to execute a %s statement — run it?"):format(kind),
    "&Yes\n&No", 2, "Warning")
  return choice == 1
end

--- Header directive lines for appending an AI-authored block into a SQL
--- buffer (poste-ai's `ga` action) — binds the block to the chat scope set
--- with /connections and /databases. Nil when no connection is bound or the
--- block already carries a @connection directive (the model may emit one).
--- @param scope table|nil chat scope snapshot
--- @param text string block text
--- @return string[]|nil
function M.append_header(scope, text)
  local conn = scope and scope.connection
  if not conn then return nil end
  if text and text:match("%-%-%s*@connection") then return nil end
  local lines = { "-- @connection " .. conn }
  if scope.database then
    lines[#lines + 1] = "-- @database " .. scope.database
  end
  return lines
end

--- Strip a leading `-- @connection x` directive the model may have copied in.
local function strip_directives(sql)
  return (sql:gsub("^%s*%-%-%s*@connection%s+%S+%s*\n?", "")
    :gsub("^%s*%-%-%s*@database%s+%S+%s*\n?", ""))
end

--- Resolve the target connection. Priority: mention refs → the poste-ai chat
--- scope (bound with /connections, /databases) → the current SQL context.
--- @param refs table|nil
--- @return string|nil conn, string|nil database, string|nil err
function M.resolve_target(refs)
  for _, ref in ipairs(refs or {}) do
    if ref.type == "context" and ref.context == "db" and type(ref.data) == "table"
      and ref.data.connection then
      return ref.data.connection, ref.data.database, nil
    end
  end
  local ok, poste_ai = pcall(require, "poste-ai")
  if ok then
    local scope = poste_ai.scope and poste_ai.scope() or nil
    if scope and scope.connection then
      return scope.connection, scope.database, nil
    end
  end
  local state = require("poste-db.state")
  if state.context and state.context.connection then
    return state.context.connection, state.context.database, nil
  end
  return nil, nil, "no target connection — scope with /connections, mention one with @connection/database, or set -- @connection in the SQL buffer"
end

--- Render a parsed legacy response into the dataset view.
function M.render_dataset(parsed, sql)
  local format = require("poste-db.format")
  local sql_buffer = require("poste-db.buffer")
  local lines, meta, layout = format.format_dataset(parsed)
  -- Prefer the decoded resultset (matches db_browser's execute_table_select)
  -- so cell preview (K) / yank / sort read fresh rows.
  local data = parsed
  if parsed and parsed.body then
    local ok, d = pcall(vim.json.decode, parsed.body)
    if ok then data = d end
  end
  sql_buffer.render_dataset(lines, meta, {
    data = data,
    layout = layout,
    original_sql = sql,
    src_file = "poste://ai_chat",
    src_buf = nil,
  })
end

--- Execute an AI-authored SQL block. Called by poste-ai's codeblock action.
--- @param sql string block text
--- @param refs table mention refs of the user turn
--- @param cb function(err, note)
function M.execute_sql(sql, refs, cb)
  local conn, database, err = M.resolve_target(refs)
  if not conn then cb(err or "no connection", nil) return end

  local connections = require("poste-db.connections")
  local url, url_err = connections.resolve_connection_url(conn)
  if not url then
    cb(("connection %q not found: %s"):format(conn, tostring(url_err)), nil)
    return
  end

  sql = strip_directives(sql)

  local executor = require("poste-db.executor")
  local ok, job_err = pcall(executor.execute, {
    sql = sql,
    conn_url = url,
    database = database,
    mode = "greedy",
    src_file = "poste://ai_chat",
    on_response = function(parsed)
      vim.schedule(function()
        local ok_r, render_err = pcall(M.render_dataset, parsed, sql)
        if ok_r then
          cb(nil, "✓ executed against " .. conn .. (database and ("/" .. database) or "")
            .. " — results are in the dataset view")
        else
          cb("dataset render failed: " .. tostring(render_err), nil)
        end
      end)
    end,
    on_error = function(message)
      vim.schedule(function() cb("SQL error: " .. tostring(message), nil) end)
    end,
  })
  if not ok then cb("failed to start execution: " .. tostring(job_err), nil) end
end

M._test = {
  is_readonly = M.is_readonly,
  resolve_target = M.resolve_target,
  strip_directives = strip_directives,
  append_header = M.append_header,
}

return M
