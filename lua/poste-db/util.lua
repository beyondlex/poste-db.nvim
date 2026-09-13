--- `clean_nil` / `find_file_upwards` / `ensure_job_data` are merged from
--- poste.nvim@5b3759e lua/poste/util.lua (family dissolution).
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

---------------------------------------------------------------------------
-- Merged from poste.nvim@5b3759e lua/poste/util.lua (family dissolution)
---------------------------------------------------------------------------

--- Recursively remove vim.NIL values from a parsed JSON table.
---
--- `vim.json.decode` converts JSON `null` to `vim.NIL`. This function
--- replaces those values with Lua `nil` so they can be safely compared
--- with `== nil`. It mutates the table in place and also returns it.
---
--- @param t table|nil  A table from vim.json.decode, or nil
--- @return table|nil    The same table with vim.NIL values removed, or nil
function M.clean_nil(t)
  if not t or type(t) ~= "table" then return t end
  for k, v in pairs(t) do
    if v == vim.NIL then
      t[k] = nil
    elseif type(v) == "table" then
      M.clean_nil(v)
    end
  end
  return t
end

--- Walk up the directory tree from `start_dir` to find a file.
--- Checks each ancestor directory for the given filename, stopping at
--- the filesystem root. Returns the first matching absolute path, or nil.
---
--- @param filename  string  File name to search for (e.g. "env.json")
--- @param start_dir string  Directory to start searching from
--- @return string|nil       Absolute path to the found file, or nil
function M.find_file_upwards(filename, start_dir)
  if not filename or filename == "" then return nil end
  local dir = start_dir or vim.fn.getcwd()
  while true do
    local candidate = dir .. "/" .. filename
    if vim.fn.filereadable(candidate) == 1 then
      return candidate
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      return nil
    end
    dir = parent
  end
end

--- Given an array of lines from a job's stdout/stderr callback, remove
--- trailing empty strings. Neovim's jobstart callbacks often include
--- one or more trailing empty strings; this is a safe normalizer.
---
--- Returns the same array (mutated in place) with trailing empties
--- removed, for consistency with existing calling conventions.
---
--- @param data string[]|nil  Lines from a job callback
--- @return string[]          Cleaned array (may be empty)
function M.ensure_job_data(data)
  if not data or type(data) ~= "table" then return {} end
  while #data > 0 and data[#data] == "" do
    data[#data] = nil
  end
  return data
end

return M
