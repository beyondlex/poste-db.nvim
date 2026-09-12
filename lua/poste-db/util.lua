local M = {}

local width = require("poste-db.width")

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

--- Deprecated: kept for callers of the old util API. strdisplaywidth()-based
--- truncation under-counts Indic spacing marks — width.truncate() is the
--- maintained implementation (see lua/poste-db/width.lua and LEARNINGS #16).
function M.truncate_displaywidth(s, max_dw)
  return width.truncate(s, max_dw)
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
