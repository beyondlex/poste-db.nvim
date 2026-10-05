local forms_advanced = require("poste-db.db_browser.forms_advanced")
local ident = require("poste-db.ident")
local util = require("poste-db.db_browser.util")
local notify = require("poste-db.db_browser.notify")

local M = {}

-- Identifier quoting goes through ident.quote: hand-built `"`/`` ` `` wrappers
-- never escape a quote inside the name, so a database called `a"b` produced
-- broken (and injectable) DDL.
local function postgres_create_database(fields, dialect)
  local parts = { "CREATE DATABASE" }
  table.insert(parts, ident.quote(fields.name, dialect))
  if fields.owner and fields.owner ~= "" then
    table.insert(parts, 'OWNER ' .. ident.quote(fields.owner, dialect))
  end
  return table.concat(parts, " ") .. ";"
end

local function mysql_create_database(fields, dialect)
  local parts = { "CREATE DATABASE", "IF NOT EXISTS" }
  table.insert(parts, ident.quote(fields.name, dialect))
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

--- Roles from a legacy-shaped exec response (`results[].rows`, first column).
--- The response already carries decoded results — re-decoding `resp.body` here
--- only duplicated the parse. nil (keep the Owner select empty) unless at least
--- one role came back.
local function extract_roles(resp)
  local roles = {}
  for _, res in ipairs(resp and resp.results or {}) do
    for _, row in ipairs(res.rows or {}) do
      -- vim.NIL is not nil, so a null rolname must be named out or it lands
      -- in the picker as the literal text "vim.NIL".
      if row[1] ~= nil and row[1] ~= vim.NIL then table.insert(roles, tostring(row[1])) end
    end
  end
  return #roles > 0 and roles or nil
end

local function build_sections(dialect)
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
    -- Choices start empty: the role list needs a server round-trip, and
    -- waiting for it inline froze the whole UI for up to the exec timeout
    -- (a VPN or a hung server). The form_handle.set_choices below fills
    -- this field when the async query answers.
    table.insert(fields, { key = "owner", label = "Owner", kind = "select", value = "", choices = {}, dialect = "postgres" })
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
    return { mysql_create_database(fields, dialect) }
  end
  return { postgres_create_database(fields, dialect) }
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

--- Fire the role-list query for the Owner select without blocking the UI. The
--- form is already open when this runs; a failed or empty answer just leaves
--- the select empty (parity with the old synchronous fetch's nil), and a
--- response after the user closed the form is a no-op through the handle.
local function populate_roles_async(form_handle, url)
  local exec_run = require("poste-db.exec_run")
  exec_run.run_async("SELECT rolname FROM pg_roles ORDER BY rolname", {
    conn_url = url,
    mode = "greedy",
    log_source = "browser",
  }, {
    on_response = function(resp)
      if form_handle.is_closed() then return end
      local roles = extract_roles(resp)
      if roles then form_handle.set_choices("owner", roles) end
    end,
  })
end

function M.open(node, context)
  local dialect = get_dialect(node, context)

  if dialect == "sqlite" then
    notify.info("SQLite does not support CREATE DATABASE")
    return
  end

  local conn = get_connection_name(node, context)
  local form_handle = forms_advanced.open({
    title = "Create Database in " .. conn,
    dialect = dialect,
    sections = build_sections(dialect),
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

  if dialect == "postgres" then
    local connections = require("poste-db.connections")
    local url, _ = connections.resolve_connection_url(conn)
    if url then
      populate_roles_async(form_handle, url)
    end
  end
end

--- Exposed for tests.
M._test = { generate_sql = generate_sql }

return M
