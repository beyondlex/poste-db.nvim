# Code Review — 2026-10-03 (round 50)

Round 50, following `docs/REVIEW-2026-10-03.md` (round 49, same day).
Scope: two sweeps the earlier rounds' per-module passes could not see —
**every place `vim.fn` RAISES instead of returning** (`jobstart` /
`vim.fn.system` on a vanished argv[0]) and **every place a present-but-
wrong-typed config field silently defaults** (`tonumber(x) or 22`) —
plus the quoted-key probe against the TOML parser and a re-read of the
round-49-adjacent small modules (`flash`, `compat`, `health`,
`statement`, `semantic_diagnostics`).

Baseline: 2088 plenary Success lines / 0 Failed (the summary block only
counts the last file; the real count is the Success-line count).
Final: **2099 / 0** (luacheck clean). The +11 are this round's
regression specs.

## Fixes (each with tests)

- **The TOML `=` splitter reads quotes** (`toml.lua`, 2216036). Three
  probes, one theme — a quoted key's own characters reaching the
  line-splitting logic:
  - `"a=b" = 1` (legal TOML) was cut at the quote-inner `=` by the plain
    find and stored the mangled halves (`"a` = `b" = 1`) with no error —
    silent corruption of whatever the consumer looked up. The line split
    and the inline-table pair split now scan for the first `=` outside
    any quote (a basic string's `\\` skip covers `"a\"b"`; an
    unterminated quote fails closed as an invalid line/entry).
  - The inline-table key's own parse error was never checked: the entry
    landed under `tostring(nil)`. Both halves now fail closed.
  - `["x"] # comment` died as `Invalid table header` — the quoted
    path's tail check ended two chars short of EOL, so the closing `]`
    landed in the tail. The quoted path now applies the unquoted path's
    rule: `]` may carry whitespace and a comment, nothing else.
- **`cli.run_async` survives `jobstart` raising E475** (`cli.lua`,
  c66a9ed). `jobstart` does not report a bad argv[0] — it RAISES
  `Vim:E475` ("is not executable"; probed). The lookup ran a moment
  earlier, but the binary can vanish in between (a reinstall
  mid-session, a stale `g:poste_binary`), and the uncaught throw would
  skip every on_error/on_exit and leave the caller's spinner running
  for the rest of the session. The throw now answers with the same
  synthesized `on_exit(-1)` + nil the binary-missing path uses, which
  `async.run` already routes to its failure branch.
  `semantic_diagnostics.run_introspect` pcalls the same call for the
  same reason — this closes the copy that was not pcall'd. First spec
  for the module.
- **`install.lua` reports a missing curl instead of crashing plugin
  load** (10884e5). `vim.fn.system` raises the same E475 (probed), and
  both curl calls sit on the setup() path via `ensure()`: a box without
  curl crashed plugin LOAD where health.lua's own warning promises
  "auto-download will fail". The download reports "curl is not
  available on PATH"; the checksum fetch routes to the existing
  skipped-verification warn.
- **`tunnel.normalize_cfg` fails closed on a non-numeric string port**
  (`tunnel.lua`, aea0e41). `tonumber(v.port) or 22` sent the typo
  `port = "22a"` to ssh's default port 22 — a different ssh endpoint
  than the one configured. `ensure` already failed closed for a
  non-numeric database port; the ssh port now does too.

## Probed, held (recorded on purpose)

- **`statement.extract_table_name` misses a table when a `--` sits
  inside a single-quoted literal** — comments are stripped before
  strings are blanked, so `SELECT 'a--b' FROM t` loses the FROM and
  returns nil ("result n" label). Removing text cannot fabricate a FROM
  token, so there is no wrong-table risk — only a conservative miss.
  Fixing it means making the comment strip string-aware; held until a
  real query trips over it.
- **The dotenv mirror is not drift** — Lua's `parse_dotenv`
  pre-substitutes `{{VAR}}` inside `.env` values while Rust's stores
  them raw, but the Rust substitution at the use site iterates to a
  fixed point (cap 10, same as Lua's depth cap), so a `{{BASE}}` inside
  a `.env` value resolves to the same URL on both sides. Verified by
  reading both implementations; the parity test in
  `sql_connection.rs` (`store_loads_toml_and_resolves_the_same_urls_as_lua`)
  pins the URL surface.
- `install.lua`'s tar/powershell/chmod `vim.fn.system` calls are not
  pcall'd — all three are platform-guaranteed on the branches that
  reach them, and the post-extraction `filereadable` check catches the
  archive-content failures.
- `db_browser/flash.lua`, `compat.lua`, `health.lua` — read, no issues.
  `flash.one_line` truncates in display cells (CJK-safe);
  `compat.opt` errors on unsupported keys; `health.check` reports the
  binary *source*, the actionable half of the five-candidate walk.
- `semantic_diagnostics.lua` — read-only pass; the settle-once
  introspect callback and the digit-fragment merge are correct as
  documented.

## Docs

- doc-poste `poste-db-dev/connection-resolution.mdx`: the TOML dialect
  table gains the shapes this round settled — a quoted key/inline-table
  key may carry its own `=`, a quoted header accepts a trailing
  comment, and an unterminated quote in a key=value line fails closed.
