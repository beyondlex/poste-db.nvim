--- SQL Dataset Export — CSV, TSV, JSON, Markdown, SQL INSERT.
--- Two-step interactive: format → destination (file or clipboard).
--- File exports copy the absolute path to system clipboard.
--- Path memory persisted in stdpath("cache")/poste_export_config.

local D = require("poste-db.dataset")
local config = require("poste-db.config")

local M = {}

local FORMATS = {
  { value = "csv",  label = "CSV",           ext = ".csv",  desc = "Comma-separated values" },
  { value = "tsv",  label = "TSV",           ext = ".tsv",  desc = "Tab-separated values" },
  { value = "json", label = "JSON",          ext = ".json", desc = "Array of objects (pretty-printed)" },
  { value = "md",   label = "Markdown",      ext = ".md",   desc = "Pipe table" },
  { value = "sql",  label = "SQL INSERT",    ext = ".sql",  desc = "INSERT statements" },
}

-------------------------------------------------------------------------------
-- Path persistence
-------------------------------------------------------------------------------

local function get_cache_file()
  return vim.fn.stdpath("cache") .. "/poste_export_config"
end

local function load_export_config()
  local f = io.open(get_cache_file(), "r")
  if f then
    local content = f:read("*a")
    f:close()
    local ok, cfg = pcall(vim.json.decode, content)
    if ok and type(cfg) == "table" then
      return cfg
    end
  end
  return { last_dir = nil }
end

local function save_export_config(cfg)
  local f = io.open(get_cache_file(), "w")
  if f then
    f:write(vim.json.encode(cfg))
    f:close()
  end
end

-------------------------------------------------------------------------------
-- Default path resolution
-------------------------------------------------------------------------------

local function get_default_dir()
  if config.config.export_path then
    return config.config.export_path
  end
  local cfg = load_export_config()
  if cfg.last_dir then
    return cfg.last_dir
  end
  if vim.fn.has("mac") == 1 then
    return vim.fn.expand("~/Downloads")
  elseif vim.fn.has("unix") == 1 then
    return vim.fn.expand("~")
  else
    return vim.fn.expand("~/Desktop")
  end
end

local function generate_filename(info, ext)
  local base = (info and info.table_name) or "export"
  -- A layout.table_name can be schema-qualified ("main.users"); the raw dot
  -- is fine in a filename but a path separator would silently relocate the
  -- export into a subdirectory.
  base = base:gsub("[/\\:%s]", "_")
  if base == "" then base = "export" end
  local ts = os.date("%Y%m%d_%H%M%S")
  return base .. "_" .. ts .. ext
end

-------------------------------------------------------------------------------
-- Dataset access
-------------------------------------------------------------------------------

--- Normalize a field that may arrive as JSON null (`vim.NIL`).
local function str(v)
  if v == nil or v == vim.NIL then return nil end
  return v
end

--- The result set to export plus the identity the formatters need.
---
--- `info` cannot be read off `results[1]`: the runner puts `table_name` and
--- `dialect` on the response body (sql_runner/response.lua) and the table name
--- again on the tab meta, while `results[1]` is the bare column/row payload.
--- Reading it off the result left every SQL export writing
--- `INSERT INTO "export"` with postgres quoting, whatever the source table or
--- dialect was.
--- @return table|nil result  results[1] (columns + rows)
--- @return table|nil info    { table_name, schema, dialect }
local function get_current_data()
  local tab = D.T()
  if not tab or not tab.data then
    vim.notify("No dataset to export", vim.log.levels.WARN)
    return nil
  end
  local body = tab.data
  if body.type ~= "resultset" then
    vim.notify("Only resultset data can be exported", vim.log.levels.WARN)
    return nil
  end
  local results = body.results
  if not results or #results == 0 then
    vim.notify("No result rows to export", vim.log.levels.WARN)
    return nil
  end
  local layout = tab.layout or {}
  local meta = tab.meta or {}
  return results[1], {
    table_name = str(body.table_name) or str(meta.table_name) or str(layout.table_name),
    schema = str(layout.schema),
    dialect = str(body.dialect) or str(layout.dialect) or "postgres",
  }
end

-------------------------------------------------------------------------------
-- Formatters
-------------------------------------------------------------------------------

