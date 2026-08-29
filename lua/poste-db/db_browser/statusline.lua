--- DB Browser statusline: connection context + yanked indicator.
---
--- Mirrors the dataset window's statusline approach (buffer/nav_ui.lua): a
--- per-window `statusline` option carrying persistent context. It shows the
--- connection/database/schema path under the cursor (so the statusline is
--- actually informative, not just the buffer name), plus the yank-register
--- indicator when the register holds a source.

local icons = require("poste-db.db_browser.icons")
local MARKER_YANKED = icons.MARKER_YANKED

local M = {}

local ICON_CONN = "\239\136\179"
local ICON_DB = "\239\135\128"
local ICON_SCHEMA = "\239\129\187"

--- Escape `%` for use inside a statusline string.
local function statusline_escape(s)
  return (s:gsub("%%", "%%%%"))
end

--- Walk up from `node` through .parent to build a conn→db→schema path label,
--- e.g. "▃ pg-dev  🗄 blog  📁 public". Hangs at the first missing piece.
---@param node table|nil browser tree node under the cursor
---@param root_nodes table list of connection root nodes
---@return string|nil
function M.node_path(node, root_nodes)
  if not node then return nil end

  local parts = {}
  local cur = node
  while cur do
    if cur.node_type == "connection" then
      table.insert(parts, 1, "%#PosteDbBrowserIconConn#" .. ICON_CONN .. " %*" .. statusline_escape(cur.name))
      break
    elseif cur.node_type == "database" then
      table.insert(parts, 1, "%#PosteDbBrowserIconDb#" .. ICON_DB .. " %*" .. statusline_escape(cur.name))
    elseif cur.node_type == "schema" then
      table.insert(parts, 1, "%#PosteDbBrowserIconSchema#" .. ICON_SCHEMA .. " %*" .. statusline_escape(cur.name))
    end
    cur = cur.parent
  end

  -- Fallback: the first root connection when the node is detached (tests).
  if #parts == 0 then
    local conn = root_nodes and root_nodes[1] and root_nodes[1].name
    if conn then
      return "%#PosteDbBrowserIconConn#" .. ICON_CONN .. " %*" .. statusline_escape(conn)
    end
    return nil
  end
  return table.concat(parts, "  ")
end

local function connection_label(conn_label)
  return "%#PosteDbBrowserIconConn#" .. ICON_CONN .. " %*" .. statusline_escape(conn_label)
end

--- Build the DB Browser statusline text.
---@param node_path string|nil conn/db/schema path under the cursor
---@param multi_select table|nil {active=boolean} for the selection counter
---@param conn_label string|nil fallback connection name shown when no cursor path
---@return string statusline text; "" keeps the default statusline
function M.build(node_path, multi_select, conn_label)
  local yank = require("poste-db.db_browser.yank")
  local yanked = yank.statusline_label()

  local text = "%#PosteDbBrowserHeader# DB Browser%*"
  local ctx = node_path
  if (not ctx or ctx == "") and conn_label and conn_label ~= "" then
    ctx = connection_label(conn_label)
  end
  if ctx and ctx ~= "" then
    text = text .. "  " .. ctx
  end

  if multi_select and multi_select.active then
    local count = 0
    for _ in pairs(multi_select.selected or {}) do
      count = count + 1
    end
    if count > 0 then
      text = text .. "  %#PosteDbBrowserSelected#[" .. count .. " selected]%*"
    end
  end

  if yanked then
    text = text .. "%<" .. "%#PosteDbBrowserYanked#  " .. MARKER_YANKED
      .. " " .. statusline_escape(yanked) .. "%*"
  end

  return text
end

--- Refresh the statusline on the window that owns `browser_buf`, if any.
--- Falls back to a buffer set so the indicator survives window swaps.
function M.update(browser_buf, node_path, multi_select, conn_label)
  if not browser_buf or not vim.api.nvim_buf_is_valid(browser_buf) then return end

  local text = M.build(node_path, multi_select, conn_label)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == browser_buf then
      if text == "" then
        pcall(vim.api.nvim_set_option_value, "statusline", "", { win = win })
      else
        pcall(vim.api.nvim_set_option_value, "statusline", text, { win = win })
      end
    end
  end

  vim.cmd("redrawstatus")
end

return M