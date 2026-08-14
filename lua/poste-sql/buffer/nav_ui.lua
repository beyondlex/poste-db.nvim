--- Dataset winbar UI --- status line fragments for the dataset window.
local D = require("poste-sql.dataset")
local state = require("poste.state")

local M = {}

local ICON_DATABASE = "\239\135\128"
local ICON_TABLE    = "\239\131\142"

function M.format_conn_short(conn)
  if not conn or conn == "" then return nil end
  local host, port, db = conn:match("^%w+://[^@]*@([^:]+):(%d+)/([^?]+)")
  if host then return string.format("%s:%s/%s", host, port, db) end
  return conn:match("/([^/]+)$") or conn
end

function M.build_statusline_context(meta)
  if not meta or meta.type ~= "resultset" then return nil end

  local parts = {}

  local conn = meta.connection
  if conn and conn ~= "" then
    local host, port = conn:match("^%w+://[^@]*@([^:]+):(%d+)")
    if host then
      parts[#parts + 1] = string.format("%s:%s", host, port)
    end
    local db = conn:match("^%w+://[^@]*@[^/]+/([^?]+)")
    if db and db ~= "" then
      db = (db:gsub("/$", ""))
      parts[#parts + 1] = ICON_DATABASE .. " " .. db
    end
  end

  local tbl = meta.table_name
  if tbl and tbl ~= "" then
    parts[#parts + 1] = ICON_TABLE .. " " .. tbl
  end

  if #parts == 0 then return nil end
  return table.concat(parts, "  ")
end

function M.update_dataset_statusline(meta)
  local buf = D.dataset_buffer
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local ctx = M.build_statusline_context(meta)
  vim.b[buf].poste_sql_context = ctx or ""
  if meta and meta.connection then
    vim.b[buf].poste_sql_conn = meta.connection
  end
  vim.cmd("redrawstatus")
end

function M.build_status_left(meta, tab)
  if not meta or meta.type ~= "resultset" then return nil end
  local rows = meta.total_rows or meta.row_count or 0
  local ms = meta.total_execution_time_ms or 0

  local left = string.format("  %d row%s · %dms", rows, rows == 1 and "" or "s", ms)

  if tab and tab.sort then
    local col_name = meta.columns and meta.columns[tab.sort.col] and meta.columns[tab.sort.col].name
    if col_name then
      local arrow = tab.sort.ascending and " ↑" or " ↓"
      left = left .. "   " .. col_name .. arrow
    end
  end

  if tab and tab.num_pages and tab.num_pages > 1 and (tab.padded_full or tab.layout) then
    if tab.pagination_enabled then
      left = left .. string.format("  %sPage %d/%d%s",
        "%#PosteDbDatasetMetaDim#", tab.page, tab.num_pages, "%#PosteDbDatasetMeta#")
    else
      left = left .. "  %#PosteDbDatasetMetaDim#All%#PosteDbDatasetMeta#"
    end
  end

  if tab and tab.filter_active and tab.filter_col_name then
    local fv = tab.filter_val
    local fvs = (fv == nil or fv == vim.NIL) and "NULL" or tostring(fv)
    left = left .. string.format("  %sfilter: %s=%s%s",
      "%#PosteDbDatasetFilterActive#", tab.filter_col_name, fvs, "%#PosteDbDatasetMeta#")
  end

  if tab and tab.search_text and tab.search_matches and #tab.search_matches > 0 then
    local cnt = string.format("%d/%d", tab.search_idx or 0, #tab.search_matches)
    local info = tab.search_text .. " (" .. cnt .. ")"
    left = left .. string.format("  %ssearch: %s%s",
      "%#PosteDbDatasetSearchActive#", info, "%#PosteDbDatasetMeta#")
  elseif tab and tab.search_text then
    left = left .. string.format("  %ssearch: %s (0)%s",
      "%#PosteDbDatasetSearchActive#", tab.search_text, "%#PosteDbDatasetMeta#")
  end

  return left
end

function M.build_status_right(meta, total_tabs, active_idx, pending)
  if not meta or meta.type ~= "resultset" then return nil end

  local right = ""
  if pending then
    right = right .. pending .. "  "
  end
  if total_tabs > 1 then
    local label = meta.table_name or ("result " .. active_idx)
    local next_k = state.get_keymap("sql_dataset", "next_tab", "<Tab>")
    local prev_k = state.get_keymap("sql_dataset", "prev_tab", "<S-Tab>")
    right = right .. string.format("[%d/%d: %s] (%s/%s) ", active_idx, total_tabs, label, prev_k, next_k)
  end

  return right
end

function M.build_pending_changes_text(tab)
  if not tab or not tab.edit_state or not tab.edit_state.dirty then
    return nil
  end
  return require("poste-sql.editor").pending_changes_text(tab.edit_state)
end

function M.build_status_winbar_text(meta, tab, total_tabs, active_idx, pending)
  if not meta or meta.type ~= "resultset" then return nil end

  local left = M.build_status_left(meta, tab)
  local right = M.build_status_right(meta, total_tabs, active_idx, pending)
  if not left or not right then return nil end

  local text = left .. "%=" .. right
  return "%#PosteDbDatasetMeta#" .. text
end

function M.build_status_winbar(meta, tab, total_tabs, active_idx)
  local current_tab = D.T()
  local pending = M.build_pending_changes_text(current_tab)
  M.update_dataset_statusline(meta)
  return M.build_status_winbar_text(meta, tab, total_tabs, active_idx, pending)
end

return M
