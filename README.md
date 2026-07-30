# poste-sql.nvim

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
  "beyondlex/poste-sql.nvim",
  dependencies = {
    "beyondlex/poste.nvim",
    "saghen/blink.cmp",
  },
  config = function()
    require("poste-sql.init").setup()
  end,
}
```

## Usage

Open a `.sql` file and press `<CR>` on a statement to execute.

### Connection management

Connections are defined in `connections.json` (walked up from the SQL file):

```json
{
  "pg-dev": {
    "dialect": "postgres",
    "host": "localhost",
    "port": 5432,
    "database": "myapp",
    "user": "app_user",
    "password": "local-pass"
  }
}
```

Reference in `.sql` files:

```sql
-- @connection pg-dev

SELECT * FROM users WHERE active = true;
```

The `USE database;` statement switches the active database for parsing/completion context.

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
| `i` / `a` | Enter edit mode |
| `dd` | Delete row |
| `o` / `O` | Insert row below/above |
| `u` | Undo edit |
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
| `s` | Generate SELECT * |
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

Requires **blink.cmp**. Auto-registers as `poste_sql` source.

### SQL Snippets

Built-in snippets appear as completion items when the prefix matches a trigger word:

| Trigger | Template |
|---------|----------|
| `ct` | `create table` |
| `sf` / `sl` | `select * from ... limit 100` |
| `cnt` | `select count(*)` |
| `ins` | `insert into ... values` |
| `upd` | `update ... set ... where` |
| `del` | `delete from ... where` |
| `wh` | `where` clause |
| `cola` | `alter table add column` |
| `colu` | `alter table modify column` |
| `cte` | `with ... as` |
| `idx` | `create index` |
| `uni` | `union all` |

All snippets use **LSP-style syntax** (`${1:placeholder}`, `$0` for exit, `$$` for literal `$`). See `:help vim.snippet` or the [LSP spec](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#snippet_syntax) for details.

**Custom snippets** via `setup()`:

```lua
require("poste-sql").setup({
  snippets = {
    -- Simple: trigger word → snippet body
    myq = "SELECT * FROM ${1:table} WHERE ${2:condition};",

    -- Full form: trigger, label, and snippet
    myf = {
      label = "my custom query",
      snippet = "with ${1:cte} as (\n  ${2:select_query}\n)\nselect * from ${1:cte};",
    },
  },
})
```

## Integration Tests

```bash
# Start test databases (PG 16 on 15432, MySQL 8.0 on 13306)
cd tests/sql && docker compose up -d

# Run queries
cargo run --manifest-path ../poste.nvim/Cargo.toml -- run tests/sql/queries/postgres.sql --line 4 --env dev

# Run Lua tests
tests/run.sh
```

## License

MIT