local function export_val(v)
  if v == nil or v == vim.NIL then return "" end
  return tostring(v)
end

local function csv_escape(v)
  local s = export_val(v)
  -- \r must quote too: a bare CR inside a field breaks the record
  -- structure just like a bare \n does.
  if s:find('["\r\n,]') then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

local function format_csv(data_result)
  local cols = data_result.columns or {}
  local rows = data_result.rows or {}
  local lines = {}
  local header = {}
  for _, col in ipairs(cols) do
    table.insert(header, csv_escape(col.name))
  end
  table.insert(lines, table.concat(header, ","))
  for _, row in ipairs(rows) do
    local vals = {}
    for i = 1, #cols do
      table.insert(vals, csv_escape(row[i]))
    end
    table.insert(lines, table.concat(vals, ","))
  end
  return table.concat(lines, "\n")
end

local function format_tsv(data_result)
  local cols = data_result.columns or {}
  local rows = data_result.rows or {}
  local lines = {}
  local header = {}
  for _, col in ipairs(cols) do
    table.insert(header, (tostring(col.name):gsub("[\t\r\n]", " ")))
  end
  table.insert(lines, table.concat(header, "\t"))
  for _, row in ipairs(rows) do
    local vals = {}
    for i = 1, #cols do
      table.insert(vals, (export_val(row[i]):gsub("[\t\r\n]", " ")))
    end
    table.insert(lines, table.concat(vals, "\t"))
  end
  return table.concat(lines, "\n")
end

local function format_json(data_result)
  local cols = data_result.columns or {}
  local rows = data_result.rows or {}
  local objects = {}
  for _, row in ipairs(rows) do
    local obj = {}
    for i, col in ipairs(cols) do
      obj[col.name] = row[i]
    end
    table.insert(objects, obj)
  end
  return vim.json.encode(objects)
end

local function format_markdown(data_result)
  local cols = data_result.columns or {}
  local rows = data_result.rows or {}
  local lines = {}
  local header_parts = {}
  for _, col in ipairs(cols) do
    table.insert(header_parts, tostring(col.name))
  end
  table.insert(lines, "| " .. table.concat(header_parts, " | ") .. " |")
  local sep_parts = {}
  for _ in ipairs(cols) do
    table.insert(sep_parts, "---")
  end
  table.insert(lines, "| " .. table.concat(sep_parts, " | ") .. " |")
  for _, row in ipairs(rows) do
    local vals = {}
    for i = 1, #cols do
      table.insert(vals, (export_val(row[i]):gsub("|", "\\|")))
    end
    table.insert(lines, "| " .. table.concat(vals, " | ") .. " |")
  end
  return table.concat(lines, "\n")
end

local ident = require("poste-db.ident")

