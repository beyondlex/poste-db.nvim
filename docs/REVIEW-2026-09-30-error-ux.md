# Code Review — 2026-09-30 (error UX)

Round 46, following `docs/REVIEW-2026-09-30.md`. Scope: a sweep of **error
handling and user-facing messaging** — how failures reach the user
(notify / flash / panel), whether error text is normalized on every path,
and whether the notify layer itself is consistent (levels, titles, style).

Baseline: 1918/0. Final: **1930 Success / 0 Failed / 0 Errors**
(luacheck 0 warnings / 0 errors). The +12 are the new regression specs.

Every claim below was verified by grep + read of the site before fixing
(sql-audit-harness rule); two subagent leads that verification disproved
are noted in "Corrected leads".

## Fixes (each with tests where the seam is testable)

### A. Error-normalization survivors (the round-45 family, continued)

`format.format_error` (format.lua:920) is the authoritative seam — it
normalizes non-strings and redacts DSNs — but four call sites still
handled raw `result.error` / `event.error` themselves:

- **`edit_commit/exec.lua` `collect_statement_errors` concatenated the
  raw error** (`"stmt " .. i .. ": " .. result.error`). JSON null
  decodes to the truthy `vim.NIL` userdata and `..` *raises* on it
  (verified in headless nvim); the raise was caught by
  `sql_runner/response.lua`'s outer pcall and shown to the user as the
  generic "SQL execution error" instead of the statement error. Now
  routed through `verdict.error_text`; a null error falls back to the
  `Unknown SQL error (has_error=true)` message.
- **`db_browser/util.lua` `run_ddl_and_refresh` collected raw errors and
  `table.concat`ed them** — same raise shape, not pcall-wrapped. Same
  fix.
- **`file_exec.lua` fed `event.error or "unknown error"` straight into
  `string.format("%s")`** — no crash, but the user saw the literal text
  "vim.NIL" (verified: `string.format("%s", vim.NIL)` renders it), and
  the notify bypassed `format_error`'s DSN redaction. Now normalized
  via `verdict.error_text` and passed through `log.redact_url` — a
  driver error that echoes its connection string can no longer leak the
  password into the dialog notify.
- **`session_conn.lua:139` forwarded the raw `event.error`** to
  `on_sql_error`, so `state.last_error.message` and the notify could be
  "vim.NIL" while the panel showed the normalized text — one event, two
  presentations. Now forwards `resp.results[1].error`, the text
  `build_response` already normalized.

### B. Fail-open failures

- **The commit path ignored `resolve_connection_url`'s error**
  (`edit_commit/init.lua`). A failed resolution (toml missing, renamed
  entry, unparsable) left `conn_url = nil`, and `exec_run.build_cmd`
  then sends no `--connection` — the binary commits the batch against
  its *own default connection*. The commit SQL is generated and carries
  no `@connection` directive belt (unlike import, whose chunks do —
  verified via the Rust `extract_connection_directive` note in
  `file_exec.lua:202-207`). Now fails closed: notify + refuse.
- **`log_viewer.clear_logs` always reported "SQL log cleared"**, even
  when `io.open(path, "w")` returned nil and the on-disk file survived.
  The in-memory view is still cleared; the notify now states the truth
  (INFO on success, WARN with the path otherwise).
- **`install.verify_checksum` silently returned true** when the checksum
  file was unavailable (download fail, unreadable, empty) — an
  unverified binary installed with no signal. The no-hasher path already
  warned; the other three skips now warn with the same wording. Install
  still proceeds (unchanged policy — the change is visibility).
- **A file run that died without a summary event was invisible**:
  `file_exec`'s `on_exit` journaled only, so the dialog just stopped
  while per-statement failures notified. Now reports on the same
  channel: "SQL file run failed: exit code N (no summary event)".

### C. Channel consistency

