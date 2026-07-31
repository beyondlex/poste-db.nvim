# Code Review Report: poste-sql.nvim

**Date**: 2026-07-31
**Scope**: All Lua source files (~35K lines, 64 files)
**Focus**: Code smells, duplication, magic numbers, encapsulation, modularity

---

## Executive Summary

The codebase is **well-structured at the module level** — clear separation of concerns (completion, format, buffer, editor, db_browser, etc.) and good use of shared infrastructure from `poste.nvim`. However, individual modules have grown too large, contain significant duplicated code, and mix multiple responsibilities. The most critical issues are: (1) ~200 lines of identical header extraction code in `buffer.lua`, (2) duplicated UTF-8 character walking across 3 modules, (3) ~30+ magic numbers, and (4) deeply nested control flow in `nav.lua`.

---

## 1. Duplicate Code (Critical)

### 1.1 Header Extraction Duplication (`buffer.lua:286-318` vs `buffer.lua:509-541`)

**Locations**: `buffer.lua` — `apply_rendered_page()` lines 286-318 and `render_dataset()` legacy path lines 509-541

**Problem**: Two almost identical blocks that:
- Extract header line from `clean` array
- Apply sort indicator (↑/↓) to header text
- Build `header_index` via `build_header_index()`
- Remove header/delimiter rows from `clean`
- Adjust `meta.data_start_line` and `meta.data_end_line`
- Pad all lines with `PADDING_SPACES`
- Insert empty line at top if header exists

**Fix**: Extract into a shared function like `extract_and_pad_header(clean, meta, tab)`.

### 1.2 UTF-8 Character Walking (`highlights.lua`, `buffer_nav.lua`, `format.lua`)

**Locations**:
- `highlights.lua:382-396` — `find_cell_range_scan()` scans │ separators
- `highlights.lua:433-454` — `find_cell_ranges_fallback()` scans │ separators (same logic, returns target+last)
- `buffer_nav.lua:58-88` — `build_header_index()` walks UTF-8 bytes
- `buffer_nav.lua:43-56` — `trunc_disp()` walks UTF-8 bytes
- `format.lua:39-52` — `truncate_to_displaywidth()` walks UTF-8 bytes

**Problem**: The │ separator scanning logic in `find_cell_range_scan` and `find_cell_ranges_fallback` is nearly identical. The UTF-8 byte-length calculation (`b < 128 and 1 or b < 224 and 2 or ...`) is repeated in at least 3 modules.

**Fix**: Extract to `poste.util` or a new `poste-sql.util` module:
- `util.find_separators(line, sep)` — find all │ positions
- `util.utf8_char_bytes(byte)` — get UTF-8 char byte length
- `util.truncate_displaywidth(s, max_dw)` — unify `trunc_disp` and `truncate_to_displaywidth`

### 1.3 Error Message String Duplication

**Locations**: `buffer.lua:208`, `buffer_page.lua:133`, `buffer_search.lua:181`, `buffer_nav.lua:617`

**Pattern**: `"Unsaved changes, commit (<leader>w) or revert (R) first"`

**Fix**: Define as a constant `EDIT_CONFLICT_MSG` in a shared location.

### 1.4 Float Window Creation (`buffer_nav.lua`, `introspect.lua`, `buffer_search.lua`)

**Locations**:
- `buffer_nav.lua:479-556` — `preview_cell()` creates float window
- `introspect.lua:22-75` — `show_float()` creates float window
- `buffer_search.lua:75-160` — `show_search()` creates float window

**Problem**: All three create float windows with similar patterns: create buffer, set lines, set filetype, set modifiable=false, open window with `relative="editor"`, style "minimal", border "rounded", setup keymaps, etc.

**Fix**: Extract a shared `poste.dialog` utility (already partially exists via `require("poste.dialog")` in `introspect.lua`). Enhance it to handle the common float window creation pattern.

### 1.5 Job Execution Pattern (`init.lua`, `edit_commit.lua`, `source_format.lua`, `introspect.lua`)

**Locations**: Multiple files use the same pattern:
```lua
local job_id = vim.fn.jobstart(cmd, {
  stdin = "pipe",
  stdout_buffered = true,
  stderr_buffered = true,
  on_stdout = function(_, data) ... end,
  on_stderr = function(_, data) ... end,
  on_exit = function(_, code) ... end,
})
```

