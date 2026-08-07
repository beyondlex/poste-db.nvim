--- SQL execution entry point — supports single-statement (normal mode)
--- and multi-statement (visual selection) execution.
--- Each statement result goes into its own dataset tab.
local state = require("poste.state")
local statement = require("poste-sql.statement")
local sql_introspect = require("poste-sql.introspect")
local sql_runner = require("poste-sql.sql_runner")
local connections = require("poste-sql.connections")

local M = {}
M.ensure_sql_keymaps = sql_runner.ensure_sql_keymaps

-- INSERT INTO value-to-column hint
require("poste-sql.insert_hint").setup()

-- Global: clear filter/search from any buffer
local ck = state.get_keymap("sql_source", "clear_filter", "<leader>cr")
if ck then
  vim.keymap.set("n", ck, function()
    local sql_buf = require("poste-sql.buffer")
    if sql_buf.is_open() then
      sql_buf.clear_filter_search()
    end
  end, { noremap = true, silent = true, desc = "Poste: clear filter/search" })
end

M.run_sql_request = sql_runner.run_sql_request
M.show_table_ddl = sql_introspect.show_table_ddl

M._test = statement._test

-------------------------------------------------------------------------------
-- SQL setup — called from poste.init.setup()
-------------------------------------------------------------------------------

local buffer_setup = require("poste.buffer_setup")

local function register_sql_completion()
  local adapter = require("poste-sql.completion.adapter")
  if not adapter.is_available() then return end

  adapter.register_source({
    name = "poste_sql",
    module = "poste-sql.completion",
    label = "PosteSQL",
    async = true,
    score_offset = 1000,
    min_keyword_length = 0,
    should_show_items = true,
  })
  adapter.register_filetype("poste_sql", "poste_sql")
  adapter.register_filetype("poste_sqlite", "poste_sql")

  adapter.set_per_filetype("poste_sql", { "poste_sql" })
  adapter.set_per_filetype("poste_sqlite", { "poste_sql" })

  adapter.patch_blocked_trigger_chars()
end

local function setup_db_browser_keymap(buf)
  local k = state.get_keymap("sql_source", "toggle_db_browser", "<leader>db")
  if k then
    vim.keymap.set("n", k, function()
      require("poste-sql.db_browser").toggle()
    end, { buffer = buf, noremap = true, silent = true, desc = "Toggle DB Browser" })
  end
end

