---
name: sql-test-harness
description: >
  Test-first harness for SQL Lua changes. Use when adding or hardening tests.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
metadata:
  trigger: test first|regression test|behavior spec|harness tests|characterization test|cover a seam|proof before refactor
---

# SQL Test Harness

Use this to protect behavior before changing code.

## Rules

- Add the smallest regression test that captures the behavior.
- Prefer a characterization test before a risky refactor.
- Test one seam at a time.
- Assert observable results, not internals.
- Test the lowest stable layer first when bugs span layers.
- Keep fixtures small; use literals when enough.

## Sequence

1. Describe current behavior in a test.
2. Run it to confirm the risk.
3. Change the code.
4. Re-run the seam test plus nearby suite.
5. Keep the test if it guards a real boundary.
