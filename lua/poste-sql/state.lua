--- SQL-specific state (isolated from HTTP/Redis).
--- Loaded by poste-sql.nvim plugin; referenced via require("poste-sql.state")
--- or via state.sql compatibility shim in poste.state.
local M = {}

M.context = {
  connection = nil,   -- current connection string or name
  database = nil,     -- current database (set by USE statement or @database)
}
M.last_dataset = nil   -- last parsed dataset JSON for cell navigation
M.pagination = {}      -- { page, page_size, total_rows, original_query }
M.cell = {             -- current cell position in dataset buffer
  row = 1,
  col = 1,
}
M.highlight_cell = true -- toggle: extmark on current cell
M._hide_header_float = false -- toggle: suppress float header window
M._hide_row_numbers = false  -- toggle: suppress row number column highlight
M._trace = false        -- toggle: perf tracing for h/j/k/l navigation
M._raw_mode = false     -- toggle: compact raw rendering (no column padding)
M.db_browser = {        -- database structure browser
  connection = nil,   -- current connection name being browsed
}

M.icons = {}  -- { [kind_name_or_int] = "icon_string" }, set via setup({ icons = {...} })

return M