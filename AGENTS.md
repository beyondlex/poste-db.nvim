# poste-db.nvim

Independent SQL plugin for Poste. Depends on [poste.nvim](https://github.com/beyondlex/poste.nvim) for shared infra (state.lua, select.lua, indicators.lua, cli.lua, etc.) and the poste Rust binary.

## Key Facts

- All SQL Lua code lives under `lua/poste-db/`
- Requires `poste.nvim` on rtp — `require("poste.state")` must succeed
- Optional: [poste-ai.nvim](https://github.com/beyondlex/poste-ai.nvim) on rtp enables the AI chat (`:PosteDbChat`, `<leader>aa`). `lua/poste-db/ai/` must only `pcall(require, "poste-ai")` and silently skip when absent
- `plugin/poste-db.lua` calls `require("poste-db.init").setup()`
- `ftdetect/poste_sql.vim` sets filetypes for `.sql` and `.sqlite`
- Uses same `poste` Rust binary from poste.nvim
- `.opencode/skills/sql/` and `.opencode/skills/sql-completion/` for agent context
- Harness order:
  1. `.opencode/skills/sql-preflight-harness/SKILL.md`
  2. one specialized harness if needed
  3. `sql-test-harness` when adding or hardening tests
  4. `sql-architecture-harness` when the code shape is the problem
  5. `sql-refactor-harness`, `sql-nav-harness`, or `sql-introspect-harness` when the task matches that area

## File Index

See `docs/dev/sql/README.md` for detailed file index.

## Naming Conventions

`poste-db` / `poste_db` = the plugin (modules, config keys, namespaces, provider).
`poste_sql` / `poste_sqlite` = ONLY the SQL **filetype** and the file/hook names
derived from it (`ftdetect/poste_sql.vim`, `after/queries/poste_sql/`, `au FileType poste_sql`).

There is no `lua/poste-sql/` and the plugin is NOT named `poste-sql` anymore.
Never write a new `poste_sql_*` global/namespace/provider — the remaining
`poste_sql_*` globals are deprecated aliases handled by `lua/poste-db/compat.lua`.
The filetype name `poste_sql` itself stays. See
`docs/dev/sql/README.md#naming-conventions--poste-db-vs-poste_sql` for the full table.

## Design Principles

- Zero coupling to HTTP modules — no `require("poste.http.*")`
- State lives in `lua/poste-db/state.lua` (accessed via `require("poste-db.state")`)
- Help in `lua/poste-db/help.lua` (filetype-aware dispatch, sits in this repo)

## Lua Pitfalls

### Local function forward declaration

When function A (e.g. `show_drop_confirm`) calls function B (e.g. `execute_drop`) that is defined
later in the same file, B must be forward-declared:

```lua
local B  -- forward declaration
local function A()
  B()  -- works: B is declared (even if nil at this point)
end
B = function()
  -- body
end
```

Without the forward declaration, `local function B() ... end` creates a new local binding that
is only visible *after* its definition, and A will capture `nil`. This is a Lua lexical scoping
rule — `local` bindings are not hoisted.

## References

| Want | Go to |
|------|-------|
| **Shared infra (state, cli, select, indicators, buffer_setup, help, etc.)** | `../poste.nvim/lua/poste/` |
| **Rust CLI (crates, build system)** | `../poste.nvim/crates/` |
| **AI chat generic layer (chat UI, SSE, markdown, context API)** | `../poste-ai.nvim/lua/poste-ai/` + `docs/dev/sql/ai-chat.md` |
| **Preflight / test / architecture / refactor / nav / introspect harnesses** | `.opencode/skills/` |
| Completion rules | `.opencode/skills/sql-completion/SKILL.md` |
| Build & test | `tests/run.sh` |
| Agent learnings | `LEARNINGS.md` |
