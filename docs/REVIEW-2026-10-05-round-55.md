# Code Review — 2026-10-05, round 55

Round 55, following round 54 (`docs/REVIEW-2026-10-05-round-54.md`). Scope:
implementing round 54's recorded held item (the async Owner populate for
`db_create`), then a hostile-input + smell ring over modules the recent
rounds had not deep-read: `db_browser/catalog`, `db_browser/tree`,
`db_browser/forms`, `dml_guard`, `tunnel`, `db_browser/copy_ddl`,
`db_browser/ops_sql`, `verdict`, plus a perf look at the dataset render
path (`format.lua`) and the log viewer's load path.

Baseline: 2038 Success / 0 Failed. Final: **2069 Success / 0 Failed**
(luacheck clean, 267 files); +31 spec cases across 2 new spec files
(`sql_db_browser_db_create`, `sql_db_browser_forms_width`) and 5 extended
files (`sql_db_browser_catalog`, `sql_db_browser_forms`,
`sql_db_browser_copy_ddl`, `sql_dml_guard`, `sql_tunnel`, `sql_verdict`).

## Feature (round 54's held item, now done)

- **The Create Database Owner list fills asynchronously**
  (`db_browser/db_create.lua`, `db_browser/forms_advanced.lua`). Opening
  the form on postgres used to run the `pg_roles` query synchronously
  inside `open()` — one fast round-trip on a healthy connection, up to
  the 30 s exec timeout of frozen UI on a VPN or a hung server.
  `forms_advanced.open` now returns a handle whose `set_choices(key,
  choices)` writes a field's choices after the fact and redraws; the
  handle no-ops once the form is closed, so a late response can never
  touch dead buffers. `db_create` opens the form immediately with empty
  Owner choices and fills them from `run_async`'s response. Two smaller
  things came with it: `extract_roles` reads `resp.results` directly
  (the legacy-shaped response already carries decoded results — the old
  `fetch_roles` re-decoded `resp.body` for nothing), and a null `rolname`
  (`vim.NIL`) is named out so it cannot reach the picker as literal text.
  Failure stays silent, matching the old nil answer. New
  `sql_db_browser_db_create_spec.lua` drives the contract: form opens
  before any round-trip, query over the resolved URL, fill from rows
  (multi-result, vim.NIL, empty/failed/closed-form cases), no query when
  the connection does not resolve, and the mysql/sqlite guards.

## Fixes (each with tests, each reproduced before the fix)

- **A quoted view name containing " as " broke the copy/paste header
  split** (`db_browser/catalog.lua`). `view_body_from_ddl` scanned for
  the header's ` AS ` with a plain `%sas%s` pattern; `CREATE VIEW
  "my as view" AS SELECT 1` (legal in every dialect) matched inside the
  name and split the header in half — the paste engine received
  `view" AS SELECT 1` as the view body. The scan now walks the text once
  and only accepts ` as ` outside any quoted segment (`'…'`, `"…"`,
  `` `…` ``), doubled quotes staying inside (`find_as_outside_quotes`,
  pure and exported for the spec). Reproduced: the old code returned
  `view" AS SELECT 1` for the input above.
