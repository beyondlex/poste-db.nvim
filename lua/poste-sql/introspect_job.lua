local const = require("poste-sql.constants")

local M = {}

function M.decode_json_table(output, failure_message)
  local ok, parsed = pcall(vim.json.decode, output)
  if not ok or type(parsed) ~= "table" then
    vim.notify(failure_message, vim.log.levels.ERROR, { title = const.PLUGIN_TITLE })
    return nil
  end
  return parsed
end

function M.append_stderr(stderr_lines, data, log_prefix)
  if not data then return end
  local state = log_prefix and require("poste.state") or nil
  for _, l in ipairs(data) do
    if l ~= "" then
      stderr_lines[#stderr_lines + 1] = l
      if log_prefix then
        state.log("ERROR", log_prefix .. l)
      end
    end
  end
end

function M.notify_exit_error(kind, code, stderr_lines, title)
  local msg = kind .. " exited with code " .. code
  if stderr_lines and #stderr_lines > 0 then
    msg = msg .. "\n" .. table.concat(stderr_lines, "\n")
  end
  vim.notify(msg, vim.log.levels.ERROR, { title = title or const.PLUGIN_TITLE })
end

return M
