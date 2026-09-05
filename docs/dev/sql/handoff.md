# Handoff — 2026-09-05

> 写给下一个 AI agent。读完这一页 + `AGENTS.md` + `LEARNINGS.md` +
> `dialect-support.md` 即可接手。所有论断都已验证；环境事实逐条可复跑。

## 世界快照（接手时）

| Checkout | 分支 | 状态 |
|---|---|---|
| `~/code/github/poste-db.nvim` | `ai` | 本文件所在提交为最新；**全部提交未推送** |
| `~/code/github/poste.nvim` | `main` @ 655900b | 未动（poste-redis 等其它依赖方共用此 checkout） |
| `~/code/github/poste-for-db` | `poste-for-db` @ e78cedc | worktree；= main + 1 个 MSSQL 提交，将来合回 main 是纯 fast-forward |

**已完成**（对应 `dialect-support.md` 的阶段划分）：

- Phase 0：11 个 PG/MySQL 兼容系别名 + `postgresql` 拼写，Lua 侧 `DIALECT_ALIASES` 归一化，Rust 零改动
- Phase 1 MSSQL：Lua 全触点 + Rust 全链路（tiberius 驱动，exec-file/session/introspect 三子命令）+ 容器/种子/playground/diag
- 审计重构：dialect URL/端口单一事实源（`constants.lua`）、11 处弃用 API 清理、`ftplugin/poste_sqlite.vim` 补齐、`import/mapping.lua` 首份测试
- 两个存量坏 spec 修复（`poste-sql→poste-db` 改名漏网）——**套件历史首次全绿：69 个 spec 文件 0 failed 0 errors**
- 实测：`cargo test --workspace` 410 通过；`diag_mssql.lua` 16/16；`playground/queries/mssql.sql` 19/19 跑两遍

## 环境事实（不读会踩）

- `tests/run.sh` 依赖：兄弟目录 `../poste.nvim`（rtp 硬编码）、可选 `../poste-ai.nvim`、plenary.nvim（自动找常见安装位置）
- 二进制解析顺序：`vim.g.poste_binary` → poste config → cwd/rtp 旁的 `target/{debug,release}/poste` → PATH。**跑 mssql 相关验证必须用 worktree 构建**（main 的二进制不认识 mssql）：
  ```bash
  POSTE_BINARY=$HOME/code/github/poste-for-db/target/debug/poste
  ```
- `poste-for-db/.cargo/config.toml` = rsproxy 镜像（本网络 crates.io 直连不通），仅该 worktree 生效，已随代码提交
- mssql 容器（`playground/docker-compose.yml`）：amd64 镜像 + Rosetta 模拟，`start_period: 120s`；**每次重启重播种子、数据清零**（entrypoint 无守卫重放），与 pg/mysql 行为不同
- diag 调用模板：
  ```bash
  MSSQL_TEST_URL='mssql://sa:Poste_test_2022@localhost:11433/playground' \
  POSTE_BINARY=$HOME/code/github/poste-for-db/target/debug/poste \
  nvim --headless -u NONE -l tests/diag/diag_mssql.lua
  ```

## 剩余工作队列（优先序）

### 1. 立即——人工决策项，agent 不要自作主张

- **push**：poste-db.nvim（`ai` 领先 origin 多个提交）与 poste-for-db（分支只存在于本地）都未推送。推不推、何时推，等用户指示
- **merge-back**：`poste-for-db` → poste.nvim `main` 是 fast-forward，等方言"发货"时执行；用户已明确 worktree 先保留、避免影响其它依赖方

### 2. 主线：Phase 2 = HTTP 传输层 + ClickHouse

- 设计依据：`dialect-support.md` §一/§四 + 文末触点清单（Lua 9 处、Rust 10 处，动手前照单全查）
- 关键架构点：`clickhouse` crate 是 HTTP-only（RowBinary over HTTP）——poste-exec 首个 HTTP 传输在此消化；`Dialect` trait 与传输解耦（`dialect_for` 返回 Some，传输单独路由）
- 连接语义 pin：`clickhouse://user:pass@host:8123/db`，默认用户 `default` 空密码仅 playground 成立
- 验收 = `dialect-support.md`"每步完成标准"十条

### 3. Phase 3/4：Trino → DuckDB（DuckDB 可不做）

- Trino：tpcds 需挂 `etc/catalog/tpcds.properties`；`tpch` 只读，跨引擎核心表进 `memory` catalog（只支持 CTAS、重启即失）
- DuckDB：`duckdb` crate 链 libduckdb 构建重；文件模式 `duckdb:<path>`，沿 `sqlite:` 前缀先例

### 4. 审计缓办清单（上一轮审计的遗留，按性价比排序）

- 补 `import/format.lua`（`parse_csv` 等，187 行零覆盖，风险最高的测试缺口）
- mssql 专属 completion 关键字/函数——**必须连 Rust `functions.rs` 一起改**，否则撞 drift 测试
- introspect job 脚手架收敛：`semantic_diagnostics.lua` 缺 epoch 守卫，迁到 `start_introspect_job`（house primitive）
- `get_search_dir` 6 份副本统一（先枚举行为差异）
- 巨型文件拆分（`db_browser/operations.lua` 1260、`copy.lua` 1207、`db_browser/init.lua` 914、`buffer/init.lua` 859）——**需要真实会话验证 UI，headless 全绿不算数**，见 architecture-harness
- `dialect_icons` 两套合一；`vim.g.poste_insert_hint_debug` 命名对齐；~22 处 `mysql or mariadb` 链待入口归一后清理

## 陷阱清单（本会话实际踩过，不是理论）

1. Lua `resolve_connection_url` 与 Rust `ConnectionConfig::to_url()` 是**镜像实现**，改一处必改另一处，否则静默误路由
2. `poste-cli/src/introspect.rs` 的 dialect_name 链对未知 scheme **静默 fallback 到 postgres**
3. TDS 三连：temp table DDL 必须走批量路径（RPC 作用域退出即丢弃）；MERGE 必须带分号而语句切分会剥掉；`GENERATE_SERIES` 不接受 `AS s(n)` 列别名（列名是 `value`），且 `datetime2` 不支持 `- 整数`
4. exec-file 的语句切分会剥尾分号、剥 `-- @指令` 行和独立 `###` 行——playground 查询文件分段用 `--` 注释
5. stub-covered 模块（session_conn、introspect、highlights/render、file_exec 等）：给它们加顶层 require 前，先看对应 spec 的 `package.loaded` 桩是否在其 require 之前安装
6. spec 顶层的 `package.loaded` 桩会泄漏到同一 nvim 实例的后续 spec 文件——新 spec 自装自卸
7. Lua 陷阱两连（前置声明、`and f() or f` 非三元）见 AGENTS.md，本仓库都真实咬过人

## 人类决策点（悬而未决）

- `connections.toml` 被 git 跟踪（含测试密码）；untrack + `.example` 方案已提议，用户决定**暂不处理**——不要主动动它
- push 与 merge-back 的时机
