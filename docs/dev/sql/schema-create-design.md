# Database / Schema Create — Design Document

## Overview

Add create-database and create-schema actions to DB Browser with a shared advanced form dialog, SQL preview, and direct execution.

## Key Design Decision: Direct Execution

Unlike existing operations (which generate SQL into source buffer), database/schema creation **executes SQL directly** via `poste run --stdin`, then refreshes the tree. Rationale:

- Database/schema creation is a one-shot administrative action, not part of a query workflow
- User doesn't want to manually arrange `CREATE DATABASE` / `CREATE SCHEMA` / `GRANT` blocks
- Result feedback (success/error per statement) is shown inline, not as buffer text

## File Plan

| File | Status | Role |
|------|--------|------|
| `lua/poste-db/db_browser/forms_advanced.lua` | **NEW** | Reusable advanced form UI component |
| `lua/poste-db/db_browser/db_create.lua` | **NEW** | Create Database: fields, SQL generation, execution |
| `lua/poste-db/db_browser/schema_create.lua` | **NEW** | Create Schema: fields, SQL generation, execution |
| `lua/poste-db/db_browser/init.lua` | MODIFY | Add one contextual `a` keymap binding |
| `lua/poste-db/db_browser/context_menu.lua` | MODIFY | Add "Create Database" / "Create Schema" menu items |
| `lua/poste-db/db_browser/operations.lua` | MODIFY | Add `create_database` / `create_schema` dispatch stubs |
| `lua/poste/state.lua` (poste.nvim) | MODIFY | Add `create_database` / `create_schema` default keymaps |

---

## 1. `forms_advanced.lua` — Reusable Form Component

### Why separate from `forms.lua`

Existing `forms.lua` is simple (text/bool/select only, no sections, no preview). Keeping it for simple operations. Advanced forms are a different UI pattern and should stay separate.

### Supported Field Types

| kind | Description | Widget |
|------|-------------|--------|
| `text` | Single-line input | `vim.ui.input` on Enter |
| `select` | Dropdown from choices | `vim.ui.select` on Enter |
| `bool` | Toggle | Space to toggle, ✓/✗ display |
| `multi_select` | Multiple choices from a set | Space to toggle individual items, shows `[A B C]` |
| `list` | Dynamic array of sub-entry forms | `a` add, `d` delete, each entry is a collapsible sub-form |
| `section` | Collapsible section header | Enter to collapse/expand |
| `preview` | SQL preview pane | Read-only buffer, auto-updated via `on_change` callback |

### API

```lua
--- Open an advanced form dialog.
--- @param opts table
---   title: string          — Window title
---   width: number?          — Default 80
---   height: number?         — Default 40
---   dialect: string         — Used for dialect-aware defaults and SQL generation
---   sections: SectionDef[]  — Form sections
---   on_change: fun(fields: table<string, any>): string[]  — Called on any field change, returns SQL lines
---   on_submit: fun(fields: table<string, any>, sql: string)  — Called on submit with generated SQL text
---   on_cancel: fun()?       — Called on cancel
---   on_validate: fun(fields: table<string, any>): string?, string?  — Called before submit; returns (error_message?, first_error_field_key?)
---   window_management: "single"|"allow_multiple"  — Default "single"; if "single" and a form is already open, close it first
function M.open(opts) end
```

### SectionDef

```lua
--- @class SectionDef
--- @field title string       — Section header text
--- @field collapsed boolean? — Default false
--- @field kind string?       — "section" (default) or "list" (dynamic)
--- @field dialect string?    — If set, only show this section when dialect matches
--- @field fields FieldDef[]  — Fields in this section
```

### FieldDef

```lua
--- @class FieldDef
--- @field key string         — Unique key for this field
--- @field label string       — Display label
--- @field kind string        — "text" | "select" | "bool" | "multi_select" | "list" | "preview"
--- @field value any          — Current value
--- @field choices string[]?  — For "select" and "multi_select"
--- @field dialect string?    — If set, only show this field when dialect matches
--- @field sub_fields FieldDef[]?  — For "list" kind, defines the sub-entry form
--- @field placeholder string? — Placeholder text for empty fields
```

### UI Layout

