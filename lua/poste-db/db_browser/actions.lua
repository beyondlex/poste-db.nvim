local icons = require("poste-db.db_browser.icons")
local tree = require("poste-db.db_browser.tree")
local async = require("poste-db.db_browser.async")
local state = require("poste.state")
local cli = require("poste.cli")
local ident = require("poste-db.ident")
local util = require("poste-db.db_browser.util")

local HEADER_LINES = icons.HEADER_LINES

local function deep_clean(t)
  for k, v in pairs(t) do
    if v == vim.NIL then
      t[k] = nil
    elseif type(v) == "table" then
      deep_clean(v)
    end
  end
end

local M = {}

local search_hl_ns = vim.api.nvim_create_namespace("poste_db_browser_search")
local search_char_ns = vim.api.nvim_create_namespace("poste_db_browser_search_char")

-- Search state for / n N navigation
local search_state = {
  matches = {},
  current = 0,
  pattern = "",
  context = nil,
}

-- Fuzzy match: each pattern char must appear in order in text (case-insensitive).
-- Returns true + 1-indexed positions of matched chars, or false.
local function fuzzy_match(text, pattern)
  local ti = 1
  local positions = {}
  local plower = pattern:lower()
  local tlower = text:lower()
  for pi = 1, #plower do
    local pc = plower:sub(pi, pi)
    local found = false
    while ti <= #tlower do
      if tlower:sub(ti, ti) == pc then
        table.insert(positions, ti)
        ti = ti + 1
        found = true
        break
      end
      ti = ti + 1
    end
    if not found then return false end
  end
  return true, positions
end

M.find_table_node = util.find_table_node

local get_connection = util.get_connection
local get_dialect = util.get_dialect
local get_search_dir = util.get_search_dir

local execute_table_select  -- forward declaration

function M.toggle_node(buf_line, context)
  local node = tree.get_node_at_line(context.line_to_node, buf_line)
  if not node then return end

  -- Table node: execute SELECT * directly instead of expanding
  if node.node_type == "table" then
    execute_table_select(node, context)
    return
  end

  if node.node_type == "column" or node.node_type == "index"
      or node.node_type == "key_item" or node.node_type == "fk_item"
      or node.node_type == "index_item" then
    return
  end

  if node.expanded then
    node.expanded = false
    local new_map = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
    for i, n in ipairs(new_map) do context.line_to_node[i] = n end
  else
    if node.children then
      node.expanded = true
      local new_map = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
      for i, n in ipairs(new_map) do context.line_to_node[i] = n end
    else
      node.loading = true
      local new_map = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
      for i, n in ipairs(new_map) do context.line_to_node[i] = n end
      local search_dir = get_search_dir(context.source_buf)
      async.fetch_children(node, function()
        node.expanded = true
        vim.schedule(function()
          local nm = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
          for i, n in ipairs(nm) do context.line_to_node[i] = n end
        end)
      end, search_dir)
    end
  end
end

local LEAF_TYPES = {
  column = true, index = true, key_item = true, fk_item = true, index_item = true,
}

