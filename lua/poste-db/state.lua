--- SQL-specific state (isolated from HTTP/Redis).
--- Loaded by poste-db.nvim plugin; referenced via require("poste-db.state").
---
--- Since the poste.nvim family dissolution this module also hosts the
--- former shared `poste.state` surface (config singleton, binary
--- resolution, highlight overrides, log) — merged from
--- poste.nvim@5b3759e lua/poste/state.lua.
local M = {}

M.context = {
  connection = nil,   -- current connection string or name
  database = nil,     -- current database (set by USE statement or @database)
}
M.last_dataset = nil   -- last parsed dataset JSON for cell navigation
M.last_error = nil     -- last failed execution: { message, sql, connection, database, at }
M._sql_session = nil   -- active SQL request session (set/cleared by session.lua)
M.cell = {             -- current cell position in dataset buffer
  row = 1,
  col = 1,
}
M.highlight_cell = true -- toggle: extmark on current cell
M._hide_header_float = false -- toggle: suppress float header window
M._hide_row_numbers = false  -- toggle: suppress row number column highlight
M._trace = false        -- toggle: perf tracing for h/j/k/l navigation

M.db_browser = {        -- database structure browser
  connection = nil,   -- current connection name being browsed
}

M.icons = {}  -- { [kind_name_or_int] = "icon_string" }, set via setup({ icons = {...} })

M.config = {
  poste_binary = vim.fn.stdpath("data") .. "/poste/bin/poste",
  log_file = vim.fn.stdpath("cache") .. "/poste-db.log",
  highlights = {},
}

M.current_env = "dev"

function M.find_poste_binary()
  local g_val = vim.g.poste_binary
  if g_val and g_val ~= "" and vim.fn.filereadable(g_val) == 1 then
    return vim.fn.fnamemodify(g_val, ":p")
  end
  if M.config.poste_binary ~= "" and vim.fn.filereadable(M.config.poste_binary) == 1 then
    return vim.fn.fnamemodify(M.config.poste_binary, ":p")
  end
  local paths = {}
  local cwd = vim.fn.getcwd()
  if cwd ~= "" then
    table.insert(paths, cwd .. "/target/debug/poste")
    table.insert(paths, cwd .. "/target/release/poste")
  end
  local src = debug.getinfo(M.find_poste_binary, "S").source
  if src:sub(1, 1) == "@" then
    local dir = src:sub(2):match("^(.+/)lua/poste%-db/") or ""
    if dir ~= "" then
      table.insert(paths, dir .. "target/debug/poste")
      table.insert(paths, dir .. "target/release/poste")
      table.insert(paths, dir .. "bin/poste")
    end
  end
  for _, p in ipairs(paths) do
    if vim.fn.filereadable(p) == 1 then return vim.fn.fnamemodify(p, ":p") end
  end
  local path = vim.fn.exepath("poste")
  return path ~= "" and path or nil
end

function M.apply_highlight_overrides(group_names)
  local overrides = M.config.highlights
  if not overrides or vim.tbl_isempty(overrides) then return end
  for _, name in ipairs(group_names) do
    local attr = overrides[name]
    if attr then
      vim.api.nvim_set_hl(0, name, attr)
    end
  end
end

function M.log(level, msg)
  if not M.config.log_file or M.config.log_file == "" then return end
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  local line = string.format("[%s] [%s] %s\n", ts, level, msg)
  local f = io.open(M.config.log_file, "a")
  if f then
    f:write(line)
    f:close()
  end
end

return M