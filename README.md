# poste-db.nvim

**SQL execution, dataset browser, and schema introspection for Neovim.** Part of the [Poste](https://github.com/beyondlex/poste.nvim) family.

**Requires**: [poste.nvim](https://github.com/beyondlex/poste.nvim) (shared infra + Rust binary)

## Features

- **Execute SQL statements** from `.sql` files (PostgreSQL, MySQL, SQLite)
- **Dataset panel** — Paginated results, cell navigation (hjkl), vim-style search/filter, sorting
- **Inline editing** — Edit cells, insert/delete rows, generate DML with transaction commit
- **DB Browser** — Tree-view of schemas, tables, columns; generate SELECT/DESCRIBE queries
- **SQL completion** — Keywords, tables, columns, functions (blink.cmp)
- **Schema introspection** — PKs, FKs, indexes, DDL
- **Export/import** — CSV, JSON, SQL INSERT statements
- **Multi-result tabs** — Each statement gets its own tab
- **Execution log viewer** — Query history with timing

## Installation

```lua
-- lazy.nvim
{
  "beyondlex/poste-db.nvim",
  dependencies = {
    "beyondlex/poste.nvim",
    "saghen/blink.cmp",
  },
  config = function()
    require("poste-db.init").setup()
  end,
}
```

## Usage

Open a `.sql` file and press `<CR>` on a statement to execute.

### Connection management

Connections are defined in `connections.toml` (walked up from the SQL file):

```toml
[pg-dev]
dialect = "postgres"
host = "localhost"
port = 5432
database = "myapp"
user = "{{PG_DEV_USER}}"
password = "{{PG_DEV_PASSWORD}}"
```

Sensitive fields support `{{VAR}}` references resolved at runtime from a
`.env` file next to `connections.toml` (same walk-up discovery), with real OS
environment variables taking precedence. Unknown references stay literal, so
plaintext configs keep working. Copy `.env.example` to `.env` and keep `.env`
out of version control — never commit credentials. `user` and `password` are
percent-encoded automatically when building connection URLs, so values
containing `@`, `:`, `/`, `%` etc. work as-is.

Reference in `.sql` files:

```sql
-- @connection pg-dev

SELECT * FROM users WHERE active = true;
```

The `USE database;` statement switches the active database for parsing/completion context.

### Statusline context

The current connection and database are shown in the statusline as `[connection/database]` when `mini.statusline` is installed. The context updates as you move the cursor (respects `@connection`, `@database`, and `USE` statements).

**Per-connection colors** — add a `color` or `link` field in `connections.toml`:

```toml
[production]
color = "#ff0000"

[staging]
link = "WarningMsg"

[development]
color = "SkyBlue"
```

| Field | Type | Example |
|-------|------|---------|
| `color = "#rrggbb"` | Hex color | `color = "#ff0000"` |
| `color = "CSS"` | CSS named color | `color = "Red"`, `color = "SkyBlue"` |
| `color = "HL"` | Highlight group (auto-detected) | `color = "Function"` |
| `link = "HL"` | Explicit highlight group link | `link = "ErrorMsg"` |

Auto-detection: `color` values that are valid Neovim highlight groups are linked (`:link`), others are treated as CSS color names.

### Dataset buffer

| Key | Action |
|-----|--------|
| `h`/`j`/`k`/`l` | Move cell |
| `H`/`L` | Previous/next page |
| `0`/`$` | First/last column |
| `gg`/`G` | First/last row |
| `s` | Sort by column |
| `<leader>/` | Search |
| `<leader>ce` | Filter by cell |
| `K` | Preview cell |
| `yy` / `yc` | Yank cell / column |
| `R` | Re-run query |
| `<Tab>`/`<S-Tab>` | Next/previous tab |

### Dataset editing

| Key | Action |
|-----|--------|
| `i` / `cc` | Enter edit mode |
| `dd` | Delete row |
| `o` | Insert row below |
| `<leader>w` | Commit changes (generate DML) |

### Export

| Key | Action |
|-----|--------|
| `<leader>ec` | Export as CSV |
| `<leader>ej` | Export as JSON |
| `<leader>es` | Export as SQL INSERT |

### DB Browser

Press `<leader>db` in a SQL file to open the database tree browser.

| Key | Action |
|-----|--------|
| `<CR>` | Toggle node expand/collapse |
| `x` | Context menu |
| `d` | Generate DESCRIBE |
| `/` | Search filter |
| `q` | Close |

Context menu (`x`) shows node-specific actions. On **schema/database** nodes, `T` inserts a **CREATE TABLE template** with tab-stop placeholders:

```
create table table_name (
  column_name INTEGER NOT NULL
);
```

Press `<Tab>` to jump between placeholders, `<S-Tab>` to go back.

### SQL completion

- **Keywords** — `SELECT`, `FROM`, `WHERE`, `JOIN`, etc.
- **Tables, columns, schemas** — Introspected from your database
- **Functions** — Aggregate and scalar functions per dialect
- **Connection-aware** — Completions reflect the actual schema

Requires **blink.cmp**. Auto-registers as `poste_db` source.

### SQL Snippets

Built-in snippets are organized as **categories**, each with per-dialect
templates picked from the current connection's dialect
(mysql / mariadb / postgres / sqlite, falling back to a `default` template).
A trigger routes to a category: `trigger -> category -> [dialect] -> template`.

Every built-in snippet appears as a completion item when the prefix matches
its trigger word:

| Trigger | Category | Template | Dialect variants |
|---------|----------|----------|------------------|
| `ct` | `create_table` | `create table` | mysql `AUTO_INCREMENT`, postgres `SERIAL`, sqlite `AUTOINCREMENT` |
| `tab` | `create_table_timestamp` | `create table` + `updated_at`/`created_at` | postgres/sqlite drop `ON UPDATE CURRENT_TIMESTAMP` |
| `cdb` | `create_database` | `create database` | mysql `CHARACTER SET`+`COLLATE`, postgres `ENCODING`/`LC_COLLATE`, sqlite `ATTACH DATABASE` |
| `col` | `column` | integer column | postgres/sqlite drop `COMMENT` |
| `colv` | `column_varchar` | varchar column | postgres/sqlite drop `COMMENT`, sqlite uses `TEXT` |
| `sf` | `select_from` | `select * from ... limit 100` | default only |
| `cnt` | `select_count` | `select count(*)` | default only |
| `ins` | `insert` | `insert into ... values` | default only |
| `upd` | `update` | `update ... set ... where` | default only |
| `del` | `delete` | `delete from ... where` | default only |
| `cte` | `cte` | `with ... as` | default only |
| `idx` | `create_index` | `create index` | default only |
| `cola` | `alter_add_column` | `alter table add column` | postgres/sqlite drop `COMMENT` |
| `colu` | `alter_modify_column` | `alter table modify column` | postgres uses `ALTER COLUMN ... SET` |
| `uni` | `union_all` | `union all` | default only |

All snippets use **LSP-style syntax** (`${1:placeholder}`, `$0` for exit, `$$` for literal `$`). See `:help vim.snippet` or the [LSP spec](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#snippet_syntax) for details.

**Custom snippets** via `setup()`:

```lua
require("poste-db").setup({
  snippets = {
    -- Simple: trigger word → snippet body
    myq = "SELECT * FROM ${1:table} WHERE ${2:condition};",

    -- Full form: trigger, label, and snippet
    myf = {
      label = "my custom query",
      snippet = "with ${1:cte} as (\n  ${2:select_query}\n)\nselect * from ${1:cte};",
    },

    -- Route a trigger to a built-in category (or override one)
    mkct = "create_table",          -- new trigger for create_table category
    -- ct  = "create_database",     -- override built-in ct

    -- Custom category with per-dialect variants
    mkb = {
      default  = "CREATE DATABASE ${1:db};",
      postgres = "CREATE DATABASE ${1:db} ENCODING 'UTF8';",
    },
  },
})
```

## Requirements

- Neovim >= 0.10.0
- [poste.nvim](https://github.com/beyondlex/poste.nvim) (sibling directory or on rtp)
- `poste` binary (from poste.nvim)
- blink.cmp (recommended) or nvim-cmp for completion

## Integration Tests

```bash
# Start test databases (PG 16 on 15432, MySQL 8.0 on 13306)
cd playground && docker compose up -d

# Run Lua tests
tests/run.sh
```

## License

MIT
