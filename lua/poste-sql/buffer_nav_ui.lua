local D = require("poste-sql.dataset")
local C = require("poste-sql.constants")

local M = {}

function M.format_conn_short(conn)
  if not conn or conn == "" then return nil end
  local host, port, db = conn:match("^%w+://[^@]*@([^:]+):(%d+)/([^?]+)")
  if host then return string.format("%s:%s/%s", host, port, db) end
  return conn:match("/([^/]+)$") or conn
end

function M.build_preview_float_opts(title)
  return {
    filetype = "text",
    title = title,
    title_pos = "left",
    width_ratio = C.FLOAT_WIDTH_RATIO,
    max_width = C.FLOAT_MAX_WIDTH,
    width_padding = 2,
    height_ratio = C.FLOAT_HEIGHT_RATIO,
    extra_height = 1,
  }
end

function M.build_status_winbar(meta, tab, total_tabs, active_idx)
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
        "%#PosteSqlMetaDim#", tab.page, tab.num_pages, "%#PosteSqlMeta#")
    else
      left = left .. "  %#PosteSqlMetaDim#All%#PosteSqlMeta#"
    end
  end

  if tab and tab.filter_active and tab.filter_col_name then
    local fv = tab.filter_val
    local fvs = (fv == nil or fv == vim.NIL) and "NULL" or tostring(fv)
    left = left .. string.format("  %sfilter: %s=%s%s",
      "%#PosteFilterActive#", tab.filter_col_name, fvs, "%#PosteSqlMeta#")
  end

  if tab and tab.search_text and tab.search_matches and #tab.search_matches > 0 then
    local cnt = string.format("%d/%d", tab.search_idx or 0, #tab.search_matches)
    local info = tab.search_text .. " (" .. cnt .. ")"
    left = left .. string.format("  %ssearch: %s%s",
      "%#PosteSearchActive#", info, "%#PosteSqlMeta#")
  elseif tab and tab.search_text then
    left = left .. string.format("  %ssearch: %s (0)%s",
      "%#PosteSearchActive#", tab.search_text, "%#PosteSqlMeta#")
  end

  local right = ""
  local current_tab = D.T()
  local pending = current_tab and current_tab.edit_state and current_tab.edit_state.dirty
    and require("poste-sql.editor").pending_changes_text(current_tab.edit_state)
  if pending then
    right = right .. pending .. "  "
  end
  if total_tabs > 1 then
    local label = meta.table_name or ("result " .. active_idx)
    right = right .. string.format("[%d/%d: %s] ", active_idx, total_tabs, label)
  elseif meta.table_name then
    right = right .. string.format("[%s] ", meta.table_name)
  end
  right = right .. (M.format_conn_short(meta.connection) or "")

  local text = left .. "%=" .. right
  return "%#PosteSqlMeta#" .. text
end

return M
