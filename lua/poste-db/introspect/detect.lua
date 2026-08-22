--- Introspection --- detect target type from cursor position and SQL context.
local M = {}

local function find_block_for_line(all_lines, line_num)
  local block_start = 1
  if line_num > 1 then
    for i = line_num - 1, 1, -1 do
      if all_lines[i] and all_lines[i]:match("^###") then
        block_start = i + 1
        break
      end
    end
  end

  local block_end = #all_lines
  for i = line_num + 1, #all_lines do
    if all_lines[i] and all_lines[i]:match("^###") then
      block_end = i - 1
      break
    end
  end

  return block_start, block_end
end

function M.find_block_for_line(all_lines, line_num)
  return find_block_for_line(all_lines, line_num)
end

function M.build_detect_payload(all_lines, line_num, slice_end_col)
  local block_start, block_end = find_block_for_line(all_lines, line_num)
  if block_start > line_num or line_num > block_end then
    return nil
  end

  local line_text = all_lines[line_num] or ""
  local before_parts = {}
  for i = block_start, line_num - 1 do
    before_parts[#before_parts + 1] = all_lines[i] or ""
  end
  before_parts[#before_parts + 1] = line_text:sub(1, slice_end_col)

  local offset = #table.concat(before_parts, "\n")
  if offset > 0 then
    offset = offset - 1
  end

  local block_parts = {}
  for i = block_start, block_end do
    block_parts[#block_parts + 1] = all_lines[i] or ""
  end

  return {
    block_start = block_start,
    block_end = block_end,
    sql_text = table.concat(block_parts, "\n"),
    offset = offset,
    line_text = line_text,
  }
end

return M
