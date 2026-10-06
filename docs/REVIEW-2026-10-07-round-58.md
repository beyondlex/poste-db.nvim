# Code Review — 2026-10-07 (round 58)

Round 58, following `REVIEW-2026-10-07.md` (round 57, earlier the same
day). Scope: cross-repo parity — the same adversarial pass ran through
poste-redis.nvim and the poste.nvim Rust workspace this round, and this
repo's vendored copies were re-diffed against their poste-redis
counterparts (the vendor-pin drift class the family reviews keep
recording), then the confirm-gate engines (`dml_guard`, `ai/actions`,
`explain`) were probed with dialect-mismatched quoting.

Baseline entering the round: **2098 Success / 0 Failed** (post-round-57
tree). Final tally: **2103 / 0 / 0**, luacheck clean on the touched files.

## Bugs fixed

1. **chansend throws on a dead channel — both write paths were unguarded**
   (`cli.lua`, `session_conn.lua`, commits `286371b`). Measured against
   the real contract: `vim.fn.chansend` raises `E900` on an invalid
   channel id and "Can't send data to closed stream" on a closed stdin —
   the `sent <= 0` checks never see those failures, the throw happens
   first. The SQL session write skipped the pending cleanup and the
   caller's on_error (the request looked dispatched to everyone), and the
   stdin write inside `cli.run_async` propagated past every callback.
   Both writes are now pcall'd into the existing failure handling. Pinned
   by a dead-channel spec on each path. This is the mirror of the
   poste-redis fix from the same round; the copies had already drifted
   exactly as the vendor-pin smell predicts.

2. **Unbalanced inline brackets stored garbage silently** (`toml.lua`,
   commit `a151230`). `ips = [1]2]` ends in `]` so the unclosed-array
   check passes, and `split_top` kept every closer it consumed: the
   config stored the string `"1]2"` with no error anywhere. The parser's
   own documented policy is fail-closed on container typos (double
   commas, missing halves); an unbalanced container now errors the same
   way. Pinned by three specs; mirrored into poste-redis's vendored copy.

3. **The confirm gates read SQL under one quote-escape reading**
   (`ai/actions.lua`, `explain.lua`, commit `2c12b63`). The readings
   disagree about where a literal ends — postgres (and SQLite) close
   `'C:\path\'` at the final quote, the backslash reading escapes it —
   and `is_readonly` (the AI codeblock gate) and `wrap_sql`'s
   single-statement refusal each stripped under one reading only. The
   wrong reading parks the `;DROP TABLE` / `;SELECT 2` that follows inside
   a phantom literal: the AI gate ran a destructive block unconfirmed,
   and EXPLAIN accepted multi-statement text it would explain (at best)
   only the first statement of. `dml_guard.regex_scan` already unions
   both readings under its documented "over-flag, never under" rule; both
   gates now scan the same way. Pinned by the trailing-backslash specs in
   `ai_actions_spec` and `sql_explain_spec`.

## Probed, held (recorded on purpose)

- `dml_guard.regex_scan` flags only DELETE/UPDATE (the missing-WHERE
  class); TRUNCATE and DROP have no WHERE to demand, so their absence is
  the design, not a gap — the AI gate's `READONLY_KINDS` catches them on
  its side. Recorded so a future round does not re-litigate it.
- `dml_guard.strip_non_code` under one reading still mangles
  cross-dialect text (an `E'\''` eats `FROM t` under the standard
  reading); every DECISION caller (`regex_scan`, and now both gates)
  runs both readings, so no decision sees the mangle. The strip output
  itself is never executed.
- `ident.quote_qualified('a..b', nil)` reads as schema `"a..b"` +
  empty table — a probe artifact, not a bug: the signature is
  `(schema, table_name, dialect)`, and `quote("")` returns `""` by
  contract.
- `tunnel.normalize_cfg` rejects every degenerate shape with a named
  error (`{ to = "" }`, numeric `to`, `"22a"` port, non-string key);
  unknown extra fields pass through untouched (deliberate tolerance).

## Family parity state after this round

- `toml.lua` / `cli.lua` / `session_conn.lua` / `util.lua` truncate:
  both siblings fixed in lockstep; the tail-diff check stays the guard.
- poste.nvim (Rust) got the hostile-offset hardening for
  `context detect` (a mid-UTF-8 cursor offset panicked the subcommand);
  the Lua callers always send boundary offsets today, the clamp is
  defense in depth on the wire.
