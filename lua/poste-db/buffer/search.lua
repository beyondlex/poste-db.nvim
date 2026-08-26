--- Dataset search --- find column, filter by cell, next/prev match, search highlight.
local D = require("poste-db.dataset")
local C = require("poste-db.constants")
local nav_ui = require("poste-db.buffer.nav_ui")
local sql_state = require("poste-db.state")

local sql_highlights = require("poste-db.highlights")
local sql_format = require("poste-db.format")
local float_window = require("poste-db.float_window")
local M = {}

-- Forward declarations
local update_winbar
local jump_to_search_match

--- Recompute search matches from search_text against the current view_indices.
--- The set of matching rows is unchanged by sort/filter (only their order), so
--- matches are re-derived to keep n/N and highlights correct after a reorder.
local function compute_matches(tab, text)
  tab.search_matches = {}
  tab.search_matches_by_page = {}
  local q = text:lower()
  local all_indices = tab.view_indices
  if not all_indices then
    all_indices = {}
    for i = 1, #tab.rows_source do all_indices[i] = i end
  end
  local total_count = 0
  for view_pos, src_idx in ipairs(all_indices) do
    local row_data = tab.rows_source[src_idx]
    for ci, val in ipairs(row_data) do
      local s = (val == nil or val == vim.NIL) and "" or tostring(val)
      if s:lower():find(q, 1, true) then
        total_count = total_count + 1
        local page = math.ceil(view_pos / tab.page_size)
        if not tab.search_matches_by_page[page] then
          tab.search_matches_by_page[page] = {}
        end
        tab.search_matches_by_page[page][#tab.search_matches_by_page[page] + 1] = {
          row = view_pos, col = ci, global_match_idx = total_count,
        }
        tab.search_matches[#tab.search_matches + 1] = { row = view_pos, col = ci }
      end
    end
  end
  tab.search_total_matches = total_count
end

--- Re-derive search matches after view_indices changed (sort/filter) so stale
--- view-position matches don't point at rows that are no longer results.
function M.recompute_after_view_change()
  local tab = D.T()
  if not tab or not tab.search_text then return end
  if not tab.rows_source then
    tab.search_text = nil; tab.search_matches = {}; tab.search_idx = 0
    tab.search_matches_by_page = nil; tab.search_total_matches = 0
    M.apply_search_highlights(); update_winbar()
    return
  end
  compute_matches(tab, tab.search_text)
  if #tab.search_matches > 0 then
    jump_to_search_match(1)
  else
    tab.search_idx = 0
    M.apply_search_highlights(); update_winbar()
  end
end

function M.apply_search_highlights()
  if not D.dataset_buffer or not vim.api.nvim_buf_is_valid(D.dataset_buffer) then return end
  vim.api.nvim_buf_clear_namespace(D.dataset_buffer, D.search_ns, 0, -1)
  local tab = D.T()
  if not tab or not tab.search_text or not tab.search_matches or #tab.search_matches == 0 then return end
  if not tab.meta then return end

  local data_start = tab.meta.data_start_line
  local page = tab.page or 1

  local matches = tab.search_matches_by_page and tab.search_matches_by_page[page]
  if not matches then return end

  for _, match in ipairs(matches) do
    local vis_row = match.row - (page - 1) * tab.page_size
    local buf_line = data_start + vis_row - 1
    local line = vim.api.nvim_buf_get_lines(D.dataset_buffer, buf_line - 1, buf_line, false)[1]
    if line then
      local range = sql_highlights.find_cell_range(line, match.col + 1)
      if range then
        local hl = (match.global_match_idx == tab.search_idx) and "PosteDbDatasetSearchCurrent" or "PosteDbDatasetSearchMatch"
        vim.api.nvim_buf_set_extmark(D.dataset_buffer, D.search_ns, buf_line - 1, range.ext_start, {
          end_row = buf_line - 1,
          end_col = range.ext_end,
          hl_group = hl,
          priority = 150,
        })
      end
    end
  end
end

jump_to_search_match = function(idx)
  local tab = D.T()
  if not tab or not tab.search_matches or #tab.search_matches == 0 then return end
  local match = tab.search_matches[idx]
  if not match then return end
  tab.search_idx = idx

  local paginated = tab.pagination_enabled and tab.num_pages and tab.num_pages > 1
    and (tab.padded_full or tab.layout)
  if paginated then
    local match_page = math.ceil(match.row / tab.page_size)
    if match_page ~= tab.page then
      tab.page = match_page
      require("poste-db.buffer.page").refresh_page()
    end
  end

  local posize = paginated and tab.page_size or nil
  local vis_row = posize and (match.row - (tab.page - 1) * posize) or match.row
  sql_state.cell.row = vis_row
  sql_state.cell.col = match.col
  local line = require("poste-db.buffer.nav").position_cursor(vis_row, match.col)
  local cs = tab.buffer_col_starts and tab.buffer_col_starts[(tab.meta.data_start_line or 1) + vis_row - 1]
  sql_highlights.highlight_cell(D.dataset_buffer, vis_row, match.col, tab.meta, line, cs)
  require("poste-db.buffer.header").update()
  M.apply_search_highlights()
  update_winbar()
end

function M.show_search()
  local tab = D.T()
  if not tab or not tab.data or not tab.meta then return end

  local buf, win = float_window.open_centered({}, {
    filetype = "poste_search",
    title = " Search ",
    title_pos = "center",
    width_ratio = 0.5,
    max_width = 50,
    width_padding = 0,
    height_ratio = 0.4,
    min_height = 1,
    extra_height = 1,
  })
  vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("complete", "", { buf = buf })

  vim.fn.prompt_setprompt(buf, "> ")
  vim.api.nvim_set_option_value("winhl", "Normal:NormalFloat,FloatBorder:FloatBorder", { win = win })

  local closed = false
  local function cleanup()
    if closed then return end
    closed = true
    pcall(vim.api.nvim_win_close, win, { force = true })
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  vim.fn.prompt_setcallback(buf, function(text)
    cleanup()
    if text == nil or text == "" then
      tab.search_text = nil; tab.search_matches = {}; tab.search_idx = 0
      M.apply_search_highlights(); update_winbar()
      return
    end
    tab.rows_source = tab.rows_source or (tab.data.results and tab.data.results[1] and tab.data.results[1].rows)
    if not tab.rows_source then return end
    tab.search_text = text
    compute_matches(tab, text)
    if #tab.search_matches > 0 then
      jump_to_search_match(1)
    else
      tab.search_idx = 0
      M.apply_search_highlights(); update_winbar()
      vim.notify("No matches for '" .. text .. "'", vim.log.levels.INFO, { title = C.TITLE })
    end
  end)

  local km = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("i", "<Esc>", cleanup, km)
  vim.keymap.set("i", "<C-c>", cleanup, km)

  vim.cmd("startinsert!")
end

function M.next_search_match()
  local tab = D.T()
  if not tab or not tab.search_matches or #tab.search_matches == 0 then return end
  local idx = (tab.search_idx % #tab.search_matches) + 1
  jump_to_search_match(idx)
end

function M.prev_search_match()
  local tab = D.T()
  if not tab or not tab.search_matches or #tab.search_matches == 0 then return end
  local idx = ((tab.search_idx - 2 + #tab.search_matches) % #tab.search_matches) + 1
  jump_to_search_match(idx)
end

function M.filter_by_current_cell()
  local tab = D.T()
  if not tab or not tab.data or not tab.meta then return end
  if tab.edit_state and tab.edit_state.dirty then
    vim.notify(C.EDIT_CONFLICT_MSG, vim.log.levels.WARN, { title = C.TITLE })
    return
  end
  local res = tab.data.results and tab.data.results[1]
  if not res or not res.rows or #res.rows == 0 then return end
  local row, col = sql_state.cell.row, sql_state.cell.col
  local paginated = tab.pagination_enabled and tab.num_pages and tab.num_pages > 1
    and (tab.padded_full or tab.layout)
  if paginated then
    row = row + (tab.page - 1) * tab.page_size
  end
  local col_name = tab.meta.columns and tab.meta.columns[col] and tab.meta.columns[col].name or tostring(col)

  tab.rows_source = tab.rows_source or res.rows
  local src_row = tab.view_indices and tab.view_indices[row] or row
  local filter_val = tab.rows_source[src_row] and tab.rows_source[src_row][col]
  if filter_val == nil or filter_val == vim.NIL then return end

  tab.filter_col = col; tab.filter_val = filter_val
  tab.filter_col_name = col_name; tab.filter_active = true
  tab.row_number_mode = "view"

  local indices = {}
  for i, r in ipairs(tab.rows_source) do
    if r[col] == filter_val then
      indices[#indices + 1] = i
    end
  end
  tab.filtered_indices = indices
  D.compute_view_indices(tab)

  local layout = tab.layout
  if layout then
    local page_limit = tab.pagination_enabled and tab.page_size or #tab.view_indices
    local lines, meta = sql_format.render_view(
      layout, tab.view_indices, 1, page_limit,
      { row_number_mode = "view" }
    )
    tab.page = 1
    require("poste-db.buffer").render_dataset(lines, meta, {
      data = tab.data,
      keep_tabs = true,
      tab_index = D.active_tab_idx,
      layout = layout,
      view_indices = tab.view_indices,
      row_number_mode = "view",
    })
  else
    local data = vim.deepcopy(tab.data)
    local fr = {}
    for _, idx in ipairs(tab.filtered_indices) do
      fr[#fr + 1] = tab.rows_source[idx]
    end
    data.results[1].rows = fr
    data.results[1].row_count = #fr
    local lines, meta = sql_format.format_resultset(data)
    require("poste-db.buffer").render_dataset(lines, meta, { data = data, keep_tabs = true, tab_index = D.active_tab_idx })
  end
end

function M.clear_filter_search()
  local tab = D.T()
  if not tab then return end
  local had_filter = tab.filter_active
  local had_search = tab.search_text ~= nil
  tab.filter_active = false; tab.filter_col = nil; tab.filter_val = nil; tab.filter_col_name = nil
  tab.filtered_indices = nil
  tab.search_text = nil; tab.search_matches = {}; tab.search_idx = 0
  tab.search_matches_by_page = nil; tab.search_total_matches = 0
  if D.dataset_buffer and vim.api.nvim_buf_is_valid(D.dataset_buffer) then
    vim.api.nvim_buf_clear_namespace(D.dataset_buffer, D.search_ns, 0, -1)
  end
  if had_filter or had_search then
    tab.view_indices = nil
    tab.row_number_mode = "source"
    if tab.layout then
      require("poste-db.buffer.page").refresh_page()
    else
      update_winbar()
    end
  end
  local parts = {}
  if had_filter then parts[#parts+1] = "filter" end
  if had_search then parts[#parts+1] = "search" end
  if #parts > 0 then
    vim.notify("Cleared " .. table.concat(parts, " + "), vim.log.levels.INFO, { title = C.TITLE })
  end
end

function M.find_column()
  local tab = D.T()
  if not tab or not tab.meta or tab.meta.type ~= "resultset" then return end
  if not tab.meta.columns or #tab.meta.columns == 0 then
    vim.notify("No columns to search", vim.log.levels.WARN, { title = C.TITLE })
    return
  end

  local picker = require("poste.select")
  local items = {}
  for i, col in ipairs(tab.meta.columns) do
    items[i] = { key = tostring(i), name = col.name or "", description = col.type or "?" }
  end

  picker.select(items, "Find column", function(choice)
    if not choice then return end
    local idx = tonumber(choice)
    if not idx then return end
    sql_state.cell.col = idx
    local row = sql_state.cell.row
    local line = require("poste-db.buffer.nav").position_cursor(row, idx)
    local cs = tab.buffer_col_starts and tab.buffer_col_starts[(tab.meta.data_start_line or 1) + row - 1]
    sql_highlights.highlight_cell(D.dataset_buffer, row, idx, tab.meta, line, cs)
    require("poste-db.buffer.header").update()
  end)
end

update_winbar = function()
  if not D.dataset_window or not vim.api.nvim_win_is_valid(D.dataset_window) then return end
  local meta = D.T() and D.T().meta
  if not meta then return end
  local text = nav_ui.build_status_winbar(meta, D.T(), #D.tabs, D.active_tab_idx)
  if D.dataset_window and vim.api.nvim_win_is_valid(D.dataset_window) then
    pcall(vim.api.nvim_set_option_value, "winbar", text or "", { win = D.dataset_window })
  end
end
M.update_winbar = update_winbar

return M
