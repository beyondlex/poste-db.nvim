--- SQL execution context management.
--- Handles connection → database context resolution and status display.
local state = require("poste.state")
local const = require("poste-db.constants")
local lex = require("poste-db.lex")

local M = {}

---------------------------------------------------------------------------
-- Context resolution
---------------------------------------------------------------------------

--- Resolve the SQL execution context from the current buffer.
--- Scans file header for @connection/@database directives, then scans
--- the cursor's ### block for USE statements and block-level overrides.
--- The last USE statement before the cursor wins (JetBrains behavior).
--- @param buf number Buffer handle (default: current buffer)
--- @return table context { connection = string|nil, database = string|nil }
function M.resolve_context(buf, limit_line)
  buf = buf or vim.api.nvim_get_current_buf()
  local cursor_line = limit_line or vim.fn.line(".")

  -- Phase 1: Scan file header (before first ###) for global defaults
  local connection = nil
  local database = nil
  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(all_lines) do
    if const.is_section_marker(line) then break end
    local conn_match = const.match_directive(line, const.DIRECTIVE_CONNECTION)
    if conn_match then connection = vim.trim(conn_match) end
    local db_match = const.match_directive(line, const.DIRECTIVE_DATABASE)
    if db_match then database = vim.trim(db_match) end
  end

  -- Phase 2: Scan cursor's ### block for USE statements and block-level overrides
  local block_start = lex.find_block_for_line(all_lines, cursor_line)
  local block_lines = vim.api.nvim_buf_get_lines(buf, block_start - 1, cursor_line, false)

  for i, line in ipairs(block_lines) do
    local conn_match = const.match_directive(line, const.DIRECTIVE_CONNECTION)
    if conn_match then connection = vim.trim(conn_match) end
    local db_match = const.match_directive(line, const.DIRECTIVE_DATABASE)
    if db_match then database = vim.trim(db_match) end

    local use_db = lex.find_use_database(line)
    if use_db then database = use_db end
  end

  return { connection = connection, database = database }
end

--- Resolve the full context chain: buffer scan → connections.json default.
--- Priority: block-level > USE > file-level > runtime connection > connections.json default
--- Does NOT fall back to state.sql.context.database — context is position-determined.
--- @param buf number Buffer handle (default: current buffer)
--- @return table context { connection = string|nil, database = string|nil }
function M.resolve_full_context(buf, limit_line)
  buf = buf or vim.api.nvim_get_current_buf()

  local ctx = M.resolve_context(buf, limit_line)

  -- Fallback to runtime state for connection (set by :PosteDbConnection or execution)
  local state_sql = state.sql
  local conn = ctx.connection or (state_sql and state_sql.context and state_sql.context.connection)

  -- Database: buffer scan → connections.json default
  local db = ctx.database
  if not db and conn then
    local connections = require("poste-db.connections")
    local config = connections.get_connection_config(conn)
    if config and config.database and config.database ~= "" then
      db = config.database
    end
  end

  return { connection = conn, database = db, raw = ctx }
end

--- Update context from a SQL response (e.g., USE statement).
--- @param response table Parsed response object
function M.handle_use_statement(response)
  if not response or not response.body then return end

  local ok, body = pcall(vim.json.decode, response.body)
  if not ok or type(body) ~= "table" then return end

  if body.type == "use" and body.database_name then
    state.sql.context.database = body.database_name
    state.log("INFO", "SQL context database updated: " .. body.database_name)
  end
end

--- Get status text for the statusline.
--- @return string Status text like "[db: conn/database]"
function M.get_status_text()
  local ctx = state.sql.context
  local conn = ctx.connection
  local db = ctx.database

  if not conn and not db then
    return ""
  end

  if conn and db then
    return string.format("[db: %s/%s]", conn, db)
  elseif conn then
    return string.format("[db: %s]", conn)
  else
    return string.format("[db: ?/%s]", db)
  end
end

--- Get status text for cursor position in a SQL buffer.
--- Resolves context at cursor line: @connection → @database/USE → connections.json default.
--- @param buf number|nil Buffer handle (default: current buffer)
--- @return string Status text like "[my-blog/inventory]" or ""
function M.get_cursor_status_text(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local ctx = M.resolve_full_context(buf)
  if not ctx.connection then return "" end
  if ctx.database then
    return string.format("%s/%s", ctx.connection, ctx.database)
  end
  return ctx.connection
end

return M
