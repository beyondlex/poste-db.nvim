# 执行 SQL 文件功能设计

## 概述

在 DB Browser 中为某个数据库执行一个 `.sql` 文件，支持流式执行、进度反馈、取消、超时、事务/贪婪模式，以及执行汇总。

## 入口

### DB Browser

数据库节点 context menu 新增一项:

```
database = {
  ...
  { letter = "f", label = "Execute SQL File...", action = "exec_file", group = "query" },
}
```

### 快捷键

SQL 源 buffer 中 `<leader>ef` 直接执行当前 buffer 对应的 `.sql` 文件。

## 交互流程

```
DB Browser → [f] Execute SQL File...
     ↓
模式选择 → Transaction / Greedy
     ↓
文件选择 → beyondlex/finder (mode = "file", extensions = { "sql" })
     ↓
执行 → 进度窗口实时更新
     ↓
完成 → 汇总展示
```

### 模式选择

使用 `poste.select` 或 `vim.ui.select` 选择执行模式:

| 模式 | 行为 |
|------|------|
| **Transaction** | 所有语句包裹在 `BEGIN` / `COMMIT` 中，任一条失败则 `ROLLBACK` |
| **Greedy** | 逐条独立执行，出错继续下一条 |

### 文件选择

复用 `beyondlex/finder`，与 export 模块相同的选择器:

```lua
finder.open({
  mode = "file",
  initial_path = vim.fn.getcwd(),
  extensions = { "sql" },
  on_confirm = function(path) ... end,
  on_cancel = function() ... end,
})
```

## 架构

### Lua 侧: `lua/poste/sql/file_exec.lua`

新模块，管理进度窗口、Rust 任务生命周期、结果收集。

```lua
local M = {}

M.run(filepath, conn, db, opts)
  -- opts: { mode = "transaction"|"greedy", timeout = 30, max_rows = 1000 }
```

### Rust 侧: `crates/poste-cli/src/exec_file.rs`

新子命令 `poste exec-file`，逐语句执行 + NDJSON 流式输出。

```
poste exec-file <file> --env <env> --mode <mode>
  --timeout <sec> --max-rows <n> --json
```

### 通信协议

NDJSON (Newline-Delimited JSON)，每行一个事件:

```
→ progress:  {"type":"progress","seq":1,"total":10,"sql":"SELECT * FROM users"}
→ result:    {"type":"result","seq":1,"status":"ok","row_count":5,"affected_rows":null,"execution_time_ms":3,"columns":[...],"rows":[[...],...],"rows_truncated":false}
→ result:    {"type":"result","seq":2,"status":"error","sql":"DROP TABLE x","error":"syntax error","execution_time_ms":1}
→ summary:   {"type":"summary","total":10,"succeeded":8,"failed":2,"total_rows":500,"total_affected":42,"total_time_ms":3200,"connection":"postgres://...","database":"mydb","dialect":"postgres","mode":"greedy"}
```

## 进度窗口

浮动窗口，非模态，实时更新:

```
┌─ Execute SQL File ───────────────────────────┐
│ Connection: myconn / mydb                    │
│ Mode: greedy                                 │
│ [■■■■■░░░░░] 5/10                            │
│ → SELECT * FROM users WHERE id ...           │
│                                              │
│  ✓ SELECT 1                    (1 row, 1ms)  │
│  ✓ INSERT INTO t ...        (3 aff, 2ms)     │
│  ✘ DROP TABLE x            (syntax error)    │
│                                              │
│ [c] Cancel  [q] Close                        │
└──────────────────────────────────────────────┘
```

### 设计要点

- **当前 SQL**: 只显示一行，超长时用 `...` 截断末尾
- **进度条**: `[■■■■■░░░░░] 5/10`，显示已执行/总数
- **结果日志**: 只保留最近 N 条 (如 10 条)，每条显示状态图标 + 简短摘要
- 状态图标: `✓` 成功, `✘` 错误, `⏳` 执行中

### 窗口 keymaps

| 键 | 行为 |
|----|------|
| `c` | 取消执行 (发出 SIGTERM) |
| `q` | 关闭窗口 (仅已完成时；未完成时提示 `Close anyway? (y/N)`) |
| `<Esc>` | 同 `q` |
| `j`/`k` | 滚动结果日志 |

