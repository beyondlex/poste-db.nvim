--- Dataset cell navigation --- extract, format, yank, highlight individual cells.
local C = require("poste-db.constants")
local state = require("poste.state")
local sql_highlights = require("poste-db.highlights")

local M = {}

function M.get_resultset_cell(tab, row, col)
  if not tab or not tab.data or not tab.meta or tab.meta.type ~= "resultset" then return nil end
  local data = tab.data
  if not data or not data.results or #data.results == 0 then return nil end
  local res = data.results[1]
  if not res.rows or not res.rows[row] then return nil end
  return res, res.rows[row][col]
end

function M.json_pretty(val, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local pad1 = string.rep("  ", indent + 1)
  if type(val) == "table" then
    local is_array = #val > 0
    if is_array then
      local items = {}
      for _, v in ipairs(val) do
        items[#items + 1] = pad1 .. M.json_pretty(v, indent + 1)
      end
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "]"
    else
      local items = {}
      for k, v in pairs(val) do
        items[#items + 1] = pad1 .. '"' .. tostring(k) .. '": ' .. M.json_pretty(v, indent + 1)
      end
      table.sort(items)
      return "{\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "}"
    end
  elseif val == vim.NIL or val == nil then
    return "null"
  elseif type(val) == "boolean" then
    return tostring(val)
  elseif type(val) == "number" then
    if val == math.floor(val) then
      return string.format("%.0f", val)
    end
    return tostring(val)
  else
    local ok, encoded = pcall(vim.json.encode, val)
    return ok and encoded or ('"' .. tostring(val) .. '"')
  end
end

function M.try_pretty_json(s)
  local ok, decoded = pcall(vim.json.decode, s)
  if ok and type(decoded) == "table" then
    return M.json_pretty(decoded)
  end
  if ok and type(decoded) == "string" then
    local ok2, decoded2 = pcall(vim.json.decode, decoded)
    if ok2 and type(decoded2) == "table" then
      return M.json_pretty(decoded2)
    end
  end
  return nil
end

function M.pretty_print(val)
  if val == nil or val == vim.NIL then
    return "(NULL)", "text"
  end
  if type(val) == "table" then
    return M.json_pretty(val), "json"
  end
  if type(val) == "number" then
    if val == math.floor(val) then
      return string.format("%.0f", val), "text"
    end
    return tostring(val), "text"
  end
  local s = tostring(val)
  if type(val) == "string" then
    local pretty = M.try_pretty_json(s)
    if pretty then return pretty, "json" end
    local trimmed = s:match("^%s*(.*)")
    if trimmed ~= s then
      pretty = M.try_pretty_json(trimmed)
      if pretty then return pretty, "json" end
    end
  end
  return s, "text"
end

function M.clipboard_text(val)
  if val == nil or val == vim.NIL then
    return ""
  elseif type(val) == "table" then
    local ok, encoded = pcall(vim.json.encode, val)
    return ok and encoded or vim.inspect(val)
  elseif type(val) == "number" then
    if val == math.floor(val) then
      return string.format("%.0f", val)
    end
    return tostring(val)
  else
    return tostring(val)
  end
end

function M.yank_preview_text(val)
  local text = M.clipboard_text(val)
  return text:sub(1, C.YANK_PREVIEW_CHARS)
end

function M.collect_column_values(tab, col)
  if not tab or not tab.data or not tab.meta or tab.meta.type ~= "resultset" then return nil end
  local data = tab.data
  if not data or not data.results or #data.results == 0 then return nil end

  local res = data.results[1]
  if not res.rows or #res.rows == 0 then return nil end

  local values = {}
  for _, row in ipairs(res.rows) do
    local v = row[col]
    if v == nil or v == vim.NIL then
      values[#values + 1] = "NULL"
    elseif type(v) == "table" then
      local ok, encoded = pcall(vim.json.encode, v)
      values[#values + 1] = ok and encoded or vim.inspect(v)
    elseif type(v) == "number" then
      if v == math.floor(v) then
        values[#values + 1] = string.format("%.0f", v)
      else
        values[#values + 1] = tostring(v)
      end
    else
      values[#values + 1] = tostring(v)
    end
  end

  local col_name = res.columns and res.columns[col] and res.columns[col].name or tostring(col)
  return values, col_name
end

function M.build_column_yank_text(tab, col)
  local values, col_name = M.collect_column_values(tab, col)
  if not values then return nil end
  return table.concat(values, ", "), #values, col_name
end

function M.build_cell_yank_text(tab, row, col)
  local _, val = M.get_resultset_cell(tab, row, col)
  val = M.clipboard_text(val)
  return val, M.yank_preview_text(val)
end

function M.apply_cell_highlight(enabled, dataset_buffer, row, col, meta, col_starts)
  if enabled then
    sql_highlights.highlight_cell(dataset_buffer, row, col, meta, nil, col_starts)
  else
    sql_highlights.clear_cell_highlight(dataset_buffer)
  end
end

function M.toggle_cell_highlight(dataset_buffer, row, col, meta, col_starts)
  state.sql.highlight_cell = not state.sql.highlight_cell
  M.apply_cell_highlight(state.sql.highlight_cell, dataset_buffer, row, col, meta, col_starts)
  return state.sql.highlight_cell
end

return M
