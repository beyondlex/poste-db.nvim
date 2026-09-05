# SQL Developer Documentation

> SQL execution engine, completion, UI design

## Module Index

One line per module. Line counts drift — responsibilities are what matter;
see `.opencode/skills/sql-architecture-harness/SKILL.md` for the house rules
(one module, one job; house primitives listed there are seams, not suggestions).

### Entry & wiring

| Module | Role |
|--------|------|
| `init.lua` | `setup()` entry: config merge, highlights, commands, autocmds, AI registration |
| `config.lua` | User config (`M.config`), defaults, keymap lookup |
| `compat.lua` | Legacy `poste_sql_*` globals + `poste_db_*`/`poste_sql_` variable-name fallbacks; deprecation warnings |
| `constants.lua` | **Single source**: supported dialects, `DIALECT_ALIASES`, `URL_SCHEMES`/`dialect_from_url`, `DIALECT_DEFAULT_PORTS`, `SYSTEM_SCHEMAS`, directive parsing helpers |
| `state.lua` | SQL context (current connection/database binding) + dataset/cell state |
| `health.lua` | `:checkhealth` — nvim version, poste.nvim presence, binary discovery |
| `autocmds.lua` | Filetype detection, directive highlighting, buffer cleanup wiring |
| `commands.lua` | `:PosteDb*` command definitions |
| `buffer_setup.lua` | Buffer-local setup for poste_sql buffers |

### SQL understanding

| Module | Role |
|--------|------|
| `statement.lua` | Statement boundary detection (Rust binary → tree-sitter → fallback) |
| `ts_stmt.lua` | Tree-sitter statement/query extraction |
| `context.lua` / `lex.lua` | Cursor context resolution; comment/string lexing |
| `semantic_diagnostics.lua` | Tree-sitter reference extraction + unknown-object validation (fetches schema via introspect jobs) |
| `syntax.lua` | Treesitter-based highlight queries / digit-prefix fragments / known error constructs |
| `ident.lua` | Identifier quoting (`quote`/`quote_qualified`) + value literals per dialect |

### Execution

| Module | Role |
|--------|------|
| `connections.lua` | connections.toml discovery/parse/cache, env `{{vars}}`, URL building (`resolve_connection_url` — mirror of Rust `to_url()`), picker |
| `executor.lua` | Chooses session vs exec path per connection/operation |
| `session_conn.lua` | Long-lived `poste session` pool (temp tables, `USE`, session vars persist across `<CR>`); keyed by conn_url, shared across buffers |
| `exec_run.lua` / `file_exec.lua` | One-shot `poste exec-file` runs (editor/file entry) with NDJSON event parsing |
| `sql_runner.lua` | Resultset request path used by the dataset R-refresh flows |
| `sql_runner/response.lua` | Response → statement results mapping, DDL classification |
| `session.lua` | Request-scoped session lifecycle (fresh Session per run, persistent context) |
| `async.lua` | jobstart/timeout scaffolding |
| `edit_commit/` | Dataset edit commit: DML generation (`dml.lua`, `dml_guard.lua`), commit/rollback exec, SQL log |
| `table_ops.lua` | Table-level DDL operations from the browser |

### Dataset UI

| Module | Role |
|--------|------|
| `buffer/` | Dataset buffer: render pipeline (`init`), paging (`page`), search/filter (`search`), keyboard nav (`nav*`), tabs/history (`history`, `header`), render (`render`), nav state (`nav_state`, `nav_ui`, `nav_sort`, `nav_preview`, `nav_raw`) |
| `dataset.lua` | Dataset data model/tab state |
| `format.lua` | Value formatting, column widths, table drawing, pagination planning |
| `highlights/` | Cell highlight extmarks (`render`) + highlight groups (`theme`) |
| `statement_indicator.lua` / `statement.lua` | Sign-column statement indicators |
| `nav/` | Cross-dataset navigation routing (`detect`/`handlers`/`route`) |
| `float_window.lua` | House floating-window primitive — all popups go through `open()`/`open_centered()` |
| `insert_hint.lua` | Debounced INSERT template hint |
| `statusline.lua` | Dataset statusline |
| `log_viewer.lua` | SQL log browsing/filtering/re-run |
| `help.lua` | Floating keymap help |

### Completion

| Module | Role |
|--------|------|
| `completion/init.lua` | Completion entry + mode handling (hybrid/rust/legacy) |
| `completion/data.lua` | Keyword/function tables, cache + epoch, lazy introspect fetchers (`start_introspect_job` is the house scaffold), `tables_db_flag` |
| `completion/ctx.lua` / `handlers.lua` | Context detection dispatch and per-context item building |
| `completion/adapter.lua` / `register.lua` | blink.cmp integration + provider registration |
| `completion/debug.lua` | On-demand completion debug window |

### DB browser / import / export / introspect

