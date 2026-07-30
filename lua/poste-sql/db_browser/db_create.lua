local state = require("poste.state")
local cli = require("poste.cli")
local forms_advanced = require("poste-sql.db_browser.forms_advanced")
local tree = require("poste-sql.db_browser.tree")
local async = require("poste-sql.db_browser.async")

local M = {}

local function postgres_create_database(fields)
  local parts = { "CREATE DATABASE" }
  table.insert(parts, '"' .. fields.name .. '"')
  if fields.owner and fields.owner ~= "" then
    table.insert(parts, 'OWNER "' .. fields.owner .. '"')
  end
  return table.concat(parts, " ") .. ";"
end

local function mysql_create_database(fields)
  local parts = { "CREATE DATABASE", "IF NOT EXISTS" }
  table.insert(parts, "`" .. fields.name .. "`")
  if fields.charset and fields.charset ~= "" then
    table.insert(parts, "CHARACTER SET " .. fields.charset)
  end
  if fields.collation and fields.collation ~= "" then
    table.insert(parts, "COLLATE " .. fields.collation)
  end
  return table.concat(parts, " ") .. ";"
end

local function get_dialect(node, context)
  if node.meta and node.meta.dialect then return node.meta.dialect end
  local conn_name = node.meta and node.meta.connection or state.sql.db_browser.connection
  for _, root in ipairs(context.root_nodes) do
    if root.name == conn_name then
      return root.meta and root.meta.dialect or "postgres"
    end
  end
  return "postgres"
end

local function get_connection_name(node, context)
  if node.node_type == "connection" then return node.name end
  return node.meta and node.meta.connection or state.sql.db_browser.connection
end

local function fetch_roles(url)
  local tmpfile = vim.fn.tempname() .. ".sql"
  local result = cli.run({
    "run", "--stdin", "--line", "1", "--json", tmpfile,
    "--connection-url", url,
  }, {
    stdin = "SELECT rolname FROM pg_roles ORDER BY rolname",
  })
  if not result then return nil end
  local ok, data = pcall(vim.json.decode, result)
  if not ok then return nil end
  local ok2, body = pcall(vim.json.decode, data.body or "{}")
  if not ok2 then return nil end
  local roles = {}
  if body.results then
    for _, res in ipairs(body.results) do
      if res.rows then
        for _, row in ipairs(res.rows) do
          table.insert(roles, row[1])
        end
      end
    end
  end
  return #roles > 0 and roles or nil
end

local function build_sections(dialect, roles)
  local fields = {
    { key = "name", label = "Name", kind = "text", value = "" },
  }

  if dialect == "mysql" then
    local charset_choices = { "utf8", "utf8mb4", "latin1", "ascii", "utf16" }
    local collation_choices = {
      "utf8_general_ci", "utf8_unicode_ci", "utf8mb4_general_ci",
      "utf8mb4_unicode_ci", "latin1_swedish_ci", "ascii_general_ci",
    }
    table.insert(fields, { key = "charset", label = "Character Set", kind = "select", value = "", choices = charset_choices, dialect = "mysql" })
    table.insert(fields, { key = "collation", label = "Collation", kind = "select", value = "", choices = collation_choices, dialect = "mysql" })
  end

  if dialect == "postgres" then
    table.insert(fields, { key = "owner", label = "Owner", kind = "select", value = "", choices = roles or {}, dialect = "postgres" })
  end

  local sections = {
    {
      title = "Database Info",
      fields = fields,
    },
    {
      title = "SQL Preview",
      fields = {
        { key = "_preview", label = "Preview", kind = "preview", value = "" },
      },
    },
  }

  return sections
end

local function generate_sql(fields, dialect)
  if not fields.name or fields.name == "" then
    return { "--- Enter a database name ---" }
  end
  if dialect == "mysql" then
    return { mysql_create_database(fields) }
  end
  return { postgres_create_database(fields) }
end

local refresh_target

