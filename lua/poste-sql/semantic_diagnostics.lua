--- Semantic SQL diagnostics — validates table/column references against database schema.
--- Uses Tree-sitter to extract references, then checks against cached schema.
--- Async: kicks off schema fetch when cache is cold.
---
--- Per-statement context resolution: each statement is checked against the
--- database context at its line (-- @database, USE, etc. are position-sensitive).
---
--- Owns its own schema cache (bypasses completion_data key ambiguity).

local context = require("poste-sql.context")
local connections = require("poste-sql.connections")
local state = require("poste.state")

local M = {}

local ns = vim.api.nvim_create_namespace("poste_sql_semantic_diagnostics")
local ns_hl = vim.api.nvim_create_namespace("poste_sql_semantic_highlight")
local _pending_checks = {}
local _updating = false
local _schema_cache = {}

--- Check if Tree-sitter SQL parser is available.
local function check_parser()
  local ok, lang = pcall(vim.treesitter.language.get_lang, "sql")
  return ok and lang ~= nil
end

local function get_parser(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "sql")
  if ok and parser then return parser end
  return nil
end

local function get_statement_nodes(buf)
  local parser = get_parser(buf)
  if not parser then return nil end
  local ok, trees = pcall(parser.parse, parser)
  if not ok or not trees or #trees == 0 then return nil end
  local root = trees[1]:root()
  local stmts = {}
  for child in root:iter_children() do
    local t = child:type()
    if t == "statement" or t == "transaction" then
      stmts[#stmts + 1] = child
    end
  end
  return #stmts > 0 and stmts or nil
end

local function extract_references_from_node(stmt_node, buf)
  local tables = {}
  local columns = {}
  local alias_map = {}
  local from_tables = {}
  local seen_tables = {}
  local seen_cols = {}

  local function get_node_range(node)
    local start_row, start_col, end_row, end_col = node:range()
    return start_row + 1, start_col + 1, end_row + 1, end_col + 1
  end

  --- tree-sitter splits digit-leading identifiers (`123_abc`) into
  --- ERROR[123] + relation/object_reference[_abc]. Rejoin the fragment
  --- when its text is pure digits and it runs directly into the
  --- identifier (byte-contiguous; `234 _tablename` has a space gap and
  --- must stay separate). The merged name is what the user wrote —
  --- digit-leading unquoted identifiers are legal in MySQL/MariaDB.
  --- @param buf number
  --- @param node TSNode  node whose previous sibling may be the digit ERROR
  --- @param tbl_name string
  --- @param id_node TSNode  the identifier node inside the relation
  --- @return string tbl_name, TSNode|nil span_start
  local function merge_digit_fragment(buf, node, tbl_name, id_node)
    local prev = node:prev_sibling()
    if not (prev and prev:type() == "ERROR") then return tbl_name, nil end
    local err_text = vim.treesitter.get_node_text(prev, buf) or ""
    if not err_text:match("^%d+$") then return tbl_name, nil end
    local _, _, per, pec = prev:range()
    local isr, isc = id_node:range()
    if per ~= isr or pec ~= isc then return tbl_name, nil end
    return err_text .. tbl_name, prev
  end

  local function add_table(name, node, db_prefix, start_node)
    name = name:gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
    if name == "" then return end
    local key = name:lower() .. ":" .. node:start() .. ":" .. node:end_()
    if seen_tables[key] then return end
    seen_tables[key] = true
    local start_row, start_col = (start_node or node):range()
    local _, _, end_row, end_col = node:range()
    table.insert(tables, {
      name = name, db_prefix = db_prefix,
      lnum = start_row + 1, col = start_col + 1,
      end_lnum = end_row + 1, end_col = end_col + 1,
    })
  end

  local function add_column(name, tbl, node)
    name = name:gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
    if name == "" then return end
    local key = (tbl or "") .. "." .. name:lower() .. ":" .. node:start() .. ":" .. node:end_()
    if seen_cols[key] then return end
    seen_cols[key] = true
    local lnum, col, end_lnum, end_col = get_node_range(node)
    table.insert(columns, { name = name, table = tbl, lnum = lnum, col = col, end_lnum = end_lnum, end_col = end_col })
  end

  local function walk(node, context_stack)
    context_stack = context_stack or {}
    local nt = node:type()

    if nt == "from" then
      table.insert(context_stack, "from")
      for c in node:iter_children() do walk(c, context_stack) end
      table.remove(context_stack)
      return
    end

    if nt == "join" then
      table.insert(context_stack, "join")
      for c in node:iter_children() do walk(c, context_stack) end
      table.remove(context_stack)
      return
    end

    if nt == "insert" then
      table.insert(context_stack, "insert")
      for c in node:iter_children() do walk(c, context_stack) end
      table.remove(context_stack)
      return
    end

    if nt == "update" then
      table.insert(context_stack, "update")
      for c in node:iter_children() do walk(c, context_stack) end
      table.remove(context_stack)
      return
    end

    if nt == "delete" then
      table.insert(context_stack, "delete")
      for c in node:iter_children() do walk(c, context_stack) end
      table.remove(context_stack)
      return
    end

    if nt == "relation" then
      local tbl_name = nil
      local db_prefix = nil
      local alias = nil
      local tbl_node = nil
      for c in node:iter_children() do
        if c:type() == "object_reference" then
          local children = {}
          for gc in c:iter_children() do
            children[#children + 1] = { type = gc:type(), text = vim.treesitter.get_node_text(gc, buf), node = gc }
          end
          if #children == 3 and children[1].type == "identifier" and children[2].type == "." and children[3].type == "identifier" then
            db_prefix = children[1].text:gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
            if db_prefix == "" then db_prefix = nil end
            tbl_name = children[3].text:gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
            if tbl_name ~= "" then tbl_node = children[3].node else tbl_name = nil end
          elseif #children == 1 and children[1].type == "identifier" then
            tbl_name = children[1].text:gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
            if tbl_name ~= "" then tbl_node = children[1].node else tbl_name = nil end
          else
            tbl_name = vim.treesitter.get_node_text(c, buf):gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
            if tbl_name ~= "" then tbl_node = c else tbl_name = nil end
          end
        elseif c:type() == "identifier" and tbl_name then
          alias = vim.treesitter.get_node_text(c, buf):gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
          if alias == "" then alias = nil end
        end
      end
      if tbl_name and tbl_node then
        local merged_name, span_start = merge_digit_fragment(buf, node, tbl_name, tbl_node)
        tbl_name = merged_name
        local is_from_or_join = false
        for _, ctx in ipairs(context_stack) do
          if ctx == "from" or ctx == "join" or ctx == "update" or ctx == "delete" or ctx == "insert" then
            is_from_or_join = true
            break
          end
        end
        if is_from_or_join then
          add_table(tbl_name, tbl_node, db_prefix, span_start)
          table.insert(from_tables, tbl_name)
          if alias then alias_map[alias] = tbl_name end
        end
      end
      return
    end

    if nt == "object_reference" then
      local is_in_insert = false
      for _, ctx in ipairs(context_stack) do
        if ctx == "insert" then is_in_insert = true; break end
      end
      if is_in_insert then
        local parent = node:parent()
        if parent and parent:type() == "invocation" then return end
        local children = {}
        for gc in node:iter_children() do
          children[#children + 1] = { type = gc:type(), text = vim.treesitter.get_node_text(gc, buf), node = gc }
        end
        if #children == 3 and children[1].type == "identifier" and children[2].type == "." and children[3].type == "identifier" then
          local db = children[1].text:gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
          if db == "" then db = nil end
          local tn = children[3].text:gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
          if tn ~= "" then
            add_table(tn, children[3].node, db)
            table.insert(from_tables, tn)
          end
        elseif #children == 1 and children[1].type == "identifier" then
          local tn = children[1].text:gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
          if tn ~= "" then
            local merged_tn, span_start = merge_digit_fragment(buf, node, tn, children[1].node)
            add_table(merged_tn, children[1].node, nil, span_start)
            table.insert(from_tables, merged_tn)
          end
        else
          local tn = vim.treesitter.get_node_text(node, buf):gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
          if tn ~= "" then
            add_table(tn, node)
            table.insert(from_tables, tn)
          end
        end
        return
      end
    end

    if nt == "field" then
      local parts = {}
      for c in node:iter_children() do
        parts[#parts + 1] = { type = c:type(), text = vim.treesitter.get_node_text(c, buf), node = c }
      end
      if #parts == 3 and parts[1].type == "object_reference" and parts[2].type == "." and parts[3].type == "identifier" then
        local qualifier = parts[1].text:gsub("^[`\"'\\[]+", ""):gsub("[]`\"'\\]+$", "")
        local col_name = parts[3].text
        local actual_table = alias_map[qualifier] or qualifier
        add_column(col_name, actual_table, parts[3].node)
      elseif #parts == 1 and parts[1].type == "identifier" then
        local col_name = parts[1].text
        if col_name ~= "*" and not col_name:match("^@") then
          add_column(col_name, nil, parts[1].node)
        end
      end
      return
    end

    if nt == "column" then
      for c in node:iter_children() do
        if c:type() == "identifier" then
          local col_name = vim.treesitter.get_node_text(c, buf)
          if not col_name:match("^@") then
            add_column(col_name, nil, c)
          end
        end
      end
      return
    end

    for c in node:iter_children() do
      walk(c, context_stack)
    end
  end

  walk(stmt_node)
  return { tables = tables, columns = columns, alias_map = alias_map, from_tables = from_tables }
end

--- Resolve connection URL from a connection name.
local function resolve_conn_url(conn)
  if not conn or conn == "" then return nil end
  local lower = conn:lower()
  if lower:match("^sqlite:")
    or lower:match("^postgres://")
    or lower:match("^postgresql://")
    or lower:match("^mysql://")
    or lower:match("^mariadb://")
  then
    return conn
  end
  local url, _ = connections.resolve_connection_url(conn)
  return url
end

--- Build schema lookup from cached data.
local function build_schema(tables, columns, db)
  local known = {}
  for _, t in ipairs(tables or {}) do known[t:lower()] = true end
  local col_lookup = {}
  for tbl, cols in pairs(columns or {}) do
    col_lookup[tbl] = {}
    for _, c in ipairs(cols or {}) do col_lookup[tbl][c:lower()] = true end
  end
  return { known_tables = known, columns = col_lookup, db = db }
end

--- Fetch tables for a database and cache them.
--- Calls the Rust CLI directly. Stores in _schema_cache with key conn.."/"..db.
--- Calls callback(true) on success, callback(false) on failure.
local function fetch_tables(buf, conn, db, callback)
  local binary = state.find_poste_binary()
  if not binary then callback(false); return end

  local url = resolve_conn_url(conn)
  if not url then callback(false); return end

  local cache_key = conn .. "/" .. db
  local args = { binary, "introspect", "--connection-url", url,
    "--type", "tables", "--database", db }

  vim.fn.jobstart(args, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then return end
      while #data > 0 and data[#data] == "" do data[#data] = nil end
      if #data == 0 then return end
      local ok, parsed = pcall(vim.json.decode, table.concat(data, "\n"))
      if ok and parsed and parsed.items then
        _schema_cache[cache_key] = _schema_cache[cache_key] or { tables = {}, columns = {} }
        _schema_cache[cache_key].tables = vim.tbl_map(function(i) return i.name end, parsed.items)
        vim.schedule(function() callback(true) end)
      else
        vim.schedule(function() callback(false) end)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function() callback(false) end)
      end
    end,
  })
end

--- Fetch columns for a table and cache them.
--- Stores in _schema_cache with key conn.."/"..db.
local function fetch_columns(buf, conn, db, tbl, callback)
  local binary = state.find_poste_binary()
  if not binary then callback(false); return end

  local url = resolve_conn_url(conn)
  if not url then callback(false); return end

  local cache_key = conn .. "/" .. db
  local args = { binary, "introspect", "--connection-url", url,
    "--type", "columns", "--table", tbl, "--database", db }

  vim.fn.jobstart(args, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then return end
      while #data > 0 and data[#data] == "" do data[#data] = nil end
      if #data == 0 then return end
      local ok, parsed = pcall(vim.json.decode, table.concat(data, "\n"))
      if ok and parsed and parsed.items then
        _schema_cache[cache_key] = _schema_cache[cache_key] or { tables = {}, columns = {} }
        _schema_cache[cache_key].columns[tbl] = vim.tbl_map(function(i) return i.name end, parsed.items)
        vim.schedule(function() callback(true) end)
      else
        vim.schedule(function() callback(false) end)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function() callback(false) end)
      end
    end,
  })
