# SQL Session 持久连接设计

## 问题

每次 `<CR>` 执行都 spawn 一个全新 `exec-file` 进程，每个进程创建独立数据库连接，执行完立即关闭。session 变量（`SET @a=1;`）在跨语句时不持久化：

```
SET @a=1;     → exec-file(进程1) → 连接1 → 执行 → 关闭
SELECT @a;    → exec-file(进程2) → 连接2 → @a 不存在
```

## 设计

Rust 新增 `poste session` 子命令 — 一个保持连接的长驻进程。Lua 端按 `connection_url` 维护 session 池，`<CR>` 时按 connection 查找复用。

### Session 池

```
session_conn.pool = {
  ["mysql://user@host:3306/db"] = {
    job_id = 123,
    conn_url = "mysql://user@host:3306/db",
    bufs = { [bufnr_a] = true, [bufnr_b] = true },
    start_time = 1234567,
    idle_timer = nil,
  },
  ["postgres://user@host:5432/db"] = { ... },
}
```

key 为 `connection_url`（Lua 解析后的完整 URL），<CR> 时按此查找。

### 查找流程

```
按 <CR>
  → 解析 -- @connection name → resolve_connection_url(name) → conn_url
  → pool[conn_url] 存在？
    → 是：复用 session，发送 SQL 到 stdin
    → 否：jobstart("poste session --connection <url>")，加入 pool
```

### 生命周期

| 事件 | 行为 |
|------|------|
| 首次 `<CR>`（某 connection） | 启动 session 进程，加入 pool |
| 后续 `<CR>`（同 connection） | 复用 session |
| 不同 connection 的 `<CR>` | 启动新 session（不同进程），两 session 独立 |
| Buffer 关闭 | 遍历 pool，从 `bufs` 移除该 buffer；若 `bufs` 为空 → 关闭 session，从 pool 删除 |
| `:PosteSQLSessionStop` | 可指定 connection_url 关闭单个，或 `--all` 关闭全部 |
| 空闲超时（可选） | 可配置 N 秒无请求后自动关闭 |

### 共享

以 connection 为准，跨 buffer 共享。同一 connection_url 的多个 buffer 共享同一个 session，变量在 buffer 间可见（符合真实 MySQL/PostgreSQL 行为）。

## Rust 侧: `crates/poste-cli/src/session.rs`

### 子命令

```
poste session --connection <url> [--database <db>] [--timeout <sec>] [--max-rows <n>]
```

### 协议

stdin 读 JSON lines，stdout 写 JSON lines（NDJSON）。

**请求格式**（Lua → Rust）：

```json
{"seq": 1, "sql": "SET @a = 1"}
{"seq": 2, "sql": "SELECT @a"}
```

**响应格式**（Rust → Lua，与 exec-file `result` 事件一致）：

```json
{"type":"result","seq":1,"status":"ok","sql":"SET @a = 1","row_count":0,"affected_rows":0,"execution_time_ms":1,"columns":[],"rows":[]}
{"type":"result","seq":2,"status":"ok","sql":"SELECT @a","row_count":1,"affected_rows":null,"execution_time_ms":1,"columns":[{"name":"@a","type":"INT"}],"rows":[[1]]}
```

**错误响应**：

```json
{"type":"result","seq":3,"status":"error","sql":"SELECT * FROM nonexistent","error":"table not found","execution_time_ms":0}
```

### 流程

```
session::execute()
  ├─ 1. 连接数据库（pool → acquire，与 exec_file 相同逻辑）
  ├─ 2. 循环：
  │    ├─ 读取 stdin 一行
  │    ├─ 解析 JSON { seq, sql }
  │    ├─ 执行 SQL（复用同一个 conn）
  │    ├─ 写 result JSON 到 stdout
  │    └─ 错误时：写 error result，继续循环（不退出）
  ├─ 3. stdin EOF → 关闭连接 → 退出（exit 0）
```

## Lua 侧: `lua/poste-sql/session_conn.lua`

### 接口

```lua
local M = {}

-- 启动 session（如果 pool 中已有则直接返回）
M.start(conn_url, opts) → session

-- 发送 SQL 到 session，返回结果（异步，通过 callback）
M.execute(session, sql, callbacks)

-- 关闭指定 session
M.stop(conn_url)

-- 关闭所有 session
M.stop_all()

-- 关闭与某个 buffer 关联的所有 session（buffer 关闭时调用）
M.cleanup_buf(bufnr)
```

### 集成到 `sql_runner.lua`

`run_sql_request()` 中，在 resolve context 得到 conn_url 后：

1. 检查 `session_conn.pool[conn_url]`
2. 存在 → `session_conn.execute(session, sql, callbacks)`（发到 stdin）
3. 不存在 → `session_conn.start(conn_url)` → 回退到 `exec_run.run_async`（或等待 session 就绪后发送）

`exec_run.run_async` 保持不变，作为 session 不可用时的回退路径。

### Session 进程管理

```lua
local session = {
  job_id = vim.fn.jobstart({"poste", "session", "--connection", conn_url, ...}, {
    stdin = "pipe",
    stdout_buffered = false,
    on_stdout = function(_, data) ... end,
    on_exit = function() ... end,
  }),
  conn_url = conn_url,
  bufs = { [bufnr] = true },
  pending = {},  -- { [seq] = { on_response, on_error } }
  seq = 0,
}
```

发送 SQL：

```lua
session.seq = session.seq + 1
local seq = session.seq
session.pending[seq] = { on_response = ..., on_error = ... }
vim.fn.chansend(session.job_id, vim.json.encode({ seq = seq, sql = sql }) .. "\n")
```

接收响应：

```lua
on_stdout = function(_, data)
  for _, line in ipairs(data) do
    if line ~= "" then
      local ok, event = pcall(vim.json.decode, line)
      if ok and event.type == "result" then
        local cb = session.pending[event.seq]
        if cb then
          session.pending[event.seq] = nil
          if event.status == "ok" then
            cb.on_response(event)
          else
            cb.on_error(event.error or "unknown error")
          end
        end
      end
    end
  end
end
```

## 修改文件清单

| 文件 | 修改内容 |
|------|---------|
| `crates/poste-cli/src/session.rs` | **新文件**: session 守护进程 |
| `crates/poste-cli/src/main.rs` | 注册 `Session` 子命令 |
| `lua/poste-sql/session_conn.lua` | **新文件**: session 池管理 + 发送/接收 |
| `lua/poste-sql/sql_runner.lua` | `run_sql_request()` 集成 session 路径 |
| `lua/poste-sql/init.lua` | `setup()` 中注册 `BufUnload` 自动清理 |

## 未来可扩展

- 空闲超时自动关闭
- `:PosteSQLSessionList` 查看所有活跃 session
- 事务模式 session（`BEGIN` 跨 `<CR>`）