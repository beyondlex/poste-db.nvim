# poste-sql.nvim

Independent SQL plugin for Poste. Depends on [poste.nvim](https://github.com/beyondlex/poste.nvim) for shared infra (state.lua, select.lua, indicators.lua, cli.lua, etc.) and the poste Rust binary.

## Key Facts

- All SQL Lua code lives under `lua/poste-sql/`
- Requires `poste.nvim` on rtp — `require("poste.state")` must succeed
- `plugin/poste-sql.lua` calls `require("poste-sql.init").setup()`
- `ftdetect/poste_sql.vim` sets filetypes for `.sql` and `.sqlite`
- Uses same `poste` Rust binary from poste.nvim
- `.opencode/skills/sql/` and `.opencode/skills/sql-completion/` for agent context

## File Index

See `docs/dev/sql/README.md` for detailed file index.

## Design Principles

- Zero coupling to HTTP modules — no `require("poste.http.*")`
- State lives in `lua/poste-sql/state.lua` (accessed via `require("poste-sql.state")`)
- Help in `lua/poste/help.lua` (shared infra, filetype-aware dispatch)
- **Module name ownership**: `poste-http.nvim` comes before `poste-sql.nvim` in rtp.
  Never create files under `lua/poste-sql/` in `poste-http.nvim` — they would shadow
  this repo's modules silently.

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
| **Shared infra (state, cli, select, indicators, buffer_setup, help, etc.)** | `../poste.nvim/lua/poste/` — edit there |
| **Rust CLI (crates, build system)** | `../poste.nvim/crates/` — edit there |
| Completion rules | `.opencode/skills/sql-completion/SKILL.md` |
| Build & test | `tests/run.sh` |
| Agent learnings | `LEARNINGS.md` |