- **`db_browser/operations.lua` reported a DDL fetch failure as a
  blocking `vim.notify` ERROR while the sibling `actions.lua` reports
  the same class of fetch failure through the non-blocking flash WARN**
  (the module's own facade, `db_browser/notify.lua`). Aligned to flash
  WARN; the journal keeps the reason either way.
- **The same SQL failure notified only on the session transport**:
  session `on_sql_error` routed into `handle_error`, which notifies;
  the exec-file path (single or multi) renders panel + ✘ indicator and
  never notifies. `handle_error`'s notify is now transport-only — a
  table `parsed` is the session's per-statement SQL error (the only
  shape that passes one), and SQL failures report through the panel on
  both transports; nil/string `parsed` (binary missing, refused start,
  dead session, non-zero exit) still notifies.

### D. Notify style

- **119 of 202 `vim.notify` calls were anonymous** — no `title` opt and
  no self-identifying message prefix, so under nvim-notify/fidget-style
  replacements the message shows no origin. All of them now pass
  `{ title = "PosteDb" }` (117 mechanical + 3 introduced by this
  round's new notifies): final state **0 anonymous, 177 titled, 38
  self-prefixed** (`install.lua`'s `[Poste] …` family keeps its prefix
  convention and no title; `db_browser`'s flash facade needs none).
  Levels were already explicit on every call — no missing-level fixes
  needed.
- **`completion/data.lua` sent a DEBUG trace at ERROR level** — a debug
  notify pages every notify UI as if a failure happened. Now INFO.
- **`exec_run`'s no-summary failure said "exit code 0"** — a success
  code reported as the failure. Now "exec-file exit code N (no summary
  event)", matching `file_exec`'s journal wording.

## Not done, and why

- **Blocking INFO/WARN outside db_browser** (~15 files: commands,
  connections, import, export, editor/nav, buffer/nav, introspect K…).
  The flash facade is `db_browser`-scoped; promoting it to a shared
  module and migrating that many call sites is a UX-behavior change
  (blocking → auto-dismiss) that deserves its own round and probably a
  config knob. Recorded as the follow-up.
- **The `pcall(json.decode) → if ok then data = d end` stale-data
  family** (`buffer/init.lua:626`, `db_browser/actions.lua:233`,
  `ai/actions.lua:157`, `sql_runner/response.lua:105`): decode failure
  keeps nil/stale data silently. Deliberate tolerance with a cache-like
  contract; a uniform "log one line on decode failure" would touch all
  consumers for marginal value. Left as-is.
- **`jobstart` return values unchecked** at `completion/data.lua:325`
  and `db_browser/copy.lua:60`: the missing-binary case is already
  guarded upstream (`resolve_fetch_target` flushes), leaving only the
  -1-without-callback corner. Narrow; noted for the next touch.
- **Read-only `resolve_connection_url` err discards** (`explain.lua:162`,
  `editor/column.lua:131`, `edit_commit/init.lua:84`, `import/execute.lua:101`):
  wrong-target risk on reads is acceptable and import has the directive
  belt; only the commit path needed fail-closed.

## Corrected leads (verification over hearsay)

- The Explore sweep claimed an all-events-undecodable exec-file run
  "renders as a normal empty result". False: `exec_run`'s no-summary
  contract (`exec_run.lua:529-533`) delivers `on_error` — the real issue
  was only the misleading "exit code 0" wording (fixed above).
- "Silent completion hang" from unchecked `jobstart` was overstated:
  `resolve_fetch_target` (completion/data.lua:307-315) already flushes
  queued callbacks when binary/url resolution fails.

## Observation recorded, not fixed

`session_conn.M.get` computes its pool key from the raw `database`
argument but `start()` infers the database from the URL when nil — so
`get(conn, nil, nil)` stores under `conn\0<inferred>` while
`execute(conn, sql, cbs)` (database=nil) looks up `conn\0` and starts a
*second* session for the same connection. Surfaced while writing the
session spec; harmless in production today (executor always passes a
resolved database string), but the key should be computed after
inference if sessions ever multiply.

## Synced

- LEARNINGS.md: the notify-rewrite incident (two corrupted passes before
  the lexer script was right) is recorded as a new entry.
