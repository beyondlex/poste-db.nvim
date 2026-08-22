# poste-db.nvim 代码审查报告

> 审查方式：核心链路逐文件通读（init / sql_runner / session_conn / exec_run / context / connections / toml / format 等）+ 五个并行深度审查（dataset buffer/UI 层、DB Browser 层、补全/上下文层、执行/导入导出/连接层、测试与工程基建）+ 亲自运行测试套件验证。
>
> 所有结论均经代码核实并标注 `file:line`；未修改任何源码。
>
> 配套文档：[修复计划与架构设计](./fix-plan.md)——由 AI agent 依据本报告与修复计划执行修复/重构。

## 目录

- [0. 总体结论](#0-总体结论)
- [1. P0 安全与数据完整性](#1-p0-安全与数据完整性)
- [2. P1 功能性缺陷](#2-p1-功能性缺陷)
- [3. P2 架构与性能](#3-p2-架构与性能)
- [4. P3 测试与工程基建](#4-p3-测试与工程基建)
- [5. 文档与仓库卫生](#5-文档与仓库卫生)
- [6. 亮点](#6-亮点)
- [7. 附录 A：模块 × 测试覆盖矩阵](#7-附录-a模块--测试覆盖矩阵)
- [8. 附录 B：跨层 Top-10 优先级](#8-附录-b跨层-top-10-优先级)

---

## 0. 总体结论

功能面广（执行、数据集浏览/编辑、DB Browser、补全、内省、导入导出、格式化、会话），模块化子目录划分清晰，部分细节处理到位（bigint 精度、CJK 显示宽度、凭据配置实践）。但存在三类欠账：

1. **安全与数据完整性**：带密码的连接 URL 被整串写入磁盘日志与进程 argv；生成 SQL 标识符几乎不引用（含注入面）；session 失败会重复执行同一语句；编辑提交无事务。
2. **正确性**：至少 5 处"未定义变量/常量/全局"类低级 bug（本可被 lint 与错误路径测试拦住）；多条 Rust 语义路径因笔误成为死代码。
3. **测试工程**：测试套件在 main 上不绿、完全无 CI、测试环境不隔离、13+ 模块零测试、README 键位表与集成测试路径与实现不符。

---

## 1. P0 安全与数据完整性

### P0-1 凭据与查询数据泄漏到磁盘日志和进程列表

**问题**

`state.log`（`poste.nvim/lua/poste/state.lua:198-207`）无级别过滤、无上限，直接 `io.open(..., "a")` 追加写入 `~/.cache/nvim/poste.log`。以下调用点把**含密码的完整连接 URL**或**查询行数据**写入日志：

| 位置 | 内容 |
|------|------|
| `exec_run.lua:322` | `state.log("INFO", "exec-run cmd: " ...)` — 完整 argv 含 `--connection postgres://user:pass@...` |
| `sql_runner.lua:487,527` | `conn=%s` 拼接完整 conn_url |
| `file_exec.lua:368` | `ExecFile cmd: <含 --connection url 的 shell 串>` |
| `db_browser/async.lua:30` | `DB Browser introspect: <argv>` |
| `db_browser/operations.lua:154` | `DB Browser DDL: <argv 含 --connection-url>` |
| `session_conn.lua:127` | stdout 前 200 字节——**含查询结果行数据** |
| `init.lua:164-166` | `:PosteDbSessionList` 通知直接展示含密码的 conn_url |

另外凭据**以 argv 传递**给每个进程，`ps` 可见；其中 session 进程长驻整个编辑会话（`session_conn.lua:192`），密码在进程列表中长期暴露。涉及：`exec_run.lua:72-94`、`session_conn.lua:192`、`introspect/table.lua:24,44,68`、`introspect/column.lua:27`、`file_exec.lua:355`、`db_browser/async.lua:18`。

**修复方向**（详见 fix-plan F1-1 / F1-2）

- `state.log` 增加级别过滤与脱敏（redact `--connection*` 参数、URL 中 password 段）。
- 凭据改经环境变量（如 `POSTE_CONNECTION_URL`）或配置文件路径传递，不进 argv。

### P0-2 语句被重复执行 / 双 fallback

**问题**

`sql_runner.lua:486-525` 的双路 fallback：

- `session_conn.execute` 的 `on_error` 回调（`:490-507`）把**任何** session 错误（含 SQL 语句本身报错）当作"会话失败"，用 `exec-file` **重跑同一段 SQL**——一条失败语句被执行两次（INSERT 部分生效后报错会双写）。
- session 启动失败时 `session_conn.lua:244-254` **既调用 `callbacks.on_error(...)` 又返回 `false`**，于是 `sql_runner` 的 on_error 闭包起 fallback job A、`if not ok` 再起 fallback job B——**两个并发 exec-file 跑同一语句**，且两份响应都通过 `sql_runner.lua:300` 的 `exec_seq` 检查，重复渲染 tab。

**修复方向**：只对传输层失败（session 死亡/未启动）降级；SQL 错误直接抛给用户；tri-state 返回或 once-guard 保证单一执行路径。

### P0-3 生成 SQL 标识符不引用（正确性 + 注入）

**问题**

除 `db_browser/copy.lua:20-26` 的本地 `quote()` 外，全层生成 SQL 均不做 identifier quoting：

- `db_browser/operations.lua:246-275`：`RENAME TABLE/ALTER TABLE ... RENAME TO <vim.ui.input 输入>`，PG/SQLite 分支**裸拼用户输入**（`x; DROP TABLE users;--` 即注入）；MySQL 分支反引号不转义内嵌反引号。
- `db_browser/actions.lua:263,500`、`operations.lua:113,685-695`、`schema_create.lua:11-13`：表/列/schema 名裸拼——混合大小写名（PG 折叠为小写）、保留字（`order`/`user`）、含空格或 `.` 的名字全部生成错误 SQL。
- `db_browser/copy.lua:148-156`：`string.format(sql, name)` 把表名插进 `'%s'`，含 `'` 的合法 PG 名即坏。
- `schema_create.lua:18-38` `gen_grant`：默认 `on_object` 路径产出 `GRANT ... ON ALL TABLES IN SCHEMA IN SCHEMA "x" TO "";`（双重 `IN SCHEMA`），且 grantee 恒为空——`forms_advanced.lua` 的列表条目**没有编辑子字段的路径**。
- `dml.lua:68-86` `build_where`：PK 值 NULL 生成 `col = NULL`（恒 false，需 `IS NOT DISTINCT FROM`）；`dml.lua:15-56` `quote_val`：MySQL 下 `\` 不转义；匹配 `^%-?%d+%.?%d*$` 的字符串被裸输出为数字（VARCHAR 列错误）。

**修复方向**：抽共享 `quote_ident(name, dialect)`（转义 `"`→`""`、`` ` ``→`` `` ``），全层统一；`gen_grant` 按 `on_object` 正确分支；DML 做方言感知转义与 NULL-safe 比较。

### P0-4 编辑提交无事务、无回滚、无 affected-rows 校验

**问题**

`edit_commit/init.lua:214-288` 以 `mode="greedy"`（每条语句自动提交）执行多语句 DML：

- 中途失败报 "Commit failed"，但**之前语句已生效**（部分写入，无 ROLLBACK——模块头注释声称支持回滚，实际不存在）。
- 行被并发删除/修改时逐语句 `affected_rows=0`，**既不检测也不提示**；成功路径（`:246-249`）在 `M < N` 时仍显示 "Committed: N update(s) ... (M row(s) affected)"。
- 无乐观锁。

**修复方向**：`BEGIN/COMMIT` + 失败 `ROLLBACK`；逐语句 affected_rows 与期望值比对，0 影响告警；补显式 rollback API。

### P0-5 导入/导出数据保真损坏

**问题**

- **导出 NULL 写 `"NIL"`**：`export.lua:106-112`（csv_escape）、`:133-150`（tsv）、`:166-188`（md）全部 `tostring(v)`，JSON null 到达为 `vim.NIL` → 导出 `"NIL"`；仅 `format_sql_insert`（`:203`）正确处理。数据完整性损坏。
- **导出 SQL INSERT**（`export.lua:190-218`）：恒用 `"` 引标识符（MySQL 需反引号）、无 schema 前缀、字符串内二进制/控制字符不转义、非原子写（`:247-253`）。
- **CSV 导入不支持带换行的引号字段**（`import/format.lua:12-56` 先按 `\n` 切行再按行解析引号）；`"a" ,b`（引号后空格）误解析出多余字段。
- **导入整读入内存**（`import.lua:132` `f:read("*a")`）+ 数据集多份拷贝；**每 chunk 一个新进程**（`import/execute.lua:90-204`，1 万行 = 100 次进程 spawn）、chunk 无事务、进程级失败后仍继续下一 chunk。
- **`import/execute.lua:59` 未定义全局 `dialog`**——import 报错路径直接崩溃（其余模块均显式 `require("poste.dialog")`）。

**修复方向**：导出 NULL → 空串或显式 `NULL` 标记（按格式约定）；CSV 用状态机解析（quote/escape/CRLF 感知）；导入复用 session + 事务包裹；修 `dialog` require。

### P0-6 TOML 解析器与配置解析缺陷

**问题**

- `toml.lua:10-24` `parse_value`：值带行内注释即损坏——`password = "abc" # c` → `v:sub(2,-2)` 得 `abc" # c`（**静默错误的凭据/配置**）；单引号字符串、数组、dotted key、多行字符串、完整转义均不支持。
- `connections.lua:130-137` `substitute_vars` 无递归（`{{A}}` 的值含 `{{B}}` 不再展开）；`.env` 值内的 `{{VAR}}` 不解析。
- `connections.lua:216-235` URL 构建只对 userinfo 做 percent-encode（`:156-161`）——**database/host/sqlite path 裸拼**（含空格/`?`/`#`/`/` 即坏）；用户自填 `url` 字段不校验。
- `connections.lua:41-42,176-182` 配置缓存（`_config_cache`/`_dotenv_cache`/`_config_search_cache`）**无任何失效机制**（无 BufWritePost 钩子）——编辑 `connections.toml` 后需重启；"找不到"结果也缓存为永久。

**修复方向**：换成熟纯 Lua TOML 解析器（或让 Rust 侧解析）；递归变量替换 + 全路径段编码；按 mtime/版本失效缓存。

---

## 2. P1 功能性缺陷

> 全部经逐行核实，均为明确 bug；修复成本低，建议尽早批量处理。

### P1-1 `statement.lua:89` 引用未定义变量 `output` → Rust 语句边界是死路径

```lua
local parsed, err = cli.run_json({ "context", "stmt-ranges" }, { stdin = input })
if not parsed then return nil end
local ok, parsed = pcall(vim.json.decode, output)   -- output 从未定义！
```

`vim.json.decode(nil)` 抛错被 pcall 吞掉 → `try_rust_stmt_ranges` **恒返回 nil**。后果：`find_stmt_lines` 的 Rust 语义边界 fallback 永远是死路径；两条无 `;` 的语句会被合并成一条；部分选区路径下 `sql_runner.lua:221`（`stmt_lines[1]`）可能 nil 索引崩溃。

**修复**：删除对 `output` 的重新 decode，直接使用 `parsed`，并补 spec。

### P1-2 `insert_hint.lua` 行索引错位 → 标准 `###` 格式下 INSERT 提示失效

`insert_hint.lua:41-51,137-148`：`lines[i - block_start + 1]` 应为 `lines[i]`；且 `block_start = i`（`:36`）未跳过 `###` 标记行。只要光标上方存在 `###`（本插件标准布局），INSERT→VALUES 列高亮的文本与字节偏移全部算错，提示要么失效要么高亮错位。

### P1-3 `constants.lua` 缺失常量 → dirty 守卫抛错、raw mode winbar 失效

`constants.lua` 只定义 `PLUGIN_TITLE`，但 `C.TITLE`/`C.EDIT_CONFLICT_MSG`/`C.RAW_MODE_WINBAR` 被 11+ 处引用：

- `buffer/init.lua:210`、`nav.lua:257`、`page.lua:136`、`search.lua:177` 的 dirty-edit 守卫调用 `vim.notify(C.EDIT_CONFLICT_MSG, ...)`，msg 为 nil → **实测抛 Lua error**，用户看到错误而非"有未保存编辑"警告。
- `nav_raw.lua:42` `C.RAW_MODE_WINBAR` 为 nil → raw mode 永无 winbar。
- `{ title = C.TITLE }` 全部丢失标题。

### P1-4 `connections.lua:341,359` `apply_connection` 未禁用 swapfile → E303

直接 `nvim_buf_set_lines` 修改源 buffer 前未置 `swapfile=false`。headless / swap 目录不可写环境下 `:PosteDbConnection` 崩溃（测试已复现 E303）。

### P1-5 statusline 按连接着色是死代码

`statusline.lua:54-66` 从 `vim.b.poste_sql_context` 提取连接名，但该变量存的是 `nav_ui.lua:17-42` 生成的**展示串**（`"localhost:5432  🗄 blog"`，不含连接名）→ `get_connection_config(name)` 精确查表恒 nil → **README 宣传的 per-connection 颜色从未生效**。

### P1-6 配置发现不一致：cwd vs buffer 目录

`connections.resolve_connection_url` 从 `vim.fn.getcwd()` 搜索（`connections.lua:198`），`get_connection_config`/`list_connections` 从 buffer 目录（`:169`）——`sql_runner.lua:257` 用 cwd 解析 URL，而命名连接的上下文来自 buffer 目录。跨目录打开 SQL 文件可能**找不到配置或找错配置**（与 README "从 SQL 文件向上查找"矛盾）。

### P1-7 `render_dataset` 不消费 `exec_seq` → 陈旧异步覆盖

- `sql_runner.lua:352,388,422` 每次都传 `opts.exec_seq`，但 `buffer/init.lua:361` `render_dataset` **从不读它**。
- `edit_commit/init.lua:116-117` refresh 以 `exec_seq = 0` 无守卫渲染：refresh 在途时用户执行新查询，旧 refresh 结果到达后 `tab_index=1` 触发 `D.tabs = {}`（`buffer/init.lua:366-369`）**清空新结果**并渲染陈旧数据。
- `db_browser/actions.lua:286-294` 无 `data` 时落入 `buffer/init.lua:392` 的 `state.last_response` 全局回退——meta 来自浏览器查询、tab.data 来自上一次手动执行，yank/preview/edit 拿错行。

### P1-8 DB Browser 异步无 epoch/取消 → 竞态覆盖

- `db_browser/async.lua:44` `run_introspect` 丢弃 job_id；`fetch_children`（`:81-344`）无 generation 计数——同一节点快速展开+刷新，旧结果覆盖新结果。
- 内省失败（`:66-77`）回调 nil 后一律 `node.children = {}`——**失败与"库里没表"不可区分**；无超时，job 挂起时节点永久显示"…"加载。
- `init.lua:589-595` `M.close` 只关窗口，不取消在途 job；模块级 `root_nodes/line_to_node`（`init.lua:9-13`）跨会话共享，关闭重开后旧回调污染新树。

### P1-9 其他功能 bug（清单）

| 位置 | 问题 |
|------|------|
| `file_exec.lua:9-30,294-418` | 模块级单例 `S` 无并发保护，第二次 run 破坏第一次的 job 回调/进度窗；`on_exit` 不 flush `partial`，末尾未换行的 JSON（可能是 summary）丢失 |
| `session_conn.lua:226-234` | session 池按 URL 键控，复用**忽略 `@database`**——共享连接的两个 buffer 可能路由到错误数据库 |
| `session_conn.lua:251-262` | `chansend` 失败后 `pending[seq]` 永久悬挂（`on_session_exit` 已跑过不会再清）；`M.stop`（`:267-276`）不 drain pending，指示器卡"running" |
| `session_conn.lua:125-160` | stdout 行缓冲无上限；一行内多个 JSON 对象无法处理 |
| `session_conn.lua:192` | `--timeout 0` 无限等待，一个挂起语句阻塞后续所有请求（顺序处理） |
| `nav.lua:221-229` + `nav_preview.lua:31` | 预览浮窗打开失败后仍以 `buffer=nil` 设键位 → **j/k/q 等被全局劫持** |
| `sql_runner.lua:218` | `clear_panel` 无条件清空 `D.tabs`（含未提交编辑的 tab）——执行新查询**静默丢弃 dirty 编辑**（仅 rerun 键有回滚） |
| `buffer/search.lua:210-213` | 分页关闭时 filter 结果静默截断到前 50 行，winbar 却显示 "All"（`nav_ui.lua:67-74`） |
| `buffer/init.lua:511-540,149-179` | 每次渲染泄漏一个全局 WinClosed autocmd；close() 不清理；149-179 清理块重复两遍（合并残留） |
| `dataset.lua:7` + `buffer/init.lua:461-471` | 单一全局 dataset 窗口无视 tabpage——跨 tabpage 执行时结果渲染到**别的 tabpage 的不可见窗口**；header/close 只扫当前 tabpage |
| `highlights/render.lua:140` | 边框高亮用 `line:sub(1,3)=="┌"` 判断，但传入的都是带 2 空格 padding 的行 → `PosteDbDatasetBorder` 从未生效 |
| `nav.lua:150-157` | `sidescrolloff` 临时置 0 后 `pcall(nvim_win_set_cursor)`，抛错则 sso 永久停在 0 |
| `buffer/init.lua:221-226` / `page.lua` | 切 tab 丢 edit highlights；翻页丢 cell highlight（`nvim_buf_set_lines` 删 extmark 后不重放） |
| `exec_run.lua:62-65`、`statement.lua:49` | USE 检测只匹配 `USE <word>;`——`USE "my db"`、`` USE `db` ``、`USE db -- comment`、多行 USE 漏检 |
| `export.lua:384-401` | `export.M.run` 忽略 `path` 参数——`:PosteDbExport csv file /x/y.csv` 仍弹交互选择器 |
| `file_exec.lua:300-301` vs `sql_runner.lua:498,533` | `max_rows` 不一致：文件执行截断 1000 行，手动执行 0 不限 |
| `exec_run.lua:40-52` | 临时 SQL 文件写进**源文件目录**（`.poste_sql_*.sql`），崩溃残留、污染 git 状态；`strftime+math.random` 同秒碰撞 |
| `completion/data.lua:537` | `vim.notify("DEBUG: binary not found!", ERROR)` **无条件触发**（同文件其余 496-529 行都有 `vim.g.poste_sql_debug` 门控，唯独此处漏）——缺 binary 时每次列补全弹 ERROR |
| `sql_runner.lua:223-225` | `first_line` 回退有运算符优先级 bug（纯外观） |
| `context.lua:19-56` | 每次光标移动读全文件 + 扫 `1..cursor_line`，O(文件大小) |

---

## 3. P2 架构与性能

### P2-1 补全热路径同步阻塞 UI

`completion/init.lua:136`：`try_rust_context_async` 用 **`vim.fn.system()` 同步 spawn `poste context detect`**；`M:get_completions` 恒返回 `is_incomplete_forward = true`（`:318`）→ blink 每次击键重新请求；缓存键含 cursor_line（`:98-101`），移动光标即失效；`extract_sql_block` 每次拷整个 buffer（`:55`）。无 debounce、无 timeout——**二进制卡死即 Neovim 永久冻结**。

讽刺的是为此写的异步客户端 `context_client.lua`（jobstart + JSON-RPC + 指数退避，约 170 行）**从未被任何模块 require，是死代码**（`:3` 注释自认 "NOT used on the completion hot path"）。

### P2-2 补全缓存失效机制残缺（`completion/data.lua`）

- `clear_cache`（`:183-188`）只清 `conn/db` 键；**`__databases__` 缓存（`:426`）永不失效**——`USE` 切库/新增库后 stale 到永远；`db:` 前缀表缓存（`:347`）同样清不到。
- 在途竞态：清缓存后，未完成 jobstart 的 `on_stdout` 无条件回填（`:317,387,582`），无 epoch 校验——被清掉的缓存被过期结果复活。
- `sql_runner.lua:307` **每次执行（含纯 SELECT）都清全量 introspect 缓存**，而非仅 DDL——跑完 SQL 后下次补全要重跑全部内省。

### P2-3 上下文解析无词法感知、跨 block 泄漏

`context.lua:38-53` Phase 2 对原始行做正则：**注释/字符串里的 `USE`、注释掉的 `-- @connection` 会生效**；扫描范围 `1..cursor_line` 是全文——**上一个 `###` block 的指令泄漏到当前 block**，与补全侧 `extract_sql_block` 的块作用域（`completion/init.lua:57-73`）及 `statement.lua` 的块处理语义矛盾。补全上下文与执行上下文对默认 database 的处理也不一致（`completion/data.lua:190-201` 不套用 connections.toml 默认库，`context.lua:63-82` 会）→ 补全缓存键 `conn/` 与执行目标 `conn/default_db` 漂移。

### P2-4 异步模型不统一

- DB Browser：`async.run_introspect`（`db_browser/async.lua:7`）与 `actions.show_table_info`/`operations.show_ddl` 内联 `cli.run_async`（`actions.lua:552`、`operations.lua:156`）与 `copy.lua:217` 裸 `vim.fn.jobstart` **三套并存**，stdout 清洗也三套。
- 阻塞点散落：`exec_run.run_sql` 同步 `vim.fn.system`（`exec_run.lua:267`）被 `editor/column.lua:145`（开编辑器做 PK 内省）与 `db_browser/db_create.lua:47`（开表单查 pg_roles）调用；`introspect/init.lua:158-159` 每次 `K` 同步 `context detect`；`source_format.lua:300` 每 formatter 阻塞至 10s（`jobwait` 且 `exit_code` 读取顺序不保证）。
- 大结果集 3 份内存拷贝：`exec_run.lua:126-198` 累积全部 event → `vim.json.encode(body_obj)` 第二份 → `sql_runner.lua:315-335` 再 decode 第三份；布局路径对全部行做 O(R×C) `strdisplaywidth` 扫描（`format.lua:502-555`），10 万行 × 10 列即百万级 RPC，即使只显示一页 50 行。

### P2-5 状态管理碎片化与双真相源

`poste-db.state`（`state.lua`）+ `poste.state.sql` 懒加载 `__index`（poste.nvim `state.lua:100-107`）+ `session.lua` 模块级 `active` + `dataset.lua` 模块级 `D`。`state.last_response`/`state.sql.cell`/`state.sql.pagination` 被多处直接读写；tab 光标同时存于 `D.tabs[].cursor` 与全局 `state.sql.cell`——**两处真相源**，漏同步即错位（如 `find_column` 只改 cell 不回写 tab.cursor）。

### P2-6 `init.lua setup()` 上帝函数与调试残留

`init.lua` 626 行：约 20 个用户命令、多组 autocmd、注册逻辑重复（`register_sql_completion` 与 `PosteDbCmpReload`）；**默认注册 7+ 个调试命令**（`PosteDbDiag:364`、`PosteDbDebugSpace:409`、`PosteDbCmpTest:434`、`PosteDbCmpDebug:480`、`PosteDbCmpStatus:266`、`PosteDbAutoTrigger:313`、`PosteDbCmpReload:342`）；`completion/init.lua:181-183` 的 `detect_context_for_completion` 是恒返回 `"keyword"` 的假桩（`:PosteDbCmpStatus`/`:PosteDbDiag` 显示假上下文）；`PosteDbDiag`（`init.lua:374`）调用已删除的 `_test.extract_from_tables` 直接报错。

### P2-7 耦合与重复

- **blink.cmp 深耦合**：`completion/adapter.lua:79,113,130` 改写 `per_filetype_provider_ids`、require `blink.cmp.completion.windows.menu`/`completion.trigger`/`types` 私有模块、monkey-patch 全局配置（`:135-147`）；`init.lua:302` 直接 require `blink.cmp.types` 违反 adapter 自声明的唯一入口约定（`adapter.lua:3-5`）；patch 有 **setup 顺序依赖**（用户 `blink.setup()` 在 poste 之后会整体覆盖补丁）。
- **文件类型设置 4 条路径并存**（ftdetect + `init.lua:120,174,551,610`）；`after/queries/sql/highlights.scm` 影响**所有** SQL 文件（越界副作用）。
- **死代码**：`context_client.lua`、`db_browser/tree.lua:102` `make_index_node`、`nav_ui.lua:10-15` `format_conn_short` 与 `format.lua:84` 重复、`highlights/render.lua:83` `invalidate_sep_cache` 空桩、`syntax/poste_sql.vim:49-51` `NONE_MATCH` 占位。
- **重复实现**：图标表（`context.lua:162` vs `connections.lua:274-279`）；单元格边界扫描（`highlights/render.lua:16-44` vs `buffer/header.lua`）；SQL 关键字表（`syntax.lua`/`log_viewer`/`completion/data.lua`）；DB Browser helpers（`actions.lua:65-93` vs `operations.lua:23-54`）；双表单系统（`forms.lua` vs `forms_advanced.lua`）。
- **require 时副作用**：`statement_indicator.lua:7-25`（`nvim_set_hl`/`sign_define`）、`highlights/init.lua:21-23`（`setup()`+autocmd）、`syntax.lua:12-16`、`init.lua:14`（`insert_hint.setup()`）——测一个模块必然连带副作用。
- **statusline 篡改第三方全局配置**：`statusline.lua:69-109` 替换 `mini.statusline.config.content.active`，无恢复机制；`setup_lualine`（`:119-141`）每次调用 `lualine.setup()` 重初始化。

### P2-8 性能与内存细节

- 搜索每次击键 O(行×列) 全扫 + `tostring` 垃圾（`buffer/search.lua:125-141`）；matches 跨页全量常驻。
- 数据集 tab 全量驻留：`dataset.lua:28-50` 保存 `padded_full/meta_full/original_rows`。
- `_ctx_cache` 无界增长（`completion/init.lua:19,145`）。
- 字节截断切坏 UTF-8：`log_viewer.lua:78,189`、`format.lua:794-800` 按 `#s` 截断，CJK 被切坏。
- `nav_cell.json_pretty`（`:17-50`）无深度/大小限制，巨深 JSON 生成数十万行预览。
- `statement_indicator.lua:27-38` `bound_sign_ids[buf]` 对已删 buffer 永不清理；长语句逐行 `sign_place`。
- `edit_commit/log.lua:46-62` 每 10 次写全量重读重写日志文件（O(n)）。

---

## 4. P3 测试与工程基建

### P3-1 测试套件在 main 上不绿

实测 `tests/run.sh`（nvim 0.12.3）：48 个 spec 文件 / 7336 行测试 / 617 用例行通过 / 2 失败：

- `tests/sql/sql_buffer_nav_spec.lua:58`：断言 winbar 含 `localhost:5432/blog`——该信息早已移到 statusline（`nav_ui.lua:17-42`），新测试 `sql_buffer_nav_ui_spec.lua:45` 明确断言 `is_falsy`。**两个测试相互矛盾**，前者为重构残留，且在 3 次全量运行中失败 2 次（间歇性，测试共享全局状态所致）。
- `tests/sql/sql_connections_spec.lua:346`：`apply_connection` 的 E303（见 P1-4）。

### P3-2 完全无 CI

`.github/` 不存在，无任何 workflow；`tests/run.sh` 从未在机器上运行过。**这是红套件长期无人发现的直接原因。**

### P3-3 测试环境不隔离

- `tests/run.sh:14-20` 启动 nvim **无 `-u NONE`/`-u minimal_init`**，加载用户真实 `~/.config/nvim/init.lua`；`minimal_init.lua` 只作为 plenary 选项追加 rtp，**从未替代 vimrc**。用户插件（mini.statusline/blink.cmp 等）会真实影响被测行为。
- `tests/run.sh:6` `PLENARY_PATH` 硬编码 lazy 安装路径，未安装直接 `exit 1`；`:17` 依赖兄弟目录 `../poste.nvim`；`:19` `runtime plugin/poste-db.lua` 会执行 `setup()`——约 20 个命令/autocmd 副作用进测试进程。
- 无 tree-sitter SQL parser 时 TS 相关测试**静默 `pending()`**（`sql_multi_stmt_spec.lua:410-450`），`make_buf` 还 `vim.wait(500)` 空等——诊断/语义诊断断言永不执行。
- 48 个 spec 在同一进程顺序执行，共享 `D.tabs`/`state.sql`/`vim.g`/`package.loaded` 全局状态（如 `sql_connections_spec.lua:19-28` 桩掉整个 toml 模块）。
- `tests/diag/diag_sql.lua` 是孤立脚本，未接入 run.sh，头部注释路径与实际不符。

### P3-4 覆盖缺口（详见附录 A）

13+ 模块零测试，最严重者：`semantic_diagnostics.lua`（517 行，tree-sitter 遍历）、`session_conn.lua`（311 行，job 生命周期）、`export.lua`（419 行）、`source_format.lua`（570 行）、`insert_hint.lua`（212 行纯解析逻辑）、`toml.lua`（真实解析器被测试桩绕过）、`buffer/search.lua`、`buffer/page.lua`、`completion/adapter.lua`、`statusline.lua`、`syntax.lua`、`health.lua`、`help.lua`。DB Browser 约 80% 交互路径零覆盖（含 `operations.lua` 1007 行、`copy.lua` 733 行）。

`test_db_browser_highlights.lua` 不以 `_spec.lua` 结尾 → **PlenaryBustedDirectory 从不执行它**，且它复制粘贴了一份被测实现。

另有 3 个测试**固化 bug 行为**：`sql_multi_stmt_spec.lua:133-176` 以 "KNOWN BUG: falsely splits" 断言当前错误行为（双引号标识符含 `;` 误切、注释/多行字符串内 `;` 泄漏）——未来重构会被这些测试锁死。

### P3-5 无 lint/格式/许可证

无 `.luacheckrc`/`.stylua.toml`/`selene.toml`/`.editorconfig`——22,783 行 Lua 无静态检查（P1 的多个"未定义变量/常量"正是 lint 能拦住的类型）。无 LICENSE 文件（README 声称 MIT）。

### P3-6 版本声明不符

`health.lua:12` 声称 `nvim >= 0.9.0`，但 `init.lua:95,123-124,554-555`、`semantic_diagnostics.lua:24`、`ts_stmt.lua:11` 使用 `vim.treesitter.language.*`（**0.10 才引入**）；0.9 上 `init.lua:95` 的 pcall 参数求值阶段就抛错（`vim.treesitter.language` 为 nil）→ **setup() 直接崩溃**而非优雅降级。winbar 选项同样要求 0.10。README 未声明最低版本；blink.cmp 与 poste binary 均未 pin。

---

## 5. 文档与仓库卫生

- **README 数据集编辑键位表错误**（`README.md:117-121`）：声称 `i`/`a` 编辑、`o`/`O` 插入行、`u` 撤销——实际只绑 `i`/`cc`/`dd`/`o`/`<leader>w`（`buffer/init.lua:122-131`），**`a`、`O`、`u` 从未绑定**。
- **README 集成测试路径错误**（`README.md:201-212`）：`cd tests/sql && docker compose up -d` 与 `tests/sql/queries/postgres.sql` 不存在；真实 compose/queries 在 `playground/sql/`。
- **补全设计文档路径全部过期**（`docs/dev/sql/completion/README.en.md:17-21`）：引用 `lua/poste/sql/`（实际 `lua/poste-db/`）与 `crates/poste-core/`（本仓库无 crates/，已迁至 poste.nvim）。
- **docs/dev/sql/README.md 索引不全**：只列 4/10 篇；"Last updated: 2026-08-01" 为未来日期。
- **AGENTS.md 引用不存在文件**：`lua/poste/help.lua`（poste.nvim 无此文件，实际在本仓库 `lua/poste-db/help.lua`）；`LEARNINGS.md` 不存在。
- **测试残留**：`minimal_init.lua:8` 引用不存在的 `tests/helpers/` 目录；`sql_tab_spec.lua:8` 注释 "Multi-statement execution is not yet implemented" 早已过期。
- **仓库卫生（合格项）**：`.gitignore` 忽略 `.env`/`.env.*`；`connections.toml` 提交的均为 `{{VAR}}` 占位符；磁盘 `.env` 无真实凭据。小瑕疵：`playground/sql/env.json` 提交了 dev 凭据形状；`syntax/*.vim` 头部 "Latest Revision: 2026-06-09" 为未来日期。

---

## 6. 亮点

- 模块化子目录划分清晰（buffer/db_browser/completion/introspect/edit_commit/import…），共享基础设施收敛在 poste.nvim。
- 架构文档齐备（`docs/dev/sql/` 有设计文档与迁移计划），补全系统有 P0-P4 分级文档。
- bigint（>2^53 字符串保真）、CJK/emoji 显示宽度（`strdisplaywidth`）等细节处理到位且有回归测试（`sql_format_bigint_spec.lua`）。
- 凭据配置实践正确：`{{VAR}}` 占位 + `.env` gitignore + 运行时解析（问题只在运行期日志泄漏与 argv 暴露）。
- 测试数量不少（46 个 spec），纯函数（format/introspect 路由/completion 关键字）覆盖尚可。

---

## 7. 附录 A：模块 × 测试覆盖矩阵

**零测试模块**（`grep -r 'poste-db.<mod>' tests/sql/` 无命中）：

`health.lua`、`help.lua`、`statusline.lua`、`insert_hint.lua`、`source_format.lua`、`syntax.lua`、`session.lua`、`session_conn.lua`、`export.lua`、`context_client.lua`、`snippets.lua`、`semantic_diagnostics.lua`、`diagnostics.lua`、`toml.lua`（被测试桩绕过）、`buffer/search.lua`、`buffer/page.lua`、`buffer/header.lua`（仅切片助手）、`completion/adapter.lua`、`completion/debug.lua`、`db_browser/{operations, copy, forms, forms_advanced, async, context_menu, db_create, schema_create, completion}.lua`、`editor/nav.lua`、`editor/column.lua`、`import/{execute, mapping}.lua`、`highlights/theme.lua`。

**薄弱测试**：

- `sql_sql_runner_spec.lua`（85 行）：仅 keymaps + "binary not found"，session/exec-file 双路径与 fallback 逻辑（P0-2）零覆盖。
- `sql_file_exec_spec.lua`（25 行）：冒烟测试，无 parse/partial-line/cancel 覆盖。
- `sql_editor_spec.lua`（976 行）：只覆盖 `editor/cell.lua` 纯函数，`editor/nav.lua` 交互流与守卫未测。
- `sql_statement_indicator_spec.lua`（~15 行）：只测 toggle/clear 无异常。
- `sql_dml_spec.lua`：无 NULL WHERE、无 MySQL 反斜杠转义、无多列 PK、无并发删除场景。
- `sql_import_spec.lua`：无内嵌换行 CSV、无 execute_import 集成、无 preview 一致性。
- `sql_state_spec.lua`/`sql_util_spec.lua`：仅默认值/少量函数。
- `db_browser_spec.lua:16-34`：同义反复的 characterization test（手写表再断言表内容）。

**可测试性提示**：纯函数（可单测）——`format.lua` 的 `cell_to_string`/`calc_column_widths`/`render_page`/`render_view`/`plan_resultset_layout`、`nav_cell.json_pretty`/`clipboard_text`、`nav_sort.next_sort_state`、`dataset.compute_view_indices`、`header.build_header_index`/`slice_header_to_win`、`log_viewer` 的 `_filter_matches`/`_format_time`/`_preview_sql` 等、`nav_ui.build_*` 文本构造。强不纯——`position_cursor`/`refresh_page`/`render_dataset`/`switch_tab`/`close`/`header.update`/`search` 全部/`statement_indicator`/`statusline.setup`。

---

## 8. 附录 B：跨层 Top-10 优先级

| # | 问题 | 证据 | 对应修复 |
|---|------|------|---------|
| 1 | 凭据/查询数据落盘与 argv 暴露 | P0-1 | F1-1/F1-2 |
| 2 | 语句重复执行 / 双 fallback | P0-2 | F1-3 |
| 3 | 生成 SQL 标识符不引用（注入） | P0-3 | F1-4 |
| 4 | 编辑提交无事务/无校验 | P0-4 | F1-5 |
| 5 | 导出 NULL 写 "NIL" / CSV 导入损坏 | P0-5 | F1-6 |
| 6 | 未定义符号类 bug（statement.lua:89、constants、import/execute.lua:59…） | P1-1/2/3 | F2 批量 |
| 7 | 补全热路径同步阻塞 + 缓存失效残缺 | P2-1/2 | F3-2/F3-3 |
| 8 | 异步竞态（DB Browser epoch、render exec_seq、file_exec 单例） | P1-7/8 | F3-1 |
| 9 | 上下文解析词法/作用域缺陷 | P2-3 | F3-4 |
| 10 | 红套件 + 无 CI + 测试不隔离 | P3-1/2/3 | F0-1/F0-2 |
