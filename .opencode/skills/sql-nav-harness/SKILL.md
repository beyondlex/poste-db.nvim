---
name: sql-nav-harness
description: >
  Harness for dataset navigation and raw mode refactors.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
metadata:
  trigger: buffer_nav|winbar|raw mode|preview_cell|yank|sort|cell focus|dataset guard|resultset guard
---

# SQL Navigation Harness

Use when navigation code mixes state, UI, and buffer logic.

## Rules

- `buffer/nav_state.lua` owns `D.T()` / window / resultset guards.
- `buffer/nav_ui.lua` owns winbar / label assembly.
- `buffer/nav_raw.lua` owns raw mode lifecycle.
- Keep `focus_cell()` small and shared.
- Prefer one guard helper over repeated `if not tab ...`.
- Formatting helpers should not touch global state.

## Common Splits

- `focus_cell()` for `move_cell()` and `goto_*`.
- `get_resultset_data_tab()` for preview / yank / sort.
- `build_status_winbar_text()` for winbar assembly.
- `toggle()` in raw mode module, with `buffer/nav.lua` forwarding.
