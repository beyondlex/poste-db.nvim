local state = require("poste.state")

local M = {}

function M.redact_url(str)
  if type(str) ~= "string" then return str end
  return (str:gsub("://([^:]+):([^@/]+)@", "://%1:***@"))
end

function M.redact_cmd(cmd)
  local parts = {}
  local skip = false
  for _, v in ipairs(cmd) do
    if skip then
      table.insert(parts, "<redacted>")
      skip = false
    elseif v == "--connection" or v == "--connection-url" then
      table.insert(parts, v)
      skip = true
    else
      table.insert(parts, v)
    end
  end
  return table.concat(parts, " ")
end

function M.redact_cmd_str(cmd)
  if type(cmd) ~= "string" then return cmd end
  return cmd:gsub("(--connection%-url [^%s]+)", "--connection-url <redacted>")
    :gsub("(--connection [^%s]+)", "--connection <redacted>")
end

local function log(level, msg)
  state.log(level, M.redact_url(msg))
end

function M.info(msg) log("INFO", msg) end
function M.warn(msg) log("WARN", msg) end
function M.error(msg) log("ERROR", msg) end
function M.debug(msg) log("DEBUG", msg) end

function M.info_fmt(fmt, ...)
  local args = { ... }
  for i, v in ipairs(args) do
    if type(v) == "string" then
      args[i] = M.redact_url(v)
    end
  end
  log("INFO", string.format(fmt, unpack(args)))
end

function M.warn_fmt(fmt, ...)
  local args = { ... }
  for i, v in ipairs(args) do
    if type(v) == "string" then
      args[i] = M.redact_url(v)
    end
  end
  log("WARN", string.format(fmt, unpack(args)))
end

return M