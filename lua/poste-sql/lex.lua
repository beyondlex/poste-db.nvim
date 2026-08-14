local M = {}

function M.is_comment_or_string(line, pos)
  local i = 1
  local in_string = false
  local string_char = nil
  local in_line_comment = false
  local in_block_comment = 0
  while i <= #line do
    local ch = line:sub(i, i)
    if in_line_comment then
      if i >= pos then return true end
      i = i + 1
    elseif in_block_comment > 0 then
      if ch == "*" and line:sub(i + 1, i + 1) == "/" then
        in_block_comment = in_block_comment - 1
        i = i + 2
      else
        i = i + 1
      end
      if i >= pos and in_block_comment > 0 then return true end
    elseif in_string then
      if ch == "\\" then
        i = i + 2
      elseif ch == string_char then
        in_string = false
        i = i + 1
      else
        i = i + 1
      end
      if i >= pos and in_string then return true end
    elseif ch == "-" and line:sub(i + 1, i + 1) == "-" then
      in_line_comment = true
      i = i + 2
    elseif ch == "/" and line:sub(i + 1, i + 1) == "*" then
      in_block_comment = in_block_comment + 1
      i = i + 2
    elseif ch == "'" or ch == '"' or ch == "`" then
      in_string = true
      string_char = ch
      i = i + 1
    else
      i = i + 1
    end
  end
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