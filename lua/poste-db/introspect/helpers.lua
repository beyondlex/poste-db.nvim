--- Introspection --- shared helpers for DDL/column display formatting.
local M = {}

local LABEL_WIDTH = 10

function M.build_connection_lines(config)
  local lines = {}
  local fields = {
    { "Dialect", config.dialect },
    { "Host", config.host },
    { "Port", config.port },
    { "Database", config.database },
    { "User", config.user },
    { "Socket", config.path },
  }
  for _, field in ipairs(fields) do
    local label, value = field[1], field[2]
    if value and value ~= "" then
      lines[#lines + 1] = string.format("  %s%s  %s", string.rep(" ", LABEL_WIDTH - #label), label, value)
    end
  end
  return lines
end

function M.build_database_info_lines(item)
  local lines = {}
  local function v(val)
    if val == vim.NIL then return nil end
    return val
  end
  local fields = {
    { "Name", v(item.name) },
    { "Table Count", v(item.table_count) },
    { "Total Size", v(item.total_size) or (v(item.size_mb) and string.format("%.2f MB", v(item.size_mb)) or nil) },
    { "Encoding", v(item.encoding) },
    { "Charset", v(item.charset) },
    { "Collation", v(item.collation) },
    { "File", v(item.file) },
  }
  for _, field in ipairs(fields) do
    local label, value = field[1], field[2]
    if value ~= nil and value ~= "" and value ~= vim.NIL then
      lines[#lines + 1] = string.format("  %-12s  %s  ", label, value)
    end
  end
  return lines
end

function M.build_table_lines(items)
  local lines = {}
  for _, item in ipairs(items or {}) do
    local suffix = item.type ~= "BASE TABLE" and "  (" .. item.type .. ")" or ""
    lines[#lines + 1] = "  " .. item.name .. suffix
  end
  return lines
end

function M.build_column_info_lines(table_name, col)
  local lines = {
    "  Table:    " .. table_name,
    "  Type:     " .. tostring(col.type or ""),
    "  Nullable: " .. tostring(col.nullable == true and "YES" or (col.nullable == false and "NO" or "?")),
    "  Default:  " .. (col.default ~= vim.NIL and col.default or "(null)"),
  }
  if col.extra and col.extra ~= "" and col.extra ~= vim.NIL then
    lines[#lines + 1] = "  Extra:    " .. tostring(col.extra)
  end
  if col.max_length then
    lines[#lines + 1] = "  Max Len:  " .. tostring(col.max_length)
  end
  if col.comment and col.comment ~= vim.NIL then
    lines[#lines + 1] = "  Comment:  '" .. tostring(col.comment) .. "'"
  end
  return lines
end

return M