```
┌ Create Object ──────────────────────────────────────────────────┐
│                                                                 │
│  ┌ Object Info ───────────────────────────────────────────┐      │
│  │  Name:       [my_name                      ]           │      │
│  │  Owner:      [postgres                     ]           │      │
│  │  If Not Exists:  [✓]                                  │      │
│  └────────────────────────────────────────────────────────┘      │
│                                                                 │
│  ┌ Optional Privileges ──────────────────────────────────┐      │
│  │  ├ Grant: SELECT ON ALL TABLES → readonly             │      │
│  │  └ Grant: USAGE ON SCHEMA → app_readers               │      │
│  └────────────────────────────────────────────────────────┘      │
│                                                                 │
│  ┌ SQL Preview ────────────────────────────────────────────┐     │
│  │  CREATE SCHEMA IF NOT EXISTS my_schema;                  │     │
│  │  GRANT USAGE ON SCHEMA my_schema TO app_readers;         │     │
│  │  GRANT SELECT ON ALL TABLES IN SCHEMA my_schema         │     │
│  │    TO readonly;                                          │     │
│  └──────────────────────────────────────────────────────────┘     │
│                                                                 │
│  [q Cancel]  [y Copy SQL]              [<Enter> Submit] [s]      │
└─────────────────────────────────────────────────────────────────┘
```

### Keymaps

| Key | Action |
|-----|--------|
| `j` / `k` | Move between fields |
| `<Tab>` / `<S-Tab>` | Next/previous field |
| `<Enter>` | Edit current field (text/select) or collapse/expand section |
| `<Space>` | Toggle bool / multi_select item |
| `a` | Add list entry (only when focus is on a list field) |
| `d` | Delete current list entry |
| `s` | Submit (execute SQL) |
| `y` | Copy SQL to clipboard |
| `q` / `<Esc>` | Close dialog |

### Implementation Notes

