--- SQL keymap help — displays SQL-specific keymaps in a floating window.
local state = require("poste.state")
local dialog = require("poste.dialog")

local M = {}

local DESCRIPTIONS = {
  sql_source = {
    run = "Execute SQL statement(s)",
    show_ddl = "Show DDL / column info",
    format = "Format SQL buffer/selection",
    clear_filter = "Clear filter / search",
    toggle_db_browser = "Toggle DB Browser panel",
    trigger_completion = "Trigger SQL completion",
    toggle_log = "Toggle execution log",
    help = "Show this help window",
  },
  sql_dataset = {
    close = "Close dataset window",
    move_left = "Move cell left",
    move_down = "Move cell down",
    move_up = "Move cell up",
    move_right = "Move cell right",
    prev_page = "Previous page",
    next_page = "Next page",
    first_col = "Jump to first column",
    last_col = "Jump to last column",
    first_row = "Jump to first row",
    last_row = "Jump to last row",
    preview_cell = "Preview cell content",
    yank_cell = "Yank current cell",
    yank_column = "Yank current column",
    sort_column = "Sort by column",
    toggle_cell_highlight = "Toggle cell highlight",
    toggle_header_float = "Toggle floating header",
    toggle_row_numbers = "Toggle row numbers",
    toggle_raw_mode = "Toggle raw table mode",
    next_tab = "Next result tab",
    prev_tab = "Previous result tab",
    rerun = "Re-run query",
    goto_first_page = "Go to first page",
    goto_last_page = "Go to last page",
    toggle_pagination = "Toggle pagination",
    find_column = "Find column",
    filter_by_cell = "Filter by cell value",
    show_search = "Search in results",
    clear_filter_search = "Clear filter / search",
    next_search = "Next search match",
    prev_search = "Previous search match",
    commit_edits = "Commit pending edits",
    edit_cell = "Edit cell value",
    edit_cell_replace = "Replace cell value",
    delete_row = "Delete row",
    insert_row = "Insert row",
    export = "Export dataset (format → destination)",
    show_sql = "Show SQL in floating window",
    help = "Show keymap help",
    history_next = "Next history entry",
    history_prev = "Previous history entry",
    history_toggle = "Toggle request history sidebar",
  },
  sql_table_ops = {
    select_all = "SELECT * from table",
    refresh_all = "Refresh table list",
    describe_all = "DESCRIBE table",
    toggle_menu = "Toggle action menu",
  },
  sql_db_browser = {
    toggle_node = "Toggle expand/collapse node",
    move_left = "Collapse node / go to parent",
    move_right = "Expand node / go to first child",
    context_menu = "Open context menu",
    refresh_node = "Refresh node children",
    search_filter = "Fuzzy search tree",
    select_query = "Generate SELECT query",
    close = "Close DB Browser",
    search_next = "Next search match",
    search_prev = "Previous search match",
    table_info = "Show table info (rows, size, engine, etc.)",
    create_object = "Create database/schema (contextual)",
  },
  sql_introspect = {
    close = "Close introspect window",
    close_alt = "Close introspect window",
  },
}

local SECTION_TITLES = {
  sql_source = "SQL Source Buffer",
  sql_dataset = "SQL Dataset Buffer",
  sql_table_ops = "SQL Table Ops",
  sql_db_browser = "DB Browser",
  sql_introspect = "Introspect Float",
}

function M.open()
  local lines = {}
  local highlights = {}
  local width = 50

  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  local buf_name = vim.api.nvim_buf_get_name(buf)
  local sections
  if ft == "poste_sql" or ft == "poste_sqlite" or ft == "sql" then
    sections = { "sql_source" }
  elseif ft == "poste_dataset" or ft == "PosteDataset" then
    sections = { "sql_dataset" }
  elseif buf_name:match("poste://db_browser") then
    sections = { "sql_db_browser" }
  else
    sections = { "sql_source", "sql_dataset", "sql_table_ops", "sql_db_browser", "sql_introspect" }
  end

  for _, section in ipairs(sections) do
    local title = SECTION_TITLES[section] or section
    local km = state.config.keymaps[section] or {}
    local desc = DESCRIPTIONS[section] or {}

    table.insert(lines, "")
    table.insert(lines, "  " .. title)
    table.insert(highlights, { line = #lines - 1, col_start = 2, col_end = 2 + #title, hl_group = "Title" })
    table.insert(lines, "  " .. string.rep("─", 46))
    table.insert(highlights, { line = #lines - 1, col_start = 2, col_end = #lines[#lines], hl_group = "Comment" })

    local actions = {}
    for action, _ in pairs(km) do
      table.insert(actions, action)
    end
    table.sort(actions)

    for _, action in ipairs(actions) do
      local key = state.get_keymap(section, action)
      if key and key ~= false then
        local key_display = state.format_key_string(key)
        local description = desc[action] or ""
        local line = string.format("  %-12s  %s", key_display, description)
        table.insert(lines, line)
        width = math.max(width, #line + 2)
        local _, key_e = line:find("%S+", 3)
        if key_e then
          table.insert(highlights, { line = #lines - 1, col_start = 2, col_end = key_e, hl_group = "Special" })
        end
      end
    end
  end

  local close_keys = {}
  local function collect_close(section, action)
    local k = state.get_keymap(section, action)
    if k then close_keys[state.format_key_string(k)] = true end
  end
  collect_close("sql_dataset", "close")
  collect_close("sql_db_browser", "close")
  collect_close("sql_introspect", "close")
  collect_close("sql_introspect", "close_alt")
  local close_parts = {}
  for k in pairs(close_keys) do
    table.insert(close_parts, k)
  end
  table.sort(close_parts, function(a, b) return #a < #b end)
  local close_text = #close_parts > 0 and table.concat(close_parts, " / ") or "q"

  local d = dialog.open({
    title = string.format(" PosteDb Keymaps   [%s] close ", close_text),
    width = width,
    height = math.min(#lines, vim.o.lines - 4),
  })
  d:update(lines, highlights)
end

return M