**Problem**: This pattern appears in ~8 places with minor variations. The stderr collection pattern (`local stderr_buf = {}`) is also repeated.

**Fix**: `poste.cli` already has `run_async()` and `run_json()`. Use these consistently. `introspect.lua` uses raw `vim.fn.jobstart` in several places where `cli.run_async` would work.

### 1.6 `update_winbar` Duplication (`buffer_search.lua` vs `buffer_page.lua`)

**Locations**:
- `buffer_search.lua:299-307` — `update_winbar()`
- `buffer_page.lua:187-193` — `M.update_winbar()`

**Problem**: Identical functions. Both check `D.dataset_window`, get `meta`, call `build_status_winbar`, set winbar.

**Fix**: Keep one, remove the other. Both modules should call the shared version.

### 1.7 Dialect Icon Tables (`connections.lua` vs `context.lua`)

**Locations**:
- `connections.lua:149-154` — `dialect_icons = { postgres = "🐘", mysql = "🐬", ... }`
- `context.lua:161` — inline `({ postgres = "🐘", mysql = "🐬", sqlite = "📦" })`

**Fix**: Define once in `state.lua` or a shared `icons.lua`.

### 1.8 `short_connection` / `parse_connection_short` / `format_conn_short`

**Locations**:
- `format.lua:9-15` — `short_connection()`
- `format.lua:85-112` — `parse_connection_short()` (unused, marked with `luacheck: ignore 211`)
- `buffer_nav.lua:769-774` — `format_conn_short()`

**Problem**: Three functions that do the same thing (extract host:port/db from connection URL). `parse_connection_short` is dead code.

**Fix**: Remove dead code, keep one implementation in a shared module.

---

## 2. Magic Numbers (30+ instances)

### 2.1 Page Size: `50`

| File | Line | Context |
|------|------|---------|
| `init.lua` | 360 | `render_page(layout, 1, 50)` |
| `dataset.lua` | 42 | `page_size = 50` |
| `format.lua` | 402 | `render_page(layout, 1, 50)` |
| `editor/nav.lua` | 343 | `tab.page_size or 50` |

**Fix**: Define `DEFAULT_PAGE_SIZE = 50` in `dataset.lua` and reference it.

### 2.2 Connection Port Defaults: `5432` and `3306`

| File | Line | Context |
|------|------|---------|
| `connections.lua` | 103 | `default_port = conn.dialect == "postgres" and 5432 or 3306` |
| `connections.lua` | 164 | `conn.port or (conn.dialect == "postgres" and 5432 or 3306)` |

**Fix**: Define `PORT_MAP = { postgres = 5432, mysql = 3306 }` in connections.lua.

### 2.3 Layout/Sizing Constants

| Value | File:Line | Context |
|-------|-----------|---------|
| `2` | `buffer.lua:344`, `dataset.lua:9`, multiple | `LEFT_PADDING` |
| `3` | `format.lua:302`, `highlights.lua` | │ separator byte length (U+2502 = 3 bytes) |
| `200` | `format.lua:490` | `calc_column_widths(columns, rows, 200)` — max table width |
| `78` | `format.lua:781` | Error wrap width |
| `40` | `format.lua:406` | Minimum footnote width |
| `25` | `format.lua:252` | Max protected date/time column width |
| `4` | `format.lua:239` | Minimum column width after scaling |
| `100` | `introspect.lua:28` | Max float width |
| `120` | `buffer_nav.lua:504` | Max preview width |
| `0.4` | `buffer.lua:605` | Split ratio `floor(vim.o.lines * 0.4)` |
| `0.6` / `0.7` | `buffer_nav.lua:511, 504` | Preview float proportions |
| `5` | `buffer.lua:698` | sidescrolloff |
| `1000` | `highlights.lua:309` | Max rows for immediate row numbering |
| `5000` | `editor/nav.lua:26` | Max rows for editing |
| `10` | `source_format.lua:300` | Jobwait timeout (seconds) |
| `10` | `edit_commit.lua:317` | Log trim frequency (every 10th write) |
| `1000` | `edit_commit.lua:302` | `MAX_LOG_ENTRIES` |
| `200` / `300` / `500` | Various | stderr/error truncation limits |

