local M = {}

function M.is_comment_or_string(line, pos)
  local i = 1
  local region_start = nil
  local region_type = nil
  local string_char = nil
  local in_block_comment = 0

  while i <= #line do
    local ch = line:sub(i, i)
    if region_type == "line_comment" then
      if pos >= region_start then return true end
      i = i + 1
    elseif region_type == "block_comment" then
      if ch == "*" and line:sub(i + 1, i + 1) == "/" then
        if pos >= region_start and pos <= i + 1 then return true end
        in_block_comment = in_block_comment - 1
        if in_block_comment == 0 then region_type = nil; region_start = nil end
        i = i + 2
      else
        i = i + 1
      end
    elseif region_type == "string" then
      if ch == "\\" then
        i = i + 2
      elseif ch == string_char then
        if pos >= region_start and pos <= i then return true end
        region_type = nil; region_start = nil; string_char = nil
        i = i + 1
      else
        i = i + 1
      end
    elseif ch == "-" and line:sub(i + 1, i + 1) == "-" then
      region_start = i; region_type = "line_comment"; i = i + 2
    elseif ch == "/" and line:sub(i + 1, i + 1) == "*" then
      if in_block_comment == 0 then region_start = i; region_type = "block_comment" end
      in_block_comment = in_block_comment + 1; i = i + 2
    elseif ch == "'" or ch == '"' or ch == "`" then
      region_start = i; region_type = "string"; string_char = ch; i = i + 1
    else
      i = i + 1
    end
  end
  if region_type == "line_comment" and pos >= region_start then return true end
  if region_type == "block_comment" and pos >= region_start then return true end
  if region_type == "string" and pos >= region_start then return true end
  return false
end

function M.find_use_database(line)
  if not line then return nil end
  local trimmed = line:match("^%s*(.-)%s*$") or ""
  if trimmed == "" then return nil end
  local _, match_end, name = trimmed:find("^[Uu][Ss][Ee]%s+(%S+)")
  if not match_end then return nil end
  name = name:gsub(";$", "")
  name = name:gsub("^['\"`]", ""):gsub("['\"`]$", "")
  if M.is_comment_or_string(trimmed, 1) then return nil end
  return name
end

function M.find_block_for_line(lines, cursor_line)
  local block_start = 1
  for i = cursor_line - 1, 1, -1 do
    if lines[i] and lines[i]:match("^%s*###") then
      block_start = i + 1
      break
    end
  end
  return block_start
end

return M