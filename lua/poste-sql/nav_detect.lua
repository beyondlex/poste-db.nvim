local const = require("poste-sql.constants")

local M = {}

local function pick_table_match(parsed_tables, word_lower)
  local matched = nil
  local schema_matched = nil
  for _, t in ipairs(parsed_tables or {}) do
    local tn = (t.name or ""):lower()
    local ta = (t.alias or ""):lower()
    local ts = (t.schema or ""):lower()
    if tn == word_lower then
      matched = t
      break
    end
    if ta == word_lower then
      matched = t
      break
    end
    if ts == word_lower then
      schema_matched = t
    end
  end
  return matched, schema_matched
end

local function resolve_alias(parsed, prefix)
  local resolved = nil
  if prefix and parsed and parsed.tables then
    for _, t in ipairs(parsed.tables) do
      if t.alias and t.alias:lower() == prefix:lower() then
        resolved = t.name
        break
      end
    end
  end
  return resolved
end

function M.build_context_detect_command(bin, offset, dialect)
  local dialect_flag = ""
  if dialect and dialect ~= "" then
    dialect_flag = " --dialect " .. dialect
  end
  return string.format("%s context detect %d%s", vim.fn.shellescape(bin), offset, dialect_flag)
end

function M.extract_sql_block(all_lines, line_num, line_text, end_col)
  local block_start = 1
  if line_num > 1 then
    for i = line_num - 1, 1, -1 do
      if const.is_section_marker(all_lines[i]) then
        block_start = i + 1
        break
      end
    end
  end

  local block_end = #all_lines
  for i = line_num + 1, #all_lines do
    if const.is_section_marker(all_lines[i]) then
      block_end = i - 1
      break
    end
  end

  if not (block_start <= line_num and line_num <= block_end) then
    return nil
  end

  local before_parts = {}
  for i = block_start, line_num - 1 do
    before_parts[#before_parts + 1] = all_lines[i] or ""
  end
  before_parts[#before_parts + 1] = line_text:sub(1, end_col)

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
    offset = offset,
    sql_text = table.concat(block_parts, "\n"),
  }
end

function M.resolve_detected_table_target(parsed, line_text, end_col, cword, full_ctx)
  if not parsed or not parsed.tables or #parsed.tables == 0 then return nil end
  local cword_lower = (cword or ""):lower()

  if parsed.ctx_type == "dot_column" and parsed.ctx_data then
    local prefix = parsed.ctx_data or ""
    local ad = line_text:sub(end_col + 2)
    local cm = ad:match("^([%w_]+)")
    return {
      action = "navigate_to_table",
      database = full_ctx.database,
      table_name = resolve_alias(parsed, prefix) or prefix,
      column_name = cm or cword,
    }
  elseif parsed.ctx_type == "insert_column" and parsed.ctx_data then
    local prefix = parsed.ctx_data or ""
    local ad = line_text:sub(end_col + 2)
    local cm = ad:match("^([%w_]+)")
    return {
      action = "navigate_to_table",
      database = full_ctx.database,
      table_name = resolve_alias(parsed, prefix) or prefix,
      column_name = cm or cword,
    }
  elseif parsed.ctx_type == "schema_table" and parsed.ctx_data then
    local schema = parsed.ctx_data or ""
    return {
      action = "navigate_to_table",
      database = schema ~= "" and schema or full_ctx.database,
      table_name = cword,
      column_name = nil,
    }
  elseif parsed.ctx_type == "table" then
    local matched, schema_matched = pick_table_match(parsed.tables, cword_lower)
    if schema_matched then
      return {
        action = "navigate_to",
        connection = full_ctx.connection,
        database = cword,
      }
    end
    if matched then
      return {
        action = "navigate_to_table",
        database = full_ctx.database,
        table_name = matched.name or matched.alias or cword,
        column_name = nil,
      }
    end
    return {
      action = "navigate_to_table",
      database = full_ctx.database,
      table_name = cword,
      column_name = nil,
    }
  elseif parsed.ctx_type == "column" or parsed.ctx_type == "keyword" then
    local after_dot_col = nil
    local nxt = line_text:sub(end_col + 1, end_col + 1)
    if nxt == "." then
      local cm = line_text:match("^([%w_]+)", end_col + 2)
      if cm then after_dot_col = cm end
    end

    if after_dot_col then
      local matched, schema_matched = pick_table_match(parsed.tables, cword_lower)
      if matched then
        return {
          action = "navigate_to_table",
          database = full_ctx.database,
          table_name = matched.name or matched.alias or cword,
          column_name = after_dot_col,
        }
      elseif schema_matched then
        return {
          action = "navigate_to_table",
          database = cword,
          table_name = schema_matched.name,
          column_name = nil,
        }
      end
      local resolved = resolve_alias(parsed, parsed.ctx_data or "")
      if resolved then
        return {
          action = "navigate_to_table",
          database = full_ctx.database,
          table_name = resolved,
          column_name = after_dot_col,
        }
      end
    else
      local matched, schema_matched = pick_table_match(parsed.tables, cword_lower)
      if matched then
        return {
          action = "navigate_to_table",
          database = full_ctx.database,
          table_name = matched.name or matched.alias or cword,
          column_name = nil,
        }
      elseif schema_matched then
        return {
          action = "navigate_to_table",
          database = cword,
          table_name = schema_matched.name,
          column_name = nil,
        }
      end

      local alias = nil
      local ws = end_col
      while ws > 0 do
        if not line_text:sub(ws + 1, ws + 1):match("[%w_]") then break end
        ws = ws - 1
      end
      if ws >= 0 and line_text:sub(ws + 1, ws + 1) == "." then
        local ae = ws - 1
        local ap = ae
        while ap >= 0 do
          if not line_text:sub(ap + 1, ap + 1):match("[%w_]") then break end
          ap = ap - 1
        end
        if ap + 1 <= ae then alias = line_text:sub(ap + 2, ae + 1) end
      end
      local resolved = nil
      if alias then
        resolved = resolve_alias(parsed, alias)
      end
      if resolved then
        return {
          action = "navigate_to_table",
          database = full_ctx.database,
          table_name = resolved,
          column_name = cword,
        }
      end
      local target = parsed.tables[1].name or parsed.tables[1].alias
      if target then
        return {
          action = "navigate_to_table",
          database = full_ctx.database,
          table_name = target,
          column_name = cword,
        }
      end
    end
  end

  return nil
end

return M
