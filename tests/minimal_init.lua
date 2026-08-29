-- Minimal Neovim configuration for running SQL tests.
-- Used as -u script (actual vimrc replacement).

vim.opt.runtimepath:append(".")
vim.opt.runtimepath:append("../poste.nvim")
-- Optional: poste-ai.nvim (AI chat integration tests are skipped when absent)
if vim.fn.isdirectory("../poste-ai.nvim") == 1 then
  vim.opt.runtimepath:append("../poste-ai.nvim")
end

package.path = package.path
  .. ";./tests/?.lua"
  .. ";./tests/?/init.lua"

if vim.api.nvim_buf_is_valid(0) then
  pcall(vim.api.nvim_buf_set_option, 0, "filetype", "poste_sql")
end