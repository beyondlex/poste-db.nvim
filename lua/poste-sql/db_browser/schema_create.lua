local forms_advanced = require("poste-sql.db_browser.forms_advanced")
local tree = require("poste-sql.db_browser.tree")
local async = require("poste-sql.db_browser.async")
local ident = require("poste-sql.ident")
local util = require("poste-sql.db_browser.util")

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

local refresh_database

local function execute_sql(sql, conn_name, context, opts)
  vim.notify("Creating schema...", vim.log.levels.INFO)

  local connections = require("poste-sql.connections")
  local url, err = connections.resolve_connection_url(conn_name)
  if not url then
    vim.notify("Schema create failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return
  end

  local exec_run = require("poste-sql.exec_run")
  local job_id = exec_run.run_async(sql, {
    conn_url = url,
    database = opts and opts.database or nil,
    mode = "greedy",
  }, {
    on_response = function(resp)
      local ok_body, body = pcall(vim.json.decode, resp.body or "{}")
      if not ok_body or type(body) ~= "table" then
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
      if resp.has_error or body.has_error or #errors > 0 then
        local msg = table.concat(errors, "\n")
        if msg == "" then msg = "Unknown SQL error" end
        vim.notify("Schema create failed:\n" .. msg, vim.log.levels.ERROR)
      else
        vim.notify("Schema created successfully", vim.log.levels.INFO)
      end
      refresh_database(opts and opts.target_node, context)
    end,
    on_error = function(message)
      vim.notify("Schema creation failed: " .. message, vim.log.levels.ERROR)
    end,
  })

  if not job_id or job_id <= 0 then
    vim.notify("Schema create: failed to start poste process", vim.log.levels.ERROR)
  end
end

refresh_database = function(target_node, context)
  local parent = target_node
  while parent and parent.node_type ~= "database" do
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

  if dialect ~= "postgres" then
    vim.notify("CREATE SCHEMA is only supported for PostgreSQL", vim.log.levels.INFO)
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
