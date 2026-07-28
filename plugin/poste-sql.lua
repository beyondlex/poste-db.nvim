-- poste-sql.nvim — SQL execution plugin for Poste
-- Requires poste-core.nvim for shared infrastructure.
local ok, _ = pcall(require, "poste.core")
if not ok then
  vim.notify("poste-sql.nvim requires poste-core.nvim. Install it first.", vim.log.levels.WARN)
  return
end
require("poste-sql.init").setup(vim.g.poste_sql_config or {})