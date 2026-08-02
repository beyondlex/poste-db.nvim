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

## Sequence

1. Capture behavior in a test.
2. Extract helper behind a wrapper.
3. Move one caller set.
4. Delete the wrapper after callers move.
5. Run `tests/run.sh`.
