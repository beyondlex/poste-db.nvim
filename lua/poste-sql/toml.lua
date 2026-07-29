--- Minimal pure-Lua TOML parser.
--- Supports: [section] headers, key = "string", key = 123, key = true/false, # comments.
--- Returns { [section] = { key = value, ... }, ... }
local M = {}

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function parse_value(v)
  v = trim(v)
  if v == "true" then return true end
  if v == "false" then return false end
  local n = tonumber(v)
  if n then return n end
  if v:sub(1, 1) == '"' then
    v = v:sub(2, -2)
    v = v:gsub('\\"', '"')
    v = v:gsub("\\n", "\n")
    v = v:gsub("\\t", "\t")
    return v
  end
  return v
end

--- Parse TOML string content.
--- @param content string Raw TOML text
--- @return table|nil, string|nil parsed table, error_message
function M.parse(content)
  local result = {}
  local section = result

  for line in content:gmatch("([^\n]*)\n?") do
    local trimmed = trim(line)
    if trimmed == "" or trimmed:sub(1, 1) == "#" then
      -- skip blank lines and comments
    elseif trimmed:sub(1, 1) == "[" then
      local close = trimmed:find("]", 2)
      if not close then
        return nil, "Invalid table header: " .. line
      end
      local name = trim(trimmed:sub(2, close - 1))
      if name == "" then
        return nil, "Empty table header"
      end
      if not result[name] then
        result[name] = {}
      end
      section = result[name]
    else
      local eq = trimmed:find("=", 1, true)
      if not eq then
        return nil, "Invalid key=value line: " .. line
      end
      local key = trim(trimmed:sub(1, eq - 1))
      local val = parse_value(trimmed:sub(eq + 1))
      if key == "" then
        return nil, "Empty key in line: " .. line
      end
      section[key] = val
    end
  end

  return result, nil
end

--- Parse TOML from file.
--- @param filepath string Path to TOML file
--- @return table|nil, string|nil parsed table, error_message
function M.parse_file(filepath)
  local ok, data = pcall(vim.fn.readfile, filepath)
  if not ok or not data then
    return nil, "Failed to read " .. filepath
  end
  return M.parse(table.concat(data, "\n"))
end

return M