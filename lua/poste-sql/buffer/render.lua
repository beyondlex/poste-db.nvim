--- Dataset render --- normalize and lay out result rows for display.
local D = require("poste-sql.dataset")
local sql_highlights = require("poste-sql.highlights")

local M = {}

local function split_render_lines(lines)
  local clean = {}
  for i, line in ipairs(lines) do
    if type(line) ~= "string" then line = tostring(line or "") end
    for seg in (line .. "\n"):gmatch("(.-)\n") do
      clean[#clean + 1] = seg
    end
  end
  return clean
end

function M.normalize_rendered_page(tab, lines, meta)
  local clean = split_render_lines(lines)
  local has_header = meta and meta.type == "resultset" and meta.header_line
  if not has_header then
    local padded = {}
    for _, line in ipairs(clean) do
      if line == "" then
        padded[#padded + 1] = ""
      else
        padded[#padded + 1] = D.PADDING_SPACES .. line
      end
    end
    return padded, meta, false
  end

  local header_line = clean[meta.header_line]
  if header_line then
    tab.header_text = header_line
    if tab.sort then
      local range = sql_highlights.find_cell_range(tab.header_text, tab.sort.col + 1)
      if range then
        local text_end = range.ext_end
        while text_end > range.ext_start + 1 do
          if tab.header_text:byte(text_end) ~= 0x20 then break end
          text_end = text_end - 1
        end
        if text_end > range.ext_start then
          local indicator = (tab.sort.ascending and " ↑" or " ↓")
          local before = tab.header_text:sub(1, text_end)
          local after = tab.header_text:sub(text_end + 3)
          tab.header_text = before .. indicator .. after
          tab.header_col_starts = nil
        end
      end
    end
    local padded_h = "  " .. tab.header_text
    tab.header_index = require("poste-sql.buffer.nav").build_header_index(padded_h)

    table.remove(clean, meta.header_line + 1)
    table.remove(clean, meta.header_line)
    if meta.header_line > 1 then table.remove(clean, meta.header_line - 1) end
    meta.header_line = nil
    meta.data_start_line = meta.data_start_line - 3
    meta.data_end_line = meta.data_end_line - 3
    table.remove(clean, meta.data_end_line + 1)
  end

  local padded = {}
  for _, line in ipairs(clean) do
    if line == "" then
      padded[#padded + 1] = ""
    else
      padded[#padded + 1] = D.PADDING_SPACES .. line
    end
  end
  table.insert(padded, 1, "")
  meta.data_start_line = meta.data_start_line + 1
  meta.data_end_line = meta.data_end_line + 1
  return padded, meta, true
end

function M.build_column_start_maps(tab, meta)
  tab.buffer_col_starts = {}
  if meta and meta.col_starts then
    for i, starts in ipairs(meta.col_starts) do
      local line_idx = meta.data_start_line + i - 1
      local padded_starts = {}
      local cum = D.LEFT_PADDING + 2
      for col_idx, cell in ipairs(starts) do
        local w = meta.col_widths and meta.col_widths[col_idx] or 0
        local disp_start = cum
        local disp_end = disp_start + w + 1
        padded_starts[col_idx] = {
          ext_start = cell.ext_start + D.LEFT_PADDING,
          ext_end = cell.ext_end + D.LEFT_PADDING,
          disp_start = disp_start,
          disp_end = disp_end,
        }
        cum = disp_end + 2
      end
      tab.buffer_col_starts[line_idx] = padded_starts
    end
  end

  tab.header_col_starts = nil
  if meta and meta.header_col_starts then
    local hdr = {}
    local cum_disp = D.LEFT_PADDING
    for col_idx, cell in ipairs(meta.header_col_starts) do
      local cell_disp = cell.ext_end - cell.ext_start
      local ext_start = cell.ext_start + D.LEFT_PADDING
      local ext_end = cell.ext_end + D.LEFT_PADDING
      hdr[col_idx] = {
        ext_start = ext_start,
        ext_end = ext_end,
        disp_start = cum_disp + 1,
        disp_end = cum_disp + 1 + cell_disp,
      }
      cum_disp = cum_disp + 1 + cell_disp
    end
    tab.header_col_starts = hdr
  end
end

return M
