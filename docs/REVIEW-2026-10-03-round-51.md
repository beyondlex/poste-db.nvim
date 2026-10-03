# Code Review — 2026-10-03 (round 51)

Round 51, following `docs/REVIEW-2026-10-03-round-50.md` (same day).
Scope: the one sweep the earlier rounds' per-module passes kept circling
but never closed — **every lexical scan that decides where a SQL region
ends** (`;`-scans, keyword probes, literal blankers) — plus the four
`jobstart` doors round 50's E475 fix left one door over, three un-pcall'd
`vim.fn.mkdir` calls, and adversarial-data passes over `export`,
`import/`, `dml`, `dataset` (sort comparator), `search`, `editor/cell`,
`ident`, `width` (perf).

Baseline: 2099 plenary Success lines / 0 Failed.
Final: **2123 / 0** (luacheck clean, 137 files). The +24 are this
round's regression specs; three KNOWN-BUG `pending`s became assertions.

## The theme: one region-aware scanner instead of four blind ones

Four modules each carried a private, comment/string-blind scan. Every
one of them mistook a `;`, `--` or `JOIN` inside a literal / comment /
dollar-quote for code — four symptoms, one root cause. `lex.lua` now
owns the fix: `lex.blank_regions(sql, keep_quoted_idents)` is a single
length- and newline-preserving state machine (single-quoted literals
with `''` escapes, `--`/`/* */` comments, `$$ … $$` bodies blanked;
double-quoted/backtick regions blanked for the `;`-scan, kept verbatim
as identifiers for the name captures). A gsub chain cannot get both
orders right — stripping comments first lets `'a--b'` swallow the FROM,
blanking literals first lets the apostrophe in `-- don't` open a phantom
literal. `dml_guard.strip_non_code` keeps its own scanner on purpose:
it runs BOTH backslash readings (a confirm gate must over-flag), which
the labeling scans must not.

- **`statement.lua`** (58027c3). The round-50 held probe
  (`SELECT 'a--b' FROM t` losing its table name) is fixed. Bigger
  payoff: `find_stmt_lines` and the `extract_stmt_at_cursor` Lua
  fallback were blind `line:match(";")` scans — a `;` inside a literal
  or comment split a multi-line statement, the visual-selection map
  misaligned results/indicators/table names, and the fallback (the only
  splitter left without tree-sitter or the binary) sent the truncated
  head off to execute a syntax error. `blank_single_quoted` is gone
  (grep: zero remaining refs, suite green).
- **`editor/cell.lua`** (a298b07). `has_join`'s gsub literal-blanker
  knew nothing of comments: `SELECT * FROM events -- join of a and b`
  answered true and the live edit guard refused the dataset's cells
  with a bogus multi-table warning; a `$$body$$`'s internal JOIN
  counted the same way.
- **`exec_run.lua`** (b9496c0). `strip_literals_and_comments` closed a
  literal blank at `'it''s` second quote — `update t set note = 'it''s
  RETURNING x'` leaked its tail and flipped an UPDATE into a query for
  the legacy-response tie-break; dollar bodies counted too.

## Fixes (each with tests)

- **The other three `jobstart` E475 doors** (4170b27). Round 50 fixed
  `cli.run_async`; the raise (argv[0] vanished between the binary
  lookup and the spawn) escaped four sibling call sites:
  - `file_exec`: skipped the `job_id <= 0` branch — progress dialog
    spun with `S.is_running` stuck true for the session. The raise now
    lands in that branch (notify, journal, flag reset; a second run
    reaches jobstart again).
  - `session_conn`: escaped `M.get` into the executor's caller instead
    of the `"start_failed"` answer every other start failure gives.
  - `completion/data start_introspect_job`: escaped into whatever
    triggered the fetch and the queued callbacks hung forever; it now
    flushes with the exit default (what a dead job's `on_exit` does).
  - `db_browser/copy introspect_ddl`: escaped the context-menu action;
    it now answers through the same `on_error` a dead job reports.
- **Three un-pcall'd `vim.fn.mkdir` calls** (4170b27, 3efe5c0).
  `mkdir` raises E739 on a permission wall / read-only dir (probed):
  `install.lua` reported its curl calls (round 50) but still crashed
  plugin load on the directory two lines later — now reports and fails
  the install; `sql_log.get_log_path` and `log_viewer.clear_logs`
  degrade to the `io.open` failure they already handle instead of
  killing the execution path that asked for a log line.
- **`export.lua`** (3efe5c0). `export_to_file` pcall'd the formatter
  and the write but not the `mkdir` above them; `:PosteDbExport xml
  clipboard` surfaced as "attempt to call a nil value" from the
  formatter dispatch — unknown formats are now rejected up front with
  the legal set. And `format_markdown` left newlines in a cell raw —
  the pipe-table row split and every row below stopped being a row;
  cells now render `\r\n?` as `<br>` (GitHub-markdown convention), the
  same record-structure break `csv_escape` quotes and TSV flattens.

## Performance

- **`width.truncate`** (c8dad65) evaluated `width_mode()` — a pcall'd
  require plus config lookups — once per *character* inside its loop,
  with a fresh `vim.fn.strdisplaywidth` field lookup beside it; the
  function runs per rendered cell. Both hoist above the loop; the mode
  cannot change mid-string, so semantics are identical.

## Read, held (recorded on purpose)

- **`dataset.compute_view_indices` comparator** — nil sinks last,
  numeric strings coerce, boolean branch, tostring fallback: no
  inconsistent triangle (a NaN cell cannot arrive — serde_json rejects
  it), so no `invalid order function` risk found.
- **`editor/cell.parse_value`** — `"0"` reaches numberhood via the JSON
  path, `"007"` deliberately stays text (leading zeros are data; a
  quoted `'007'` coerces server-side). The `''`-escape reading stays
  postgres-flavored here, dialect-blind on purpose — the dialect
  readings live on the Rust side and in dml_guard's both-readings scan.
- **`dml.generate_insert` drops a cell whose string is exactly
  `"[Auto]"`** — the add-row form uses that marker for auto-increment
  columns, so a user wanting the literal text `"[Auto]"` in a varchar
  gets it silently omitted. The marker never collides with real data in
  practice (it is typed only by the form); held until a real case.
- **`lex.is_comment_or_string` treats `\` as an escape inside ALL quote
  styles, `lex.block_comment_depth_after` excludes backticks** — two
  heuristics for two callers (USE-line vs comment-depth), divergence
  only reachable via a backslash inside a quoted identifier on a USE
  line. Cosmetic; held.
- **`import/` is clean** — `mapping.coerce_value` keeps `007` text,
  gates booleans to boolean columns, bounds doubles at 2^53;
  `format.parse_csv` is RFC-4180-shaped (mid-field quote is data,
  rectangularity enforced, duplicate headers fail closed);
  `execute.lua` chunking clamps its user config. `col_type` is nil-safe
  end to end (`import.lua` defaults it to "TEXT").

## Docs

- doc-poste `poste-db/export-import.mdx`: the `md` format's `<br>`
  newline rendering; directory auto-creation reports on failure; unknown
  formats name the legal set.
- doc-poste `poste-db-dev/execution-pipeline.mdx`: the Lua-side
  labeling scan (visual selection, no-parser fallback) is region-aware
  now — same reading as the Rust splitter, one scanner (`lex.blank_regions`)
  shared with the table-name extraction and the JOIN probe.
