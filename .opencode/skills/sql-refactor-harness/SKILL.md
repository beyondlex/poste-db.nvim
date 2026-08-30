---
name: sql-refactor-harness
description: >
  Minimal harness for refactoring SQL Lua modules without changing behavior.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
metadata:
  trigger: sql refactor|extract helper|module split|wrapper|magic string|magic constant|thin wrapper|behavior harness
---

# SQL Refactor Harness

Use this for small, reversible refactors.

## Rules

- Add/update the smallest regression test first.
- Extract one seam per diff: route, guard, formatter, or executor.
- Keep wrappers until all callers move.
- Use pure helpers for string assembly, target selection, and guard logic.
- Promote shared literals to `constants.lua` only when reused or public.
- Do not mix rename, move, and logic changes unless necessary.

## Delete the shell in the same effort

A refactor that leaves a husk behind is half done. When you extract a seam,
the old stub, dead parameter, no-op alias, and ceremonial call sites die in
the same commit series — do not defer them to "later cleanup". Historical
 husks this repo carried for months:

- `invalidate_sep_cache()` — an empty function with four ceremonial call sites
- `M.clear_panel(seq)` — a parameter the function ignored
- `context_client.lua` — a 173-line module with zero requirers
- `HEADER_LINES = 0` — threaded through 29 sites as a no-op subtraction

## Moving code between modules

- Enumerate the closure's captured upvalues first; turn them into an
  explicit deps table. Live module state (e.g. an execution sequence)
  passes as a getter, not a snapshot. Model: `lua/poste-db/sql_runner/response.lua`.
- Preserve the original's failure semantics per call site (sync flush vs
  scheduled flush vs skip-if-already-flushed) — pick one deliberately and
  record the delta if you unify them.

## Unifying duplicated helpers

Unification always picks one behavior. Enumerate every visible delta in
the commit message (output format, failure value, extra capabilities).
Past deltas worth recording: `format_bytes` kB vs KB rounding, a latent
callback hang fixed by adopting one flush semantics, a module gaining
user-override support it previously lacked.

## Lua traps (both bit this repo in one session)

- Demoting `M.x` to a local: every use must be lexically after the
  definition, or forward-declare `local x` first. `normalize_type` broke
  because `is_numeric_column` (line ~180) called it before its definition
  (line ~438). This is the AGENTS.md forward-declaration rule in a new
  disguise — the call site can be far from the definition.
- Never write `cond and f() or f` when `f()` may return nil/false: the
  expression falls back to the else branch. `theme.apply`'s spec evaluation
  passed a raw function to `nvim_set_hl` this way. Use explicit `if`.
- Check which requires a moved body actually used before pruning the
  donor module's requires — verify with a pattern that matches the real
  call shape (`D.T()` is `D\.T`, not `D\.\.`).

## Stub-covered modules

Adding a top-level `require` to a module that specs stub via
`package.loaded` (model: `tests/sql/sql_sql_runner_spec.lua`) means the
stub applies only if installed before the first require, and only to
eagerly-required modules. Do not force-load an un-stubbed module eagerly
into a stub-covered module — lazy-require it inside the function.

## Sequence

1. Capture behavior in a test.
2. Extract helper behind a wrapper.
3. Move one caller set.
4. Delete the wrapper after callers move.
5. Run `tests/run.sh`.