| Module | Role |
|--------|------|
| `db_browser/init.lua` | Browser tree window + buffer setup |
| `db_browser/operations.lua` | Table/column DDL operations (SQL builders + confirm dialogs + batch jobs) |
| `db_browser/copy.lua` | Cross-server table clone (DDL rewrite + data copy + progress dialogs) |
| `db_browser/actions.lua` / `context_menu.lua` / `flash.lua` | Tree actions, menu, flash highlight |
| `db_browser/catalog.lua` | Per-dialect catalog SQL (views/triggers/routines/sizes) |
| `db_browser/forms.lua` / `forms_advanced.lua` / `schema_create.lua` / `db_create.lua` | Create/alter form dialogs |
| `db_browser/tree.lua` / `util.lua` | Tree model + expand/refresh primitives |
| `db_browser/icons.lua` / `theme.lua` / `statusline.lua` / `notify.lua` / `yank.lua` / `completion.lua` / `sql_conn.lua` / `async.lua` | Browser support modules |
| `import.lua` + `import/` | CSV/JSON import: parse (`format`), column mapping (`mapping`), preview, execute |
| `export.lua` | Resultset export (csv/tsv/json/markdown/sql) |
| `introspect/` | Table DDL viewer routing (`init` + column/context/detect/exec/helpers/job/route/table/target/ui — each with its own spec) |
| `editor.lua` + `editor/` | Cell editing: value parse/validate (`cell`), column metadata (`column`), grid navigation (`nav`) |

### AI

| Module | Role |
|--------|------|
| `ai/init.lua` | poste-ai.nvim registration (silently absent-safe) |
| `ai/system_prompt.lua` | "db" context system prompt (dialect list lives here) |
| `ai/actions.lua` / `commands.lua` / `mentions.lua` / `schema.lua` / `introspect.lua` | Ask/actions commands, @connection mentions, schema injection |

## Naming Conventions — `poste-db` vs `poste_sql`

> Read this before writing any code. It is the source of truth for which name
> to use, and it is what keeps AI agents from reintroducing `poste_sql_*`
> identifiers.

There are exactly THREE spellings to know, and they mean different things:

| Name | Means | Used for | Examples |
|------|-------|----------|----------|
| `poste-db` | **The plugin** | Repo, module paths, user commands | `lua/poste-db/`, `require("poste-db.state")`, `:PosteDbInfo` |
| `poste_db` | **The plugin, snake_cased** | Lua-config globals, buffer vars, extmark namespaces, completion provider | `g:poste_db_config`, `b:poste_db_context`, `vim.api.nvim_create_namespace("poste_db_dataset")`, `add_source_provider("poste_db")` |
| `poste_sql` / `poste_sqlite` | **The Vim filetype** for SQL buffers this plugin manages | Filetype value and the file/hook names derived from it ONLY | `set filetype=poste_sql`, `ftdetect/poste_sql.vim`, `after/queries/poste_sql/`, `au FileType poste_sql` |

### Rule of thumb

- **`db` → the plugin.** Every new plugin-facing identifier uses `poste-db` or
  `poste_db` (and highlight groups use the `PosteDb*` prefix).
- **`sql` → the filetype only.** `poste_sql` / `poste_sqlite` are reserved for
  the buffer filetype value and the `ftdetect/`/`syntax/`/`ftplugin/`/`after/queries/`
  files named after it. This is the same contract poste.nvim relies on
  (`lua/poste/buffer_setup.lua` switches on these filetypes), so it must NOT change.
- Never introduce a new `poste_sql_*`-prefixed global, buffer var, namespace, or
  provider name. The `poste_sql_*` globals that still exist are **deprecated
  aliases** read only by `lua/poste-db/compat.lua` (they log a deprecation
  warning); do not add new readers, do not write them, and treat them as
  migration-only.
- The filetype name `poste_sql` itself is NOT deprecated — only the
  plugin-level `poste_sql_*` API names are.

Cheat sheet for the integration points where both names legitimately meet:

```lua
-- completion provider id (plugin)        → "poste_db"
adapter.register_source({ name = "poste_db", ... })
-- filetype → provider mapping (both)     → filetype is poste_sql, provider is poste_db
adapter.register_filetype("poste_sql", "poste_db")
-- treesitter language registration       → filetype stays poste_sql/poste_sqlite
vim.treesitter.language.register("sql", "poste_sql")
-- conform per-filetype mapping           → key is the filetype
conform.formatters_by_ft["poste_sql"] = ...
-- user config global                     → poste_db
vim.g.poste_db_legacy_completion = "rust"
```

## Design Docs

| Document | Description |
|----------|-------------|
| [Dialect Support](./dialect-support.md) | 新增 SQL 方言：优先级、别名机制、三层测试、容器方案、**Lua/Rust 触点清单**（动手前照单全查） |
| [Code Review Report](./review-report.md) | 全量代码审查报告（P0-P3 分级缺陷，全部带 file:line 证据） |
| [Architecture Review](./architecture-review.md) | 架构坏味道审查 + UI 渲染选型（nui-components 评估）+ 重构路线图 |
| [Fix Plan & Architecture Design](./fix-plan.md) | 修复计划与架构设计（AI agent 执行依据，含异步模型/缓存/上下文/执行器设计） |
| [Completion System](./completion/INDEX.md) | P0-P4 implementation guide (✅ complete) |
| [Context Architecture](./context-architecture.md) | SQL completion context detection architecture |
| [DB Browser Context Menu](./db-browser-context-menu.md) | Database browser context menu design |
| [Schema Create](./schema-create-design.md) | Schema creation dialog, advanced form component, SQL execution from DB browser |
| [Refactor Agent Guide](./refactor-agent-guide.zh.md) | AI agent execution guide for the refactor branch |
| [AI Chat Integration](./ai-chat.md) | poste-ai.nvim "db" context: @connection mentions, schema injection, SQL code-block execution into the dataset |

> **Archived design docs** (features implemented, kept for reference):  
> SQL Feature Design, Dataset UI Design, Dataset Editing, Data Import — these are in [archived docs](../archived/README.md) as their features are now implemented.

---

*SQL developer documentation — Last updated: 2026-09-05 (module index rewritten; naming section unchanged)*