**Fix**: Define named constants. Use `vim.o.columns` and `vim.o.lines` for dynamic sizing instead of hardcoded proportions where possible.

### 2.4 Highlight Color Values

`highlights.lua:33-205` — ~30 inline hex color values (e.g., `0x001e00`, `0xc6efc6`, etc.). These are hard to maintain and tune.

**Fix**: Consider extracting to a config table or grouping by semantic purpose with comments. The current approach of computing dark/light variants inline is reasonable but could be consolidated.

---

## 3. Module Size & Responsibility Issues

### 3.1 Overlarge Modules (>700 lines)

| Module | Lines | Issue |
|--------|-------|-------|
| `init.lua` | 963 | Mixes: keymap setup, SQL execution, completion registration, user commands, autocmds |
| `buffer_nav.lua` | 839 | Mixes: cell navigation, header float, preview, yank, sort, raw mode, winbar |
| `buffer.lua` | 802 | Mixes: buffer creation, keymaps, tab switching, rendering (2 paths), close |
| `format.lua` | 792 | Mixes: type normalization, column width calc, table rendering, error formatting, connection parsing |
| `completion.lua` | 757 | Mixes: context detection, item generation, blink.cmp interface, nvim-cmp interface |
| `edit_commit.lua` | 710 | Mixes: DML generation, SQL logging, commit execution, dataset refresh |
| `introspect.lua` | 672 | Mixes: float window, column info, DDL, table listing |
| `highlights.lua` | 629 | Mixes: color setup, dataset highlights, cell highlight, edit highlights |

**Recommendation**: Split modules >600 lines. Priority targets:
- `init.lua` → extract `sql_runner.lua` for `run_sql_request()`, keep setup/commands in `init.lua`
- `buffer.lua` → extract rendering into `buffer_render.lua`, keep buffer/keymap/tab logic
- `edit_commit.lua` → extract `dml.lua` for DML generation, keep commit/refresh in `edit_commit.lua`
- `introspect.lua` → extract `introspect_ui.lua` for float window, keep DDL/column logic

### 3.2 God Function: `nav.lua:goto_definition()` (300+ lines)

**Location**: `nav.lua:5-302`

**Problem**: One function with ~10 levels of nesting, handling:
- `@connection` directive goto → connections.toml
- `@database` directive goto → db_browser
- Table name goto → db_browser (with Rust context detection for alias resolution, schema qualification, column detection, etc.)
- Multiple context types: `dot_column`, `insert_column`, `schema_table`, `table`, `column`, `keyword`

**Fix**: Extract into separate handler functions:
```lua
local function handle_connection_directive(conn_name) ... end
local function handle_database_directive(db_name) ... end
local function handle_table_reference(ctx, table_name, column_name) ... end
local function handle_dot_column(rust_ctx, line_text, end_col) ... end
-- etc.
```

### 3.3 `render_dataset` Dual Path (`buffer.lua:403-700`)

**Problem**: `render_dataset()` has two completely different code paths (layout-aware vs legacy). The function is 300 lines with `if opts.layout` at line 449 branching into entirely different rendering logic.

**Fix**: Split into `render_dataset_layout()` and `render_dataset_legacy()`, dispatch from a thin wrapper.

---

## 4. Inconsistencies & Code Smells

### 4.1 Inconsistent API Usage

- `introspect.lua:625` uses raw `vim.fn.jobstart`, while `introspect.lua:294` uses `cli.run_async` — inconsistent within the same module
- `source_format.lua:271` uses `vim.fn.jobstart` synchronously (blocking with `jobwait`), while other modules use async job patterns
- `context_client.lua` uses `vim.fn.jobstart` directly (acceptable for a persistent subprocess)

### 4.2 Dead Code

- `format.lua:85-112` — `parse_connection_short()` is defined but never called (marked `luacheck: ignore 211`)
- `highlights.lua:456-457` — `invalidate_sep_cache()` is now a stub `function M.invalidate_sep_cache() end` — kept for backward compatibility

### 4.3 Fragile Patterns

