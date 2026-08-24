--- SQL connection management UI.
--- Provides :PosteDbConnection command to list, select, and test connections.
local cli = require("poste.cli")
local state = require("poste.state")
local util = require("poste.util")
local select_mod = require("poste.select")
local const = require("poste-db.constants")

local M = {}

-----------------------------------------------------------------------
-- Get search directory for connections.toml
-----------------------------------------------------------------------
local function get_search_dir()
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name ~= "" then
    return vim.fn.fnamemodify(buf_name, ":h")
  end
  return vim.fn.getcwd()
end

-----------------------------------------------------------------------
-- Config file discovery
-----------------------------------------------------------------------

local _config_search_cache = {}
local _config_search_cache_mtime = {}

--- Walk up from `search_dir` to find connections.toml.
--- Caches results to avoid directory traversal on every cursor move.
--- Invalidated when the found file's mtime changes.
--- @param search_dir string Directory to start from
--- @return string|nil Path to connections.toml
function M.find_connections_toml(search_dir)
  if _config_search_cache[search_dir] ~= nil then
    local cached = _config_search_cache[search_dir]
    if cached == false then return nil end
    local mtime = vim.fn.getftime(cached)
    if _config_search_cache_mtime[search_dir] == mtime then
      return cached
    end
  end
  local result = util.find_file_upwards("connections.toml", search_dir)
  _config_search_cache[search_dir] = result or false
  _config_search_cache_mtime[search_dir] = result and vim.fn.getftime(result) or nil
  return result
end

local _config_cache = nil
local _config_cache_path = nil
local _config_cache_mtime = nil

-----------------------------------------------------------------------
-- Environment variable resolution (dotenv + env.json + OS env)
-----------------------------------------------------------------------

local _dotenv_cache = {}
local _dotenv_cache_mtime = {}

--- Parse dotenv content: `KEY=VALUE` lines, optional `export` prefix,
--- `#` comments, and single/double quoted values. Also resolves `{{VAR}}`
--- references within values.
--- @param content string
--- @param vars table<string,string> existing vars for recursive substitution
--- @return table<string,string>
local function parse_dotenv(content, vars)
  vars = vars or {}
  for line in content:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      local key, value = trimmed:match("^export%s+([%w_.]+)%s*=%s*(.-)%s*$")
      if not key then
        key, value = trimmed:match("^([%w_.]+)%s*=%s*(.-)%s*$")
      end
      if key then
        value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
        vars[key] = value
      end
    end
  end
  for k, v in pairs(vars) do
    vars[k] = M.substitute_vars(v, vars)
  end
  return vars
end

--- Find and parse `.env` walking up from `search_dir` (same discovery as
--- connections.toml). Cached per search_dir with mtime invalidation.
--- @param search_dir string
--- @return table<string,string>
local function load_dotenv(search_dir)
  local path = util.find_file_upwards(".env", search_dir)
  local mtime = path and vim.fn.getftime(path) or nil
  if _dotenv_cache[search_dir] ~= nil and _dotenv_cache_mtime[search_dir] == mtime then
    return _dotenv_cache[search_dir]
  end
  local vars = {}
  if path then
    local ok, data = pcall(vim.fn.readfile, path)
    if ok and data then
      vars = parse_dotenv(table.concat(data, "\n"), vars)
    end
  end
  _dotenv_cache[search_dir] = vars
  _dotenv_cache_mtime[search_dir] = mtime
  return vars
end

