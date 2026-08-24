local state = require("poste.state")
local statement = require("poste-db.statement")
local sql_introspect = require("poste-db.introspect")
local sql_runner = require("poste-db.sql_runner")

local M = {}
M.ensure_sql_keymaps = sql_runner.ensure_sql_keymaps

local ck = state.get_keymap("sql_source", "clear_filter", "<leader>cr")
if ck then
  vim.keymap.set("n", ck, function()
    local sql_buf = require("poste-db.buffer")
    if sql_buf.is_open() then sql_buf.clear_filter_search() end
  end, { noremap = true, silent = true, desc = "Poste: clear filter/search" })
end

M.run_sql_request = sql_runner.run_sql_request
M.show_table_ddl = sql_introspect.show_table_ddl
M._test = statement._test

function M.setup(opts)
  opts = opts or {}
  local state = require("poste.state")
  state.config.db_browser = vim.tbl_deep_extend("force", state.config.db_browser, opts.db_browser or {})
  if opts.hide_empty_result_tabs ~= nil then
    state.config.hide_empty_result_tabs = opts.hide_empty_result_tabs
  end
  require("poste-db.snippets").setup(opts)
  require("poste-db.insert_hint").setup()

  local sql_state = require("poste-db.state")
  if vim.tbl_isempty(sql_state.icons) then
    sql_state.icons = vim.tbl_deep_extend("force", {}, { Text = "", Field = "󰇨", Variable = "󰆧", Class = "", Interface = "󰏘", Function = "󰊕", Keyword = "󰌆", TypeParameter = "󰜢" })
  end
  if opts.icons then sql_state.icons = vim.tbl_deep_extend("force", sql_state.icons, opts.icons) end
  if opts.history_max ~= nil then
    require("poste-db.dataset").set_max_history(opts.history_max)
  end

  if not pcall(vim.treesitter.language.get_lang, "sql") then
    vim.notify("poste-db: Tree-sitter SQL parser not found. Run :TSInstall sql to enable. Falling back to Rust/Lua heuristics.", vim.log.levels.WARN, { title = "PosteDb" })
  end

  local ok = pcall(require("poste-db.completion.register").register)
  if not ok then
    local group = vim.api.nvim_create_augroup("PosteDbCmpRegister", { clear = true })
    vim.api.nvim_create_autocmd("InsertEnter", { group = group, once = true, callback = function()
      pcall(require("poste-db.completion.register").register)
      pcall(vim.api.nvim_del_augroup_by_name, "PosteDbCmpRegister")
    end })
  end

  require("poste-db.highlights").setup()
  require("poste-db.statement_indicator").setup()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = function()
    require("poste-db.highlights").setup()
    require("poste-db.statement_indicator").setup()
  end })
  require("poste-db.autocmds").setup()
  require("poste-db.commands").setup()
  -- Statusline integration on by default (opt-out)
  -- always-on behavior so the SQL-file/dataset context stays visible.
  if opts.statusline ~= false then require("poste-db.statusline").setup() end
  require("poste-db.autocmds").setup_existing_buffers()
end

return M