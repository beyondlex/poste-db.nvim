local M = {}

function M.next_sort_state(tab, col)
  if not tab.sort or tab.sort.col ~= col then
    return { col = col, ascending = true }, false
  elseif tab.sort.ascending then
    return { col = col, ascending = false }, false
  else
    return nil, true
  end
end

function M.build_sort_render_payload(tab, data, active_idx)
  local sql_format = require("poste-sql.format")
  if tab.layout then
    local lines, meta = sql_format.render_view(
      tab.layout, tab.view_indices, tab.page, tab.page_size,
      { row_number_mode = tab.row_number_mode or "source" }
    )
    return lines, meta, {
      keep_tabs = true,
      tab_index = active_idx,
      layout = tab.layout,
      view_indices = tab.view_indices,
    }
  end

  local new_data = vim.deepcopy(data)
  local lines, meta = sql_format.format_resultset(new_data)
  return lines, meta, {
      keep_tabs = true,
      tab_index = active_idx,
  }
end

function M.prepare_current_col_sort(tab, data, active_idx, col)
  if not tab or not data or not data.results or #data.results == 0 then return nil end

  local res = data.results[1]
  if not res.rows or #res.rows == 0 then return nil end

  local next_sort, is_reset = M.next_sort_state(tab, col)
  if is_reset then
    tab.sort = nil
  else
    tab.sort = next_sort
  end

  tab.rows_source = tab.rows_source or res.rows
  require("poste-sql.dataset").compute_view_indices(tab)
  return M.build_sort_render_payload(tab, data, active_idx)
end

return M