- **SQL Preview**: Use a dedicated preview pane or a second floating window. Do not assume a single Neovim window can render two buffers at once.
- **Dynamic resize**: Window height adapts as sections collapse/expand (max capped at `opts.height`).
- **Dialect filtering**: Fields with `field.dialect` are only rendered when `dialect == field.dialect`. Sections with `section.dialect` are hidden entirely when the dialect doesn't match.
- **List fields**: Each entry in a list can be collapsed/expanded, showing a summary of the first field on the collapsed line.
- **Validation**: `on_validate` is called before submit. If it returns an error message, the submit is aborted and the error is shown via `vim.notify`. The optional second return value (field key) can be used to focus the erroneous field.
- **Window management**: When `window_management = "single"`, opening a new form closes any previously open form. This is implemented by tracking the active form window in a module-level variable and closing it on `open()` if set. When `"allow_multiple"`, multiple forms can coexist (caller's responsibility to manage).
- **`vim.ui` interaction**: The form uses `vim.ui.input` and `vim.ui.select` for text/select fields. If the user has a custom `vim.ui` implementation (e.g., dressing.nvim), those overrides will be used. This is by design — the form doesn't bypass user preferences.

---

## 2. `db_create.lua` — Create Database Logic

### Entry Point

```lua
function M.open(node, context)
  local dialect = get_dialect(node, context)

  if dialect == "sqlite" then
    vim.notify("SQLite does not support CREATE DATABASE", vim.log.levels.INFO)
    return
  end

  local conn = get_connection_name(node, context)
  local sections = build_sections(dialect)
  forms_advanced.open({
    title = "Create Database: " .. conn,
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
```

### Fields

| Field | kind | dialect | Notes |
|-------|------|---------|-------|
| `name` | text | all | Database name |
| `if_not_exists` | bool | all | Wrap in `IF NOT EXISTS` |
| `charset` | select | mysql | MySQL only |
| `collation` | select | mysql | MySQL only |
| `owner` | text | postgres | PostgreSQL only, optional |

### SQL Generation

```lua
function M.generate_sql(fields, dialect)
  if dialect == "mysql" then
    return {
      mysql_create_database(fields),
    }
  end
  return {
    postgres_create_database(fields),
  }
end
```

### Execution

```lua
function M.execute_sql(sql, conn_name, context, opts)
  local connections = require("poste-db.connections")
  local url, err = connections.resolve_connection_url(conn_name)
  if not url then
    vim.notify("Database create failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return
  end
  local cmd = {
    "run", "--line", "1", "--json", "--stdin",
    "--connection-url", url,
  }
  -- Send sql through stdin, then refresh the connection node.
  -- Do not pass --database here: the target database does not exist yet.
end
```

---

## 3. `schema_create.lua` — Create Schema Logic

### Entry Point

```lua
function M.open(node, context)
  local dialect = get_dialect(node, context)

  if dialect ~= "postgres" then
    vim.notify("CREATE SCHEMA is only supported for PostgreSQL", vim.log.levels.INFO)
    return
  end

  local conn = get_connection_name(node, context)
  local db_name = node.name
  local sections = build_sections(dialect)
  forms_advanced.open({
    title = "Create Schema: " .. db_name,
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
      execute_sql(sql, conn, context, { database = db_name })
    end,
    window_management = "single",
  })
end
```

### Sections

#### Section 1: Schema Info

| Field | kind | dialect | Notes |
|-------|------|---------|-------|
| `name` | text | all | Schema name |
| `owner` | text | postgres | Optional, `AUTHORIZATION owner` |
| `if_not_exists` | bool | all | Wrap in `IF NOT EXISTS` |

#### Section 2: Grants (list kind)

Each entry in the grants list has a sub-form:

| Field | kind | dialect | Notes |
|-------|------|---------|-------|
| `type` | select | all | `"grant"` \| `"grant_usage"` |
| — when type = "grant": | | | |
| `grantee` | text | all | User/role name |
| `privileges` | multi_select | postgres | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `USAGE` |
| `on_object` | select | postgres | `ALL TABLES IN SCHEMA`, `ALL SEQUENCES IN SCHEMA`, `ALL FUNCTIONS IN SCHEMA`, `SCHEMA` |
| `with_grant_option` | bool | postgres | `WITH GRANT OPTION` |
| — when type = "grant_usage": | | | |
| `grantee` | text | postgres | User/role name |
| `with_grant_option` | bool | postgres | Optional |

### SQL Generation

```lua
function M.generate_sql(fields, dialect)
  local lines = {}

  table.insert(lines, postgres_create_schema(fields))

  -- Optional grants after schema creation
  for _, grant in ipairs(fields.grants) do
    if grant.type == "grant" then
      table.insert(lines, gen_grant(grant, dialect))
    elseif grant.type == "grant_usage" then
      table.insert(lines, gen_grant_usage(grant))
    end
  end

  return lines
end
```

#### Dialect-Specific SQL

**PostgreSQL:**
```sql
CREATE SCHEMA IF NOT EXISTS "my_schema" AUTHORIZATION "postgres";
GRANT USAGE ON SCHEMA "my_schema" TO "app_readers";
GRANT SELECT ON ALL TABLES IN SCHEMA "my_schema" TO "readonly";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA "my_schema" TO "readonly";
```

**MySQL:**
```sql
-- Not applicable: CREATE SCHEMA is PostgreSQL-only in this design.
```

**SQLite:**
```sql
-- Not applicable: SQLite does not support CREATE SCHEMA.
```

### Execution

```lua
function M.execute_sql(sql, conn_name, context, opts)
  local connections = require("poste-db.connections")
  local url, err = connections.resolve_connection_url(conn_name)
  if not url then
    vim.notify("Schema create failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return
  end

  local binary = cli.binary()
  if not binary then
    vim.notify("Poste binary not found", vim.log.levels.ERROR)
    return
  end

  local file_path = vim.fn.tempname() .. ".sql"
  local cmd = {
    binary, "run", file_path,
    "--line", "1",
    "--json",
    "--stdin",
    "--connection-url", url,
  }
  if opts and opts.database then
    table.insert(cmd, "--database")
    table.insert(cmd, opts.database)
  end
  local stderr_buf = {}
  local stdio_done = false
  local job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then return end
      stdio_done = true
      -- Parse JSON response for per-statement success/error
      local output = table.concat(data, "\n")
      local ok, resp = pcall(vim.json.decode, output)
      if ok and resp then
        vim.schedule(function()
          local ok2, body = pcall(vim.json.decode, resp.body or "{}")
          local errors = {}
          if ok2 and body and body.results then
            for _, result in ipairs(body.results) do
              if result.error and result.error ~= "" then
                table.insert(errors, result.error)
              end
            end
          end
          if #errors > 0 then
            vim.notify("Schema created with errors:\n" .. table.concat(errors, "\n"),
              vim.log.levels.WARN)
          else
            vim.notify("Schema created successfully", vim.log.levels.INFO)
          end
          -- Refresh tree
          refresh_database(opts and opts.target_node or nil, context)
        end)
      end
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
          vim.notify("Schema creation failed: " .. table.concat(stderr_buf, "\n"),
            vim.log.levels.ERROR)
        end)
      end
    end,
  })

  if job_id > 0 then
    vim.fn.chansend(job_id, sql)
    vim.fn.chanclose(job_id, "stdin")
  end
end

function refresh_database(target_node, context)
  local parent = target_node
  while parent and parent.node_type ~= "database" do
    parent = parent.parent
  end
  if not parent then return end

  parent.children = nil
  parent.expanded = false
  parent.loading = true

  local tree = require("poste-db.db_browser.tree")
  local nm = tree.render_tree(context.browser_buf, context.line_to_node,
    context.root_nodes, context.conn_label)
  for i, n in ipairs(nm) do context.line_to_node[i] = n end

  local async = require("poste-db.db_browser.async")
  async.fetch_children(parent, function()
    parent.expanded = true
    vim.schedule(function()
      local nm2 = tree.render_tree(context.browser_buf, context.line_to_node,
        context.root_nodes, context.conn_label)
      for i, n in ipairs(nm2) do context.line_to_node[i] = n end
    end)
  end, context.search_dir or vim.fn.getcwd())
end
```

---

## 4. Integration Points

### `init.lua` — Keymap

```lua
-- In setup_browser_buffer()
k = state.get_keymap("sql_db_browser", "create_object", "a")
if k then
  -- Contextual binding:
  --   connection node -> create database
  --   database node   -> create schema
  vim.keymap.set("n", k, function()
    local node = tree.get_node_at_line(line_to_node, vim.fn.line("."))
    if node and node.node_type == "connection" then
      require("poste-db.db_browser.db_create").open(node, make_context())
    elseif node and node.node_type == "database" then
      require("poste-db.db_browser.schema_create").open(node, make_context())
    end
  end, opts)
end
```

### `state.lua` — Default Keymap

```lua
sql_db_browser = {
  ...
  create_object = "a",
}
```

### `context_menu.lua` — Menu Item

```lua
connection = {
  ...
  { letter = "N", label = "Create Database", action = "create_database", group = "modify" },
}

database = {
  ...
  { letter = "N", label = "Create Schema", action = "create_schema", group = "modify" },
}
```

### `operations.lua` — Dispatch

```lua
function M.create_database(node, context)
  require("poste-db.db_browser.db_create").open(node, context)
end

function M.create_schema(node, context)
  require("poste-db.db_browser.schema_create").open(node, context)
end
```

---

## 5. Future Extensibility

The `forms_advanced.lua` component is designed to be reused for:

| Feature | Form Fields | SQL Generation |
|---------|-------------|----------------|
| Create Database | name, charset, collation, owner | `CREATE DATABASE ...` |
| Create Schema | name, owner, grants | `CREATE SCHEMA ...` |
| Alter Table (advanced) | columns (add/drop/modify), constraints | `ALTER TABLE ...` |
| Table rename + migrate | old name, new name, cascade | `ALTER TABLE ... RENAME TO ...` |

Each new feature would be a separate `lua/poste-db/db_browser/<feature>.lua` file following the same pattern: build sections → generate SQL → execute.

---

## 6. Implementation Order

1. **`forms_advanced.lua`** — Core UI component (most complex, ~400 lines)
2. **`db_create.lua`** — SQL generation + execution for CREATE DATABASE (~250 lines)
3. **`schema_create.lua`** — SQL generation + execution for CREATE SCHEMA (~250 lines)
4. **Integration** — init.lua, context_menu.lua, operations.lua, state.lua (~50 lines total)