### 关闭确认

`q` 键在任务未完成时需要确认:

```
Close anyway? (y/N)
```

用 `vim.ui.input` 或 `vim.fn.input("Close anyway? (y/N)")` 实现。

## 超时

- Rust 侧用 `tokio::time::timeout` 实现每语句超时
- 超时后该语句记为错误
- 事务模式: 超时 → `ROLLBACK`
- 贪婪模式: 超时 → 继续下一条
- 默认超时 30 秒，可通过 `--timeout` 配置

## 内存控制

### Rust 侧

- `--max-rows` 限制每个 SELECT 返回的行数 (默认 1000)
- 超出限制的行标记 `rows_truncated: true`
- NDJSON 逐行输出，不缓存全部结果
- 使用 `fetch_many` 流式读取 (替代 `fetch_all`)

### Lua 侧

- `stdout_buffered = false`，逐行读取 NDJSON
- 不缓存所有行，实时解析
- 结果日志窗口只保留最近 10 条

## 结果处理

**SELECT 语句不渲染到 dataset buffer tab。**

因为一个 `.sql` 文件可能包含几十条 SELECT，都渲染到 dataset 会撑爆界面。改为:

1. 每条 SELECT 结果只在进度窗口显示行数摘要
2. 如果用户想查看具体数据，汇总窗口会显示 "10 statements produced resultsets"
3. 后续可考虑加一个 "查看上次文件执行的所有结果" 的入口

### 汇总信息

执行完成后，进度窗口转为汇总展示:

```
┌─ Execute SQL File — Complete ───────────────┐
│ Database: myconn / mydb                      │
│ Mode: greedy                                 │
│ Total: 10 statements                         │
│ Succeeded: 8                                 │
│ Failed: 2                                    │
│ Total rows returned: 500                     │
│ Total rows affected: 42                      │
│ Total time: 3.2s                             │
│                                              │
│  ✓ SELECT 1                    (1 row, 1ms)  │
│  ✓ INSERT INTO t ...        (3 aff, 2ms)     │
│  ✘ DROP TABLE x            (syntax error)    │
│  ✘ INSERT INTO bad ...     (timeout)         │
│                                              │
│ [q] Close                                    │
└──────────────────────────────────────────────┘
```

## 修改文件清单

| 文件 | 修改内容 |
|------|---------|
| `crates/poste-cli/src/main.rs` | 注册 `ExecFile` 子命令 |
| `crates/poste-cli/src/exec_file.rs` | **新文件**: 逐语句执行 + NDJSON 输出 |
| `lua/poste/sql/file_exec.lua` | **新文件**: 进度窗口 + 任务管理 |
| `lua/poste/sql/db_browser/context_menu.lua` | 数据库菜单加 `exec_file` 项 |
| `lua/poste/sql/db_browser/operations.lua` | 加 `M.exec_file()` 操作 |
| `lua/poste/state.lua` (poste.nvim) | `sql_source` 加 `exec_file` keymap |
| `lua/poste/help.lua` (poste.nvim) | 加帮助说明 |

## Rust 执行流程

```
exec_file::execute()
  │
  ├─ 1. 读取 .sql 文件内容
  │
  ├─ 2. 用 Parser::parse_at_line() 构建 Request
  │    (line=1, 借道 parser 获取 @connection/@database 指令)
  │
  ├─ 3. 解析 connection 名 → URL (复用 ConnectionStore)
  │
  ├─ 4. 用 sql_parser::split_statements() 拆分语句
  │
  ├─ 5. 事务模式: 先执行 BEGIN
  │
  ├─ 6. 循环执行每条语句:
  │    ├─ emit progress JSON
  │    ├─ tokio::time::timeout(per_stmt_timeout, exec_stmt)
  │    ├─ 限制 SELECT 行数 ≤ max_rows
  │    ├─ emit result JSON
  │    └─ 错误时: 事务模式→ROLLBACK, 贪婪模式→继续
  │
  ├─ 7. 事务模式: COMMIT 或 ROLLBACK
  │
  └─ 8. emit summary JSON
```