--- Load `env.json` vars for the current environment (matches the Rust
--- binary's `--env` flow: `{ "dev": { ... }, "prod": { ... } }`).
--- @param search_dir string
--- @return table<string,string>
local function load_env_json_vars(search_dir)
  local path = util.find_file_upwards("env.json", search_dir)
  if not path then return {} end
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data then return {} end
  local ok2, parsed = pcall(vim.json.decode, table.concat(data, "\n"))
  if not ok2 or type(parsed) ~= "table" then return {} end
  local envs = parsed.envs or parsed
  local vars = envs[state.current_env or "dev"]
  if type(vars) ~= "table" then return {} end
  local result = {}
  for k, v in pairs(vars) do result[k] = v end
  return result
end

--- Merge all environment sources.
--- Precedence (highest wins): OS environment > `.env` > `env.json`.
--- @param search_dir string
--- @return table<string,string>
function M.get_env_vars(search_dir)
  local vars = {}
  for k, v in pairs(load_env_json_vars(search_dir)) do vars[k] = v end
  for k, v in pairs(load_dotenv(search_dir)) do vars[k] = v end
  -- `vim.fn.environ()` enumerates real OS vars; `pairs(vim.env)` does not.
  for k, v in pairs(vim.fn.environ()) do vars[k] = v end
  return vars
end

--- Substitute `{{VAR}}` references in a string. Unknown references are
--- kept literal, matching Rust's `substitute_vars` behavior.
--- Recursively resolves values that contain further `{{VAR}}` references
--- (up to a max depth to prevent infinite loops).
--- @param s any
--- @param vars table<string,string>
--- @return any
function M.substitute_vars(s, vars, depth)
  if type(s) ~= "string" or not s:find("{{", 1, true) then
    return s
  end
  depth = depth or 0
  if depth >= 10 then return s end
  local result = (s:gsub("{{([%w_.]+)}}", function(name)
    return vars[name] or "{{" .. name .. "}}"
  end))
  if result:find("{{", 1, true) then
    return M.substitute_vars(result, vars, depth + 1)
  end
  return result
end

--- Copy a connection config with `{{VAR}}` references resolved.
--- @param conn table Connection config (raw values)
--- @param vars table<string,string>
--- @return table Resolved connection config
local function apply_env(conn, vars)
  local resolved = {}
  for k, v in pairs(conn) do
    resolved[k] = M.substitute_vars(v, vars)
  end
  return resolved
end

--- Percent-encode a component for URL building.
--- Encodes every byte outside the RFC 3986 unreserved set.
--- @param s any
--- @return any
local function percent_encode(s)
  if type(s) ~= "string" or s == "" then return s end
  return (s:gsub("[^%w%.%-%_%~]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

--- Get the config for a named connection by reading connections.toml directly.
--- Returns values with `{{var}}` references resolved from .env / env.json / OS env.
--- Caches parsed config to avoid file I/O on every cursor move.
--- @param name string Connection name
--- @return table|nil Connection config or nil
function M.get_connection_config(name)
  local search_dir = get_search_dir()
  local config_path = M.find_connections_toml(search_dir)
  if not config_path then
    _config_cache = nil
    _config_cache_path = nil
    return nil
  end
  local mtime = vim.fn.getftime(config_path)
  if _config_cache_path ~= config_path or _config_cache_mtime ~= mtime then
    local toml = require("poste-db.toml")
    local parsed, err = toml.parse_file(config_path)
    if not parsed then return nil end
    _config_cache = parsed
    _config_cache_path = config_path
    _config_cache_mtime = mtime
  end
  local conn = _config_cache[name]
  if not conn then return nil end
  conn = apply_env(conn, M.get_env_vars(search_dir))
  if conn.dialect == "mariadb" then
    conn.dialect = "mysql"
  end
  return conn
end

--- Resolve a connection name to a URL by reading connections.toml from cwd.
--- Replicates Rust's ConnectionConfig::to_url() logic, resolving `{{var}}`
--- references first.
--- @param name string Connection name
--- @return string|nil, string|nil url, error_message
function M.resolve_connection_url(name)
  local search_dir = get_search_dir()
  local config_path = M.find_connections_toml(search_dir)
  if not config_path then
    return nil, "connections.toml not found (searched from " .. search_dir .. ")"
  end
  local toml = require("poste-db.toml")
  local parsed, err = toml.parse_file(config_path)
  if not parsed then return nil, err end
  local conn = parsed[name]
  if not conn then return nil, "Connection '" .. name .. "' not found in " .. config_path end
  conn = apply_env(conn, M.get_env_vars(search_dir))

  -- Use url field directly if present
  if conn.url and conn.url ~= "" then
    return conn.url, nil
  end

  -- Build URL from individual fields
  if conn.dialect == "sqlite" then
    local path = conn.path or ":memory:"
    if path == ":memory:" then
      return "sqlite::memory:", nil
    end
    return "sqlite:" .. path .. "?mode=rwc", nil
  end

  local scheme = conn.dialect == "postgres" and "postgres" or "mysql"
  local host = conn.host or "localhost"
  local default_port = conn.dialect == "postgres" and 5432 or 3306
  local port = conn.port or default_port
  local db = conn.database or ""
  local auth = ""
  if conn.user and conn.password then
    auth = percent_encode(conn.user) .. ":" .. percent_encode(conn.password) .. "@"
  elseif conn.user then
    auth = percent_encode(conn.user) .. "@"
  end
  return scheme .. "://" .. auth .. host .. ":" .. port .. "/" .. percent_encode(db), nil
end

---------------------------------------------------------------------------
-- Binary discovery
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- List connections
---------------------------------------------------------------------------

--- Fetch connections from connections.toml.
--- @param callback function(connections: table[]) Called with parsed connection list
function M.list_connections(callback)
  local search_dir = get_search_dir()
  local config_path = M.find_connections_toml(search_dir)
  if not config_path then
    vim.schedule(function() callback({}) end)
    return
  end
  local toml = require("poste-db.toml")
  local parsed, _ = toml.parse_file(config_path)
  if not parsed then
    vim.schedule(function() callback({}) end)
    return
  end
  local list = {}
  local vars = M.get_env_vars(search_dir)
  for name, conn in pairs(parsed) do
    conn = apply_env(conn, vars)
    table.insert(list, { name = name, dialect = conn.dialect, host = conn.host, port = conn.port, database = conn.database, path = conn.path })
  end
  vim.schedule(function() callback(list) end)
end

---------------------------------------------------------------------------
-- Format connection for display
---------------------------------------------------------------------------

local dialect_icons = {
  postgres = "🐘",
  mysql = "🐬",
  mariadb = "🐬",
  sqlite = "📦",
}

local function format_connection(conn)
  local icon = dialect_icons[conn.dialect] or "❓"
  local name = conn.name or "?"

  if conn.dialect == "sqlite" then
    return string.format("%s %s — %s", icon, name, conn.path or "?")
  else
    local host = conn.host or "localhost"
    local port = conn.port or (conn.dialect == "postgres" and 5432 or 3306)
    local db = conn.database or ""
    return string.format("%s %s — %s:%d/%s", icon, name, host, port, db)
  end
end

---------------------------------------------------------------------------
-- Select connection
---------------------------------------------------------------------------

--- Open connection picker.
function M.select_connection()
  M.list_connections(function(connections)
    if #connections == 0 then
      vim.notify("No connections found. Create a connections.toml file.", vim.log.levels.WARN)
      return
    end

    local items = {}
    for _, conn in ipairs(connections) do
      table.insert(items, format_connection(conn))
    end

    select_mod.select(items, "Select Connection", function(selected)
      if not selected then return end

      -- Find the matching connection
      for i, item in ipairs(items) do
        if item == selected then
          local conn = connections[i]
          M.apply_connection(conn)
          break
        end
      end
    end)
  end)
end

--- Apply a selected connection to the current buffer.
--- Updates @connection directive and state.sql.context.connection.
function M.apply_connection(conn)
  local conn_name = conn.name
  state.sql.context.connection = conn_name

  -- Update or insert @connection directive in the current buffer
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].swapfile = false
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local found = false

  for i, line in ipairs(lines) do
    if const.match_directive(line, const.DIRECTIVE_CONNECTION) then
      -- Update existing directive
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { "-- @" .. const.DIRECTIVE_CONNECTION .. " " .. conn_name })
      found = true
      break
    end
    -- Stop searching after first ### marker
    if const.is_section_marker(line) then break end
  end

  if not found then
    -- Insert at the top of the file (before first ### or at line 1)
    local insert_line = 1
    for i, line in ipairs(lines) do
      if const.is_section_marker(line) then
        insert_line = i
        break
      end
      insert_line = i + 1
    end
    vim.api.nvim_buf_set_lines(buf, insert_line - 1, insert_line - 1, false, {
      "-- @" .. const.DIRECTIVE_CONNECTION .. " " .. conn_name,
      "",
    })
  end

  vim.notify(string.format("Connection set to: %s", conn_name), vim.log.levels.INFO)
end

---------------------------------------------------------------------------
-- Test connection
---------------------------------------------------------------------------

--- Test a connection by name.
function M.test_connection()
  M.list_connections(function(connections)
    if #connections == 0 then
      vim.notify("No connections found.", vim.log.levels.WARN)
      return
    end

    local items = {}
    for _, conn in ipairs(connections) do
      table.insert(items, format_connection(conn))
    end

    select_mod.select(items, "Test Connection", function(selected)
      if not selected then return end

      for i, item in ipairs(items) do
        if item == selected then
          local conn = connections[i]
          M.run_test(conn)
          break
        end
      end
    end)
  end)
end

--- Run the test for a specific connection.
function M.run_test(conn)
  local search_dir = get_search_dir()
  local cmd = { "connection", "test", conn.name, "--path", search_dir }

  vim.notify(string.format("Testing '%s'...", conn.name), vim.log.levels.INFO)

  cli.run_async(cmd, {
    on_exit = function(code)
      vim.schedule(function()
        if code == 0 then
          vim.notify(string.format("✓ Connection '%s' OK", conn.name), vim.log.levels.INFO)
        else
          vim.notify(string.format("✗ Connection '%s' FAILED", conn.name), vim.log.levels.ERROR)
        end
      end)
    end,
  })
end

---------------------------------------------------------------------------
-- Main entry point
---------------------------------------------------------------------------

--- Show the connection management menu.
function M.show_menu()
  local items = {
    "Select connection",
    "Test connection",
  }

  select_mod.select(items, "Connection Manager", function(selected)
    if selected == "Select connection" then
      M.select_connection()
    elseif selected == "Test connection" then
      M.test_connection()
    end
  end)
end

return M
