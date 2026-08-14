local M = {}

local function normalize_text(text)
  if text:sub(1, 3) == "\239\187\191" then
    text = text:sub(4)
  end
  text = text:gsub("\r\n", "\n")
  text = text:gsub("\r", "\n")
  return text
end

function M.parse_csv(text)
  text = normalize_text(text)
  local parsed_rows = {}
  local i = 1
  local len = #text

  while i <= len do
    local row = {}
    local in_quoted = false
    local val_chars = {}

    while i <= len do
      local ch = text:sub(i, i)
      if in_quoted then
        if ch == '"' then
          local next = text:sub(i + 1, i + 1)
          if next == '"' then
            table.insert(val_chars, '"')
            i = i + 2
          else
            in_quoted = false
            i = i + 1
          end
        else
          table.insert(val_chars, ch)
          i = i + 1
        end
      elseif ch == '"' then
        in_quoted = true
        i = i + 1
      elseif ch == "," then
        table.insert(row, table.concat(val_chars))
        val_chars = {}
        i = i + 1
      elseif ch == "\n" or ch == "\r" then
        i = i + 1
        break
      else
        table.insert(val_chars, ch)
        i = i + 1
      end
    end
    table.insert(row, table.concat(val_chars))

    local trimmed_first = (row[1] or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #row > 1 or trimmed_first ~= "" then
      table.insert(parsed_rows, row)
    end
  end

  if #parsed_rows == 0 then
    return nil, "No data rows found"
  end

  local header = parsed_rows[1]
  local num_cols = #header
  local data_rows = {}
  for i = 2, #parsed_rows do
    local row = parsed_rows[i]
    if #row ~= num_cols then
      return nil, string.format("Row %d: expected %d columns, got %d", i, num_cols, #row)
    end
    table.insert(data_rows, row)
  end

  return { columns = header, rows = data_rows }
end

function M.parse_tsv(text)
  text = normalize_text(text)
  local raw_lines = vim.split(text, "\n")
  local rows = {}
  for _, raw in ipairs(raw_lines) do
    local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then
      local row = vim.split(trimmed, "\t")
      table.insert(rows, row)
    end
  end

  if #rows == 0 then
    return nil, "No data rows found"
  end

  local header = rows[1]
  local num_cols = #header
  local data_rows = {}
  for i = 2, #rows do
    local row = rows[i]
    if #row ~= num_cols then
      return nil, string.format("Row %d: expected %d columns, got %d", i, num_cols, #row)
    end
    table.insert(data_rows, row)
  end

  return { columns = header, rows = data_rows }
end

function M.parse_json(text)
  text = normalize_text(text)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return nil, "Invalid JSON: " .. tostring(ok)
  end
  if #data == 0 then
    return nil, "JSON array is empty"
  end

  local seen = {}
  for _, obj in ipairs(data) do
    if type(obj) == "table" then
      for k, _ in pairs(obj) do
        seen[k] = true
      end
    end
  end
  local keys = {}
  for k, _ in pairs(seen) do
    table.insert(keys, k)
  end
  table.sort(keys)

  if #keys == 0 then
    return nil, "No keys found in JSON objects"
  end

  local rows = {}
  for _, obj in ipairs(data) do
    if type(obj) ~= "table" then
      return nil, "Expected array of objects"
    end
    local row = {}
    for _, k in ipairs(keys) do
      local v = obj[k]
      if v == nil or v == vim.NIL then
        table.insert(row, vim.NIL)
      else
        table.insert(row, tostring(v))
      end
    end
    table.insert(rows, row)
  end

  return { columns = keys, rows = rows }
end

function M.detect_format(content, filepath)
  if filepath then
    local ext = filepath:lower():match("%.([^%.]+)$")
    if ext == "csv" then return "csv" end
    if ext == "tsv" then return "tsv" end
    if ext == "json" then return "json" end
  end

  local trimmed = content:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed:sub(1, 1) == "[" or trimmed:sub(1, 1) == "{" then
    local ok, _ = pcall(vim.json.decode, trimmed)
    if ok then return "json" end
  end

  local first_line = content:match("^[^\n]+")
  if first_line then
    local tab_count = select(2, first_line:gsub("\t", ""))
    local comma_count = select(2, first_line:gsub(",", ""))
    if tab_count > comma_count and tab_count > 0 then
      return "tsv"
    end
    if comma_count > 0 then
      return "csv"
    end
  end

  return nil
end

return M
