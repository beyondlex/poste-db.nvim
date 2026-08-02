---
name: sql-architecture-harness
description: >
  General harness for keeping SQL Lua code modular, readable, and easy to
  extend. Use when designing new code or when code starts turning into
  spaghetti, nested branching, or mixed responsibilities.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
metadata:
  trigger: spaghetti|modular|modularity|architecture|refactor structure|nested branches|mixed responsibilities|thin wrapper|pure helper|module boundary|design new code|new feature structure
---

# SQL Architecture Harness

Use this when code shape matters more than the feature.

## Rules

- One module, one job.
- Entry functions should orchestrate, not do everything.
- Keep pure logic away from IO, UI, and global state.
- Split by responsibility, not by line count.
- Turn repeated guards into a shared helper or state module.
- Keep wrappers thin until callers move.
- Avoid another `if` inside already complex code.

## Pattern

1. Find the stable seam.
2. Extract the pure part first.
3. Move one branch or call site.
4. Keep the old entry as a wrapper.
5. Add/update a regression test.
6. Remove the wrapper when callers migrate.

## Smells

- Deep nested `if` / `elseif`.
- UI + command execution + state mutation in one file.
- Repeated `D.T()` / guard checks.
- Large top-to-bottom functions.
