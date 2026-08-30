local forms_advanced = require("poste-db.db_browser.forms_advanced")
local util = require("poste-db.db_browser.util")
local notify = require("poste-db.db_browser.notify")

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
  return util.get_dialect(node, context and context.root_nodes or {})
end

local function get_connection_name(node, context)
  return util.get_connection(node)
end

local function fetch_roles(url)
  local exec_run = require("poste-db.exec_run")
  local resp = exec_run.run_sql("SELECT rolname FROM pg_roles ORDER BY rolname", {
    conn_url = url,
    mode = "greedy",
  })
  if not resp then return nil end
  local ok, data = pcall(vim.json.decode, resp.body or "{}")
  if not ok then return nil end
  local body = data
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

  if dialect == "mysql" or dialect == "mariadb" then
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
  if dialect == "mysql" or dialect == "mariadb" then
    return { mysql_create_database(fields) }
  end
  return { postgres_create_database(fields) }
end

local function execute_sql(sql, conn_name, context, opts)
  util.run_ddl_and_refresh(sql, conn_name, context, {
    pending_msg = "Creating database...",
    success_msg = "Database created successfully",
    fail_prefix = "Database create",
    target_node = opts and opts.target_node or nil,
    node_type = "connection",
  })
end

function M.open(node, context)
  local dialect = get_dialect(node, context)

  if dialect == "sqlite" then
    notify.info("SQLite does not support CREATE DATABASE")
    return
  end

  local conn = get_connection_name(node, context)
  local roles = nil
  if dialect == "postgres" then
    local connections = require("poste-db.connections")
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