end

function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.diagnostic.reset(ns, buf)
    vim.api.nvim_buf_clear_namespace(buf, ns_hl, 0, -1)
  end
  _pending_checks[buf] = nil
end

function M.update(buf)
  if _updating then return end
  _updating = true

  local ok, err = pcall(function()
    if not vim.api.nvim_buf_is_valid(buf) then _updating = false; return end
    local ft = vim.bo[buf].filetype
    if ft ~= "poste_sql" and ft ~= "poste_sqlite" and ft ~= "sql" then _updating = false; return end
    if not check_parser() then _updating = false; return end

    local default_ctx = context.resolve_full_context(buf, vim.api.nvim_buf_line_count(buf))
    if not default_ctx.connection then _updating = false; return end

    local stmt_nodes = get_statement_nodes(buf)
    if not stmt_nodes then
      vim.diagnostic.reset(ns, buf)
      vim.api.nvim_buf_clear_namespace(buf, ns_hl, 0, -1)
      _updating = false
      return
    end

    local diags = {}
    local pending_column_fetches = {}
    local last_conn, last_db = nil, nil
    local schema = nil

    for _, stmt_node in ipairs(stmt_nodes) do
      local stmt_line = stmt_node:start() + 1

      local ctx = context.resolve_full_context(buf, stmt_line)
      local conn = ctx.connection or default_ctx.connection
      local db = ctx.database or default_ctx.database
      if not conn or not db then goto continue end

      if conn ~= last_conn or db ~= last_db then
        local cache_key = conn .. "/" .. db
        local cached = _schema_cache[cache_key]

        if cached and cached.tables and #cached.tables > 0 then
          schema = build_schema(cached.tables, cached.columns or {}, db)
        else
          schema = nil
          if not _pending_checks[buf] then
            _pending_checks[buf] = true
            fetch_tables(buf, conn, db, function(success)
              _pending_checks[buf] = nil
              if success and vim.api.nvim_buf_is_valid(buf) then
                vim.schedule(function()
                  M.update(buf)
                end)
              end
            end)
          end
        end
        last_conn, last_db = conn, db
      end

      if not schema then goto continue end

      local refs = extract_references_from_node(stmt_node, buf)
      if #refs.tables == 0 and #refs.columns == 0 then goto continue end

      for _, tbl in ipairs(refs.tables) do
        local target_db = tbl.db_prefix or schema.db
        local target_schema = schema
        if tbl.db_prefix and tbl.db_prefix ~= schema.db then
          local cache_key = conn .. "/" .. tbl.db_prefix
          local cached = _schema_cache[cache_key]
          if cached and cached.tables and #cached.tables > 0 then
            target_schema = build_schema(cached.tables, cached.columns or {}, tbl.db_prefix)
          end
        end
        if target_schema and not target_schema.known_tables[tbl.name:lower()] then
          table.insert(diags, {
            lnum = tbl.lnum - 1,
            col = tbl.col - 1,
            end_lnum = tbl.end_lnum - 1,
            end_col = tbl.end_col - 1,
            severity = vim.diagnostic.severity.WARN,
            source = "poste-sql",
            message = string.format("Table '%s' not found in database '%s'", tbl.name, target_db),
          })
        end
      end

      for _, col in ipairs(refs.columns) do
        if col.table then
          if schema.known_tables[col.table:lower()] then
            local cols = schema.columns[col.table]
            if cols then
              if not cols[col.name:lower()] then
                table.insert(diags, {
                  lnum = col.lnum - 1,
                  col = col.col - 1,
                  end_lnum = col.end_lnum - 1,
                  end_col = col.end_col - 1,
                  severity = vim.diagnostic.severity.WARN,
                  source = "poste-sql",
                  message = string.format("Column '%s' not found in table '%s'", col.name, col.table),
                })
              end
            else
              pending_column_fetches[col.table] = { conn = conn, db = db }
            end
          end
        elseif #refs.from_tables == 1 then
          local ptable = refs.from_tables[1]
          if schema.known_tables[ptable:lower()] then
            local cols = schema.columns[ptable]
            if cols then
              if not cols[col.name:lower()] then
                table.insert(diags, {
                  lnum = col.lnum - 1,
                  col = col.col - 1,
                  end_lnum = col.end_lnum - 1,
                  end_col = col.end_col - 1,
                  severity = vim.diagnostic.severity.WARN,
                  source = "poste-sql",
                  message = string.format("Column '%s' not found in table '%s'", col.name, ptable),
                })
              end
            else
              pending_column_fetches[ptable] = { conn = conn, db = db }
            end
          end
        end
      end

      ::continue::
    end

    vim.diagnostic.set(ns, buf, diags, { priority = 200 })
    vim.api.nvim_buf_clear_namespace(buf, ns_hl, 0, -1)
    for _, d in ipairs(diags) do
      vim.api.nvim_buf_set_extmark(buf, ns_hl, d.lnum, d.col, {
        end_row = d.end_lnum,
        end_col = d.end_col,
        hl_group = "DiagnosticWarn",
        hl_mode = "combine",
        priority = 200,
      })
    end

    for tbl_name, ctx_info in pairs(pending_column_fetches) do
      if _pending_checks[buf] then _updating = false; return end
      _pending_checks[buf] = true
      fetch_columns(buf, ctx_info.conn, ctx_info.db, tbl_name, function(success)
        _pending_checks[buf] = nil
        if success and vim.api.nvim_buf_is_valid(buf) then
          vim.schedule(function()
            M.update(buf)
          end)
        end
      end)
    end
    _updating = false
  end)

  if not ok then
    _updating = false
    state.log("ERROR", "semantic_diagnostics: " .. tostring(err))
  end
end

M._test = {
  extract_references_from_node = extract_references_from_node,
}

return M