local function get_indent(buf, line_nr)
  local text = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1] or ""
  local leading = text:match("^%s*") or ""
  return math.floor(#leading / 2)
end

local function find_parent_line(buf, start_line_nr, current_depth, line_to_node, header_lines)
  for line = start_line_nr - 1, header_lines + 1, -1 do
    local parent_depth = get_indent(buf, line)
    if parent_depth < current_depth then
      local idx = line - header_lines
      if idx >= 1 and idx <= #line_to_node and line_to_node[idx] then
        return line
      end
    end
  end
  return nil
end

function M.collapse_or_parent(buf_line, context)
  local node = tree.get_node_at_line(context.line_to_node, buf_line)
  if not node then return end

  local is_leaf = LEAF_TYPES[node.node_type]
  local current_depth = get_indent(context.browser_buf, buf_line)

  if not is_leaf and node.expanded then
    -- Collapse: fold children, stay on this node
    node.expanded = false
    local new_map = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
    for i, n in ipairs(new_map) do context.line_to_node[i] = n end
    -- Keep cursor on the collapsed node
    for i, n in ipairs(context.line_to_node) do
      if n == node then
        vim.api.nvim_win_set_cursor(0, { i + HEADER_LINES, 0 })
        return
      end
    end
  else
    -- Go to parent (leaf, or non-leaf already collapsed)
    local parent_line = find_parent_line(context.browser_buf, buf_line, current_depth, context.line_to_node, HEADER_LINES)
    if parent_line then
      vim.api.nvim_win_set_cursor(0, { parent_line, 0 })
    end
  end
end

function M.expand_or_child(buf_line, context)
  local node = tree.get_node_at_line(context.line_to_node, buf_line)
  if not node then return end

  local is_leaf = LEAF_TYPES[node.node_type]
  if is_leaf then return end

  if not node.expanded then
    -- Expand node directly (don't call toggle_node which executes SELECT on tables)
    if node.children then
      node.expanded = true
      local new_map = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
      for i, n in ipairs(new_map) do context.line_to_node[i] = n end
    else
      node.loading = true
      local new_map = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
      for i, n in ipairs(new_map) do context.line_to_node[i] = n end
      local search_dir = vim.fn.getcwd()
      async.fetch_children(node, function()
        node.expanded = true
        vim.schedule(function()
          local nm = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
          for i, n in ipairs(nm) do context.line_to_node[i] = n end
        end)
      end, search_dir)
    end
  else
    -- Already expanded → jump to first child (next line)
    local total_lines = vim.api.nvim_buf_line_count(context.browser_buf)
    local next_line = buf_line + 1
    if next_line <= total_lines then
      local next_depth = get_indent(context.browser_buf, next_line)
      local current_depth = get_indent(context.browser_buf, buf_line)
      if next_depth > current_depth then
        vim.api.nvim_win_set_cursor(0, { next_line, 0 })
      end
    end
  end
end

function M.refresh_node(buf_line, context)
  local node = tree.get_node_at_line(context.line_to_node, buf_line)
  if not node then return end
  if node.node_type == "column" or node.node_type == "index"
      or node.node_type == "key_item" or node.node_type == "fk_item"
      or node.node_type == "index_item" then
    return
  end

  node.children = nil
  node.expanded = false
  node.loading = true
  local new_map = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
  for i, n in ipairs(new_map) do context.line_to_node[i] = n end

  local search_dir = get_search_dir(context.source_buf)
  async.fetch_children(node, function()
    node.expanded = true
    vim.schedule(function()
      local nm = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
      for i, n in ipairs(nm) do context.line_to_node[i] = n end
    end)
  end, search_dir)
end

--- Execute SELECT * on a table node and render results in the dataset buffer.
execute_table_select = function(node, context)
  local dialect = get_dialect(node, context.root_nodes)
  local conn = get_connection(node, context.root_nodes)
  local schema_prefix = ""
  if node.meta and node.meta.schema and dialect == "postgres" then
    schema_prefix = ident.quote(node.meta.schema, dialect) .. "."
  end

  local sql = "-- @connection " .. conn .. "\nSELECT * FROM " .. schema_prefix .. ident.quote(node.name, dialect) .. " LIMIT 100;"
  local search_dir = vim.fn.getcwd()

  local connections = require("poste-db.connections")
  local url, err = connections.resolve_connection_url(conn)
  if not url then
    vim.notify("Connection '" .. conn .. "' not found: " .. (err or "unknown"), vim.log.levels.ERROR)
    return
  end

  local exec_run = require("poste-db.exec_run")
  local job_id = exec_run.run_async(sql, {
    src_file = search_dir .. "/browser_select.sql",
    conn_url = url,
    database = node.meta and node.meta.database or nil,
    mode = "greedy",
  }, {
    on_response = function(parsed)
      local sql_format = require("poste-db.format")
      local sql_buffer = require("poste-db.buffer")
      local lines, meta, layout = sql_format.format_dataset(parsed)
      meta = meta or {}
      meta.table_name = node.name
      -- Pass the fresh resultset explicitly: render_dataset otherwise falls
      -- back to state.last_response.body (only the sql_runner path updates
      -- it), so cell preview (K) / yank / sort would read stale rows.
      local data = nil
      if parsed and parsed.body then
        local ok, d = pcall(vim.json.decode, parsed.body)
        if ok then data = d end
      end
      sql_buffer.render_dataset(lines, meta, {
        data = parsed,
        layout = layout,
        data = data,
        original_sql = sql,
        src_file = "poste://db_browser",
        src_buf = context.source_buf,
      })
    end,
    on_error = function(message)
      vim.schedule(function()
        vim.notify("Query failed for '" .. node.name .. "': " .. message, vim.log.levels.ERROR)
      end)
    end,
  })

  if not job_id or job_id <= 0 then
    vim.notify("Failed to start poste job", vim.log.levels.ERROR)
  end
end

local function ensure_expanded(node, search_dir, callback)
  if node.expanded then
    callback()
  elseif node.children then
    node.expanded = true
    callback()
  else
    node.loading = true
    async.fetch_children(node, function()
      node.expanded = true
      callback()
    end, search_dir)
  end
end

local function expand_ancestors(ancestors, search_dir, callback, i)
  i = i or 1
  if i > #ancestors then
    callback()
    return
  end
  ensure_expanded(ancestors[i], search_dir, function()
    expand_ancestors(ancestors, search_dir, callback, i + 1)
  end)
end

local function highlight_match_chars(buf, line_to_node, matches)
  vim.api.nvim_buf_clear_namespace(buf, search_char_ns, 0, -1)
  for _, match in ipairs(matches) do
    for i, n in ipairs(line_to_node) do
      if n == match.node then
        local line_nr = i + HEADER_LINES - 1 -- 0-indexed
        local text = vim.api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1] or ""
        local name_start = text:find(match.node.name, 1, true)
        if name_start and match.positions then
          for _, pos in ipairs(match.positions) do
            local char_col = name_start + pos - 2
            vim.api.nvim_buf_add_highlight(buf, search_char_ns, "PosteDbBrowserSearchChar",
              line_nr, char_col, char_col + 1)
          end
        end
        break
      end
    end
  end
end

local function do_jump(index)
  local s = search_state
    if #s.matches == 0 then return end

  index = ((index - 1) % #s.matches) + 1
  s.current = index

  local match = s.matches[index]
  local ctx = s.context
  local search_dir = get_search_dir(ctx.source_buf)

  expand_ancestors(match.ancestors, search_dir, function()
    vim.schedule(function()
      -- Update header with match info
      _G.poste_search_info = { pattern = s.pattern, current = s.current, total = #s.matches }
      local new_map = tree.render_tree(ctx.browser_buf, ctx.line_to_node, ctx.root_nodes, ctx.conn_label)
      for i, n in ipairs(new_map) do ctx.line_to_node[i] = n end

      -- Highlight matching chars on all matches
      highlight_match_chars(ctx.browser_buf, ctx.line_to_node, s.matches)

      -- Line-level highlight only on current match
      for i, n in ipairs(ctx.line_to_node) do
        if n == match.node then
          local target_line = i + HEADER_LINES
          vim.api.nvim_buf_clear_namespace(ctx.browser_buf, search_hl_ns, 0, -1)
          vim.api.nvim_buf_add_highlight(ctx.browser_buf, search_hl_ns, "PosteDbBrowserSearchMatch",
            target_line - 1, 0, -1)
          vim.api.nvim_win_set_cursor(0, { target_line, 0 })
          break
        end
      end
    end)
  end)
end

local function walk_tree(nodes, lower, ancestors, matches)
  for _, node in ipairs(nodes) do
    local ok, positions = fuzzy_match(node.name, lower)
    if ok then
      local anc = {}
      for _, a in ipairs(ancestors) do table.insert(anc, a) end
      table.insert(matches, { node = node, ancestors = anc, positions = positions })
    end
    if node.children then
      local new_anc = {}
      for _, a in ipairs(ancestors) do table.insert(new_anc, a) end
      table.insert(new_anc, node)
      walk_tree(node.children, lower, new_anc, matches)
    end
  end
end

function M.search_filter(buf_line, context)
  vim.ui.input({
    prompt = "Search: ",
    buf_options = { filetype = "" },
  }, function(input)
    if not input or input == "" then
      search_state = { matches = {}, current = 0, pattern = "", context = nil }
      _G.poste_search_info = nil
      local new_map = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
      for i, n in ipairs(new_map) do context.line_to_node[i] = n end
      vim.api.nvim_buf_clear_namespace(context.browser_buf, search_hl_ns, 0, -1)
      vim.api.nvim_buf_clear_namespace(context.browser_buf, search_char_ns, 0, -1)
      return
    end

    local lower = input:lower()
    local matches = {}

    walk_tree(context.root_nodes, lower, {}, matches)

    if #matches > 0 then
      search_state = { matches = matches, current = 0, pattern = input, context = context }
      do_jump(1)
      return
    end

    -- No matches in visible tree
    _G.poste_search_info = { pattern = input, current = 0, total = 0 }
    vim.api.nvim_buf_clear_namespace(context.browser_buf, search_hl_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(context.browser_buf, search_char_ns, 0, -1)
    local new_map = tree.render_tree(context.browser_buf, context.line_to_node, context.root_nodes, context.conn_label)
    for i, n in ipairs(new_map) do context.line_to_node[i] = n end
  end)
end

function M.search_clear(context)
  local c = context or search_state.context
  if not c then return end
  search_state = { matches = {}, current = 0, pattern = "", context = nil }
  _G.poste_search_info = nil
  local new_map = tree.render_tree(c.browser_buf, c.line_to_node, c.root_nodes, c.conn_label)
  for i, n in ipairs(new_map) do c.line_to_node[i] = n end
  vim.api.nvim_buf_clear_namespace(c.browser_buf, search_hl_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(c.browser_buf, search_char_ns, 0, -1)
end

function M.search_next()
  if #search_state.matches == 0 then return end
  do_jump(search_state.current + 1)
end

function M.search_prev()
  if #search_state.matches == 0 then return end
  do_jump(search_state.current - 1)
end

local function format_bytes(bytes)
  if type(bytes) ~= "number" then return tostring(bytes or "?") end
  if bytes >= 1073741824 then return string.format("%.2f GB", bytes / 1073741824) end
  if bytes >= 1048576 then return string.format("%.2f MB", bytes / 1048576) end
  if bytes >= 1024 then return string.format("%.2f kB", bytes / 1024) end
  return bytes .. " B"
end

function M.show_column_info(buf_line, context)
  local node = tree.get_node_at_line(context.line_to_node, buf_line)
  if not node or node.node_type ~= "column" then
    vim.notify("Move cursor to a column", vim.log.levels.INFO)
    return
  end

  local meta = node.meta
  local lines = {}
  local label_width = 10

  local function add(label, value)
    if value ~= nil and value ~= "" and value ~= vim.NIL then
      lines[#lines + 1] = string.format("  %s%s  %s", string.rep(" ", label_width - #label), label, value)
    end
  end

  add("Type",     meta.col_type)
  add("Default",  meta.default ~= vim.NIL and tostring(meta.default) or "(null)")
  add("Nullable", meta.nullable == true and "YES" or (meta.nullable == false and "NO" or "?"))
  if meta.extra and meta.extra ~= "" then
    add("Extra", meta.extra)
  end
  add("Comment",  meta.comment ~= "" and ("'" .. meta.comment .. "'") or nil)
  add("Collation", meta.collation)

  vim.schedule(function()
    local title = "Column Info: " .. node.name
    require("poste-db.introspect").show_float(lines, title, "text")
  end)
end

function M.show_table_info(buf_line, context)
  local idx = buf_line - HEADER_LINES
  local table_node = M.find_table_node(context.line_to_node, idx)
  if not table_node then
    vim.notify("Move cursor to a table node", vim.log.levels.INFO)
    return
  end

  local conn = get_connection(table_node, context.root_nodes)
  local schema = table_node.meta and table_node.meta.schema
  local database = table_node.meta and table_node.meta.database
  local dialect = get_dialect(table_node, context.root_nodes)

  local connections = require("poste-db.connections")
  local url, url_err = connections.resolve_connection_url(conn)
  if not url then
    vim.notify("Table info: " .. (url_err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  local cmd = { "introspect", "--connection-url", url, "--type", "table_info", "--table", table_node.name }
  if dialect == "postgres" and schema then
    table.insert(cmd, "--schema"); table.insert(cmd, schema)
  end
  if database then
    table.insert(cmd, "--database"); table.insert(cmd, database)
  end

  cli.run_async(cmd, {
    on_stdout = function(data)
      if not data then return end
      while #data > 0 and data[#data] == "" do data[#data] = nil end
      if #data == 0 then return end
      local output = table.concat(data, "\n")
      local ok, parsed = pcall(vim.json.decode, output)
      if not ok or type(parsed) ~= "table" then
        vim.schedule(function()
          vim.notify("Table info: failed to parse response", vim.log.levels.WARN)
        end)
        return
      end
      deep_clean(parsed)
      local items = parsed.items
      if not items or #items == 0 then
        vim.schedule(function()
          vim.notify("Table info: no data returned", vim.log.levels.WARN)
        end)
        return
      end
      local info = items[1]
      local lines = {}
      table.insert(lines, "Table:  " .. (info.table_name or "?"))
      if info.schema_name then
        table.insert(lines, "Schema: " .. info.schema_name)
      end
      if info.engine then
        table.insert(lines, "Engine: " .. info.engine)
      end
      if info.row_count ~= nil or info.row_count_estimate ~= nil then
        local rc = info.row_count or info.row_count_estimate
        table.insert(lines, "Rows:   " .. tostring(rc))
      end
      if info.data_length ~= nil then
        table.insert(lines, "Data:   " .. format_bytes(info.data_length))
      end
      if info.index_length ~= nil then
        table.insert(lines, "Index:  " .. format_bytes(info.index_length))
      end
      if info.data_size then
        table.insert(lines, "Data:   " .. info.data_size)
      end
      if info.index_size then
        table.insert(lines, "Index:  " .. info.index_size)
      end
      if info.total_size then
        table.insert(lines, "Total:  " .. info.total_size)
      end
      if info.create_time then
        table.insert(lines, "Created: " .. info.create_time)
      end
      if info.update_time then
        table.insert(lines, "Updated: " .. info.update_time)
      end
      if info.collation then
        table.insert(lines, "Collation: " .. info.collation)
      end
      if info.auto_increment then
        table.insert(lines, "Auto-inc:  " .. tostring(info.auto_increment))
      end
      if info.comment and info.comment ~= "" then
        table.insert(lines, "Comment: " .. info.comment)
      end
      vim.schedule(function()
        local title = "Table Info: " .. (info.table_name or "?")
        require("poste-db.introspect").show_float(lines, title, "text")
      end)
    end,
    on_stderr = function(data)
      if not data or #data == 0 then return end
      vim.schedule(function()
        vim.notify("Table info: " .. table.concat(data, "\n"), vim.log.levels.WARN)
      end)
    end,
  })
end

return M