--- Dataset pagination --- page navigation, refresh, and winbar updates.
local D = require("poste-db.dataset")
local C = require("poste-db.constants")
local sql_state = require("poste-db.state")

local nav_ui = require("poste-db.buffer.nav_ui")
local M = {}

function M.goto_header()
  require("poste-db.buffer.nav").goto_first_row()
end

--- Refresh buffer content from the tab's layout.
function M.refresh_page()
  local tab = D.T()
  if not tab or not D.dataset_window then return end
  -- Resultset tabs are always layout-aware now (render_dataset guarantees
  -- tab.layout); nothing to refresh for error/affected/raw pages.
  if not tab.layout then return end

  local fmt = require("poste-db.format")
  local lines, meta  -- locals: assigning them without `local` would leak globals
  local total_rows
  if tab.view_indices then
    total_rows = #tab.view_indices
  else
    total_rows = tab.layout.total_rows or #tab.layout.rows
  end

  if total_rows and tab.pagination_enabled and total_rows > tab.page_size then
    tab.num_pages = math.ceil(total_rows / tab.page_size)
    tab.page = math.min(tab.page or 1, tab.num_pages)
    local page_rows = math.min(tab.page_size, total_rows - (tab.page - 1) * tab.page_size)
    tab.visible_rows = page_rows

    if tab.view_indices then
      lines, meta = fmt.render_view(tab.layout, tab.view_indices, tab.page, tab.page_size,
        { row_number_mode = tab.row_number_mode or "source" })
    else
      lines, meta = fmt.render_page(tab.layout, tab.page, tab.page_size)
    end

    meta.table_name = tab.meta and tab.meta.table_name
    local buffer = require("poste-db.buffer")
    buffer.apply_rendered_page(tab, lines, meta)

    if sql_state.cell.row > page_rows then
      sql_state.cell.row = page_rows
    end
    if tab.cursor.row > page_rows then
      tab.cursor.row = page_rows
    end
  else
    tab.visible_rows = total_rows or 0
    local page_size = total_rows or 0
    if tab.view_indices then
      lines, meta = fmt.render_view(tab.layout, tab.view_indices, 1, page_size,
        { row_number_mode = tab.row_number_mode or "source" })
    else
      lines, meta = fmt.render_page(tab.layout, 1, page_size)
    end
    meta.table_name = tab.meta and tab.meta.table_name
    local buffer = require("poste-db.buffer")
    buffer.apply_rendered_page(tab, lines, meta)
  end

  -- Re-create header float if it was closed (e.g. after raw mode toggle)
  if tab.header_text and not sql_state._hide_header_float then
    require("poste-db.buffer.header").update()
  end
end

local function is_dirty()
  local tab = D.T()
  return tab and tab.edit_state and tab.edit_state.dirty
end

local function block_if_dirty()
  if is_dirty() then
    vim.notify(C.EDIT_CONFLICT_MSG, vim.log.levels.WARN, { title = C.TITLE })
    return true
  end
  return false
end

function M.prev_page()
  if block_if_dirty() then return end
  local tab = D.T()
  if not tab or not tab.pagination_enabled or tab.num_pages <= 1 then return end
  if not tab.layout then return end
  tab.page = tab.page - 1
  if tab.page < 1 then tab.page = tab.num_pages end
  M.refresh_page()
end

function M.next_page()
  if block_if_dirty() then return end
  local tab = D.T()
  if not tab or not tab.pagination_enabled or tab.num_pages <= 1 then return end
  if not tab.layout then return end
  tab.page = tab.page + 1
  if tab.page > tab.num_pages then tab.page = 1 end
  M.refresh_page()
end

function M.goto_first_page()
  if block_if_dirty() then return end
  local tab = D.T()
  if not tab or not tab.pagination_enabled or tab.num_pages <= 1 then return end
  if not tab.layout then return end
  tab.page = 1
  M.refresh_page()
end

function M.goto_last_page()
  if block_if_dirty() then return end
  local tab = D.T()
  if not tab or not tab.pagination_enabled or tab.num_pages <= 1 then return end
  if not tab.layout then return end
  tab.page = tab.num_pages
  M.refresh_page()
end

function M.toggle_pagination()
  local tab = D.T()
  if not tab then return end
  tab.pagination_enabled = not tab.pagination_enabled
  M.refresh_page()
  local status = tab.pagination_enabled and ("Page " .. tab.page .. "/" .. tab.num_pages) or "All"
  vim.notify(string.format("Pagination: %s", status),
    vim.log.levels.INFO, { title = C.TITLE })
end

function M.update_winbar()
  if not D.dataset_window or not vim.api.nvim_win_is_valid(D.dataset_window) then return end
  local meta = D.T() and D.T().meta
  if not meta then return end
  local text = nav_ui.build_status_winbar(meta, D.T(), #D.tabs, D.active_tab_idx)
  pcall(vim.api.nvim_set_option_value, "winbar", text or "", { win = D.dataset_window })
end

return M
