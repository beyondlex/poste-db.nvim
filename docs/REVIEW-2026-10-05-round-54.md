# Code Review — 2026-10-05, round 54

Round 54, following round 53 (`docs/REVIEW-2026-10-05.md`). Scope: the
zero-test-reference ring the previous rounds had not opened end to end
(`db_browser/schema_create`, `completion/adapter`, `db_browser/flash`,
`health`, `help`), the session stdout line assembler, and a hostile-input
pass over the recently-touched modules (`dataset` sort comparator,
`editor/cell`, `insert_hint`, `import/execute`, `db_browser/copy`,
`toml`, `ident`, `ops_sql`).

Baseline: 2013 plenary Success / 0 Failed by this round's counting
(per-file `Success:` lines summed; previous rounds' 2xxx figures use a
different tally — the Failed count is the comparable number).
Final: **0 Failed** (luacheck clean, 138 files); the +17 spec cases and
2 new spec files are this round's additions.

## Fixes (each with tests)

- **Every grant the Create Schema form generates was invalid SQL**
  (`db_browser/schema_create.lua`). `gen_grant` appended a fixed
  `IN SCHEMA <name>` tail for the `ALL TABLES/SEQUENCES/FUNCTIONS IN
  SCHEMA` choices — duplicating the object literal's own `IN SCHEMA`
  (`GRANT SELECT ON ALL TABLES IN SCHEMA IN SCHEMA "db" TO r;`) — and
  appended nothing for the `SCHEMA` choice (`GRANT SELECT ON SCHEMA TO
  r;`, no schema name at all). Both are syntax errors on every postgres
  server; `grant_usage` was the only correct branch. Every `on_object`
  choice ends exactly where the name goes, so the generator now appends
  the quoted name unconditionally. New
  `sql_db_browser_schema_create_spec.lua` drives the form contract
  (on_change SQL for each choice, on_validate, on_submit wiring, the
  non-postgres guard) — the module had zero test references before.
- **A complete non-result JSON line muted the session for life**
  (`session_conn.lua`). `on_session_stdout` kept the newline-less tail
  in the line buffer whenever it decoded as JSON but was not a result
  event, so a session that ever emitted such a line glued the stale
  text onto every later chunk and parsed nothing for the rest of its
  life — a mute session with no error anywhere. A complete JSON value
  is a complete message; one the viewer doesn't understand is now
  dropped. Incomplete tails are still kept until the rest arrives.
  `_test` gains `on_session_stdout`; the spec drives the assembler
  directly (junk-with-newline, partial-JSON tail, non-result tail).
- **`adapter.show` dropped its opts in the blink.cmp branch**
  (`completion/adapter.lua`). The docstring promised
  `{ force, trigger_kind }` handling, but the blink branch called
  `b.show()` bare. Today's autocmd calls were unharmed — blink's
  top-level `show` forces a manual trigger internally — but
  `providers` / `initial_selected_item_idx` / `callback` would have
  been swallowed for any future caller. New
  `completion_adapter_spec.lua` plants a fake blink in
  `package.loaded` and pins the pass-through, the
  `completion.trigger` fallback, and the no-blink no-ops.
- **Eight bound keys were invisible to `:PosteDbHelp`** (`config.lua`,
  `help.lua`). `yank_node` (y), `copy_tables` (p), `multi_select_toggle`
  (<Tab>), `multi_select_drop` (D), `multi_select_exit` (<Esc>) and
  `goto_definition` (gd) in the DB browser, plus `goto_definition` (gd)
  in the source buffer, lived only as `get_keymap` call-site defaults:
  bound and rebindable, but the help window walks
  `config.config.keymaps`, so it never listed them. Three more
  (`sql_dataset.ask_ai`, `sql_db_browser.ask_ai`, `sql_db_browser.help`)
  were bound yet had no description — help silently skips undescribed
  actions. All are now real config defaults with descriptions, and the
  new `help_spec.lua` pins the invariant: every bound action of a
  covered section must have a description, every described section must
  have a title, and the rendered lines must contain the section's
  bindings — the next undocumented keymap fails the suite instead of
  vanishing from help.

## Probed, held (recorded on purpose)

- **`db_create`'s Owner dropdown blocks the UI on a synchronous
  `pg_roles` query.** Opening the Create Database form on postgres runs
  `exec_run.run_sql(..., mode = "greedy")` inline (30 s timeout) before
  `forms_advanced.open`. On a healthy connection this is one fast
  introspection round-trip — acceptable; on a VPN or a hung server the
  browser freezes for up to 30 s with no feedback. An async populate
  (open the form immediately, fill the Owner select when the query
  answers) would fix it, but it needs a "field choices changed" hook in
  forms_advanced — recorded, not attempted this round.
- **`ops_sql.build_directive_lines` cursor lands one line past the
  insertion when there is no directive to write** (conn nil and no
  `meta.database`). The browser tree always sits under a connection, so
  the defensive path should be unreachable; left as is.
- `db_browser/flash.lua` — the CJK-aware one-line/truncate path, the
  timer/close lifecycle, and the `opened == false` cleanup all check
  out; no findings.
- `health.lua` — the `vim.health.start or report_start` shims, the
  parser-probe pcall, and the platform allowlist read fine; no findings.
- `dataset.lua` sort comparator — the nil/NIM ordering, numeric-string
  coercion (`^-?%d+%.?%d*$`), boolean ordering and the tostring
  fallback keep the comparator consistent (no `invalid order function`
  risk found); no findings.
- `insert_hint.lua` — recomputed `text_offset` against `full_text` by
  hand (the `get_lines(0, cursor_row)` exclusive end includes the
  cursor's row; the accumulator counts rows strictly before it): the
  offsets are right, including the documented newline-slot mapping in
  `to_buf_pos`. No findings.
- `import/execute`, `db_browser/copy`, `toml`, `ident`, `ops_sql` —
  hostile-input pass only; all were hardened in rounds 49-53 and no new
  hole surfaced.

## Not done and why

- **Testing `flash`/`health` window behavior.** Both are thin UI
  wrappers over `float_window`/`vim.health`; a spec would stub more
  than it verifies. The audit harness's dead-code rules were respected:
  both modules have production callers (`db_browser.notify`,
  `plugin/poste-db.lua`'s `:checkhealth` wiring).
- **Async Owner populate for `db_create`** — see the held item; it is a
  forms_advanced feature (choices refresh callback), not a one-line fix.
