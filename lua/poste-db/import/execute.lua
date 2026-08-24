local state = require("poste.state")
local dml = require("poste-db.dml")
local edit_commit = require("poste-db.edit_commit")
local mapping = require("poste-db.import.mapping")
local dialog = require("poste.dialog")

local M = {}

local function dedup_error(msg)
  local s = msg:match("^error returned from database: (.*)")
  if not s then s = msg end
  local n = #s
  for i = 1, math.floor((n - 2) / 2) do
    local left = s:sub(1, i)
    local sep = s:sub(i + 1, i + 2)
    if sep == ": " and s:sub(i + 3) == left then
      return left
    end
  end
  return s
end

local function show_import_errors(errors)
  if #errors == 0 then return end
  local groups = {}
  local order = {}
  for _, err in ipairs(errors) do
    local text = dedup_error(err.error)
    if groups[text] then
      groups[text].count = groups[text].count + 1
    else
      groups[text] = { count = 1, row = err.row, chunk_start = err.chunk_start, chunk_end = err.chunk_end }
      table.insert(order, text)
    end
  end

  local lines = {}
  local function add(l) table.insert(lines, l) end
  for _, text in ipairs(order) do
    local g = groups[text]
    add("")
    local suffix = g.count > 1 and string.format(" (%dx)", g.count) or ""
    local r = g.row or g.chunk_start
    local label = g.row and string.format("Row %d", r) or string.format("Row %d-%d", g.chunk_start, g.chunk_end)
    add(label .. suffix .. ":")
    for _, eline in ipairs(vim.split(text, "\n")) do
      add("  " .. eline)
    end
  end

  if #lines == 0 then return end

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 4, math.floor(vim.o.columns * 0.8))
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.5))

  local d = dialog.open({
    title = "Import Errors",
    width = width,
    height = height,
  })
  d:update(lines)
end

function M.execute_import(table_info, valid_rows, col_map, table_cols, callback)
  if #valid_rows == 0 then
    vim.notify("No valid rows to import", vim.log.levels.WARN)
    if callback then callback(nil) end
    return
  end

  local norm_cols = mapping.normalize_columns(table_cols)
  local chunk_size = state.config.import_chunk_size or 100
  local total_imported = 0
  local all_errors = {}

  local src_file = table_info.search_dir .. "/.__poste_import_temp.sql"

  local conn_prefix = ""
  local conn_url = nil
  if table_info.connection and table_info.connection ~= "" then
    conn_prefix = "-- @connection " .. table_info.connection .. "\n"
    local connections = require("poste-db.connections")
    conn_url, _ = connections.resolve_connection_url(table_info.connection)
  end
  local db_prefix = ""
  if table_info.database and table_info.database ~= "" then
    db_prefix = "-- @database " .. table_info.database .. "\n"
  end

  local function send_chunk(start_idx)
    if start_idx > #valid_rows then
      vim.schedule(function()
        local msg = string.format("Imported %d rows into %s%s",
          total_imported,
          table_info.schema and (table_info.schema .. ".") or "",
          table_info.name)
        if #all_errors > 0 then
          vim.notify(msg .. string.format(" (%d chunk(s) with errors)", #all_errors), vim.log.levels.WARN)
          show_import_errors(all_errors)
        else
          vim.notify(msg, vim.log.levels.INFO)
        end
        if callback then callback({ imported = total_imported, errors = all_errors }) end
      end)
      return
    end

    local end_idx = math.min(start_idx + chunk_size - 1, #valid_rows)
    local sql_parts = {}
    for i = start_idx, end_idx do
      local row_vals = valid_rows[i]
      local stmt = dml.generate_insert(
        table_info.schema, table_info.name, norm_cols, row_vals, table_info.dialect)
      table.insert(sql_parts, stmt)
    end
    local sql_content = conn_prefix .. db_prefix .. table.concat(sql_parts, "\n")

    state.log("INFO", string.format("Import chunk: rows %d-%d (%d rows, target=%s.%s)",
      start_idx, end_idx, end_idx - start_idx + 1,
      table_info.schema or "(default)", table_info.name))

    local chunk_start = vim.fn.reltime()
    local exec_run = require("poste-db.exec_run")
    exec_run.run_async(sql_content, {
      src_file = src_file,
      conn_url = conn_url,
      database = table_info.database,
      mode = "greedy",
    }, {
      on_response = function(resp)
        local ok_body, body = pcall(vim.json.decode, resp.body or "{}")
        if not ok_body or type(body) ~= "table" then body = {} end

        local has_error = false
        if resp.has_error and body.results then
          for ri, result in ipairs(body.results) do
            if result.error and result.error ~= "" then
              has_error = true
              table.insert(all_errors, {
                row = start_idx + ri - 1,
                chunk_start = start_idx, chunk_end = end_idx,
                error = result.error,
              })
            end
          end
        end

        local affected = 0
        if body.results then
          for _, result in ipairs(body.results) do
            local ar = result.affected_rows
            if type(ar) == "number" then affected = affected + ar end
          end
        end
        total_imported = total_imported + affected

        local elapsed = vim.fn.reltimefloat(vim.fn.reltime(chunk_start)) * 1000
        if has_error then
          edit_commit.write_log({
            source = "import",
            table_name = table_info.schema and (table_info.schema .. "." .. table_info.name) or table_info.name,
            connection = table_info.connection or "",
            dialect = table_info.dialect or "",
            database = table_info.database or "",
            sql = sql_content,
            status = "error",
            elapsed_ms = math.floor(elapsed + 0.5),
            error_msg = "One or more statements in chunk failed",
          })
        else
          edit_commit.write_log({
            source = "import",
            table_name = table_info.schema and (table_info.schema .. "." .. table_info.name) or table_info.name,
            connection = table_info.connection or "",
            dialect = table_info.dialect or "",
            database = table_info.database or "",
            sql = sql_content,
            status = "success",
            elapsed_ms = math.floor(elapsed + 0.5),
          })
        end

        send_chunk(end_idx + 1)
      end,
      on_error = function(message)
        local elapsed = vim.fn.reltimefloat(vim.fn.reltime(chunk_start)) * 1000
        edit_commit.write_log({
          source = "import",
          table_name = table_info.schema and (table_info.schema .. "." .. table_info.name) or table_info.name,
          connection = table_info.connection or "",
          dialect = table_info.dialect or "",
          database = table_info.database or "",
          sql = sql_content,
          status = "error",
          elapsed_ms = math.floor(elapsed + 0.5),
          error_msg = "Process error:\n" .. message,
        })
        table.insert(all_errors, {
          chunk_start = start_idx, chunk_end = end_idx,
          error = "Process error:\n" .. message,
        })
        state.log("WARN", "Import chunk error: " .. message)
        vim.schedule(function()
          vim.notify("Import stopped due to process error", vim.log.levels.ERROR)
          if callback then callback({ imported = total_imported, errors = all_errors }) end
        end)
      end,
    })
end

send_chunk(1)
end

return M
