# SQL Developer Documentation

> SQL execution engine, completion, UI design

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
adapter.register_filetype("poste_sqlite", "poste_db")
-- treesitter language registration       → filetype stays poste_sql/poste_sqlite
vim.treesitter.language.register("sql", "poste_sql")
-- conform per-filetype mapping           → key is the filetype
conform.formatters_by_ft["poste_sql"] = ...
-- user config global                     → poste_db
vim.g.poste_db_legacy_completion = "rust"
```

| Document | Description |
|----------|-------------|
| [Code Review Report](./review-report.md) | 全量代码审查报告（P0-P3 分级缺陷，全部带 file:line 证据） |
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

*SQL developer documentation — Last updated: 2026-08-29*
