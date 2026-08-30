--- SQL plugin configuration — owns all `sql_*` defaults, keymaps, and
--- SQL-only options. Generic shared infra (binary, env, split, log) stays in
--- `poste.state`; anything SQL-specific belongs here.

local M = {}

--- SQL-only defaults. Merged with user opts in M.merge().
M.defaults = {
  sql_formatters = { "sqlfluff", "sqlfmt", "sql-formatter", "pg_format" },
  hide_empty_result_tabs = true,
  default_max_rows = 0,
  export_path = nil,
  import_chunk_size = 100,
  -- Enable debug commands (:PosteDbCmpDebug, :PosteDbDiag, ...). Off by
  -- default; turn on via setup({ debug = true }) or g:poste_db_debug = true.
  debug = false,
  -- Confirm before executing DELETE/UPDATE statements that lack a WHERE clause
  confirm_unfiltered_dml = true,
  db_browser = {
    split_position = "left",  -- "left" or "right"
    split_width = 40,
  },
  keymaps = {
    sql_source = {
      run = "<CR>",
      show_ddl = "K",
      format = "<leader>ff",
      clear_filter = "<leader>cr",
      toggle_db_browser = "<leader>db",
      trigger_completion = "<C-Space>",
      ask_ai = "<leader>aa",
      help = "g?",
    },
    sql_dataset = {
      close = "q",
      ask_ai = "a",
      move_left = "h",
      move_down = "j",
      move_up = "k",
      move_right = "l",
      prev_page = "H",
      next_page = "L",
      first_col = "0",
      last_col = "$",
      first_row = "gg",
      last_row = "G",
      preview_cell = "K",
      yank_cell = "yy",
      yank_column = "yc",
      sort_column = "s",
      toggle_raw_mode = "<leader>gp",
      next_tab = "<Tab>",
      prev_tab = "<S-Tab>",
      rerun = "R",
      goto_first_page = "<leader>hh",
      goto_last_page = "<leader>ll",
      toggle_pagination = "<leader>pa",
      find_column = "<leader>fc",
      filter_by_cell = "<leader>ce",
      show_search = "<leader>/",
      clear_filter_search = "<leader>cr",
      next_search = "n",
      prev_search = "N",
      edit_cell = "i",
      edit_cell_replace = "cc",
      delete_row = "dd",
      insert_row = "o",
      commit_edits = "<leader>w",
      export = "E",
      history_toggle = "<leader>ph",
      history_next = "<leader>n",
      history_prev = "<leader>p",
      help = "g?",
    },
    sql_table_ops = {
      select_all = "ma",
      refresh_all = "mr",
      describe_all = "md",
      toggle_menu = "mt",
    },
    sql_db_browser = {
      toggle_node = "<CR>",
      move_left = "h",
      move_right = "l",
      context_menu = "x",
      refresh_node = "r",
      search_filter = "/",
      close = "q",
      search_next = "n",
      search_prev = "N",
      help = "g?",
      table_info = "i",
      ask_ai = "a",
    },
    sql_introspect = {
      close = "q",
      close_alt = "<Esc>",
    },
  },
}

--- Effective config (defaults + merged user opts).
M.config = vim.deepcopy(M.defaults)

--- Merge user opts into the effective config (deep for nested tables).
--- Called from poste-db.setup().
--- @param opts table|nil
function M.merge(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    if type(v) == "table" and type(M.config[k]) == "table" then
      M.config[k] = vim.tbl_deep_extend("force", M.config[k], v)
    else
      M.config[k] = v
    end
  end
end

local KEY_DISPLAY_NAMES = {
  ["<Tab>"] = "Tab",
  ["<S-Tab>"] = "S-Tab",
  ["<CR>"] = "Enter",
  ["<Esc>"] = "Esc",
  ["<Space>"] = "<Space>",
  ["<Up>"] = "Up",
  ["<Down>"] = "Down",
  ["<Left>"] = "Left",
  ["<Right>"] = "Right",
  ["<C-Space>"] = "C-Space",
  ["<BS>"] = "BS",
}

--- Resolve a keymap for (section, action). `false` disables; nil → default.
--- Legacy: falls through to `poste.state.config.keymaps` first so overrides
--- configured via `require("poste").setup({ keymaps = {...} })` still work.
--- @param section string
--- @param action string
--- @param default string|nil
--- @return string|nil
function M.get_keymap(section, action, default)
  local ok, poste_state = pcall(require, "poste.state")
  if ok and poste_state.config and poste_state.config.keymaps
    and poste_state.config.keymaps[section] ~= nil then
    local key = poste_state.config.keymaps[section][action]
    if key ~= nil then
      if key == false then return nil end
      return key
    end
  end
  local sec = M.config.keymaps[section]
  if not sec then return default end
  local key = sec[action]
  if key == nil then return default end
  if key == false then return nil end
  return key
end

--- Format a key string for display (handles <leader> and named keys).
--- @param key string
--- @return string
function M.format_key_string(key)
  if not key or key == "" then return "" end
  if KEY_DISPLAY_NAMES[key] then return KEY_DISPLAY_NAMES[key] end
  if key:sub(1, 8) == "<leader>" then
    local leader = vim.g.mapleader or "\\"
    if leader == " " then leader = "<Space>"
    elseif leader == "\t" then leader = "<Tab>"
    elseif leader == "\r" then leader = "<CR>"
    end
    leader = KEY_DISPLAY_NAMES[leader] or leader
    return leader .. key:sub(9)
  end
  return key
end

--- Resolve and format a keymap for (section, action).
--- @param section string
--- @param action string
--- @return string
function M.format_keymap(section, action)
  local key = M.get_keymap(section, action)
  if not key then return "" end
  return M.format_key_string(key)
end

M._test = {
  get_keymap = M.get_keymap,
  format_key_string = M.format_key_string,
  format_keymap = M.format_keymap,
  merge = M.merge,
}

return M