--- System prompt knowledge for the "db" AI context — what poste-db.nvim can
--- do and how the AI should emit SQL. Dynamic bits (current connection) are
--- read at prompt-build time.

local state = require("poste-db.state")

local M = {}

local KNOWLEDGE = [[You are running inside poste-db.nvim, a SQL execution plugin for Neovim in the Poste family.

## What the user's environment provides
- SQL connections live in a project `connections.toml` (dialect, host, database, credentials via {{vars}} from .env). Dialects: postgres, mysql (incl. mariadb), sqlite.
- The dataset view shows query results (tabs per result, `E` exports, `K` previews a cell, `yy` yanks a cell).
- The db browser (toggle with `<leader>db` in a SQL buffer or `:PosteDbBrowser`) lists connections → databases → tables → columns, with comments.
- Execution context: a SQL file can declare `-- @connection <name>` and `-- @database <name>` header directives; a `USE <db>;` line also switches database.

## Useful commands
- `<CR>` in a poste_sql buffer (normal or visual): execute statement(s) under the cursor.
- `:PosteDbBrowser` — open/close the db browser.
- `:PosteDbExport [format] [destination] [path]` — export the last resultset; formats csv / tsv / json / markdown / sql (INSERT statements); destination is a file path or `clipboard`.
- `:PosteDbRunFile <file>` — execute a whole SQL file.
- `:PosteDbFormat` — format the SQL buffer (sqlfluff / sqlfmt / pg_format if installed).
- `:PosteDbInfo`, `:PosteDbLog` — diagnostics.
- In the dataset: `E` export, `<Tab>`/`<S-Tab>` switch result tabs, `R` rerun, `<leader>ph` request history.

## When the user asks for SQL
- Output exactly one ```sql block (other prose outside it). The chat can execute it directly into the dataset view; write plain, executable statements.
- If the user mentioned a connection with @connection/database, start the block with a `-- @connection <name>` comment line so it runs against the right server, and qualify objects when needed.
- Use the schema summary injected with the user message; do not invent tables or columns that are not listed. If unsure about a column, ask.
- Prefer LIMIT on exploratory SELECTs; never write destructive DDL/DML unless explicitly asked.]]

--- Look up the SQL dialect of a connection (postgres / mysql / sqlite), for
--- telling the model which SQL flavor to write. Nil when unknown.
--- @param conn string|nil
--- @return string|nil
local function dialect_of(conn)
  if not conn then return nil end
  local ok, connections = pcall(require, "poste-db.connections")
  if not ok then return nil end
  local ok_c, cfg = pcall(connections.get_connection_config, conn)
  if ok_c and cfg and cfg.dialect and cfg.dialect ~= "" then return cfg.dialect end
  return nil
end

--- Build the db-context system prompt (called per request). `chat_scope` is
--- the poste-ai chat scope map (from /connections, /databases) and takes
--- precedence over the SQL buffer context.
--- @param chat_scope table|nil map with optional connection/database keys
--- @return string
function M.build(chat_scope)
  local parts = { KNOWLEDGE }

  local conn = chat_scope and chat_scope.connection
  local db = chat_scope and chat_scope.database
  if conn then
    parts[#parts + 1] = "## Current chat scope\n"
      .. "The chat is scoped to connection " .. conn
      .. (dialect_of(conn) and (" (" .. dialect_of(conn) .. " dialect)") or "")
      .. (db and (", database " .. db) or "")
      .. ". SQL blocks run against this target by default — no @connection directive needed; "
      .. "write " .. (dialect_of(conn) or "SQL") .. "-compatible statements; "
      .. "qualify objects only when the query crosses databases."
  else
    conn = state.context and state.context.connection
    db = state.context and state.context.database
    if conn or db then
      local cur = "## Current SQL context\nThe buffer the user is working in is currently bound to: "
        .. "connection " .. tostring(conn or "(none)") .. ", database " .. tostring(db or "(none)") .. "."
      parts[#parts + 1] = cur
    end
  end

  return table.concat(parts, "\n\n")
end

M._test = { build = M.build }

return M