- `highlights.lua:297` — `line:sub(1, 3) == "┌"` — compared UTF-8 border characters by byte prefix. This works because all U+250x box-drawing chars share the same 3-byte UTF-8 prefix `\xe2\x94`, but the first distinguishing byte is the 4th byte. The comment at line 295 explains this, but it remains fragile. The safer approach would be `line:match("^[\xe2\x94\x80-\xbc]")` or checking the first UTF-8 codepoint.
- `connections.lua:64` — `if conn.dialect == "mariadb" then conn.dialect = "mysql"` — mutates the cached config. The `vim.deepcopy(conn)` at line 65 mitigates this, but it's a side-effect in a seemingly pure accessor.

### 4.4 Nested Callback Hell

- `completion.lua:250-524` — `detect_context_async` callback contains deeply nested `if ctx_type == ...` branches that each call `data.ensure_X()` with callbacks. This is difficult to read and test.
- `edit_commit.lua:591-700` — `commit_edits()` has a 100-line `on_stdout` callback with nested conditionals.

### 4.5 Module Init Side Effects

- `highlights.lua:227-229` — calls `M.setup()` at module load time and registers autocmds. This is acceptable for a highlight module but should be documented.

---

## 5. Optimization Plan (Priority Order)

### P0 — Immediate (1-2 days)

1. **Unify header extraction** in `buffer.lua` — extract `extract_and_pad_header()` function, removing ~30 lines of duplication
2. **Fix `update_winbar` duplication** — `buffer_search.lua` should call `buffer_page.update_winbar()` instead of duplicating
3. **Remove dead code** — `parse_connection_short()` in `format.lua`
4. **Define magic number constants** — page size (50), port defaults (5432/3306), LEFT_PADDING (2), stderr truncation limits

### P1 — Short-term (1 week)

5. **Extract UTF-8 utility functions** — create `poste-sql.util` or add to `poste.util`:
   - `util.find_separators(line, sep)` — │ scanning
   - `util.utf8_char_bytes(byte)` — byte length calculator
   - `util.truncate_displaywidth(s, max_dw)` — unified truncation
6. **Refactor `nav.lua:goto_definition()`** — split into handler functions by context type
7. **Unify job execution pattern** — use `cli.run_async()` consistently in `introspect.lua` and `source_format.lua`

### P2 — Medium-term (2-3 weeks)

8. **Split `init.lua`** — extract `sql_runner.lua` for `run_sql_request()`
9. **Split `buffer.lua` render paths** — extract `render_dataset_layout()` and `render_dataset_legacy()`
10. **Extract float window utility** — enhance `poste.dialog` to handle common float creation patterns
11. **Refactor `edit_commit.lua`** — extract `dml.lua` for DML generation, keep commit logic

### P3 — Long-term (1 month)

12. **Split `completion.lua`** — extract `completion_handlers.lua` for per-context-type item generation
13. **Unify dialect icon tables** — define once in `state.lua`
14. **Refactor `introspect.lua`** — extract `introspect_ui.lua`, use `cli.run_async` consistently
15. **Eliminate callback nesting** — use `vim.schedule_wrap` patterns or create a simple async flow control utility

---

## 6. Test Coverage Gaps

| Area | Current Coverage | Risk |
|------|-----------------|------|
| `nav.lua:goto_definition()` | None (300-line function, hard to test) | High |
| `introspect.lua` | None (all async job-based) | High |
| `buffer.lua:render_dataset()` | Partial | Medium |
| `source_format.lua` | None | Medium |
| `edit_commit.lua` | None | Medium |

**Recommendation**: Add tests for the extracted utility functions first (P0-P1), then add integration tests for the async job-based modules.

---

## Summary

**Strengths**: Good module-level separation, clear naming conventions, consistent use of `poste.nvim` shared infra, well-documented public API functions.

**Weaknesses**: Overlarge modules, duplicated rendering logic, ~30+ magic numbers, 300-line god function, inconsistent job API usage, dead code, shared float window pattern not unified.

**Overall**: The codebase is maintainable but has accumulated significant technical debt as features were added. The P0-P1 fixes would reduce code duplication by ~15% and clarify the architecture significantly.