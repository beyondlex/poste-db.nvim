# Tree-sitter Migration Plan

## Goals

Replace Rust-based semantic parsing + Lua regex fallback with Tree-sitter AST for three features:

1. **Highlighting** — `syntax.lua` (regex + keyword map) → Tree-sitter `highlights.scm`
2. **Boundary detection** — `statement.lua` (Rust `poste context stmt` + `;` heuristic) → Tree-sitter AST query
3. **Syntax diagnostics** — New capability: `ERROR`/`MISSING` nodes → `vim.diagnostic`

Completion stays in Rust (schema-aware, Tree-sitter can't do that).

## Architecture

```
Before:
  syntax.lua          → Lua regex + keyword map (O(n*k), fragile)
  statement.lua       → Rust CLI + Lua ;-fallback (two-tier, complex)
  statement_indicator.lua → Rust CLI async (50ms debounce)

After:
  after/queries/poste_sql/highlights.scm  → Tree-sitter AST (correct, fast)
  lua/poste/sql/ts_stmt.lua               → Tree-sitter AST query (single path)
  lua/poste/sql/diagnostics.lua           → New: Tree-sitter ERROR nodes
  statement.lua                           → Thin wrapper around ts_stmt
  statement_indicator.lua                 → Use ts_stmt instead of Rust CLI
  syntax.lua                              → Only directive highlighting remains
```

## File-by-file Changes

### 1. `init.lua` — Enable Tree-sitter for `poste_sql`/`poste_sqlite`

**Current** (lines 528-529, 832-833):
```lua
pcall(vim.treesitter.language.register, "__poste_sql_disabled__", "poste_sql")
pcall(vim.treesitter.language.register, "__poste_sql_disabled__", "poste_sqlite")
```

**Change**: Remove these two lines. Register the real `sql` parser for `poste_sql` and `poste_sqlite`:
```lua
pcall(vim.treesitter.language.register, "sql", "poste_sql")
pcall(vim.treesitter.language.register, "sql", "poste_sqlite")
```

**Effect**: Tree-sitter now parses `poste_sql` buffers with the standard SQL grammar. All `after/queries/poste_sql/` query files apply automatically.

### 2. `after/queries/poste_sql/highlights.scm` — New file

Replace `lua/poste/sql/syntax.lua`'s regex + keyword map with Tree-sitter captures.

**Location**: `after/queries/poste_sql/highlights.scm` (new directory, new file)

**Content**: Standard SQL highlights from `nvim-treesitter`'s `tree-sitter-sql` grammar, plus poste-specific overrides:

```scheme
; sqlComment — already handled by default grammar
; sqlString — already handled by default grammar
; sqlNumber — already handled by default grammar

; Override comment highlighting for -- @connection / @database / @protocol
(
  (comment) @sqlDirectiveComment
  (#match? @sqlDirectiveComment "^--%s*@(connection|database|protocol)")
)

; Statement keywords
(statement) @sqlStatement
(keyword) @sqlKeyword
; ... more captures mapped to sqlStatement/sqlKeyword/sqlType/sqlFunction/sqlSpecial
```

**Note**: The `@sql*` highlight groups are already defined in `syntax.lua`:
- `sqlComment`, `sqlString`, `sqlNumber` — standard groups
- `sqlStatement`, `sqlKeyword`, `sqlType`, `sqlFunction`, `sqlSpecial` — keyword groups
- `sqlDirective`, `sqlDirectiveValue`, `sqlDirectiveComment` — directive groups

These groups are referenced by Tree-sitter queries via `@` captures. Tree-sitter resolves them to the underlying `:highlight` groups defined in `syntax.lua`.

**Priority**: Tree-sitter uses default priority 100. Directive extmarks use priority 101-102 (unchanged, they override TS).

### 3. `lua/poste/sql/ts_stmt.lua` — New file

Tree-sitter-based statement boundary detection. Replaces `try_rust_stmt_span()` and `try_rust_stmt_ranges()`.

**API**:

```lua
--- Find the statement containing a given line using Tree-sitter AST.
--- @param buf number  buffer handle
--- @param cursor_line number  1-based
--- @return {start_line: number, end_line: number}|nil
M.find_stmt_span(buf, cursor_line)
```

```lua
--- Find all statement boundaries in a range using Tree-sitter AST.
--- @param buf number  buffer handle
--- @param start_line number  1-based
--- @param end_line number  1-based
--- @return number[]  statement start lines (1-based)
M.find_all_stmt_lines(buf, start_line, end_line)
```

**Implementation**:

```lua
-- Query the Tree-sitter AST for (statement) nodes at the cursor line.
-- A (statement) node in tree-sitter-sql is a top-level SQL statement.
-- Use vim.treesitter.get_parser(buf, "sql") to get the parser.
-- Use parser:parse() to get the syntax tree.
-- Walk the tree to find the statement node containing cursor_line.

-- For find_stmt_span:
--   local root = parser:parse()[1]:root()
--   local cursor_row = cursor_line - 1  -- TS uses 0-based lines
--   -- Find the smallest (statement) node containing cursor_row
--   -- Return {start_line = node:start() + 1, end_line = node:end_() + 1}

-- For find_all_stmt_lines:
--   Walk all top-level (statement) nodes in the given line range
--   Return 1-based start lines that are non-blank, non-comment
```

**Key difference from current Rust approach**: Tree-sitter handles semicolons in strings, `$$` dollar strings, nested parentheses, and PL/pgSQL blocks natively. No need for a custom tokenizer or semantic keyword heuristics.

### 4. `statement.lua` — Refactor to use `ts_stmt`

**Changes**:

- Add `M.try_ts_stmt_span(buf, cursor_line)` — calls `ts_stmt.find_stmt_span()`
- Add `M.try_ts_stmt_ranges(buf, start_line, end_line)` — calls `ts_stmt.find_all_stmt_lines()`
- `extract_stmt_at_cursor()`: try TS first, then fall back to Rust (if TS fails), then fall back to `;` heuristic
- `find_stmt_lines()`: try TS first, then Rust, then `;` heuristic
- `_test` table: replace `try_rust_stmt_span` and `try_rust_stmt_ranges` with `try_ts_stmt_span` and `try_ts_stmt_ranges`

**Old flow**:
```
extract_stmt_at_cursor:
  try_rust_stmt_span() → Rust CLI → ; heuristic
```

**New flow**:
```
extract_stmt_at_cursor:
  try_ts_stmt_span() → Tree-sitter AST → try_rust_stmt_span() → ; heuristic
```

### 5. `statement_indicator.lua` — Use `ts_stmt` instead of Rust CLI

**Current**: Calls `cli.run_async({ "context", "stmt", ... })` with 50ms debounce.

**Change**: Replace `cli.run_async` call with `require("poste-sql.ts_stmt").find_stmt_span()`.

**Effect**: Async job eliminated. No more `_job_id` tracking. Result is synchronous (Tree-sitter parse is fast). Debounce can be reduced further or removed.

**Signature change**: `fetch_and_highlight(buf, cursor_line)` no longer needs a callback. Just call `ts_stmt.find_stmt_span(buf, cursor_line)` directly.

### 6. `lua/poste/sql/diagnostics.lua` — New file

Tree-sitter syntax error diagnostics. New capability.

**API**:

```lua
--- Update diagnostics for a buffer using Tree-sitter ERROR nodes.
--- @param buf number  buffer handle
M.update_diagnostics(buf)
```

**Implementation**:

```lua
-- Parse the buffer with Tree-sitter
-- Walk the tree for ERROR and MISSING nodes
-- Map to vim.diagnostic with severity = vim.diagnostic.severity.ERROR
-- Highlight ERROR nodes with a red underline or virtual text
```

**Trigger**: On `TextChanged`/`TextChangedI` (debounced, 300ms). On `BufWritePost`.

**Note**: This is a new feature, not a replacement. No existing code is removed.

### 7. `syntax.lua` — Deprecate SQL keyword highlighting

**Keep**: `highlight_directive_comments()` — still needed because Tree-sitter doesn't understand `-- @connection` semantics (it only sees `(comment)` nodes). The extmark approach at priority 101-102 overrides the Tree-sitter comment highlight.

**Deprecate**: `highlight_line()` — the regex + keyword map for SQL keywords. Tree-sitter's `highlights.scm` handles this now. The `kw_map` and `patterns` tables can be removed.

**Remove**: All autocmd triggers that call `highlight_line()` (in `init.lua`):
- `FileType poste_sql` → `syn_refresh` → `highlight_line` — remove
- `TextChanged`/`TextChangedI` → `schedule_syn_refresh` → `highlight_line` — remove
- `BufWritePost` → `schedule_syn_refresh` → `highlight_line` — remove

**Keep**: `highlight_directive_comments()` autocmd — still fires on `FileType` and `CursorMoved`.

### 8. `highlights.lua` (dataset) — Insert-field pair highlighting

**Current**: Achieved via `PosteInsertHint` extmark group, likely using cursor-moved logic.

**Change**: Tree-sitter can make this more reliable by parsing the `INSERT INTO t (col1, col2) VALUES (v1, v2)` to find the column index at cursor position in `VALUES`, then highlighting the matching column name.

**No immediate change needed** — this is a future enhancement. The existing cursor-moved logic works. Tree-sitter can be used to validate/improve it later.

## Test Migration

### Rust tests to migrate

The following Rust tests test boundary detection logic that will be replaced by Tree-sitter:

| Rust test | What it tests | Lua equivalent |
|-----------|---------------|----------------|
| `test_find_statement_span_simple` | `SELECT 1;` / `SELECT 2;` cursor on each → correct span | `ts_stmt spec: find_stmt_span` |
| `test_find_statement_span_with_semicolon_in_string` | `;` inside string → not a boundary | `ts_stmt spec: semicolon in string` |
| `test_find_statement_span_semicolon_in_dollar_string` | `$$` dollar string with `;` → not a boundary | `ts_stmt spec: dollar string` |
| `test_find_statement_span_multi_statement_on_same_line` | `SELECT 1; SELECT 2;` on same line → cursor on line 0 → stmt 0 | `ts_stmt spec: multi-statement same line` |
| `test_tables_isolated_to_current_statement` | Semicolons isolate statement scope | → `statement spec: tables isolated by semicolon` (completion path, not boundary) |
| `test_tables_from_all_statements_without_semicolon` | Semantic boundary (UPDATE vs SELECT) without `;` | → `statement spec: semantic boundary` |

### New Lua test file: `tests/sql/sql_ts_stmt_spec.lua`

New test file for `ts_stmt.lua`. Uses `vim.treesitter` to parse SQL strings and verify statement boundaries.

**Test structure**:

```lua
local ts_stmt = require("poste-sql.ts_stmt")

describe("find_stmt_span", function()
  it("returns correct span for single statement", function()
    local lines = { "SELECT 1;", "SELECT 2;" }
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "poste_sql"
    -- Wait for Tree-sitter to parse
    vim.wait(100, function() return vim.treesitter.get_parser(buf, "sql") end)
    local span = ts_stmt.find_stmt_span(buf, 1)
    assert.same({1, 1}, span)
  end)

  it("handles semicolon in string literal", function()
    -- "SELECT 'hello;world'" → single statement, not split by ;
    ...
  end)

  it("handles dollar-quoted string", function()
    -- "SELECT $$abc;def$$; SELECT 2" → cursor on line 2 → stmt 2
    ...
  end)

  it("multi-statement on same line", function()
    -- "SELECT 1; SELECT 2;" → cursor on line 0 → stmt (0,0)
    ...
  end)

  it("handles multi-line statement", function()
    -- "SELECT *\nFROM users\nWHERE id = 1;" → span (1, 3)
    ...
  end)

  it("handles nested parentheses in function calls", function()
    -- "SELECT COUNT(DISTINCT id) FROM users;" → single statement
    ...
  end)

  it("handles INSERT with subquery", function()
    -- "INSERT INTO t SELECT * FROM u;" → single statement
    ...
  end)

  it("handles CTE (WITH clause)", function()
    -- "WITH cte AS (SELECT 1) SELECT * FROM cte;" → single statement
    ...
  end)

  it("handles PL/pgSQL block", function()
    -- "BEGIN\nUPDATE t SET x=1;\nUPDATE t2 SET x=2;\nEND;" → single statement
    ...
  end)
end)
```

### Update `tests/sql/sql_multi_stmt_spec.lua`

**Changes**:

- `try_rust_stmt_span` tests → `try_ts_stmt_span` tests (or add both, keep Rust as fallback)
- Add tests for `try_ts_stmt_span` with Tree-sitter buffer setup
- Keep existing `find_stmt_lines` and `extract_stmt_at_cursor` tests (they test the orchestration logic, which still works)
- Remove the "KNOWN BUG" tests for `;` in strings (Tree-sitter handles this correctly, they should pass now)

**Add new describe blocks**:

```lua
describe("try_ts_stmt_span", function()
  it("handles semicolon in string — no longer a bug", ...)
  it("handles semicolon in double-quoted ident — no longer a bug", ...)
  it("handles multi-line string — no longer a bug", ...)
end)
```

### Test infrastructure

No changes needed to `tests/run.sh` or `tests/minimal_init.lua`. Tree-sitter is already available in test Neovim. The `sql` parser is loaded by `nvim-treesitter`.

## Execution Order

| Step | File | Description | Dependencies |
|------|------|-------------|--------------|
| 1 | `after/queries/poste_sql/highlights.scm` | Create TS highlight queries | None |
| 2 | `init.lua` | Enable TS for `poste_sql`/`poste_sqlite` | Step 1 |
| 3 | `lua/poste/sql/ts_stmt.lua` | New TS boundary detection module | Step 2 |
| 4 | `statement.lua` | Add TS path, keep Rust as fallback | Step 3 |
| 5 | `statement_indicator.lua` | Replace Rust async with TS sync | Step 3 |
| 6 | `lua/poste/sql/diagnostics.lua` | New syntax error diagnostics | Step 2 |
| 7 | `syntax.lua` | Remove `highlight_line()`, keep `highlight_directive_comments()` | Step 1 |
| 8 | `init.lua` | Remove `syn_refresh` autocmds, remove `schedule_syn_refresh` | Step 7 |
| 9 | `tests/sql/sql_ts_stmt_spec.lua` | New test file for `ts_stmt.lua` | Step 3 |
| 10 | `tests/sql/sql_multi_stmt_spec.lua` | Update tests, remove KNOWN BUG marks | Step 4 |

## Files to Create

| File | Purpose |
|------|---------|
| `after/queries/poste_sql/highlights.scm` | Tree-sitter highlight queries for `poste_sql` filetype |
| `lua/poste/sql/ts_stmt.lua` | Tree-sitter statement boundary detection |
| `lua/poste/sql/diagnostics.lua` | Tree-sitter syntax error diagnostics |
| `tests/sql/sql_ts_stmt_spec.lua` | Tests for `ts_stmt.lua` |

## Files to Modify

| File | Change |
|------|--------|
| `init.lua` | Remove `__poste_sql_disabled__` registration, register `sql` parser, remove `syn_refresh` autocmds |
| `statement.lua` | Add `try_ts_stmt_span()` and `try_ts_stmt_ranges()`, keep Rust as fallback |
| `statement_indicator.lua` | Replace `cli.run_async` with `ts_stmt.find_stmt_span()` |
| `syntax.lua` | Remove `highlight_line()`, `kw_map`, `patterns`; keep `highlight_directive_comments()` |
| `tests/sql/sql_multi_stmt_spec.lua` | Add TS tests, update KNOWN BUG tests, keep existing orchestration tests |

## Files to Remove (no content)

None. All existing files are modified or kept.

## Rollback Plan

If Tree-sitter boundary detection fails for any buffer:

1. `statement.lua` still has the Rust fallback path (`try_rust_stmt_span`, `try_rust_stmt_ranges`)
2. `statement_indicator.lua` can fall back to Rust async if `ts_stmt` returns nil
3. `init.lua` can re-register `__poste_sql_disabled__` via `:PosteSQLToggleTS` command

This means zero risk of regression — the new TS path is additive, not a replacement. Rust stays as a working fallback.