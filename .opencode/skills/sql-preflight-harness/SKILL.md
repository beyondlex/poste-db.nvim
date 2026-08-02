---
name: sql-preflight-harness
description: >
  Short preflight checklist for SQL Lua changes. Use before editing code.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
metadata:
  trigger: preflight|checklist|before coding|design first|module boundary check|test first|change review
---

# SQL Preflight Harness

Use this before writing code.

## Check

- Smallest behavior to preserve?
- Which module owns it?
- Is it logic, state, UI, IO, or routing?
- Can I add a regression test first?
- Does it cross responsibilities or callers?
- Is there already a helper to reuse?

## Rules

- Split if responsibilities cross.
- Separate state from rendering.
- Share repeated guards.
- Put repeated literals in `constants.lua`.
- Skip splits that only make code shorter, not clearer.

## Result

Know the owning module, the test, the seam, and the next smallest diff.
