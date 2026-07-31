local M = {}

function M.utf8_char_bytes(byte)
  if byte < 0x80 then return 1 end
  if byte < 0xE0 then return 2 end
  if byte < 0xF0 then return 3 end
  return 4
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

return M