--- Single-quoted SQL literal. Control bytes need dialect-aware handling:
--- NO dialect interprets a `\xHH` escape inside a regular string literal —
--- PostgreSQL keeps the four characters verbatim (standard_conforming_strings
--- is on by default), MySQL drops the backslash (`\x` → `x`), SQLite keeps
--- the literal text — so the old dialect-blind `\xNN` form silently
--- corrupted every exported value that carried a control byte.
---   postgres: E'' literal with \xHH escapes (printable AND round-trips)
---   mysql/sqlite: the raw byte inside the quotes (valid on both; SQLite
---   string constants may hold any byte, MySQL's too). NUL can never come
---   back from a PG/MySQL TEXT column, so the raw form stays unreachable
---   there in practice.
local function sql_escape_val(v, dialect)
  if v == nil or v == vim.NIL then return "NULL" end
  if type(v) == "number" then return tostring(v) end
  if type(v) == "boolean" then return v and "TRUE" or "FALSE" end
  local s = tostring(v):gsub("'", "''")
  if dialect == "postgres" and s:find("[%z\1-\8\11-\12\14-\31]") then
    -- The literal becomes an E'' string, where `\` re-enters escape duty:
    -- backslashes the VALUE carries must double first, or `C:\data\x07`'s
    -- `\d` reads back as plain 'd'.
    s = s:gsub("\\", "\\\\")
    s = s:gsub("[%z\1-\8\11-\12\14-\31]", function(c)
      return string.format("\\x%02X", c:byte())
    end)
    return "E'" .. s .. "'"
  end
  -- MySQL/MariaDB/ClickHouse interpret `\` inside ordinary literals too (and
  -- drop the backslash: `\t` → tab, `\p` → p), so the raw-byte rule below
  -- only holds for SQLite — on a backslash dialect the value's `\` must be
  -- doubled or the re-imported text differs from the exported one.
  if dialect == "mysql" or dialect == "mariadb" or dialect == "clickhouse" then
    s = s:gsub("\\", "\\\\")
  end
  return "'" .. s .. "'"
end

local function format_sql_insert(data_result, info)
  local cols = data_result.columns or {}
  local rows = data_result.rows or {}
  local table_name = (info and info.table_name) or "export"
  local schema = (info and info.schema) or ""
  local dialect = (info and info.dialect) or "postgres"
  local qualified = schema ~= "" and ident.quote_qualified(schema, table_name, dialect) or ident.quote(table_name, dialect)
  local col_names = {}
  for _, col in ipairs(cols) do
    table.insert(col_names, ident.quote(col.name, dialect))
  end
  local col_names_str = table.concat(col_names, ", ")
  local lines = {}
  for _, row in ipairs(rows) do
    local vals = {}
    for i = 1, #cols do
      table.insert(vals, sql_escape_val(row[i], dialect))
    end
    table.insert(lines, string.format("INSERT INTO %s (%s) VALUES (%s);",
      qualified, col_names_str, table.concat(vals, ", ")))
  end
  return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------
-- Dispatch
-------------------------------------------------------------------------------

local FORMATTERS = {
  csv = format_csv,
  tsv = format_tsv,
  json = format_json,
  md   = format_markdown,
  sql  = format_sql_insert,
}

-------------------------------------------------------------------------------
-- Export actions
-------------------------------------------------------------------------------

local function export_to_file(data_result, info, format_value, path)
  local fn = FORMATTERS[format_value]
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir and dir ~= "" then
    vim.fn.mkdir(dir, "p")
  end
  local ok, text = pcall(fn, data_result, info)
  if not ok then
    vim.notify("Export failed: " .. tostring(text), vim.log.levels.ERROR)
    return
  end
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    vim.notify("Cannot write to " .. path, vim.log.levels.ERROR)
    return
  end
  f:write(text)
  f:close()
  os.rename(tmp, path)
  local abs_path = vim.fn.fnamemodify(path, ":p")
  vim.fn.setreg("+", abs_path)
  vim.fn.setreg('"', abs_path)
  local row_count = data_result.row_count or #(data_result.rows or {})
  vim.notify(string.format("Exported %d rows to %s (path in clipboard)", row_count, abs_path), vim.log.levels.INFO)
end

local function export_to_clipboard(data_result, info, format_value)
  local fn = FORMATTERS[format_value]
  local ok, text = pcall(fn, data_result, info)
  if not ok then
    vim.notify("Export failed: " .. tostring(text), vim.log.levels.ERROR)
    return
  end
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  local row_count = data_result.row_count or #(data_result.rows or {})
  local fmt_label = ""
  for _, f in ipairs(FORMATS) do
    if f.value == format_value then
      fmt_label = f.label
      break
    end
  end
  vim.notify(string.format("Copied %d rows as %s to clipboard", row_count, fmt_label), vim.log.levels.INFO)
end

-------------------------------------------------------------------------------
-- Interactive flow
-- Functions are stored in P{} to avoid LuaJIT closure capture limits:
-- nested callbacks can only access upvalues of their direct parent, not
-- module-level locals. P is a module-level local accessible by all.
-------------------------------------------------------------------------------

local P = {}

local function save_default_dir(dir)
  local cfg = load_export_config()
  cfg.last_dir = dir
  save_export_config(cfg)
  vim.notify("Default export directory saved: " .. dir, vim.log.levels.INFO)
end

function P.format_picker(on_format)
  vim.ui.select(FORMATS, {
    prompt = "Select export format",
    format_item = function(f) return f.label .. "  " .. f.desc end,
  }, function(choice)
    if choice then on_format(choice.value) end
  end)
end

function P.browse_path(format_value)
  local data_result, info = get_current_data()
  if not data_result then return end
  local ext = ""
  for _, f in ipairs(FORMATS) do
    if f.value == format_value then ext = f.ext; break end
  end
  local filename = generate_filename(info, ext)
  local initial_dir = get_default_dir()

  local ok, finder = pcall(require, "finder")
  if not ok then
    vim.notify(
      "beyondlex/finder required for Browse. Add { \"beyondlex/finder\" } to your plugin specs.",
      vim.log.levels.ERROR
    )
    return
  end

  finder.open({
    mode = "dir",
    initial_path = initial_dir,
    on_confirm = function(path)
      local full_path = path .. "/" .. filename
      export_to_file(data_result, info, format_value, full_path)
      save_default_dir(path)
    end,
    on_cancel = function()
      P.destination_picker(format_value)
    end,
  })
end

function P.destination_picker(format_value)
  local _ = P
  local data_result, info = get_current_data()
  if not data_result then return end
  local dir = get_default_dir()
  local ext = ""
  for _, f in ipairs(FORMATS) do
    if f.value == format_value then
      ext = f.ext
      break
    end
  end
  local filename = generate_filename(info, ext)
  local default_path = dir .. "/" .. filename
  local destinations = {
    { value = "quick",  label = "→ " .. dir,          desc = "Quick save to default dir" },
    { value = "browse", label = "Browse...",           desc = "Pick directory (Go to Folder)" },
    { value = "clip",   label = "Clipboard",           desc = "Copy to system clipboard" },
  }
  vim.ui.select(destinations, {
    prompt = "Export " .. format_value:upper() .. " to...",
    format_item = function(d) return d.label end,
  }, function(choice)
    if not choice then
      P.format_picker(function(fmt) P.destination_picker(fmt) end)
      return
    end
    if choice.value == "clip" then
      export_to_clipboard(data_result, info, format_value)
    elseif choice.value == "browse" then
      P.browse_path(format_value)
    else
      export_to_file(data_result, info, format_value, default_path)
    end
  end)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Main entry: :PosteDbExport [format] [destination] [path]
--- format: csv|tsv|json|md|sql (optional, prompts if omitted)
--- destination: file|clipboard (optional, prompts if omitted)
--- path: file path (only if destination=file, prompts if omitted)
function M.run(format_value, destination, path)
  if format_value and destination == "clipboard" then
    local data_result, info = get_current_data()
    if data_result then
      export_to_clipboard(data_result, info, format_value)
    end
    return
  end

  if format_value and destination == "file" then
    -- documented as `:PosteDbExport [format] file [path]` — the path argument
    -- used to be accepted and silently ignored (interactive picker instead)
    local data_result, info = get_current_data()
    if not data_result then return end
    if path and path ~= "" then
      export_to_file(data_result, info, format_value, vim.fn.expand(path))
    else
      -- path omitted: prompt via the directory browser (generated filename)
      P.browse_path(format_value)
    end
    return
  end

  if format_value then
    P.destination_picker(format_value)
    return
  end

  P.format_picker(function(fmt)
    P.destination_picker(fmt)
  end)
end

--- Command completion helper
function M.complete(ArgLead, CmdLine)
  -- prefix match on plain text: f:find(ArgLead) treats the arg as a Lua
  -- pattern, so a magic `%`/`-` on the command line errors the completion.
  local function starts_with(list, lead)
    local out = {}
    for _, item in ipairs(list) do
      if item:sub(1, #lead) == lead then out[#out + 1] = item end
    end
    return out
  end
  local parts = {}
  for word in CmdLine:gmatch("%S+") do
    table.insert(parts, word)
  end
  local n = #parts
  if n == 0 or (n == 1 and not CmdLine:match("%s$")) then
    return starts_with({ "csv", "tsv", "json", "md", "sql" }, ArgLead)
  end
  if n == 1 or (n == 2 and not CmdLine:match("%s$")) then
    return starts_with({ "clipboard", "file" }, ArgLead)
  end
  return vim.fn.getcompletion(ArgLead, "file")
end

M._test = {
  get_current_data = get_current_data,
  format_csv = format_csv,
  format_tsv = format_tsv,
  format_json = format_json,
  format_markdown = format_markdown,
  format_sql_insert = format_sql_insert,
  sql_escape_val = sql_escape_val,
  csv_escape = csv_escape,
  generate_filename = generate_filename,
}

return M