function M.setup(opts)
  opts = opts or {}
  local state = require("poste.state")
  state.config.db_browser = vim.tbl_deep_extend("force", state.config.db_browser, opts.db_browser or {})
  require("poste-sql.snippets").setup(opts)
  local default_icons = {
    Text = "",
    Field = "󰇨",
    Variable = "󰆧",
    Class = "",
    Interface = "󰏘",
    Function = "󰊕",
    Keyword = "󰌆",
    TypeParameter = "󰜢",
  }
  local sql_state = require("poste-sql.state")
  if vim.tbl_isempty(sql_state.icons) then
    sql_state.icons = vim.tbl_deep_extend("force", {}, default_icons)
  end
  if opts.icons then
    sql_state.icons = vim.tbl_deep_extend("force", sql_state.icons, opts.icons)
  end
  -- Check if Tree-sitter SQL parser is available
  local ok_ts = pcall(vim.treesitter.language.get_lang, "sql")
  if not ok_ts then
    vim.notify(
      "poste-sql: Tree-sitter SQL parser not found. "
        .. "Run :TSInstall sql to enable syntax highlighting, "
        .. "boundary detection, and diagnostics. "
        .. "Falling back to Rust/Lua heuristics.",
      vim.log.levels.WARN,
      { title = "Poste SQL" }
    )
  end

  local ok = pcall(register_sql_completion)
  if not ok then
    local group = vim.api.nvim_create_augroup("PosteSQLCmpRegister", { clear = true })
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      once = true,
      callback = function()
        pcall(register_sql_completion)
        vim.api.nvim_del_augroup_by_name("PosteSQLCmpRegister")
      end,
    })
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "poste_sql", "poste_sqlite" },
    callback = function(args)
      pcall(vim.treesitter.language.register, "sql", "poste_sql")
      pcall(vim.treesitter.language.register, "sql", "poste_sqlite")
      buffer_setup.setup_buffer_keymaps(args.buf)
      sql_runner.ensure_sql_keymaps(args.buf)
      setup_db_browser_keymap(args.buf)
    end,
  })

  require("poste-sql.statusline").setup()

  vim.api.nvim_set_hl(0, "PosteDbSqlDirectiveComment", { link = "Special" })

  -- Close SQL sessions when a buffer is unloaded (sessions with no remaining
  -- referencing buffers are shut down).
  vim.api.nvim_create_autocmd("BufUnload", {
    pattern = { "poste_sql", "poste_sqlite" },
    callback = function(args)
      pcall(require("poste-sql.session_conn").cleanup_buf, args.buf)
    end,
  })

  vim.api.nvim_create_user_command("PosteSQLSessionStop", function(args)
    local session_conn = require("poste-sql.session_conn")
    local arg = vim.trim(args.args)
    if arg == "" or arg == "--all" then
      session_conn.stop_all()
      vim.notify("Closed all SQL sessions", vim.log.levels.INFO, { title = "Poste SQL" })
    else
      session_conn.stop(arg)
      vim.notify("Closed SQL session: " .. arg, vim.log.levels.INFO, { title = "Poste SQL" })
    end
  end, {
    nargs = "*",
    desc = "Close SQL session(s) — :PosteSQLSessionStop [--all] [connection_url]",
  })

  vim.api.nvim_create_user_command("PosteSQLSessionList", function()
    local session_conn = require("poste-sql.session_conn")
    local sessions = session_conn.list()
    local lines = { "Active SQL sessions:" }
    local count = 0
    for conn_url, info in pairs(sessions) do
      count = count + 1
      table.insert(lines, string.format("  %s  (job %d, %s)", conn_url, info.job_id, info.dialect))
    end
    if count == 0 then
      table.insert(lines, "  (none)")
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Poste SQL" })
  end, { desc = "List active SQL sessions" })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "sql", "poste_sql", "poste_sqlite" },
    callback = function(args)
      local sql_syntax = require("poste-sql.syntax")
      sql_syntax.highlight_directive_comments(args.buf)
      -- Re-highlight directives on edits so manually typed @connection gets colored immediately
      local group = vim.api.nvim_create_augroup("PosteSQLDirectiveHL_" .. args.buf, { clear = true })
      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        buffer = args.buf,
        callback = function()
          sql_syntax.highlight_directive_comments(args.buf)
        end,
      })
    end,
  })

  vim.api.nvim_create_user_command("PosteDbInfo", function()
    local sep = "─"
    local parts = { sep }

    local binary = state.find_poste_binary()
    if binary then
      table.insert(parts, "poste_binary: " .. binary)
      local mtime = vim.loop.fs_stat(binary)
      if mtime then
        local date_str = os.date("%Y-%m-%d %H:%M:%S", mtime.mtime.sec)
        table.insert(parts, "built:       " .. date_str)
      end
      local handle = io.popen('"' .. binary .. '" --version 2>/dev/null')
      if handle then
        local version = handle:read("*a"):gsub("%s+$", "")
        handle:close()
        if version ~= "" then
          local tag, date = version:match("poste ([^%(]+)%(([^%)]+)%)")
          if tag and date then
            table.insert(parts, "version:     " .. tag)
            table.insert(parts, "released:    " .. date)
          else
            table.insert(parts, "version:     " .. version)
          end
        end
      end
    else
      table.insert(parts, "poste_binary: not found")
    end

    local buf_name = vim.api.nvim_buf_get_name(0)
    local search_dir = buf_name ~= "" and vim.fn.fnamemodify(buf_name, ":h") or vim.fn.getcwd()
    local config_path = connections.find_connections_toml(search_dir)
    if config_path then
      table.insert(parts, "connections: " .. config_path)
    else
      table.insert(parts, "connections: not found (searched from " .. search_dir .. ")")
    end

    local parser_dir = vim.fn.stdpath("data") .. "/site/parser"
    local ts_ok, _ = pcall(vim.treesitter.get_parser, 0, "sql")
    local ts_file = (vim.fn.filereadable(parser_dir .. "/sql.so") == 1) and "installed" or "missing"
    table.insert(parts, "treesitter: " .. (ts_ok and "active" or "unavailable") .. " (" .. ts_file .. ")")

    table.insert(parts, sep)

    local blink_ok = pcall(require, "blink.cmp")
    if blink_ok then
      local providers = {}
      local config_ok, config = pcall(require, "blink.cmp.config")
      if config_ok and config.sources and config.sources.providers then
        for id, _ in pairs(config.sources.providers) do
          table.insert(providers, id)
        end
      end
      local has_poste_sql = vim.tbl_contains(providers, "poste_sql") and "yes" or "no"
      table.insert(parts, "blink.cmp: loaded")
      table.insert(parts, "  providers:  " .. (#providers > 0 and table.concat(providers, ", ") or "(none)"))
      table.insert(parts, "  poste_sql:  " .. has_poste_sql)
    else
      table.insert(parts, "blink.cmp: not loaded")
    end

    local cmp_ok = pcall(require, "cmp")
    if cmp_ok then
      table.insert(parts, "nvim-cmp:   loaded")
    end

    local ft = vim.bo.filetype or "(none)"
    table.insert(parts, "filetype:   " .. ft)
    table.insert(parts, sep)

    vim.notify(table.concat(parts, "\n"), vim.log.levels.INFO)
  end, { desc = "Show Poste SQL environment info" })

  vim.api.nvim_create_user_command("PosteSQLCmpStatus", function()
    local sql_comp = require("poste-sql.completion")
    local ft = vim.bo.filetype
    local buf = vim.api.nvim_get_current_buf()

    local status = {
      "SQL Completion Status:",
      "  Current filetype: " .. ft,
      "  Buffer: " .. buf,
    }

    local instance = sql_comp.new()
    table.insert(status, "  Enabled: " .. tostring(instance:enabled()))

    table.insert(status, "  blink.cmp loaded: " .. tostring(require("poste-sql.completion.adapter").is_available()))
    local adapter = require("poste-sql.completion.adapter")
    if adapter.is_available() then
      local has_sql = adapter.has_provider("poste_sql")
      table.insert(status, "  poste_sql provider registered: " .. tostring(has_sql))
    end

    local ctx_mod = require("poste-sql.context")
    local ctx = ctx_mod.resolve_context(buf)
    table.insert(status, "  Connection: " .. (ctx.connection or "none"))
    table.insert(status, "  Database: " .. (ctx.database or "none"))

    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local col = cursor[2]
    local line_before = line:sub(1, col)

    table.insert(status, "\nAt cursor position (col=" .. col .. "):")
    table.insert(status, "  Line: " .. line)
    table.insert(status, "  Before cursor: '" .. line_before .. "'")
    table.insert(status, "  After cursor: '" .. line:sub(col + 1) .. "'")

    if sql_comp._test then
      local ctx_type, ctx_data = sql_comp._test.detect_context_for_completion(line_before)
      table.insert(status, "  Detected context: " .. tostring(ctx_type))
      if ctx_data then
        table.insert(status, "  Context data: " .. tostring(ctx_data))
      end
    end

    vim.notify(table.concat(status, "\n"), vim.log.levels.INFO)
  end, { desc = "Check SQL completion status" })

  vim.api.nvim_create_user_command("PosteSQLAutoTrigger", function()
    local group = vim.api.nvim_create_augroup("PosteSQLAutoComplete", { clear = true })
    vim.api.nvim_create_autocmd("TextChangedI", {
      group = group,
      buffer = 0,
      callback = function()
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]

        if col > 0 and line:sub(col, col) == " " then
          local before = line:sub(1, col - 1)
          local last_word = before:match("(%w+)%s*$")

          if last_word then
            local lw = last_word:lower()
            if lw == "from" or lw == "join" or lw == "where" or
               lw == "set" or lw == "on" or lw == "having" or
               lw == "by" or lw == "and" or lw == "or" then
              vim.schedule(function()
                pcall(function() require("poste-sql.completion.adapter").show() end)
              end)
            end
          end
        end
      end
    })
    vim.notify("SQL auto-trigger installed for current buffer", vim.log.levels.INFO)
  end, { desc = "Install SQL auto-trigger for completion" })

  vim.api.nvim_create_user_command("PosteSQLCmpReload", function()
    package.loaded["poste-sql.completion"] = nil
    require("poste-sql.completion")
    local adapter = require("poste-sql.completion.adapter")

    if not adapter.is_available() then
      vim.notify("blink.cmp not loaded, cannot re-register", vim.log.levels.WARN)
      return
    end
    adapter.register_source({
      name = "poste_sql",
      module = "poste-sql.completion",
      label = "PosteSQL",
      score_offset = 1000,
      min_keyword_length = 0,
      should_show_items = true,
    })
    adapter.register_filetype("poste_sql", "poste_sql")
    adapter.register_filetype("poste_sqlite", "poste_sql")
    vim.notify("SQL completion reloaded and re-registered with blink.cmp", vim.log.levels.INFO)
  end, { desc = "Reload SQL completion provider" })

  vim.api.nvim_create_user_command("PosteSQLDiag", function()
    local sql_comp = require("poste-sql.completion")
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local col = cursor[2]
    local line_before = line:sub(1, col)
    local cursor_lnum = cursor[1]

    local ctx_type, _ = sql_comp._test.detect_context_for_completion(line_before)
    local tbls, alias_map = sql_comp._test.extract_from_tables(buf, cursor_lnum)
    local conn = sql_comp._test.conn_key()

    local blink_src = require("poste-sql.completion.adapter").get_source_lib()
    local blink_config = require("poste-sql.completion.adapter").get_config()
    local active_providers = blink_src.get_enabled_provider_ids("insert")
    local per_ft = "(unavailable)"
    if blink_config.sources and blink_config.sources.per_filetype then
      per_ft = vim.inspect(blink_config.sources.per_filetype["poste_sql"])
    end
    local runtime_ft = vim.inspect(blink_src.per_filetype_provider_ids)

    local msg = {
      "line_before: '" .. line_before .. "'",
      "ctx: " .. tostring(ctx_type),
      "conn_key: " .. tostring(conn),
      "cursor_lnum: " .. cursor_lnum,
      "ft: " .. vim.bo.filetype,
      "active blink providers: " .. vim.inspect(active_providers),
      "static per_filetype[poste_sql]: " .. per_ft,
      "runtime per_filetype_provider_ids: " .. runtime_ft,
    }
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, cursor_lnum, false)
    for i, l in ipairs(buf_lines) do
      table.insert(msg, "  " .. i .. ": " .. l)
    end
    table.insert(msg, "tables: " .. vim.inspect(tbls))
    table.insert(msg, "alias_map: " .. vim.inspect(alias_map))

    sql_comp._test.get_items(buf, line_before, cursor_lnum, function(items)
      table.insert(msg, "items(" .. #items .. "): " .. vim.inspect(vim.list_slice(items, 1, 3)))
      vim.notify(table.concat(msg, "\n"), vim.log.levels.WARN)
    end)
  end, { desc = "Diagnose SQL completion at cursor" })

  vim.api.nvim_create_user_command("PosteSQLDebugSpace", function()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local before = line:sub(1, col)
    local last_word = before:match("(%w+)%s*$")

    local adapter = require("poste-sql.completion.adapter")

    local msg = {
      "PosteSQLDebugSpace:",
      "  line_before cursor: '" .. before .. "'",
      "  last_word: " .. tostring(last_word),
      "  blink loaded: " .. tostring(adapter.is_available()),
      "  blink.show exists: " .. tostring(adapter.is_available()),
      "  menu currently open: " .. tostring(adapter.is_menu_open()),
    }

    if adapter.is_available() then
      vim.notify(table.concat(msg, "\n") .. "\n  → calling blink.show() now...", vim.log.levels.WARN)
      adapter.show()
    else
      vim.notify(table.concat(msg, "\n"), vim.log.levels.ERROR)
    end
  end, { desc = "Debug SQL space completion trigger" })

  vim.api.nvim_create_user_command("PosteSQLCmpTest", function()
    local sql_comp = require("poste-sql.completion")
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local col = cursor[2]
    local line_before = line:sub(1, col)
    local cursor_line = cursor[1]

    local status = {
      "SQL Completion Test:",
      "  line_before: '" .. line_before .. "'",
      "  cursor_line: " .. cursor_line,
    }

    if sql_comp._test then
      local ctx_type = sql_comp._test.detect_context_for_completion(line_before)
      table.insert(status, "  Context: " .. tostring(ctx_type))

      if ctx_type == "column" and sql_comp._test.extract_from_tables then
        local tbls = sql_comp._test.extract_from_tables(buf, cursor_line)
        table.insert(status, "  Tables found: " .. #tbls .. " - " .. vim.inspect(tbls))
      end

      local conn = sql_comp._test.conn_key and sql_comp._test.conn_key()
      table.insert(status, "  Connection key: " .. tostring(conn))
    end

    if sql_comp._test and sql_comp._test.get_items then
      sql_comp._test.get_items(buf, line_before, cursor_line, function(items)
        table.insert(status, "\nReturned " .. #items .. " items:")
        for i, item in ipairs(items) do
          if i <= 10 then
            table.insert(status, "  " .. item.label .. " (" .. (item.documentation or "") .. ")")
          end
        end
        if #items > 10 then
          table.insert(status, "  ... and " .. (#items - 10) .. " more")
        end
        vim.notify(table.concat(status, "\n"), vim.log.levels.INFO)
      end)
    else
      vim.notify(table.concat(status, "\n"), vim.log.levels.INFO)
    end
  end, { desc = "Test SQL completion at cursor" })

  vim.api.nvim_create_user_command("PosteSQLCmpDebug", function()
    require("poste-sql.completion.debug").toggle()
  end, { desc = "Toggle SQL completion debug floating window" })

  vim.api.nvim_create_user_command("PosteConnection", function()
    require("poste-sql.connections").show_menu()
  end, { desc = "Manage SQL connections" })

  vim.api.nvim_create_user_command("PosteFormat", function()
    local _, source_format = pcall(require, "poste-sql.source_format")
    if source_format then
      source_format.format_buffer()
    else
      vim.notify("Poste source_format module not available", vim.log.levels.ERROR)
    end
  end, { desc = "Format SQL buffer/selection using detected formatter (sqlfluff/sqlfmt/...)" })

  vim.api.nvim_create_user_command("PosteFormatStatus", function()
    local _, source_format = pcall(require, "poste-sql.source_format")
    if source_format then
      source_format.status()
    else
      vim.notify("Poste source_format module not available", vim.log.levels.ERROR)
    end
  end, { desc = "Show formatter status: installed, priority, dialect" })

  vim.api.nvim_create_user_command("PosteDBBrowser", function()
    require("poste-sql.db_browser").toggle()
  end, { desc = "Toggle database structure browser sidebar" })

  vim.api.nvim_create_user_command("PosteExport", function(args)
    local parts = {}
    for word in args.args:gmatch("%S+") do
      table.insert(parts, word)
    end
    require("poste-sql.export").run(parts[1], parts[2], parts[3])
  end, {
    nargs = "*",
    complete = function(ArgLead, CmdLine)
      return require("poste-sql.export").complete(ArgLead, CmdLine)
    end,
    desc = "Export dataset — :PosteExport [format] [destination] [path]",
  })

  vim.api.nvim_create_user_command("PosteSqlLog", function()
    require("poste-sql.log_viewer").toggle()
  end, { desc = "Toggle SQL execution log viewer" })

  vim.api.nvim_create_user_command("PosteSQLContext", function(args)
    local context = require("poste-sql.context")
    local parts = {}
    for word in args.args:gmatch("%S+") do
      table.insert(parts, word)
    end
    context.switch_context(parts)
  end, {
    nargs = "*",
    desc = "Switch SQL execution context (connection/database)",
  })

  vim.api.nvim_create_user_command("PosteSQLRunFile", function(args)
    require("poste-sql.file_exec").run({
      filepath = args.args,
      mode = "greedy",
    })
  end, {
    nargs = 1,
    complete = "file",
    desc = "Execute a SQL file",
  })

  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = { "*.sql", "*.sqlite" },
    callback = function()
      pcall(vim.treesitter.language.register, "sql", "poste_sql")
      pcall(vim.treesitter.language.register, "sql", "poste_sqlite")
      local name = vim.api.nvim_buf_get_name(0)
      if name:match("%.sqlite$") then
        vim.bo.filetype = "poste_sqlite"
      else
        vim.bo.filetype = "poste_sql"
      end

      local k = state.get_keymap("sql_source", "trigger_completion", "<C-Space>")
      if k then
        vim.keymap.set("i", k, function()
          pcall(function() require("poste-sql.completion.adapter").show() end)
        end, { buffer = 0, noremap = true, silent = true, desc = "Trigger completion" })
      end

      local sql_keywords = { from=true, join=true, where=true, set=true,
                              on=true, having=true, by=true, ["and"]=true, ["or"]=true,
                              use=true }
      local group = vim.api.nvim_create_augroup("PosteSQLTrigger_" .. vim.api.nvim_get_current_buf(), { clear = true })
      vim.api.nvim_create_autocmd("CursorMovedI", {
        group = group,
        buffer = 0,
        callback = function()
          local line = vim.api.nvim_get_current_line()
          local col  = vim.api.nvim_win_get_cursor(0)[2]
          if col < 1 or line:sub(col, col) ~= " " then return end
          local last_word = line:sub(1, col - 1):match("(%w+)%s*$")
          if last_word and sql_keywords[last_word:lower()] then
            local adapter = require("poste-sql.completion.adapter")
            adapter.show({ force = true, trigger_kind = "manual" })
          end
        end,
      })

      vim.api.nvim_create_autocmd("InsertEnter", {
        group = group,
        buffer = 0,
        callback = function()
          local line = vim.api.nvim_get_current_line()
          local col = vim.api.nvim_win_get_cursor(0)[2]
          local before = line:sub(1, col)
          local prefix = before:match("[%w_]*$") or ""
          if #prefix > 0 then
            vim.schedule(function()
              local adapter = require("poste-sql.completion.adapter")
              adapter.show({ force = true, trigger_kind = "manual" })
            end)
          end
        end,
      })

      vim.b.blink_cmp_min_keyword_length = 0
    end,
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("%.sqlite$") then
      vim.api.nvim_buf_set_option(buf, "filetype", "poste_sqlite")
      buffer_setup.setup_buffer_keymaps(buf)
      sql_runner.ensure_sql_keymaps(buf)
      setup_db_browser_keymap(buf)
    elseif name:match("%.sql$") then
      vim.api.nvim_buf_set_option(buf, "filetype", "poste_sql")
      buffer_setup.setup_buffer_keymaps(buf)
      sql_runner.ensure_sql_keymaps(buf)
      setup_db_browser_keymap(buf)
    end
  end
end

return M
