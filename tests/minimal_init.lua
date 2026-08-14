-- Minimal Neovim configuration for running SQL tests.
-- Used as -u script (actual vimrc replacement).

vim.opt.runtimepath:append(".")
vim.opt.runtimepath:append("../poste.nvim")

package.path = package.path
  .. ";./tests/?.lua"
  .. ";./tests/?/init.lua"

if vim.api.nvim_buf_is_valid(0) then
  pcall(vim.api.nvim_buf_set_option, 0, "filetype", "poste_sql")
end