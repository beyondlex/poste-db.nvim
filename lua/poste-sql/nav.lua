local util = require("poste.util")

local M = {}

local function handle_connection_directive(buf, conn_name)
  local connections = require("poste-sql.connections")
  local search_dir = vim.api.nvim_buf_get_name(buf)
  if search_dir ~= "" then
    search_dir = vim.fn.fnamemodify(search_dir, ":h")
  else
    search_dir = vim.fn.getcwd()
  end
  local config_path = connections.find_connections_toml(search_dir)
  if not config_path then
    vim.notify("connections.toml not found", vim.log.levels.WARN)
    return true
  end
  local config_lines = vim.fn.readfile(config_path)
  if not config_lines then
    vim.notify("Cannot read connections.toml", vim.log.levels.WARN)
    return true
  end
  local target_line = nil
  local pattern = '^%[' .. vim.pesc(conn_name) .. '%]'
  for i, l in ipairs(config_lines) do
    if l:match(pattern) then
      target_line = i
      break
    end
  end
  if not target_line then
    vim.notify("Connection '" .. conn_name .. "' not found in connections.toml", vim.log.levels.WARN)
    return true
  end
  vim.cmd("normal! m'")
  vim.cmd("edit " .. vim.fn.fnameescape(config_path))
  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  return true
end

local function handle_database_directive(buf, line_num, db_name)
  local ctx = require("poste-sql.context")
  local full_ctx = ctx.resolve_full_context(buf, line_num)
  if not full_ctx.connection then
    vim.notify("No connection context for database '" .. db_name .. "'. Add -- @connection <name> to the file.", vim.log.levels.WARN)
    return true
  end
  vim.cmd("normal! m'")
  require("poste-sql.db_browser").navigate_to(full_ctx.connection, db_name)
  return true
end

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

local function resolve_detected_table_target(parsed, line_text, end_col, cword, full_ctx)
  if not parsed or not parsed.tables or #parsed.tables == 0 then return nil end
  local cword_lower = (cword or ""):lower()

  local function resolve_alias(prefix)
    local resolved = nil
    if prefix and parsed.tables then
      for _, t in ipairs(parsed.tables) do
        if t.alias and t.alias:lower() == prefix:lower() then
          resolved = t.name
          break
        end
      end
    end
    return resolved
  end

  if parsed.ctx_type == "dot_column" and parsed.ctx_data then
    local prefix = parsed.ctx_data or ""
    local ad = line_text:sub(end_col + 2)
    local cm = ad:match("^([%w_]+)")
    return {
      action = "navigate_to_table",
      database = full_ctx.database,
      table_name = resolve_alias(prefix) or prefix,
      column_name = cm or cword,
    }
  elseif parsed.ctx_type == "insert_column" and parsed.ctx_data then
    local prefix = parsed.ctx_data or ""
    local ad = line_text:sub(end_col + 2)
    local cm = ad:match("^([%w_]+)")
    return {
      action = "navigate_to_table",
      database = full_ctx.database,
      table_name = resolve_alias(prefix) or prefix,
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
      local resolved = resolve_alias(parsed.ctx_data or "")
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
        resolved = resolve_alias(alias)
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

local function handle_table_reference(buf, line_num, line_text, cursor, full_ctx, table_name)
  local data = require("poste-sql.completion_data")
  local bin = data.find_binary()
  local column_name = nil

  if bin then
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local nav_line_text = all_lines[line_num] or ""
    local col = cursor[2]
    local line_len = #nav_line_text

    local end_col = col
    while end_col < line_len do
      local ch = line_text:sub(end_col + 1, end_col + 1)
      if ch:match("[%w_]") then end_col = end_col + 1 else break end
    end

    local block_start = 1
    if line_num > 1 then
      for i = line_num - 1, 1, -1 do
        if all_lines[i] and all_lines[i]:match("^###") then block_start = i + 1; break end
      end
    end
    local block_end = #all_lines
    for i = line_num + 1, #all_lines do
      if all_lines[i] and all_lines[i]:match("^###") then block_end = i - 1; break end
    end

    if block_start <= line_num and line_num <= block_end then
      local before_parts = {}
      for i = block_start, line_num - 1 do
        table.insert(before_parts, all_lines[i] or "")
      end
      table.insert(before_parts, line_text:sub(1, end_col))
      local offset = #table.concat(before_parts, "\n")
      if offset > 0 then
        offset = offset - 1
      end

      local block_parts = {}
      for i = block_start, block_end do table.insert(block_parts, all_lines[i] or "") end
      local sql_text = table.concat(block_parts, "\n")

      local dialect_flag = ""
      local conn_config = require("poste-sql.connections").get_connection_config(full_ctx.connection)
      if conn_config and conn_config.dialect then
        dialect_flag = " --dialect " .. conn_config.dialect
      end

      local cmd = string.format("%s context detect %d%s",
        vim.fn.shellescape(bin), offset, dialect_flag)
      local output = vim.fn.system(cmd, sql_text)
      if vim.v.shell_error == 0 then
        local ok, parsed = pcall(vim.json.decode, output)
        if ok and parsed then
          util.clean_nil(parsed)
          local target = resolve_detected_table_target(parsed, line_text, end_col, table_name, full_ctx)
          if target then
            if target.action == "navigate_to" then
              vim.cmd("normal! m'")
              require("poste-sql.db_browser").navigate_to(
                target.connection or full_ctx.connection,
                target.database or full_ctx.database or table_name
              )
              return true
            end
            table_name = target.table_name or table_name
            column_name = target.column_name
            if target.database then
              full_ctx.database = target.database
            end
          end
        end
      end
    end
  end

  vim.cmd("normal! m'")
  require("poste-sql.db_browser").navigate_to_table(full_ctx.connection, full_ctx.database, table_name, column_name)
  return true
end

function M.goto_definition()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1] or ""
  local conn_match = line_text:match("^%s*--%s*@connection%s+(.+)")
  if conn_match then
    handle_connection_directive(buf, vim.trim(conn_match))
    return
  end
  local db_match = line_text:match("^%s*--%s*@database%s+(.+)")
  if db_match then
    handle_database_directive(buf, line_num, vim.trim(db_match))
    return
  end
  local table_name = vim.fn.expand("<cword>")
  if table_name and table_name ~= "" then
    local ctx = require("poste-sql.context")
    local full_ctx = ctx.resolve_full_context(buf, line_num)
    if full_ctx.connection then
      handle_table_reference(buf, line_num, line_text, cursor, full_ctx, table_name)
      return
    end
  end
  vim.notify("No connection context. Add -- @connection <name> to the file header.", vim.log.levels.WARN)
end

M._test = {
  resolve_detected_table_target = resolve_detected_table_target,
}

return M
