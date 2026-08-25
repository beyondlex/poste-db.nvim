--- SQL request session lifecycle (Phase 2b / F5).
---
--- Each `run_sql_request()` creates a fresh Session at entry and clears
--- request-scoped dataset/response state. Connection/database context is
--- intentionally persistent across runs.

local M = {}

local active = nil

--- @param meta? table  { buf, line, file }
--- @return table
function M.new(meta)
  return {
    response = nil,
    dataset = nil,
    meta = meta or {},
  }
end

--- Begin a fresh SQL session; clears request-scoped dataset state.
--- @param meta? table
--- @return table
function M.begin(meta)
  local state = require("poste.state")
  local sql_state = require("poste-db.state")
  local session = M.new(meta)

  -- Request-scoped clear (connection/database context intentionally kept)
  state.last_response = nil
  sql_state.last_dataset = nil
  sql_state.pagination = {}
  sql_state.cell = { row = 1, col = 1 }

  active = session
  sql_state._sql_session = session
  return session
end

--- @return table|nil
function M.active()
  return active
end

function M.finish()
  active = nil
  local sql_state = require("poste-db.state")
  sql_state._sql_session = nil
end

return M