local function execute_sql(sql, conn_name, context, opts)
  vim.notify("Creating database...", vim.log.levels.INFO)

  local connections = require("poste-sql.connections")
  local url, err = connections.resolve_connection_url(conn_name)
  if not url then
    vim.notify("Database create failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return
  end

  local binary = cli.binary()
  if not binary then
    vim.notify("Poste binary not found", vim.log.levels.ERROR)
    return
  end

  local file_path = vim.fn.tempname() .. ".sql"
  local cmd = {
    binary, "run", "--stdin", "--line", "1", "--json", file_path,
    "--connection-url", url,
  }

  local stderr_buf = {}
  local stdio_done = false
  local job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data or #data == 0 then return end
      stdio_done = true
      local output = table.concat(data, "\n")
      vim.schedule(function()
        local ok, resp = pcall(vim.json.decode, output)
        if not ok or not resp then
          local stderr = table.concat(stderr_buf, "\n")
          vim.notify("Database create: failed to parse response\n" .. stderr:sub(1, 300),
            vim.log.levels.ERROR)
          return
        end
        local ok2, body = pcall(vim.json.decode, resp.body or "{}")
        if not ok2 or type(body) ~= "table" then
          body = {}
        end
        local errors = {}
        if body.results then
          for _, result in ipairs(body.results) do
            if result.error and result.error ~= "" then
              table.insert(errors, result.error)
            end
          end
        end
        if body.has_error or #errors > 0 then
          local msg = table.concat(errors, "\n")
          if msg == "" then msg = "Unknown SQL error" end
          vim.notify("Database create failed:\n" .. msg, vim.log.levels.ERROR)
        else
          vim.notify("Database created successfully", vim.log.levels.INFO)
        end
        refresh_target(opts and opts.target_node or nil, context)
      end)
    end,
    on_stderr = function(_, data)
      if data then
        for _, l in ipairs(data) do
          if l ~= "" then table.insert(stderr_buf, l) end
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 and not stdio_done then
        vim.schedule(function()
          vim.notify("Database creation failed: " .. table.concat(stderr_buf, "\n"),
            vim.log.levels.ERROR)
        end)
      end
    end,
  })

  if job_id > 0 then
    local full_sql = "-- @connection " .. url .. "\n" .. sql
    vim.fn.chansend(job_id, full_sql)
    vim.fn.chanclose(job_id, "stdin")
  else
    vim.schedule(function()
      vim.notify("Database create: failed to start poste process", vim.log.levels.ERROR)
    end)
  end
end

refresh_target = function(target_node, context)
  local parent = target_node
  while parent and parent.node_type ~= "connection" do
    parent = parent.parent
  end
  if not parent then return end

  parent.children = nil
  parent.expanded = false
  parent.loading = true

  local nm = tree.render_tree(context.browser_buf, context.line_to_node,
    context.root_nodes, context.conn_label)
  for i, n in ipairs(nm) do context.line_to_node[i] = n end

  local search_dir = vim.fn.getcwd()
  async.fetch_children(parent, function()
    parent.expanded = true
    vim.schedule(function()
      local nm2 = tree.render_tree(context.browser_buf, context.line_to_node,
        context.root_nodes, context.conn_label)
      for i, n in ipairs(nm2) do context.line_to_node[i] = n end
    end)
  end, search_dir)
end

function M.open(node, context)
  local dialect = get_dialect(node, context)

  if dialect == "sqlite" then
    vim.notify("SQLite does not support CREATE DATABASE", vim.log.levels.INFO)
    return
  end

  local conn = get_connection_name(node, context)
  local roles = nil
  if dialect == "postgres" then
    local connections = require("poste-sql.connections")
    local url, _ = connections.resolve_connection_url(conn)
    if url then
      roles = fetch_roles(url)
    end
  end
  local sections = build_sections(dialect, roles)
  forms_advanced.open({
    title = "Create Database in " .. conn,
    dialect = dialect,
    sections = sections,
    on_change = function(fields) return generate_sql(fields, dialect) end,
    on_validate = function(fields)
      if not fields.name or fields.name == "" then
        return "Database name is required", "name"
      end
      return nil
    end,
    on_submit = function(fields, sql)
      execute_sql(sql, conn, context, { target_node = node })
    end,
    window_management = "single",
  })
end

return M
