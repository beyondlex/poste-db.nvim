--- Edit commit log --- thin delegate to the central sql_log writer.
--- The write/trim implementation lives in poste-db.sql_log so every request
--- path (not just edit commits) shares one journal and one trim policy.
local sql_log = require("poste-db.sql_log")

local M = {}

function M.format_log_entry(entry)
  return sql_log.format_entry(entry)
end

function M.write_log(entry)
  return sql_log.record(entry)
end

function M.set_log_path(path)
  sql_log.set_log_path(path)
end

return M
