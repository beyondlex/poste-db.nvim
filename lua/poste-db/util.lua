local M = {}

function M.utf8_char_bytes(byte)
  if byte < 0x80 then return 1 end
  if byte < 0xE0 then return 2 end
  if byte < 0xF0 then return 3 end
  return 4
end

function M.is_dark_color(color)
  if not color then return true end
  local r = math.floor(color / 0x10000) % 0x100 / 255
  local g = math.floor(color / 0x100) % 0x100 / 255
  local b = color % 0x100 / 255
  return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
end

function M.truncate_displaywidth(s, max_dw)
  if not s or s == "" then return s or "" end
  local dw = 0
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    local char_byte_len = M.utf8_char_bytes(b)
    local char = s:sub(i, i + char_byte_len - 1)
    local char_dw = vim.fn.strdisplaywidth(char)
    if dw + char_dw > max_dw then break end
    dw = dw + char_dw
    i = i + char_byte_len
  end
  return s:sub(1, i - 1)
end

--- Truncate at a BYTE budget without splitting a UTF-8 character: the cut
--- point backs up over continuation bytes. (No ellipsis appended.) A plain
--- `sub` cut emitted invalid UTF-8 whenever the budget landed inside a CJK
--- character — schema summaries and AI context blocks are routinely CJK.
function M.utf8_safe_cut(s, max_bytes)
  if not s or #s <= max_bytes then return s or "" end
  local cut = max_bytes
  while cut > 0 do
    local b = s:byte(cut + 1)
    if not b or b < 0x80 or b >= 0xC0 then break end -- not a continuation byte
    cut = cut - 1
  end
  return s:sub(1, cut)
end

return M
