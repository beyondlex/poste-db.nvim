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

## Check before touching anything

- `git status` first. Uncommitted user WIP gets committed separately
  before refactor batches start — never mix your diff with theirs.
  (Watch for new user edits appearing mid-session too.)
- Is the claim you are acting on verified by you, or relayed from an
  audit? Relay = stop, verify first (see sql-audit-harness).
- Does the module under edit have stub-based specs that intercept
  `package.loaded` before require? Then new top-level requires change
  what the stubs capture.

## Rules

- Split if responsibilities cross.
- Separate state from rendering.
- Share repeated guards.
- Put repeated literals in `constants.lua`.
- Skip splits that only make code shorter, not clearer.
- Deleting code requires a grep pattern you have eyeballed AND a green
  full-suite run afterward.

## Result

Know the owning module, the test, the seam, and the next smallest diff.
