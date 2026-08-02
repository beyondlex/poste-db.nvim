--- Highlight groups and extmark application for SQL dataset buffer.
local theme = require("poste-sql.highlights_theme")
local render = require("poste-sql.highlights_render")

local M = {}

function M.setup()
  theme.setup()
end

M.apply_dataset_highlights = render.apply_dataset_highlights
M.find_cell_range = render.find_cell_range
M.find_cell_ranges = render.find_cell_ranges
M.find_cell_ranges_fallback = render.find_cell_ranges_fallback
M.invalidate_sep_cache = render.invalidate_sep_cache
M.highlight_cell = render.highlight_cell
M.clear_cell_highlight = render.clear_cell_highlight
M.apply_edit_highlights = render.apply_edit_highlights
M.clear_edit_highlights = render.clear_edit_highlights

M.setup()
vim.api.nvim_create_autocmd("ColorScheme", { callback = M.setup })
vim.api.nvim_create_autocmd("VimEnter", { callback = M.setup, once = true })

return M
