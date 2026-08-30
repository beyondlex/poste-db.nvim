local forms_advanced = require("poste-db.db_browser.forms_advanced")
local ident = require("poste-db.ident")
local util = require("poste-db.db_browser.util")
local notify = require("poste-db.db_browser.notify")

local M = {}

local function postgres_create_schema(fields)
  local parts = { "CREATE SCHEMA", "IF NOT EXISTS" }
  table.insert(parts, ident.quote(fields.name, "postgres"))
  if fields.owner and fields.owner ~= "" then
    table.insert(parts, "AUTHORIZATION " .. ident.quote(fields.owner, "postgres"))
  end
  return table.concat(parts, " ") .. ";"
end

local function gen_grant(grant, dialect)
  local schema_name = grant._schema_name or ""
  local parts = { "GRANT" }
  local privs = grant.privileges or {}
  if #privs > 0 then
    table.insert(parts, table.concat(privs, ", "))
  else
    table.insert(parts, "ALL")
  end
  local on_object = grant.on_object or "SCHEMA"
  table.insert(parts, "ON")
  table.insert(parts, on_object)
  if on_object ~= "SCHEMA" and schema_name ~= "" then
    table.insert(parts, "IN SCHEMA " .. ident.quote(schema_name, dialect))
  end
  table.insert(parts, "TO " .. ident.quote(grant.grantee, dialect))
  if grant.with_grant_option then
    table.insert(parts, "WITH GRANT OPTION")
  end
  return table.concat(parts, " ") .. ";"
end

local function gen_grant_usage(grant)
  local schema_name = grant._schema_name or ""
  return "GRANT USAGE ON SCHEMA " .. ident.quote(schema_name, "postgres") .. " TO " .. ident.quote(grant.grantee, "postgres") .. ";"
end

local function get_dialect(node, context)
  return util.get_dialect(node, context and context.root_nodes or {})
end

local function get_connection_name(node, context)
  return util.get_connection(node)
end

local function build_sections(dialect, db_name)
  local schema_info_fields = {
    { key = "name", label = "Name", kind = "text", value = "" },
    { key = "owner", label = "Owner", kind = "text", value = "", dialect = "postgres" },
    
  }

  local grant_privileges = { "SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "USAGE" }
  local grant_on_objects = {
    "ALL TABLES IN SCHEMA", "ALL SEQUENCES IN SCHEMA",
    "ALL FUNCTIONS IN SCHEMA", "SCHEMA",
  }
  local grant_types = { "grant", "grant_usage" }

  local grant_sub_fields = {
    { key = "type", label = "Type", kind = "select", value = "grant", choices = grant_types },
    { key = "grantee", label = "Grantee", kind = "text", value = "" },
    { key = "privileges", label = "Privileges", kind = "multi_select", value = { "SELECT" }, choices = grant_privileges, dialect = "postgres" },
    { key = "on_object", label = "On Object", kind = "select", value = "ALL TABLES IN SCHEMA", choices = grant_on_objects, dialect = "postgres" },
    { key = "with_grant_option", label = "Grant Option", kind = "bool", value = false, dialect = "postgres" },
  }

  local sections = {
    {
      title = "Schema Info",
      fields = schema_info_fields,
    },
    {
      title = "Grants",
      fields = {
        {
          key = "grants",
          label = "Grants",
          kind = "list",
          value = {},
          sub_fields = grant_sub_fields,
        },
      },
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
    return { "--- Enter a schema name ---" }
  end

  local lines = {}
  table.insert(lines, postgres_create_schema(fields))

  local grants = fields.grants or {}
  for _, grant in ipairs(grants) do
    grant._schema_name = fields.name
    if grant.type == "grant" then
      table.insert(lines, gen_grant(grant, dialect))
    elseif grant.type == "grant_usage" then
      table.insert(lines, gen_grant_usage(grant))
    end
  end

  return lines
end

local function execute_sql(sql, conn_name, context, opts)
  util.run_ddl_and_refresh(sql, conn_name, context, {
    pending_msg = "Creating schema...",
    success_msg = "Schema created successfully",
    fail_prefix = "Schema create",
    database = opts and opts.database or nil,
    target_node = opts and opts.target_node or nil,
    node_type = "database",
  })
end

function M.open(node, context)
  local dialect = get_dialect(node, context)

  if dialect ~= "postgres" then
    notify.info("CREATE SCHEMA is only supported for PostgreSQL")
    return
  end

  local conn = get_connection_name(node, context)
  local db_name = node.name
  local sections = build_sections(dialect, db_name)
  forms_advanced.open({
    title = "Create Schema in " .. db_name,
    dialect = dialect,
    sections = sections,
    on_change = function(fields) return generate_sql(fields, dialect) end,
    on_validate = function(fields)
      if not fields.name or fields.name == "" then
        return "Schema name is required", "name"
      end
      return nil
    end,
    on_submit = function(fields, sql)
      execute_sql(sql, conn, context, { database = db_name, target_node = node })
    end,
    window_management = "single",
  })
end

return M
