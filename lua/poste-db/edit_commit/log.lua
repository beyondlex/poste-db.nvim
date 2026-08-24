--- Edit commit log --- persistent log of committed edits.
local M = {}
local const = require("poste-db.constants")

local SQL_LOG_PATH = nil
local MAX_LOG_ENTRIES = const.LOG_MAX_ENTRIES
local _log_write_count = 0

local function get_log_path()
  if SQL_LOG_PATH then return SQL_LOG_PATH end
  SQL_LOG_PATH = vim.fn.stdpath("data") .. "/poste/sql_log.jsonl"
  local dir = vim.fn.fnamemodify(SQL_LOG_PATH, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  return SQL_LOG_PATH
end

function M.format_log_entry(entry)
  local data = {
    ts = os.date("!%Y-%m-%dT%H:%M:%S"),
  }
  if entry.source then data.source = entry.source end
  if entry.table_name then data["table"] = entry.table_name end
  if entry.connection then data.connection = entry.connection end
  if entry.dialect then data.dialect = entry.dialect end
  if entry.database then data.database = entry.database end
  if entry.sql then data.sql = entry.sql end
  if entry.status then data.status = entry.status end
  if entry.elapsed_ms then data.elapsed_ms = entry.elapsed_ms end
  if entry.error_msg then data.error = entry.error_msg end
  if entry.edit_summary then data.edit_summary = entry.edit_summary end
  if entry.affected_rows then data.affected_rows = entry.affected_rows end
  return vim.json.encode(data)
end

function M.write_log(entry)
  local path = get_log_path()
  local line = M.format_log_entry(entry) .. "\n"
  local f = io.open(path, "a")
  if f then
    f:write(line)
    f:close()
  end
  _log_write_count = _log_write_count + 1
  if _log_write_count < const.LOG_TRIM_EVERY then return end
  _log_write_count = 0
  local lines = {}
  for l in io.lines(path) do
    lines[#lines + 1] = l
  end
  if #lines > MAX_LOG_ENTRIES then
    local keep = {}
    for i = #lines - MAX_LOG_ENTRIES + 1, #lines do
      keep[#keep + 1] = lines[i]
    end
    f = io.open(path, "w")
    if f then
      f:write(table.concat(keep, "\n"), "\n")
      f:close()
    end
  end
end

function M.set_log_path(path)
  SQL_LOG_PATH = path
end

return M
