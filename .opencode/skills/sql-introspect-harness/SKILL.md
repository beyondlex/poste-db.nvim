---
name: sql-introspect-harness
description: >
  Harness for introspection routing refactors.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
metadata:
  trigger: introspect|show_table_ddl|context detect|ddl|float window|route|target|job wrapper
---

# SQL Introspect Harness

Use this when introspection code is drifting into a monolith.

## Rules

- Split entry into route, detect payload, target mapping, and action/UI.
- Keep `introspect_route.lua`, `introspect_detect.lua`, and
  `introspect_target.lua` pure where possible.
- Keep jobs in `introspect_exec.lua` and rendering in `introspect_ui.lua`.
- Do not mix shell construction, JSON parsing, and float rendering in one
  function unless the file is already a thin wrapper.
- Add tests for each layer before touching `show_table_ddl()`.

## Safe Sequence

1. Write the route/detect/target test.
2. Extract one pure helper.
3. Move only the matching branch or call site.
4. Keep the entry as orchestration only.
5. Re-run `tests/run.sh`.
