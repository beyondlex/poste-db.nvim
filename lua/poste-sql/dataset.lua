--- Shared dataset state extracted from buffer.lua.
--- Tabs, floats, scroll state — no poste deps, only vim.api.*.

local M = {}

M.dataset_buffer = nil
M.dataset_window = nil
M.dataset_tabpage = nil

M.LEFT_PADDING = 2
M.PADDING_SPACES = string.rep(" ", M.LEFT_PADDING)

M.tabs = {}
M.active_tab_idx = 0

M.scroll_autocmd_id = nil
M.resize_autocmd_id = nil
M.search_ns = vim.api.nvim_create_namespace("poste_sql_search")

function M.tab_count()
  return #M.tabs
end

function M.T()
  return M.tabs[M.active_tab_idx]
end

function M.alloc_tab(idx)
  if not M.tabs[idx] then
    M.tabs[idx] = {
      meta = nil, lines = nil, padded = nil,
      header_text = nil, header_index = nil,
      sort = nil, original_rows = nil, is_sorting = false,
      data = nil,
      cursor = { row = 1, col = 1 },
      leftcol = 0,
      padded_full = nil, meta_full = nil,
      page = 1, page_size = 50, num_pages = 1,
      pagination_enabled = true, visible_rows = nil,
      filter_col = nil, filter_val = nil, filter_col_name = nil,
      filter_active = false, filtered_indices = nil,
      search_text = nil, search_matches = {}, search_idx = 0,
      search_matches_by_page = nil, search_total_matches = 0,
      layout = nil, rows_source = nil, view_indices = nil,
      row_number_mode = "source",
      edit_state = nil,
      original_sql = nil,
      src_file = nil,
      src_buf = nil,
    }
  end
  return M.tabs[idx]
end

--- Compute view_indices from filtered_indices + sort state.
--- Operates on tab state only; no poste module deps.
function M.compute_view_indices(tab)
  local src = tab.rows_source
  if not src then return end
  local indices = {}
  if tab.filtered_indices then
    for i, idx in ipairs(tab.filtered_indices) do indices[i] = idx end
  else
    for i = 1, #src do indices[i] = i end
  end
  if tab.sort then
    local col = tab.sort.col
    local ascending = tab.sort.ascending
    table.sort(indices, function(a, b)
      local va, vb = src[a][col], src[b][col]
      if va == nil or va == vim.NIL then return false end
      if vb == nil or vb == vim.NIL then return true end
      local ta, tb = type(va), type(vb)
      if ta == "number" and tb == "number" then
        if ascending then return va < vb else return va > vb end
      end
      if ta == "boolean" and tb == "boolean" then
        if ascending then return not va and vb else return va and not vb end
      end
      -- Coerce numeric-looking strings (bigints arrive as strings) so a
      -- bigint column sorts numerically instead of lexicographically.
      local na = ta == "number" and va
        or (ta == "string" and va:match("^%-?%d+%.?%d*$") and tonumber(va)) or nil
      local nb = tb == "number" and vb
        or (tb == "string" and vb:match("^%-?%d+%.?%d*$") and tonumber(vb)) or nil
      if na and nb then
        if ascending then return na < nb else return na > nb end
      end
      local sa, sb = tostring(va), tostring(vb)
      if ascending then return sa < sb else return sa > sb end
    end)
  end
  tab.view_indices = indices
end

return M
