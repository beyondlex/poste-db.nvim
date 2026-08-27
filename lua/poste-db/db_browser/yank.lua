--- Yank register for DB Browser copy/paste.
---
--- Single-slot registry: `y` on a table/view/database node records the
--- source; `p` on a target database (or under one) pastes from it.
--- Survives across connections and browser re-opens within the session.

local M = {}

---@class poste_db.YankEntry
---@field kind "table"|"view"|"database"
---@field name string|nil        item name when kind ~= "database"
---@field schema string|nil      PG schema of the source item/db scope
---@field conn string            source connection name
---@field db string|nil          source database (nil for sqlite connections)
---@field dialect string

local entry = nil

---@param e poste_db.YankEntry|nil
function M.set(e)
  entry = e
end

function M.get()
  return entry
end

function M.clear()
  entry = nil
end

--- Human-readable description, e.g. "table maria-dev.blog.posts".
---@return string|nil
function M.describe()
  if not entry then return nil end
  local scope = entry.conn
  if entry.db then scope = scope .. "." .. entry.db end
  if entry.schema and entry.kind == "database" then scope = scope .. "." .. entry.schema end
  if entry.kind == "database" then return "database " .. scope end
  return entry.kind .. " " .. scope .. "." .. tostring(entry.name)
end

--- Build a register entry from a DB Browser tree node.
--- Table nodes carry table_type ("BASE TABLE"/"VIEW"); SQLite exposes its
--- tables directly under the connection node, so a sqlite connection acts as
--- the database itself for whole-database yanks.
---@param node table tree node
---@param dialect string fallback dialect (from root/meta)
---@return poste_db.YankEntry|nil nil when the node type is not copyable
function M.from_node(node, dialect)
  if not node or not node.node_type then return nil end

  local function meta_conn()
    if node.meta and node.meta.connection then return node.meta.connection end
    if node.node_type == "connection" then return node.name end
    return nil
  end

  -- Resolve the effective dialect: database/schema/table nodes carry it in
  -- meta only sometimes; callers may pass the root-level value instead.
  local effective_dialect = dialect
  if node.meta and node.meta.dialect then effective_dialect = node.meta.dialect end

  if node.node_type == "table" then
    local ttype = node.meta and node.meta.table_type or "BASE TABLE"
    return {
      kind = (ttype == "VIEW") and "view" or "table",
      name = node.name,
      schema = node.meta and node.meta.schema or nil,
      conn = meta_conn(),
      db = node.meta and node.meta.database or nil,
      dialect = effective_dialect,
    }
  elseif node.node_type == "schema" then
    -- A PG schema yanks as a scoped database copy.
    return {
      kind = "database",
      name = nil,
      schema = node.name,
      conn = meta_conn(),
      db = node.meta and node.meta.database or nil,
      dialect = effective_dialect,
    }
  elseif node.node_type == "database" then
    return {
      kind = "database",
      name = nil,
      schema = nil,
      conn = meta_conn(),
      db = node.name,
      dialect = effective_dialect,
    }
  elseif node.node_type == "connection" then
    -- Only meaningful for sqlite, where tables hang directly off the
    -- connection (one file = one database).
    if effective_dialect == "sqlite" then
      return {
        kind = "database",
        name = nil,
        schema = nil,
        conn = node.name,
        db = nil,
        dialect = effective_dialect,
      }
    end
    return nil
  end
  return nil
end

return M
