--- Dataset cell navigation --- cursor movement, header float, raw mode, sort, yank.
local D = require("poste-sql.dataset")
local C = require("poste-sql.constants")
local state = require("poste.state")
local sql_highlights = require("poste-sql.highlights")
local util = require("poste-sql.util")
local nav_state = require("poste-sql.buffer.nav_state")
local cell = require("poste-sql.buffer.nav_cell")
local preview = require("poste-sql.buffer.nav_preview")
local raw_mode = require("poste-sql.buffer.nav_raw")
local sort_helper = require("poste-sql.buffer.nav_sort")
local M = {}

local preview_win = nil

-- Helper: get pre-computed column positions for a data row
local function get_col_starts(tab, row)
  if not tab or not tab.buffer_col_starts or not tab.meta then return nil end
  local line_idx = (tab.meta.data_start_line or 1) + row - 1
  return tab.buffer_col_starts[line_idx]
end

------------------------------------------------------------------------------
-- Trace helpers (opt-in via state.sql._trace)
------------------------------------------------------------------------------
local T_items = {}
local function T_clear() T_items = {} end
local function T_mark(label)
  if not state.sql._trace then return end
  T_items[#T_items + 1] = { label = label, t = vim.fn.reltime() }
end
local function T_report()
  if not state.sql._trace or #T_items == 0 then return end
  local t0 = T_items[1].t
  local total = vim.fn.reltimefloat(vim.fn.reltime(t0)) * 1000
  local lines = {}
  for i, ti in ipairs(T_items) do
    local step = i == 1 and 0 or vim.fn.reltimefloat(vim.fn.reltime(T_items[i - 1].t, ti.t)) * 1000
    local cum  = vim.fn.reltimefloat(vim.fn.reltime(t0, ti.t)) * 1000
    lines[#lines + 1] = string.format("  %s: %7.3fms (+%.3f)", ti.label, cum, step)
  end
  lines[#lines + 1] = string.format("  total: %7.3fms", total)
  local msg = table.concat(lines, "\n")
  T_clear()
  state.log("TRACE", "move_cell trace:\n" .. msg)
end

local function focus_cell(tab, row, col, update_header)
  T_mark("position_cursor")
  state.sql.cell.row = row
  state.sql.cell.col = col
  local line = M.position_cursor(row, col)
  T_mark("highlight_cell")
  sql_highlights.highlight_cell(D.dataset_buffer, row, col, tab.meta, line, get_col_starts(tab, row))
  if update_header then
    T_mark("update_header_float")
    M.update_header_float()
  end
end

--- Truncate a string to fit within a given display width, preserving UTF-8 validity.
local function trunc_disp(s, max_dw)
  return util.truncate_displaywidth(s, max_dw)
end

local function build_header_index(line)
  local sep = "│"
  local sep_len = #sep
  local index = {}
  local disp_pos = 0
  local byte_idx = 1
  while byte_idx <= #line do
    local char_bytes, char_width, is_sep
    if line:sub(byte_idx, byte_idx + sep_len - 1) == sep then
      char_bytes, char_width, is_sep = sep_len, 1, true
    else
      local b = line:byte(byte_idx)
      char_bytes = util.utf8_char_bytes(b)
      if byte_idx + char_bytes - 1 > #line then char_bytes = #line - byte_idx + 1 end
      char_width = char_bytes == 1 and 1
        or vim.fn.strdisplaywidth(line:sub(byte_idx, byte_idx + char_bytes - 1))
      if char_width == 0 then char_width = 1 end
      is_sep = false
    end
    index[#index + 1] = { bs=byte_idx, be=byte_idx+char_bytes-1,
                          ds=disp_pos, de=disp_pos+char_width, sep=is_sep }
    disp_pos = disp_pos + char_width
    byte_idx = byte_idx + char_bytes
  end
  return index
end
M.build_header_index = build_header_index

local function slice_header_to_win(leftcol, win_width, padded_header, index)
  if not padded_header or not index then return D.PADDING_SPACES end
  local right_edge = leftcol + win_width

  local parts = {}
  for _, c in ipairs(index) do
    if c.de <= leftcol then goto continue end
    if c.ds >= right_edge then break end

    local text
    if c.ds < leftcol then
      text = string.rep(" ", math.min(c.de, right_edge) - leftcol)
    elseif c.de > right_edge then
      text = string.rep(" ", right_edge - c.ds)
    else
      text = padded_header:sub(c.bs, c.be)
    end
    parts[#parts + 1] = text

    ::continue::
  end

  if #parts == 0 then return D.PADDING_SPACES end
  return table.concat(parts)
end

--- Slice header using pre-computed column positions (O(#visible_cols), no strdisplaywidth).
--- @param leftcol number Display-width offset of viewport left edge
--- @param win_width number Viewport width in display columns
--- @param padded_header string Header line with padding (includes D.LEFT_PADDING)
--- @param header_col_starts table[] Pre-computed column positions with disp_start/disp_end
--- @return string Sliced header text
function M.slice_header_by_col_starts(leftcol, win_width, padded_header, header_col_starts)
  if not padded_header or not header_col_starts then return D.PADDING_SPACES end
  local right_edge = leftcol + win_width

  -- Handle the 2-space left padding (display positions 0-1) before first │
  local parts = {}
  if leftcol < D.LEFT_PADDING then
    local pad_start = math.max(leftcol, 0)
    local pad_end = math.min(D.LEFT_PADDING, right_edge)
    local pad_width = pad_end - pad_start
    if pad_width > 0 then
      parts[#parts + 1] = string.rep(" ", pad_width)
    end
  end

  local last_fully_visible_idx
  local has_partial_right = false

  for i, cell in ipairs(header_col_starts) do
    if cell.disp_end <= leftcol then goto continue end
    if cell.disp_start > right_edge then break end

    local text
    if cell.disp_start < leftcol then
      text = string.rep(" ", math.min(cell.disp_end, right_edge) - leftcol)
    elseif cell.disp_end > right_edge then
      -- Partially visible on right: show │ + as much content as fits
      local seg_start
      if i == 1 then
        seg_start = D.LEFT_PADDING
      else
        seg_start = header_col_starts[i - 1].ext_end
      end
      local full_cell = padded_header:sub(seg_start + 1, cell.ext_end)
      local visible_dw = right_edge - cell.disp_start + 1
      if visible_dw > 0 then
        text = trunc_disp(full_cell, visible_dw)
        has_partial_right = true
      end
    else
      -- Fully visible: extract │ before this cell + content (no trailing │)
      local seg_start
      if i == 1 then
        seg_start = D.LEFT_PADDING  -- first │ at byte 2
      else
        seg_start = header_col_starts[i - 1].ext_end  -- byte of │ between cols
      end
      text = padded_header:sub(seg_start + 1, cell.ext_end)
      last_fully_visible_idx = i
    end
    if text then
      parts[#parts + 1] = text
    end

    ::continue::
  end

  -- Add trailing │ when last visible column is fully visible (no partial-right column)
  if last_fully_visible_idx and not has_partial_right then
    local last_cell = header_col_starts[last_fully_visible_idx]
    parts[#parts + 1] = padded_header:sub(last_cell.ext_end + 1, last_cell.ext_end + 3)
  end

  if #parts == 0 then return D.PADDING_SPACES end
  return table.concat(parts)
end

function M.update_header_float()
  local tab = D.T()
  if not tab or not tab.header_text or not D.dataset_window then T_mark("  hdr:early_exit"); return end
  if not vim.api.nvim_win_is_valid(D.dataset_window) then T_mark("  hdr:early_exit"); return end
  if state.sql._hide_header_float then D.close_header_float(); return end

  T_mark("  hdr:win_width")
  local win_width = vim.api.nvim_win_get_width(D.dataset_window)
  if win_width <= 0 then return end

  T_mark("  hdr:winsaveview")
  local leftcol
  if vim.api.nvim_get_current_win() == D.dataset_window then
    leftcol = vim.fn.winsaveview().leftcol
  else
    leftcol = vim.api.nvim_win_call(D.dataset_window, function()
      return vim.fn.winsaveview().leftcol
    end)
  end

  T_mark("  hdr:cache_check")
  if leftcol == D._float_cache_leftcol and win_width == D._float_cache_width
     and tab.header_text == D._float_cache_header then
    T_mark("  hdr:cached")
    return
  end

  D._float_cache_leftcol = leftcol
  D._float_cache_width = win_width
  D._float_cache_header = tab.header_text

  T_mark("  hdr:slice_to_win")
  local padded = "  " .. tab.header_text
  local text
  if tab.header_col_starts then
    text = M.slice_header_by_col_starts(leftcol, win_width, padded, tab.header_col_starts)
  else
    local index = tab.header_index or build_header_index(padded)
    text = slice_header_to_win(leftcol, win_width, padded, index)
  end

  local float_buf = D.float_buf
  local float_win = D.float_win

  if float_buf and vim.api.nvim_buf_is_valid(float_buf) then
    T_mark("  hdr:set_lines")
    vim.api.nvim_set_option_value("modifiable", true, { buf = float_buf })
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, { text })
    vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
    T_mark("  hdr:set_config")
    if float_win and vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_set_config(float_win, { width = win_width })
      T_mark("  hdr:done")
      return
    end
  end

  T_mark("  hdr:create_float")
  D.close_header_float()
  D.float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[D.float_buf].buftype = "nofile"
  vim.bo[D.float_buf].bufhidden = "wipe"
  vim.bo[D.float_buf].swapfile = false
  vim.api.nvim_buf_set_lines(D.float_buf, 0, -1, false, { text })
  vim.bo[D.float_buf].modifiable = false

  D.float_win = vim.api.nvim_open_win(D.float_buf, false, {
    relative = "win",
    win = D.dataset_window,
    row = 0,
    col = 0,
    width = win_width,
    height = 1,
    style = "minimal",
    border = "none",
    focusable = false,
    zindex = 40,
  })
  vim.wo[D.float_win].winhighlight = "Normal:PosteDbDatasetHeader"
  T_mark("  hdr:done")
end

function M.move_cell(drow, dcol)
  local tab = D.T()
  if not tab or not tab.meta or tab.meta.type ~= "resultset" then return end

  if state.sql._trace then T_clear() end
  T_mark("move_cell")

  local row = state.sql.cell.row + drow
  local col = state.sql.cell.col + dcol

  row = math.max(1, math.min(row, tab.meta.row_count or 0))
  col = math.max(1, math.min(col, tab.meta.col_count or 0))

  focus_cell(tab, row, col, false)
  T_mark("update_header_float")
  if dcol ~= 0 then
    M.update_header_float()
  end
  T_mark("done")
  T_report()
end

function M.goto_first_col()
  local tab = D.T()
  if not tab or not tab.meta then return end
  focus_cell(tab, state.sql.cell.row, 1, true)
end

function M.goto_last_col()
  local tab = D.T()
  if not tab or not tab.meta then return end
  local last = tab.meta.col_count or 1
  focus_cell(tab, state.sql.cell.row, last, true)
end

function M.goto_first_row()
  local tab = D.T()
  if not tab or not tab.meta then return end
  focus_cell(tab, 1, state.sql.cell.col, false)
end

function M.goto_last_row()
  local tab = D.T()
  if not tab or not tab.meta then return end
  local last = tab.meta.row_count or 1
  focus_cell(tab, last, state.sql.cell.col, false)
end

function M.position_cursor(row, col)
  local tab = D.T()
  if not tab or not tab.meta or not D.dataset_window then return "" end
  if not vim.api.nvim_win_is_valid(D.dataset_window) then return "" end

  local line_idx = (tab.meta.data_start_line or 1) + row - 1
  local buf = vim.api.nvim_win_get_buf(D.dataset_window)
  local last_col = tab.meta.col_count or 0

  -- Use pre-computed column byte/display offsets when available (O(1), no │ scan)
  local col_starts = tab.buffer_col_starts and tab.buffer_col_starts[line_idx]
  local target_col, target_disp, line, ranges
  if col_starts then
    local tc = col_starts[col + 1]
    if tc then
      target_col = tc.ext_start
      target_disp = tc.disp_start
    end
    T_mark("  pos:col_starts_lookup")
  else
    T_mark("  pos:get_line_fallback")
    line = vim.api.nvim_buf_get_lines(buf, line_idx - 1, line_idx, false)[1] or ""
    T_mark("  pos:find_cell_ranges")
    ranges = sql_highlights.find_cell_ranges(line, col + 1, last_col + 1)
    target_col = ranges and ranges.target.cursor_col or 0
    target_disp = vim.fn.strdisplaywidth(line:sub(1, target_col))
    T_mark("  pos:strdisp_fallback")
  end

  T_mark("  pos:winsaveview")
  local saved = vim.fn.winsaveview()
  local saved_leftcol = saved.leftcol
  local win_width = vim.api.nvim_win_get_width(D.dataset_window)

  local left_margin = 2
  local right_margin = 3
  local target_on_screen = target_disp >= math.max(0, saved_leftcol - left_margin)
    and target_disp < saved_leftcol + win_width - right_margin

  T_mark("  pos:cursor_set")
  if target_on_screen then
    local saved_sso = vim.api.nvim_get_option_value("sidescrolloff", { win = D.dataset_window })
    if saved_sso > 0 then
      vim.api.nvim_set_option_value("sidescrolloff", 0, { win = D.dataset_window })
    end
    pcall(vim.api.nvim_win_set_cursor, D.dataset_window, { line_idx, target_col })
    if saved_sso > 0 then
      vim.api.nvim_set_option_value("sidescrolloff", saved_sso, { win = D.dataset_window })
    end
  else
    pcall(vim.api.nvim_win_set_cursor, D.dataset_window, { line_idx, target_col })
  end

  -- Left-align to the buffer start when at the first data column so the
  -- row-number column (left padding + `#` cell) scrolls back into view.
  if col == 1 then
    local v = vim.fn.winsaveview()
    if v.leftcol ~= 0 then
      v.leftcol = 0
      vim.fn.winrestview(v)
    end
  end

  -- Right-align the last column when:
  -- 1. Cursor is on the last column (prevents sidescrolloff from pushing it left)
  -- 2. Moving right off-screen and remaining columns (target..last) fit in the window
  if last_col > 0 then
    local last_right
    if col_starts then
      local lc = col_starts[last_col + 1]
      if lc then
        last_right = lc.disp_end + 1
      end
    elseif ranges and ranges.last then
      last_right = vim.fn.strdisplaywidth(line:sub(1, ranges.last.ext_end + 3))
    end
    if last_right then
      local remaining_width = last_right - target_disp
      local should_right_align = col == last_col
        or (not target_on_screen and target_disp >= saved_leftcol and remaining_width <= win_width)
      if should_right_align then
        local v = vim.fn.winsaveview()
        local new_leftcol = math.max(0, last_right - win_width)
        if new_leftcol ~= v.leftcol then
          v.leftcol = new_leftcol
          vim.fn.winrestview(v)
        end
      end
    end
  end

  T_mark("  pos:done")
  return line or ""
end

function M.preview_cell()
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_close(preview_win, true)
    preview_win = nil
    return
  end

  local tab = nav_state.get_resultset_data_tab()
  if not tab then return end
  local row = state.sql.cell.row
  local col = state.sql.cell.col

  local res, raw_val = cell.get_resultset_cell(tab, row, col)
  if not res then return end
  local text, ft = cell.pretty_print(raw_val)

  local col_name = res.columns[col] and res.columns[col].name or "?"

  local float_buf, win = preview.open_preview_float(col_name, text, ft)

  preview_win = win

  local close_fn = function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    preview_win = nil
  end
  preview.set_preview_keymaps(float_buf, close_fn)
end

function M.yank_cell()
  local tab = nav_state.get_resultset_data_tab()
  if not tab then return end
  local row = state.sql.cell.row
  local col = state.sql.cell.col
  local text, preview_text = cell.build_cell_yank_text(tab, row, col)
  vim.fn.setreg('"', text)
  vim.fn.setreg('+', text)
  vim.notify(string.format('Yanked to clipboard: %s', preview_text), vim.log.levels.INFO, { title = C.TITLE })
end

function M.yank_column()
  local tab = nav_state.get_resultset_data_tab()
  local col = state.sql.cell.col
  local result, count, col_name = cell.build_column_yank_text(tab, col)
  if not result then return end
  vim.fn.setreg('"', result)
  vim.fn.setreg('+', result)
  vim.notify(string.format('Yanked %d values from "%s"', count, col_name), vim.log.levels.INFO, { title = C.TITLE })
end

function M.sort_by_current_col()
  local tab = nav_state.get_resultset_data_tab()
  if not tab then return end
  if nav_state.is_dirty(tab) then
    vim.notify(C.EDIT_CONFLICT_MSG, vim.log.levels.WARN, { title = C.TITLE })
    return
  end
  local data = tab.data
  if not data or not data.results or #data.results == 0 then return end

  local col = state.sql.cell.col
  local lines, meta, render_opts = sort_helper.prepare_current_col_sort(tab, data, D.active_tab_idx, col)
  if not lines then return end

  tab.is_sorting = true
  local buffer = require("poste-sql.buffer")
  buffer.render_dataset(lines, meta, render_opts)
  tab.is_sorting = false
  M.move_cell(0, 0)
end

function M.toggle_cell_highlight()
  local tab = nav_state.get_tab()
  local enabled = cell.toggle_cell_highlight(D.dataset_buffer, state.sql.cell.row, state.sql.cell.col, tab and tab.meta, get_col_starts(tab, state.sql.cell.row))
  vim.notify(string.format("Cell highlight: %s", enabled and "ON" or "OFF"),
    vim.log.levels.INFO, { title = C.TITLE })
end

function M.toggle_header_float()
  state.sql._hide_header_float = not state.sql._hide_header_float
  if state.sql._hide_header_float then
    D.close_header_float()
  else
    M.update_header_float()
  end
  vim.notify(string.format("Header float: %s", state.sql._hide_header_float and "OFF" or "ON"),
    vim.log.levels.INFO, { title = C.TITLE })
end

function M.toggle_row_numbers()
  state.sql._hide_row_numbers = not state.sql._hide_row_numbers
  local tab = nav_state.get_resultset_tab()
  if tab and tab.padded and tab.meta then
    sql_highlights.apply_dataset_highlights(D.dataset_buffer, tab.padded, tab.meta)
  end
  vim.notify(string.format("Row numbers: %s", state.sql._hide_row_numbers and "OFF" or "ON"),
    vim.log.levels.INFO, { title = C.TITLE })
end

function M.restore_from_raw_mode()
  raw_mode.exit()
end

--- Delegates to buffer_nav_ui.build_status_winbar with current dataset context.
function M.build_status_winbar(meta)
  return require("poste-sql.buffer.nav_ui").build_status_winbar(meta, D.T(), #D.tabs, D.active_tab_idx)
end

M.toggle_raw_mode = raw_mode.toggle

function M.goto_header()
  M.goto_first_row()
end
M._test = {
  build_header_index = build_header_index,
}

return M