- **MySQL trigger DDL emitted un-doubled backticks**
  (`db_browser/catalog.lua`). `compose_trigger_sql` interpolated the
  trigger and table names bare: a name `a\`b` arrives from
  information_schema already escaped as `a\`\`b`, and the composer both
  produced a syntax error (`` `a`b` ``) and unwrapped the name. The names
  go through `esc_backtick` like every other MySQL identifier in the
  module.
- **An IPv6 literal database host broke the ssh forward spec**
  (`tunnel.lua`). `forward_arg` built `127.0.0.1:PORT:::1:5432` for
  `host = "::1"` — ssh reads the address groups as extra host:port
  fields and the forward points somewhere else. Hosts containing `:` are
  bracketed now; an already-bracketed host passes through unchanged.
- **A null `failed` flag read as a failure with no explanation**
  (`verdict.lua`). `classify` tested `result.failed` by truthiness and
  JSON null decodes to the truthy `vim.NIL`; an envelope carrying
  `"failed": null` would report a failure and show
  `UNEXPLAINED_FAILURE`. Every real producer writes exactly `true` or
  omits the flag, so the check is a strict inequality now.
- **`dml_guard.confirm_message({})` produced a nonsense question**
  (`dml_guard.lua`). "SQL contains 0 statement(s) without a WHERE clause
  ()" — unreachable from the only caller (it gates on `#risky > 0`),
  but the API is exported; it answers with a sentence now.

## Refactors (behavior-preserving, suite green after each)

- **`db_browser/tree.lua`** — `scan_prefix` owns the "first non-space
  byte + is it a 3-byte tree marker" scan that `calc_icon_position` and
  `apply_highlights` each carried; the marker list lives in one place
  now, so icon highlighting and cursor positioning cannot drift apart.
- **`db_browser/forms.lua`** — the float width was computed twice (once
  by `calc_size` for the geometry, once by `render_form` for the border
  art); `calc_width` owns the number and a first `_test` seam pins it
  (`sql_db_browser_forms_width_spec.lua`). The `vim.ui.select` closure
  was written verbatim twice (Enter on a select row, the `t` key);
  `pick_select` is that one closure.
- **`db_browser/copy_ddl.lua`** — `rename_routine_in_def`'s MySQL
  first-backtick-pair loop could only ever examine ONE candidate (every
  branch returned or nil-ed the loop variable), was byte-for-byte
  equivalent to the plain-find fallback below it, and its comment
  contradicted its `break`. The fallback is the whole behavior now; new
  tests pin the name-before-body precedence, the doubled-backtick
  limitation (name with a backtick stays unrenamed, surfacing in the
  summary), and the schema-qualified postgres shape.
- **`db_browser/ops_sql.lua`** — `sp_rename`'s local `lit` helper
  re-spelled `ident.quote_literal(v, "mssql")`; apostrophe doubling is
  one fact and lives in ident once.

## Probed, held (recorded on purpose)

- **`format.lua` plans the layout with a full scan of every row.**
  `plan_resultset_layout` runs `cell_to_string` + display width over all
  rows (`--max-rows 0` = unlimited) so pagination totals and column
  widths are exact; a 100k-row result pays one O(rows×cols) pass, and
  `is_numeric_column` walks the rows a second time. Merging the passes
  or sampling for widths would change rendered output the specs pin, and
  the pass is Lua-fast per cell — recorded, not worth the churn.
- **`tree.apply_highlights` fetches buffer lines one at a time.** One
  `nvim_buf_get_lines` call per rendered node; browsers are hundreds of
  nodes and renders are user-paced, so the win is small against the
  risk of touching a hardened function. Recorded.
- **`tunnel.ensure` waits the full 5 s when ssh hangs on auth.** Without
  a TTY a password prompt cannot succeed anyway; `-o BatchMode=yes`
  would fail fast but changes the story for hosts that auth by agent or
  other means. The current 5 s-and-stderr failure is defensible.
- `dml_guard` regex_scan hostile pass — CTE-chained DELETE, subquery-only
  WHERE, parens-wrapped WHERE, dollar-quoted bodies hiding a DELETE, both
  backslash readings, `ON UPDATE CASCADE`, bare `DELETE`, no-semicolon
  batches: all flag or hold exactly as documented (over-flag bias).
  `TRUNCATE` remains out of scope per round 09-24's explicit ruling.
- `log_viewer.load_entries` decodes the whole journal synchronously, but
  the writer trims the file to `LOG_MAX_ENTRIES` (1000) every
  `LOG_TRIM_EVERY` writes — the read is bounded and fast. No change.
- `verdict.lua`, `db_browser/catalog` async collectors (`enumerate`
  finished-guard, `sizes` tolerance), `ops_sql` dialect spellings — no
  findings beyond the recorded items.

## Not done and why

- **Sampling column widths on huge results** — see the held item; it is
  a rendering-contract change, not a fix.
- **`log_viewer` incremental load** — the journal is capped by its
  writer; nothing to gain.

## Housekeeping note

One self-inflicted slip this round, caught by the suite: the extracted
`find_as_outside_quotes` was defined *after* its first caller in
`catalog.lua`, which is exactly the local forward-declaration pitfall
AGENTS.md documents — the call resolved to a global nil. Definition
moved above the use; no code change needed, ordering did.
