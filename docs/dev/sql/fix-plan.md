# poste-sql.nvim 修复计划与架构设计

> 本文件是 [代码审查报告](./review-report.md) 的执行配套文档。后续由 AI agent 依据本文件执行修复/重构。
>
> **执行约定**：
> - 每个任务以 `### Fx-y <标题>` 为单位，独立提交；一次只做一批，批内可并行。
> - 每个任务完成后必须：`./tests/run.sh` 全绿（或该批明确说明新增的失败为预期并附理由）；无 lint 新增告警（阶段 0 落地后）。
> - 涉及 poste.nvim 共享基础设施的改动需在 `../poste.nvim` 同步提交并说明。
> - 每个任务标注 `涉及文件` 与 `验收标准`；改动不得扩大本任务范围。
> - 优先级：P0 = 数据安全/完整性，P1 = 功能 bug，P2 = 架构，P3 = 工程。
> - 复杂的架构任务（F3 系列）必须先读对应设计小节再动手，禁止边改边设计。

## 目录

- [阶段 0 基建先行（安全网）](#阶段-0-基建先行安全网)
- [阶段 1 P0：安全与数据完整性](#阶段-1-p0安全与数据完整性)
- [阶段 2 P1：功能 bug 批量修复](#阶段-2-p1功能-bug-批量修复)
- [阶段 3 P2：架构重构与设计](#阶段-3-p2架构重构与设计)
- [阶段 4 P3：测试体系升级](#阶段-4-p3测试体系升级)
- [阶段 5 文档与收尾](#阶段-5-文档与收尾)
- [依赖关系图](#依赖关系图)

---

## 阶段 0 基建先行（安全网）

> 先建 CI 与测试隔离，让后续每个任务都有可验证的基线。此阶段结束的标志：`tests/run.sh` 在干净环境全绿，且 CI 上同样全绿。

### F0-1 建立 CI 与修绿测试套件

- **优先级**：P3（但最先做）
- **问题**：无 `.github/`；`sql_buffer_nav_spec.lua:58`（winbar 断言与现行实现矛盾、间歇失败）与 `sql_connections_spec.lua:346`（E303）使套件不绿。
- **方案**：
  1. 修 `sql_connections_spec.lua` 暴露的根因：`connections.lua:341,359` 的 `apply_connection` 在 `nvim_buf_set_lines` 前对目标 buffer 置 `vim.bo[buf].swapfile = false`（或 pcall 包裹），消除 E303。
  2. 裁决 winbar 断言之争：与 `sql_buffer_nav_ui_spec.lua:45` 对齐——若 winbar 有意不显示连接信息，删除 `sql_buffer_nav_spec.lua:58` 的断言（其覆盖内容已由 nav_ui spec 承担）；若认为 winbar 应显示连接，则改 `nav_ui.build_status_left` 加入连接片段并更新两个 spec。
  3. 新增 `.github/workflows/ci.yml`：Ubuntu + nvim stable + nightly；按 run.sh 约定 clone `poste.nvim` 为兄弟目录；安装 plenary（`vim.fn.stdpath` 或检测候选路径）；`:TSInstall sql`（让 TS 相关测试真正执行）；跑 `tests/run.sh`。binary 缺失时相关测试应显式 skip 并输出 skip 计数（见 F0-2）。
- **涉及文件**：`connections.lua`、`tests/sql/sql_connections_spec.lua`、`tests/sql/sql_buffer_nav_spec.lua`、`.github/workflows/ci.yml`（新增）
- **验收标准**：本地 `./tests/run.sh` 全绿；CI 工作流在干净 Ubuntu 上通过；失败时 CI 红。
- **风险**：nvim nightly 行为漂移——CI 用 stable 为准，nightly 允许 warn。

### F0-2 测试环境隔离

- **优先级**：P3
- **问题**：`tests/run.sh:14-20` 无 `-u NONE`，加载用户真实配置；`PLENARY_PATH` 硬编码 lazy 路径；`runtime plugin/poste-sql.lua` 带入 `setup()` 全部副作用。
- **方案**：
  1. `tests/run.sh` 改为 `nvim --headless -u tests/minimal_init.lua`（真正替代 vimrc）+ 显式 `runtime plugin/plenary.vim`；`-c "lua require('poste-sql.init').setup()"` 显式调用 setup（隔离后的受控副作用）。
  2. `PLENARY_PATH` 参数化：优先环境变量 `PLENARY_PATH`，其次检测常见路径，找不到则提示安装并给一键引导（如 `git clone --depth 1 https://github.com/nvim-lua/plenary.nvim`）。
  3. `minimal_init.lua` 清理：删除不存在的 `tests/helpers/?.lua` 引用（`:8`）；buffer 0 的 filetype 设置加守卫。
  4. `tests/diag/diag_sql.lua` 决定去留：接入 run.sh 或删除；修正头部注释路径。
  5. TS 相关测试：无 parser 时改为显式 `pending` 并汇总输出 skip 计数（而非静默），CI 装 parser。
- **涉及文件**：`tests/run.sh`、`tests/minimal_init.lua`、`tests/diag/diag_sql.lua`
- **验收标准**：测试日志无用户配置输出；无 plenary 依赖时给出可执行指引；TS 用例在装/不装 parser 两种环境下行为可预期。

### F0-3 静态检查与格式基线

- **优先级**：P3
- **问题**：无 `.luacheckrc`/`.stylua.toml`/`selene.toml`；P1 的"未定义变量/常量/全局"类 bug 本可被 lint 拦截。
- **方案**：新增 `.luacheckrc`（启用 `globals` 声明、`unused`、`undefined` 检查；为 `vim.*`、`_G` 声明）+ `.stylua.toml`（2 空格、与现有风格一致）+ `.editorconfig`。跑一遍，存量告警列入清单分批清理（不要求一次清零，但新代码不得新增）。
- **涉及文件**：`.luacheckrc`（新增）、`.stylua.toml`（新增）、`.editorconfig`（新增）
- **验收标准**：`luacheck lua/` 可运行且告警数单调下降；CI 中接入（可选）。
- **注意**：`completion/init.lua:176-179` 的 `detect_context_for_completion` 假桩与 `_test` 导出会触发告警，先记录后处理（见 F2-8）。

### F0-4 许可证与仓库卫生

- **优先级**：P3
- **问题**：无 LICENSE 文件（README 声称 MIT）；测试运行会在仓库根目录产生 `nvim.log`（未被 gitignore）。
- **方案**：新增 MIT `LICENSE` 文件；删除 `playground/sql/env.json` 或改为占位符（不提交凭据形状）；`.gitignore` 增加 `nvim.log`；清理 `sql_tab_spec.lua:8` 过期注释。
- **验收标准**：`git ls-files` 含 LICENSE；`playground/sql/env.json` 无真实值。

---

## 阶段 1 P0：安全与数据完整性

### F1-1 日志脱敏与级别过滤

- **优先级**：P0
- **问题**：审查报告 P0-1。带密码 URL 写入 `~/.cache/nvim/poste.log`；`state.log` 无级别过滤、无上限；session stdout 含行数据入日志。
- **方案（设计）**：
  1. 在 `poste.nvim` 的 `state.log` 增加级别门控：`M.config.log_level`（默认 `"WARN"`），`DEBUG`/`INFO` 不落盘除非显式开启。**注意**：`state.log` 是 poste.nvim 共享设施，改动需评估对 HTTP/Redis 模块的影响——建议在 poste.nvim 侧做兼容性修改（新增 `state.log_level` 配置，默认保持现行为或按调用方传入级别过滤，需与 poste.nvim 维护者确认）。
  2. 若不能改共享设施，则在 poste-sql 侧新增 `lua/poste-sql/log.lua` 包装层：`M.info(conn_url, ...)` 等，统一在入口做 URL 脱敏后再调 `state.log`。
  3. 脱敏规则（统一函数 `redact_url(url)`）：`scheme://user:***@host:port/db`——只保留 user 与 host:port/db，抹掉 password 段；argv 日志中对 `--connection*` 参数整体替换为 `<redacted>`。
  4. 逐点替换（必须全改）：`exec_run.lua:322`、`sql_runner.lua:487,527`、`file_exec.lua:368`、`db_browser/async.lua:30`、`db_browser/operations.lua:154`、`session_conn.lua:127`（改记字节数）、`init.lua:164-166`（`:PosteSQLSessionList` 显示脱敏 URL）。
- **涉及文件**：`poste.nvim/lua/poste/state.lua`、`lua/poste-sql/{exec_run,sql_runner,file_exec,init,context}.lua`、`lua/poste-sql/db_browser/{async,operations}.lua`、`lua/poste-sql/session_conn.lua`、新增 `lua/poste-sql/log.lua`
- **验收标准**：grep 确认所有 `state.log` 调用不再含 password 段；`:PosteSQLSessionList` 展示脱敏；开启 DEBUG 日志后 URL 仍脱敏；`session_conn.lua:127` 不再打印行数据。
- **风险**：poste.nvim 共享改动需同步回归其 HTTP/Redis 模块。

### F1-2 凭据传递改环境变量（不进 argv）

- **优先级**：P0
- **问题**：审查报告 P0-1 后半。凭据以 argv 传进程，`ps` 可见；session 进程长驻。
- **方案（设计）**：
  1. 在 poste.nvim 的 `cli.run_async`/`cli.run` 增加 `opts.env` 支持（`jobstart` 的 `env` 字段 / `vim.fn.system` 不直接支持 env——同步路径改用临时 env 包装或 `vim.fn.environ()` 合并后逐项覆盖？**注意**：`vim.fn.system` 无 env 参数，同步路径需评估：a) 改为 `vim.system`（异步，支持 env）；b) 或接受同步路径走 argv 但确保该路径不经手用户凭据。建议优先异步化同步路径（见 F3-1/F3-5）。
  2. 新增共享约定：`POSTE_CONNECTION_URL` 环境变量传递连接 URL；Rust 侧 `poste` binary 需支持从该环境变量读连接（**跨仓库任务**：poste.nvim crates 侧改动，需同步设计文档）。
  3. poste-sql 侧所有 `build_cmd`（`exec_run.lua:72-94`、`session_conn.lua:192`、`introspect/table.lua`、`introspect/column.lua`、`db_browser/async.lua`、`file_exec.lua:355`）不再拼 `--connection <url>` 进 argv，改传 env。
- **涉及文件**：`poste.nvim/lua/poste/cli.lua`、`poste.nvim/crates/*`、`lua/poste-sql/{exec_run,session_conn,file_exec}.lua`、`lua/poste-sql/introspect/{table,column}.lua`、`lua/poste-sql/db_browser/async.lua`
- **验收标准**：`ps` 中看不到连接 URL/密码；session 进程环境变量可读性受限（`procfs` 仍可见，但比 argv 面小且可控）；Rust 侧有对应读取实现。
- **风险**：跨仓库任务，先出设计文档（poste.nvim 侧 issue/PR）再实现；若 Rust 侧排期不允许，本任务可降级为：仅修 F1-1 脱敏 + 文档标注 argv 风险，并给 `state.log` 移除 argv 日志。

### F1-3 修重复执行 / 双 fallback

- **优先级**：P0
- **问题**：审查报告 P0-2。session 语句错误触发 exec-file 重跑；session 启动失败双 job。
- **方案（设计）——执行路由状态机**：
  1. `session_conn.execute` 返回值改为三态：`"dispatched"` / `"start_failed"` / `"not_running"`，并保证 start 失败时**只**返回状态、不回调 `on_error`（或回调但标记 `fallback_started`）。
  2. `sql_runner.lua:486-525` 重构：引入 `executed = false` once-guard，fallback 只允许一次；`on_error` 回调中区分错误类型：
     - 传输层错误（session 退出、start 失败）→ 走 exec-file fallback（一次）；
     - SQL 语句错误（`resp.has_error`）→ 直接渲染错误、**不重跑**。
  3. `session_conn.lua:99-116` `process_event`：`resp.has_error` 时改调专用 `on_sql_error`（新增回调槽位），与传输层 `on_error` 分离。
  4. 补 `exec_seq` 语义：同一个 run 的 session 响应与 fallback 响应共享一个 token，二者只渲染其一（先到者赢）。
- **涉及文件**：`lua/poste-sql/sql_runner.lua`、`lua/poste-sql/session_conn.lua`
- **验收标准**：新增测试覆盖——a) session 内 SQL 报错只执行一次（用 mock session 断言 exec-file 未被调用）；b) session 启动失败只起一个 fallback；c) 双路径响应不重复渲染 tab。`sql_runner` 现有 spec 补充这些用例。
- **风险**：行为变更会影响用户已习惯的"错误自动重试"（若有）——审查确认当前无此特性，属纯修复。

### F1-4 标识符引用统一（quote_ident）

- **优先级**：P0
- **问题**：审查报告 P0-3。
- **方案（设计）**：
  1. 新增 `lua/poste-sql/ident.lua`：
     ```lua
     -- 方言感知的标识符引用
     function M.quote(name, dialect)
       -- postgres/sqlite: "name" 且内部 " 转义为 ""；mysql/mariadb: `name` 且内部 ` 转义为 ``；
       -- 已含引号/已合格（a.b）分段引用；空/含通配符 * 原样
     end
     function M.quote_qualified(schema, table, dialect)  -- 分段各自引用后 . 连接
     function M.quote_literal(v, dialect)                -- 字符串字面量（' 转 ''，MySQL 额外转义 \）
     end
     ```
  2. 接入点（全改）：`db_browser/operations.lua:246-275`（rename/modify——用户输入必须 quote + 转义）、`:113,521-531,685-695`、`db_browser/actions.lua:263,500`、`db_browser/schema_create.lua:11-13`（含 gen_grant 重写：`on_object` 分支正确化 + grantee 非空校验）、`db_browser/copy.lua:148-156`、`dml.lua:15-56,68-86`（NULL-safe WHERE：`col IS NOT DISTINCT FROM ?` 或 `col IS NULL` 分支；字符串按列类型决定是否裸输出）。
  3. `schema_create.gen_grant` 重写（P0-3 细节）：`on_object="ALL TABLES IN SCHEMA"` 时不再追加第二个 `IN SCHEMA`；`on_object="SCHEMA"` 时附 schema 名；`forms_advanced.lua` 列表条目增加子字段编辑（Enter 进入 grantee/privileges 编辑）或至少阻止空 grantee 提交。
- **涉及文件**：新增 `lua/poste-sql/ident.lua`、`lua/poste-sql/db_browser/{operations,actions,schema_create,copy}.lua`、`lua/poste-sql/dml.lua`、`lua/poste-sql/db_browser/forms_advanced.lua`
- **验收标准**：新增 `tests/sql/sql_ident_spec.lua`（各方言引用/转义/合格名/通配符）；DB Browser 生成的 SQL 在 PG/MySQL/SQLite 下对含空格、大写、保留字的名字可执行（集成验证可选）；rename 输入 `x; DROP TABLE users;--` 被引用为字面名。
- **风险**：行为变更影响生成 SQL 的显示——引用后 `SELECT * FROM "MyTable"` 与旧 `MyTable` 不同，需在变更说明中列出。

### F1-5 编辑提交事务化

- **优先级**：P0
- **问题**：审查报告 P0-4。
- **方案（设计）**：
  1. `edit_commit/init.lua:214-288` 改为：`BEGIN` → 逐语句执行（每语句独立序号，收集 affected_rows）→ 全部成功 `COMMIT`，任一失败 `ROLLBACK` 并报告已回滚。
  2. 依赖：session 模式天然支持多语句与事务（`mode="transaction"` 或逐条 `BEGIN/COMMIT` 经 session 通道）；exec-file 路径（fallback）需评估是否支持事务模式（`exec_run.build_cmd` 已有 `mode` 参数，`"transaction"` 语义需与 Rust 侧确认）。
  3. 逐语句 affected_rows 与期望值比对：DELETE/UPDATE 期望影响行数在提交前从 tab 状态得出；0 影响时 WARN 并提示"行可能已被并发修改"（乐观锁 v1：仅告警；v2：WHERE 加版本列——本期不做）。
  4. 新增 `rollback_edits` 显式入口（`editor/nav.lua:369-383` 已有逻辑，需接入提交失败路径与键位）。
- **涉及文件**：`lua/poste-sql/edit_commit/init.lua`、`lua/poste-sql/session_conn.lua`（若需事务透传）、`lua/poste-sql/editor/nav.lua`
- **验收标准**：新增 `sql_edit_commit_exec_spec.lua` 用例——中途失败后数据库无部分写入（用 SQLite 内存库集成验证）；0 影响行 WARN 提示；回滚后 tab 状态恢复可编辑。
- **风险**：事务会持有锁更久，长编辑批量提交可能阻塞——提交前提示影响行数上限（沿用 `EDIT_MAX_ROWS`）。

### F1-6 导入/导出数据保真

- **优先级**：P0
- **问题**：审查报告 P0-5。
- **方案**：
  1. 导出 NULL：`export.lua:106-112,133-150,166-188` 的 csv/tsv/md 中 `vim.NIL`/nil → 空串（CSV/TSV/MD 惯例）或可配置 `NULL` 标记；与 `format_sql_insert`（`:203` 已正确）行为对齐。补 spec（`sql_export_spec.lua` 新增）。
  2. 导出 SQL INSERT：`export.lua:190-218` 方言感知引用（MySQL 反引号）、schema 前缀（可选参数）、二进制/控制字符 hex 转义、原子写（先写临时文件再 rename）。
  3. CSV 导入：`import/format.lua:12-56` 改为全文本状态机解析（quote/`""` 转义/CRLF/内嵌换行）；`"a" ,b` 空格处理。补 `sql_import_spec.lua` 用例（RFC 4180 内嵌换行、引号字段含逗号、CRLF）。
  4. 导入执行：`import/execute.lua:90-204` 改为复用 session 批量执行（一次进程、多语句）或至少按 chunk 事务化；进程级 `on_error` 停止而非继续；修 `import/execute.lua:59` 未定义全局 `dialog`（`local dialog = require("poste.dialog")`）。
  5. 导入内存：`import.lua:132` 整读改流式（按行解析 + 行数上限提示）；preview 显示**校验/强转后**的值（`import/preview.lua:18-38` 与 `import/mapping.lua:9-34` 对齐，如 `"007"` → `7`）。
- **涉及文件**：`lua/poste-sql/export.lua`、`lua/poste-sql/import/format.lua`、`lua/poste-sql/import/execute.lua`、`lua/poste-sql/import.lua`、`lua/poste-sql/import/preview.lua`、`lua/poste-sql/import/mapping.lua`、新增 `tests/sql/sql_export_spec.lua`
- **验收标准**：导出 CSV 中 NULL 为空串（或标记）；含逗号/引号/换行的值导出后可被标准 CSV 解析器还原；导入含内嵌换行的 CSV 行数正确；导入中途进程失败即停；`dialog` 报错路径不再崩溃。

### F1-7 TOML 解析器与配置解析

- **优先级**：P0（配置错误=凭据错误）
- **问题**：审查报告 P0-6。
- **方案（设计）**：
  1. 替换 `toml.lua`：优先引入成熟纯 Lua TOML 解析器（评估 `lua-toml`/`toml.lua` 等，要求纯 Lua、无外部依赖、可进 runtimepath）；**备选**：让 Rust 侧暴露 `poste config parse` 子命令解析（避免 Lua 侧维护 TOML 语法）。
  2. 若保留自研：至少支持——行内注释（字符串外剥离）、单引号字符串、`\u`/`\x`/`\b`/`\f`/`\r` 转义、数组、dotted key、多行字符串；parse_value 对未闭合引号报错而非静默截断。
  3. `connections.substitute_vars`（`:130-137`）支持递归展开（上限防环）；`.env` 值内 `{{VAR}}` 解析（`parse_dotenv` 后对值再做一轮 substitute）。
  4. URL 构建（`:216-235`）：database/host/sqlite path 分段 percent-encode；`url` 字段直接使用前做 scheme 校验。
  5. 配置缓存失效：`_config_cache`/`_dotenv_cache`/`_config_search_cache`（`:41-42,77-91,168-190`）按文件 mtime 失效（缓存条目带 `{mtime, value}`）；"not found" 缓存加短 TTL（如 5s）或监听 BufWritePost。
- **涉及文件**：`lua/poste-sql/toml.lua`、`lua/poste-sql/connections.lua`、新增 `tests/sql/sql_toml_spec.lua`
- **验收标准**：`sql_toml_spec.lua` 覆盖——行内注释不损坏值、单引号串、转义、错误输入报错；`sql_connections_spec.lua` 取消 toml 桩改测真实解析器；编辑 connections.toml 后 5s 内新配置生效；URL 含特殊字符可正确构建。
- **风险**：换解析器可能改变少量合法 TOML 的解析结果——先在 fixtures 上跑差异对比。

---

## 阶段 2 P1：功能 bug 批量修复

> 每个任务独立、低风险，可并行；全部为审查报告 P1 章节的直接落地。完成后各自补最小测试。

### F2-1 修 `statement.lua:89` 未定义变量

- 删除对 `output` 的重复 decode，直接校验并使用 `cli.run_json` 的 `parsed`；`find_stmt_lines` 的空结果路径返回 nil 前打日志。
- **涉及**：`lua/poste-sql/statement.lua`、`tests/sql/sql_statement_spec.lua`（补 `try_rust_stmt_ranges` 用例，mock `cli.run_json`）
- **验收**：`try_rust_stmt_ranges` 在 mock 返回合法数组时正确产出绝对行号；`sql_runner.lua:221` 的 nil 索引路径消失。

### F2-2 修 `insert_hint.lua` 行索引

- `block_start = i + 1`（跳过 `###` 行）；`lines[i - block_start + 1]` → `lines[i]`（三处：`:41`、`:137-148` 的 text_offset 与 `to_buf_pos`）。
- **涉及**：`lua/poste-sql/insert_hint.lua`、新增 `tests/sql/sql_insert_hint_spec.lua`（纯解析函数抽取后测：`###` 上方/下方、多 block、光标在 VALUES 内）
- **验收**：标准 `###` 布局下 INSERT 提示列号正确。

### F2-3 补 `constants.lua` 缺失常量

- 定义 `M.TITLE`（= `PLUGIN_TITLE`）、`M.EDIT_CONFLICT_MSG`、`M.RAW_MODE_WINBAR`；或将 11 处引用统一改为 `PLUGIN_TITLE` 并补两个新常量。
- **涉及**：`lua/poste-sql/constants.lua`、`lua/poste-sql/buffer/{init,nav,page,search}.lua`、`lua/poste-sql/buffer/nav_raw.lua`
- **验收**：dirty-edit 守卫弹出 WARN 而非 Lua error；raw mode winbar 显示；`grep -rn 'C\.TITLE\|C\.EDIT_CONFLICT\|C\.RAW_MODE'` 全部有定义。

### F2-4 修 `apply_connection` E303

- 修改 buffer 前置 `swapfile=false`（或用临时无 swap buffer 操作后同步）。
- **涉及**：`lua/poste-sql/connections.lua:341,359`
- **验收**：`sql_connections_spec.lua` 全绿（含 headless）。

### F2-5 修 statusline 连接着色

- `nav_ui` 在写 `vim.b.poste_sql_context` 展示串的同时写 `vim.b.poste_sql_conn`（原始连接名）；`statusline.lua:54-66` 改读后者。
- **涉及**：`lua/poste-sql/buffer/nav_ui.lua`、`lua/poste-sql/statusline.lua`
- **验收**：配置 `color`/`link` 的连接在状态栏正确着色（`get_connection_config` 命中）。

### F2-6 统一配置搜索目录

- `connections.resolve_connection_url`（`:198`）改从 buffer 目录搜索（与 `get_connection_config` 一致）；`db_browser` 内的 cwd 混用（`db_browser/init.lua:93-95` vs `actions.lua:126`）统一为 buffer 目录。
- **涉及**：`lua/poste-sql/connections.lua`、`lua/poste-sql/db_browser/{init,actions}.lua`
- **验收**：`sql_connections_spec.lua` 补"buffer 目录 vs cwd"用例；子目录打开 SQL 文件可找到项目根配置。

### F2-7 修 `render_dataset` exec_seq 竞态

- `buffer/init.lua:361` `render_dataset` 消费 `opts.exec_seq`：落后于当前全局 exec_seq 时丢弃；`edit_commit/init.lua:116-117` 传当前 seq（从 `sql_runner` 的全局 `exec_seq` 读取，需先暴露 getter）；删除 `buffer/init.lua:392` 的 `state.last_response` 回退，强制调用方传 `data`（`db_browser/actions.lua:286-294` 修）。
- **涉及**：`lua/poste-sql/buffer/init.lua`、`lua/poste-sql/sql_runner.lua`、`lua/poste-sql/edit_commit/init.lua`、`lua/poste-sql/db_browser/actions.lua`
- **验收**：新增测试——refresh 在途时执行新查询，旧 refresh 结果不覆盖新 tab（mock 回调乱序）。

### F2-8 DB Browser 异步 epoch 与失败可见性

- `db_browser/async.lua`：`fetch_children` 开始时 `node.epoch = (node.epoch or 0) + 1`，回调校验 `node.epoch == epoch`；`run_introspect` 捕获 job_id 并登记活动 job，`M.close`/`init.lua:589-595` 统一 `jobstop`；失败回调区分"error"状态（`node.meta.error`，树中渲染可见错误行）与"空"；introspect 加超时（`vim.defer_fn` 兜底复位 loading 并报错）。
- **涉及**：`lua/poste-sql/db_browser/async.lua`、`lua/poste-sql/db_browser/{init,tree}.lua`、`lua/poste-sql/db_browser/actions.lua:115-116,200-201,238-242`、`lua/poste-sql/db_browser/operations.lua:294-295`
- **验收**：快速展开+刷新不出现陈旧覆盖；内省失败显示错误而非空节点；关闭浏览器后无残留回调写状态。

### F2-9 `file_exec` 并发保护与末行 flush

- `file_exec.lua:294-318` `run()` 检查 `S.is_running`，运行中直接拒绝并提示（或排队）；`on_exit`（`:402-411`）flush `partial` 缓冲解析末行 JSON；状态从模块级单例改为 per-run 表（`S` 重建）。
- **涉及**：`lua/poste-sql/file_exec.lua`
- **验收**：连续两次 `<leader>ef` 第二次被拒或排队；summary 事件不因缺换行丢失。

### F2-10 session_conn 生命周期修复

- `session_conn.lua:251-262`：`chansend <= 0` 时调 `on_error` 并清理 `pending[seq]`；`M.stop`（`:267-276`）drain 全部 pending（fail-fast）；stdout 缓冲加上限（超阈值判死）；`M.get`（`:226-234`）池键改为 `conn_url .. "|" .. db` 或复用后按请求发 `USE`；`--timeout 0` 改为可配置默认超时（如 30s，0 仅显式开启）。
- **涉及**：`lua/poste-sql/session_conn.lua`、新增 `tests/sql/sql_session_conn_spec.lua`（mock jobstart 通道测 pending 生命周期）
- **验收**：`chansend` 失败无悬挂回调；`M.stop` 后无 pending 残留；不同 `@database` 的 buffer 路由到正确库。

### F2-11 预览浮窗失败防护

- `nav.lua:221-229`：`open_preview_float` 失败直接 return；`nav_preview.lua:31` 对 nil buf 提前退出。
- **涉及**：`lua/poste-sql/buffer/nav.lua`、`lua/poste-sql/buffer/nav_preview.lua`
- **验收**：预览打开失败后数据集键位不受影响（补测试：mock 浮窗失败后 `j` 仍走 `move_cell`）。

### F2-12 dirty 编辑保护

- `sql_runner.lua:218` `clear_panel` 前检查当前 tab 是否 dirty：是则提示并等待确认（或仅清非 dirty tab）。
- **涉及**：`lua/poste-sql/sql_runner.lua`、`lua/poste-sql/buffer/init.lua`
- **验收**：有未提交编辑时执行新查询弹确认；取消则不执行。

### F2-13 filter 分页语义

- `buffer/search.lua:210-213`：`pagination_enabled=false` 时传 `#view_indices` 而非 `page_size`；winbar "All" 与实际行数一致。
- **涉及**：`lua/poste-sql/buffer/search.lua`、`lua/poste-sql/buffer/nav_ui.lua:67-74`
- **验收**：过滤 200 行、分页关闭时全部可见；补 `buffer/search` 测试（本批新增首个 search spec）。

### F2-14 WinClosed autocmd 泄漏

- `buffer/init.lua:511-540`：重渲染前先删旧 `winclose_autocmd_id`；`M.close`（`:587-595`）补删；删除 `:149-179` 的重复清理块。
- **涉及**：`lua/poste-sql/buffer/init.lua`
- **验收**：连续 10 次查询后 autocmd 数量不增长（`nvim_get_autocmds` 断言）。

### F2-15 tabpage 感知

- `buffer/init.lua:461-471` 渲染前校验 `nvim_win_get_tabpage(D.dataset_window) == 当前 tabpage`，不符则重建窗口；`header.close`/`clear_panel`/`close` 遍历所有 tabpage 关闭浮窗。
- **涉及**：`lua/poste-sql/buffer/init.lua`、`lua/poste-sql/buffer/header.lua`
- **验收**：跨 tabpage 执行时结果在当前 tabpage 可见。

### F2-16 其余小 bug 批量（可合并为一个 PR）

- 边框高亮：`highlights/render.lua:140` 改 `line:match("^%s*[┌├└]")`。
- `sidescrolloff` 恢复：`nav.lua:150-157` 用 `xpcall` + finally。
- 切 tab/翻页高亮：`buffer/init.lua:221-226`、`page.lua` 补 `apply_edit_highlights`/`highlight_cell` 重放。
- USE 检测：`exec_run.lua:62-65`、`statement.lua:49` 支持引号/注释/多行。
- `export.M.run` 的 `path` 参数生效（`export.lua:384-401`）。
- `max_rows` 统一（`file_exec.lua:300-301` 与 `sql_runner` 对齐，或经 `state.config` 配置）。
- 临时文件：`exec_run.lua:40-52` 改用 `vim.fn.tempname()`（评估删除"放源目录"的旧理由——连接发现已走 URL 直传，不再需要）；同秒碰撞消除。
- `completion/data.lua:537` 加 `vim.g.poste_sql_debug` 门控。
- `sql_runner.lua:223-225` 优先级修正。
- **验收**：各自补最小测试或手动验证清单。

---

## 阶段 3 P2：架构重构与设计

> 复杂任务。每个任务必须先读设计小节，允许拆分为子 PR，但需保持行为兼容（除明确标注的破坏性变更）。

### F3-1 异步任务统一模型（epoch / job 管理）

- **问题**：审查报告 P2-4、P1-7/8。DB Browser、内省、导入、刷新各自为政，无统一取消/超时/代际校验。
- **设计（建议）**：
  1. 在 `lua/poste-sql/` 新增 `async.lua`（与 `db_browser/async.lua` 区分，或收敛后者）提供：
     ```lua
     -- 统一异步任务：封装 cli.run_async / jobstart
     M.run(args, { timeout, on_data, on_error, on_exit }) -> task
     task:cancel()      -- jobstop + 触发 on_cancel
     task:is_alive()
     -- epoch 工具：创建代际令牌，回调校验
     M.epoch() -> { get = fn() -> n, bump = fn() -> n, is_current = fn(n) -> bool }
     ```
  2. 所有内省/刷新/补全数据获取改走该封装；每个 UI 会话（DB Browser 打开、dataset 刷新、编辑器打开）持有一个 epoch，关闭/重开时 bump，回调内 `is_current` 校验后才有权写状态。
  3. 统一超时：`run_introspect`/`ensure_*`/import chunk 全部带默认超时（如 15s），超时走 `on_error` 并复位 loading。
  4. **收敛三套调用风格**：`db_browser/async.run_introspect` 为唯一入口；`actions.show_table_info`/`operations.show_ddl`（`actions.lua:552`、`operations.lua:156`）与 `copy.lua:217` 的裸 jobstart 全部改走封装。
  5. 同步阻塞点（`exec_run.lua:267`、`editor/column.lua:145`、`db_browser/db_create.lua:47`、`introspect/init.lua:158-159`、`source_format.lua:300`）逐个异步化（回调填充 UI），这是本任务的一半工作量。
- **涉及文件**：新增 `lua/poste-sql/async.lua`、`lua/poste-sql/db_browser/async.lua`（收敛）、`lua/poste-sql/db_browser/{actions,operations,copy,db_create}.lua`、`lua/poste-sql/editor/column.lua`、`lua/poste-sql/introspect/init.lua`、`lua/poste-sql/source_format.lua`、`lua/poste-sql/exec_run.lua`
- **验收标准**：grep 无新增 `vim.fn.system`（补全路径除外，见 F3-2）；所有异步回调有 epoch/超时保护；UI 不再因网络/进程卡死。
- **风险**：行为面广，建议按调用方分 3-4 个子 PR 落地。

### F3-2 补全热路径异步化与缓存重设计

- **问题**：审查报告 P2-1/P2-2。
- **设计（建议）**：
  1. **异步化**：`completion/init.lua:136` 的 `vim.fn.system` 改为 `vim.system(cmd, { text = true, timeout = 2000 }, callback)`（或复活 `context_client.lua` 的 jobstart 管线——二选一，推荐 `vim.system` + 现有 `_ctx_cache`，少维护一套 JSON-RPC）。
  2. **节流**：`get_items` 入口加 100-150ms debounce（blink 层面难以拦截时在 provider 内做 coalesce：同一 buffer 的连续请求合并，缓存命中直接返回）。
  3. **减少拷贝**：`extract_sql_block`（`:55`）只读光标所在 `###` block 区间而非全 buffer（与 `statement.lua` 的块定位复用）。
  4. **缓存重设计**（核心）：
     - 引入 `cache_epoch` 计数器；`clear_cache` 自增并记录 epoch；所有 jobstart `on_stdout` 回填前校验 epoch，过期结果丢弃。
     - `__databases__`（`:426`）与 `db:` 前缀缓存（`:347`）纳入失效范围——统一以 `conn_key_str` 前缀清除。
     - `sql_runner.lua:307` 只在 DDL 型响应（`body.type` 或结果含 `create/alter/drop` 语句）时清缓存，SELECT 不清。
     - `_ctx_cache`（`completion/init.lua:19,145`）加容量上限（LRU 或按 buffer 只留最新）。
  5. **死代码处置**：`context_client.lua` 接入或删除（接入则替换 `vim.system` 方案，二选一后删除另一个并更新 `docs/dev/sql/completion/README*`）。
- **涉及文件**：`lua/poste-sql/completion/init.lua`、`lua/poste-sql/completion/data.lua`、`lua/poste-sql/sql_runner.lua`、`lua/poste-sql/context_client.lua`（接入或删除）、`lua/poste-sql/completion/handlers.lua`
- **验收标准**：大文件（>1000 行）补全不冻结 UI（实测击键延迟 <16ms 或至少不再线性增长）；缓存失效后 introspect 重跑；`USE` 切库后数据库列表更新；DDL 后列缓存失效、SELECT 后不失效。
- **风险**：`vim.system` 需 nvim 0.10+（与 F5-3 版本声明一并处理）；blink 的 `is_incomplete_forward` 恒 true 行为若保留，需确认 debounce 与之兼容。

### F3-3 上下文解析重构（block 作用域 + 词法感知）

- **问题**：审查报告 P2-3、P1-9（context 行）。
- **设计（建议）**：
  1. **作用域收敛**：`context.resolve_context`（`context.lua:19-56`）Phase 2 改为只扫描**光标所在 `###` block**（从 `find_block_for_line` 起点到光标），消除跨 block 指令泄漏；文件头（Phase 1）作为全局默认保留。
  2. **词法感知**：扫描时用简单状态机跳过 `--` 注释、`/* */`、单/双/反引号字符串（复用 `ts_stmt` 或 `insert_hint` 的字符串跟踪逻辑，抽成 `lua/poste-sql/lex.lua` 共享）；`USE` 匹配要求语句级（行首 + 非注释内）。
  3. **语义对齐**：`completion/data.lua:190-201` 的 `resolve_current_context` 套用 `resolve_full_context` 的默认 database fallback（仅用于缓存键，不影响 buffer 指令优先级）；消除补全键 `conn/` 与执行目标 `conn/default_db` 漂移。
  4. **性能**：`context.lua:21` 全文件读取改为按需区间读取（`nvim_buf_get_lines(buf, block_start-1, cursor_line)`）；`get_cursor_status_text` 已有 100ms debounce（`sql_runner.lua:112-135`），保持。
  5. **两套上下文系统**（`context.lua` vs `completion/ctx.lua`）明确职责边界：`context.lua` = 执行/状态栏上下文；`completion/ctx.lua` = 补全项构造。删除重叠的 `detect_context_for_completion` 假桩（`completion/init.lua:181-183`），调试命令改走真实异步检测。
- **涉及文件**：`lua/poste-sql/context.lua`、新增 `lua/poste-sql/lex.lua`、`lua/poste-sql/completion/data.lua`、`lua/poste-sql/completion/init.lua`、`lua/poste-sql/statement.lua`（复用块定位）
- **验收标准**：`sql_context_spec.lua` 补用例——注释内 USE 不生效、跨 block 指令不泄漏、引号内 USE 不生效、`USE "my db"` 生效；补全缓存键与执行目标一致（默认库场景）。

### F3-4 会话/执行双路径收敛

- **问题**：审查报告 P0-2（已在 F1-3 修 bug 面）、P2-4。
- **设计（建议）**：在 F1-3 状态机之上，把"session vs exec-file"路由收敛为**单一执行器接口**：
  ```lua
  -- lua/poste-sql/executor.lua（新增）
  M.execute({ sql, conn_url, database, mode, callbacks, prefer_session }) -> token
  -- 内部：session 可用 → session 通道；session 不可用/传输失败 → exec-file（仅一次降级）；
  --       SQL 错误永不降级。返回 token 供 exec_seq 校验。
  ```
  `sql_runner`/`file_exec`/`edit_commit`/`import` 统一走该接口，删除各自重复的 job 管理；`max_rows` 默认值收敛为配置项（`state.config`）。
- **涉及文件**：新增 `lua/poste-sql/executor.lua`、`lua/poste-sql/sql_runner.lua`、`lua/poste-sql/file_exec.lua`、`lua/poste-sql/edit_commit/init.lua`、`lua/poste-sql/import/execute.lua`
- **验收标准**：四条调用路径行为一致；降级只发生一次；`max_rows` 统一可配置。
- **依赖**：F1-3 完成后进行。

### F3-5 数据集缓冲重构（tabpage / 内存 / 单例）

- **问题**：审查报告 P2-5、P1-9（tabpage 行）、P2-8（内存）。
- **设计（建议）**：
  1. **tabpage**：`D.dataset_window` 记录 `tabpage`；渲染/关闭前校验（已在 F2-15 打底）。
  2. **多源隔离（产品决策）**：评估两种模型——a) 维持单面板（REPL 式），b) 每 src_buf 独立结果缓冲（JetBrains 式）。建议**维持单面板**（与现状一致、改动小），但 tab 命名含 src 文件名并在 winbar 显示来源；跨 buffer 执行时提示"将替换当前结果"（若 dirty）。若选 b，`dataset.lua` 的 `tabs` 改为 `{ [src_buf] = tabs }`，render_dataset 按 src_buf 路由——列为可选项，不在本期强制。
  3. **内存**：`padded_full/meta_full` 全量驻留改为惰性——分页开启时只保留当前页 `padded`；`original_rows` 保留（编辑需要）但加行数上限提示（>N 行禁编辑，沿用 `EDIT_MAX_ROWS`）；布局扫描抽样（`format.lua:502-555` 只扫前 1000 行做宽度/数值探测，或依赖 Rust 返回的列元数据）。
  4. **搜索**：`buffer/search.lua:125-141` 同步全扫改异步（`vim.defer_fn` 分片扫描，每片 50ms 让出）或加行数上限；matches 按页存储（`search_matches_by_page` 已存在，淘汰全量 `search_matches`）。
  5. **双真相源**：`state.sql.cell` 收敛为 `D.T().cursor` 的投影（只读）；所有写入点（`search.lua:65-66,283`、`nav.lua:50-51`、`buffer/init.lua:191,200-201`）改走 tab。
- **涉及文件**：`lua/poste-sql/dataset.lua`、`lua/poste-sql/buffer/init.lua`、`lua/poste-sql/buffer/{nav,search,page}.lua`、`lua/poste-sql/format.lua`、`lua/poste-sql/state.lua`
- **验收标准**：10 万行结果内存峰值显著下降（测量）；大结果分页流畅；搜索大结果不卡 UI；跨 tabpage 行为正确。
- **风险**：内存/惰性渲染改动面大，建议拆 3 个子 PR（tabpage → 内存 → 搜索/状态），每个独立验收。

### F3-6 `init.lua setup()` 拆分与调试命令收敛

- **问题**：审查报告 P2-6。
- **设计（建议）**：`init.lua` 的 626 行拆为注册模块：
  - `lua/poste-sql/commands.lua`：全部 `nvim_create_user_command`（保留调试命令但加 `vim.g.poste_sql_debug` 门控，默认不注册 `PosteSQLDiag/PosteSQLDebugSpace/PosteSQLCmpTest` 等；`PosteSQLCmpReload/PosteSQLCmpStatus` 保留为运维命令）。
  - `lua/poste-sql/autocmds.lua`：全部 autocmd（FileType/BufRead/BufNewFile/BufUnload/ColorScheme），收敛文件类型 4 条路径为一条（ftdetect 负责检测、setup 只注册一次 FileType 回调 + 存量 buffer 循环）。
  - `lua/poste-sql/completion/register.lua`：`register_sql_completion` 与 `PosteSQLCmpReload` 共用（消除重复注册代码）。
  - `setup()` 变为组装调用。
- **涉及文件**：`lua/poste-sql/init.lua`、新增 `lua/poste-sql/{commands,autocmds}.lua`、`lua/poste-sql/completion/register.lua`
- **验收标准**：`setup()` 行数显著下降；调试命令默认不注册（`vim.g.poste_sql_debug` 时注册）；现有行为（键位/命令/自动注册）回归通过。

### F3-7 DB Browser 收敛（单一 introspect 封装 + helpers 去重）

- **问题**：审查报告 P2-7（重复/死代码）、P1-8。
- **设计（建议）**：
  1. `db_browser/util.lua`（新增）：`get_dialect/get_connection/get_search_dir/find_table_node` 从 `actions.lua:56-93` 与 `operations.lua:23-54` 收敛；`quote_ident` 用 F1-4 的 `ident.lua`。
  2. 单一表单引擎：`forms.lua` 与 `forms_advanced.lua` 的能力（字段编辑/select/列表）合并为一个引擎（保留两者对外 API 以减小破坏），`db_create/schema_create` 统一使用；`forms_advanced` 列表条目补子字段编辑（配合 F1-4）。
  3. 死代码清理：`tree.make_index_node`（`tree.lua:102`）、`context_menu.MENU_DEFS.view` 永不命中分支（`context_menu.lua:43-47`）、`async.lua:7` 未用的 `search_dir` 参数、`schema_create.lua:2` 未用 require。
  4. 搜索只覆盖已加载节点（`actions.walk_tree`）的局限：改为按需加载祖先链后再匹配，或明确提示"仅搜索已加载节点"；`M.close` 清理 `search_state` 与 `_G.poste_search_info`。
- **涉及文件**：`lua/poste-sql/db_browser/{actions,operations,forms,forms_advanced,context_menu,tree,async,init}.lua`、新增 `lua/poste-sql/db_browser/util.lua`
- **验收标准**：`operations.lua`/`actions.lua` 行数显著下降；行为回归（DB Browser 键位/表单/复制）通过；无死代码告警（luacheck）。

### F3-8 状态管理与 require 副作用收敛

- **问题**：审查报告 P2-5、P2-7（require 副作用）。
- **设计（建议）**：
  1. `session.lua` 的模块级 `active` 与 `state._sql_session` 合一（保留一个）；`M.finish()` 补调用点（`sql_runner` 请求结束/错误路径）或删除死 API。
  2. require 副作用移入 `setup()`：`statement_indicator.lua:7-25`（`nvim_set_hl`/`sign_define`）、`highlights/init.lua:21-23`（`setup()`+autocmd）、`syntax.lua:12-16`、`init.lua:14`（`insert_hint.setup()`）——测试与加载解耦。
  3. `statusline.lua:69-109` 的 mini.statusline monkey-patch：改为仅当用户显式 `setup({ statusline = true })` 时生效，并提供还原函数；记录 patch 前的原值。
- **涉及文件**：`lua/poste-sql/session.lua`、`lua/poste-sql/statement_indicator.lua`、`lua/poste-sql/highlights/init.lua`、`lua/poste-sql/syntax.lua`、`lua/poste-sql/init.lua`、`lua/poste-sql/statusline.lua`
- **验收标准**：`require("poste-sql.buffer")` 等不再触发高亮/autocmd 注册；测试可独立加载模块。

### F3-9 blink.cmp 耦合降级

- **问题**：审查报告 P2-7（adapter）。
- **设计（建议）**：
  1. 去掉对 blink config/运行时私有字段的**写**：`adapter.lua:79`（`per_filetype_provider_ids`）与 `:72`（`cfg.sources.per_filetype`）改为仅通过公开 API（`add_source_provider`/`add_filetype_source`）注册；确认 blink 运行时对 provider 内 `get_trigger_characters` 的读取路径，把"空格触发"改为 provider 内部处理（`get_trigger_characters` 返回空格 + `get_completions` 对空格触发做空前缀处理），**删除** `patch_blocked_trigger_chars` 的全局 monkey-patch（`adapter.lua:135-147`）。
  2. 私有模块 require（`adapter.lua:113,130`、`completion/init.lua:302`）降级为 pcall + fallback；`completion_item_kind` 走公开枚举或本地映射。
  3. `set_per_filetype` 的无效写（setup 后改写 config 对运行时无效）删除。
  4. 版本声明：README 注明最低 blink.cmp 版本（以 CI 固定版本为准）。
- **涉及文件**：`lua/poste-sql/completion/adapter.lua`、`lua/poste-sql/completion/init.lua`、`lua/poste-sql/init.lua`
- **验收标准**：无 blink 私有字段写入（grep 验证）；空格触发在 poste setup 先/后于 blink.setup 两种顺序下都生效；`PosteSQLCmpReload` 幂等。
- **风险**：空格触发是既有用户习惯，改动需覆盖测试（mock blink provider 接口）。

### F3-10 大结果集管线（内存 3 份拷贝 → 流式）

- **问题**：审查报告 P2-4（内存）、P0-5（导入）。
- **设计（建议）**：`exec_run.lua:126-198` 与 `sql_runner.lua:315-335` 的"event 累积 → encode → decode"管线：改为主结果集**单份**保留（`resp.results` 直接传下游，`resp.body` 仅在需要落盘/日志时构造）；布局/分页直接消费 `results`（`format.plan_resultset_layout` 已能接受 data 结构）。session 通道（`session_conn.build_response`）同样避免先 encode 再 decode（`body_obj` 按需构造）。分页场景下 Rust 侧 `--max-rows` 配合客户端游标（可选，跨仓库）。
- **涉及文件**：`lua/poste-sql/exec_run.lua`、`lua/poste-sql/sql_runner.lua`、`lua/poste-sql/session_conn.lua`、`lua/poste-sql/format.lua`
- **验收标准**：大 SELECT 的峰值内存下降（测量对比）；`resp.body` 只在需要处构造。

---

## 阶段 4 P3：测试体系升级

### F4-1 零覆盖模块补测（分批）

- **批次 A（纯逻辑，优先）**：`toml.lua`（F1-7 后）、`insert_hint.lua`（F2-2 后抽纯函数）、`buffer/search.lua`、`buffer/page.lua`、`completion/ctx.lua`、`ident.lua`（F1-4 后）、`nav_sort`/`dataset.compute_view_indices` 现有补充。
- **批次 B（需 mock vim/job）**：`session_conn.lua`（F2-10 后，mock jobstart 通道）、`export.lua`（F1-6 后）、`semantic_diagnostics.lua`（`extract_references_from_node` 纯函数抽取——用 mock parser 或真实 parser + TSInstall）、`diagnostics.lua`、`editor/nav.lua` 守卫（raw mode/`EDIT_MAX_ROWS`/JOIN）、`editor/column.lua` 的 `has_join`/`ensure_primary_key`。
- **批次 C（集成）**：`db_browser/operations.lua` 的 SQL 生成（与 ident.lua 组合）、`copy.lua`、`forms/forms_advanced`、`import/execute`（复用 session）。
- **涉及文件**：`tests/sql/` 新增 spec；必要时为可测性抽取纯函数（遵循报告附录 A 的纯/不纯清单）
- **验收标准**：新增 spec 全部通过；`tests/run.sh` 全绿。

### F4-2 修 `sql_multi_stmt_spec` 固化 bug 的测试

- `sql_multi_stmt_spec.lua:133-176` 的 "KNOWN BUG" 断言：改为 `pending` 并标注对应 issue（F2-16 的语句边界修复后转为真实断言），避免重构被错误测试锁死。
- **涉及**：`tests/sql/sql_multi_stmt_spec.lua`
- **验收**：语句边界修复后（`statement.lua`/ts_stmt 改进）这些用例变为绿色断言。

### F4-3 测试隔离加固

- 每个 spec `before_each` 完整重置 `state.sql` 与 `D`（tabs/active_tab_idx）；跨文件全局污染（`package.loaded`/`vim.g`）在每个文件头显式保存/恢复。
- **涉及**：`tests/sql/*.lua`
- **验收**：3 次连续全量运行 0 失败（消除间歇性）。

---

## 阶段 5 文档与收尾

### F5-1 README 修正

- 数据集编辑键位表（`README.md:117-121`）与实现一致（`i`/`cc`/`dd`/`o`/`<leader>w`，删除 `a`/`O`/`u` 或补绑定后更新）；声明最低 nvim 版本（0.10，与 F0-4 一致）；blink.cmp 最低版本。
- **涉及**：`README.md`

### F5-2 开发文档修正

- `docs/dev/sql/completion/README*`：路径 `lua/poste/sql/` → `lua/poste-sql/`，crates 段落改指 poste.nvim；`docs/dev/sql/README.md` 索引补全 10 篇并修正日期；AGENTS.md 修正 `help.lua` 归属与 `LEARNINGS.md` 引用（补文件或删引用）。
- **涉及**：`docs/dev/sql/completion/README.en.md`、`docs/dev/sql/completion/README.zh.md`、`docs/dev/sql/README.md`、`AGENTS.md`

### F5-3 版本声明与兼容性

- `health.lua:12` 改 `nvim-0.10.0`（或对 `vim.treesitter.language` 做 0.9 兼容保护 + 明确降级路径）；`health` 增加 `connections.toml` 查找/解析检查；补 `vim.g.poste_sql_legacy_completion` 检查。
- **涉及**：`lua/poste-sql/health.lua`

---

## 依赖关系图

```
F0-1 (CI+修绿) ──┬──> F0-2 (隔离) ──> F0-3 (lint) ──> F0-4 (LICENSE/版本)
                 │
F1-1 (日志脱敏) <── F1-2 (env 凭据, 依赖 Rust 侧)
F1-3 (重复执行) ──> F3-4 (执行器收敛)
F1-4 (ident) ──> F3-7 (db_browser 收敛)
F1-5 (事务) ──依赖── F3-1 (异步统一) 的 session 通道
F1-6 (导入导出)
F1-7 (toml) ──> F4-1 批次 A

F2-* 各独立，可在 F0 完成后并行 ──> F3-5/3-6/3-8 依赖部分 F2 修复（tabpage/常量/状态）

F3-1 (异步) ──> F3-2 (补全异步) / F3-10 (管线)
F3-3 (上下文) 独立
F4-1/4-2/4-3 贯穿各阶段，随功能修复同步补测
F5-* 收尾，最后做
```

**建议执行顺序**：F0 全批 → F1 全批 → F2 并行批 → F3 按依赖串行 → F4 穿插 → F5 收尾。每个批次结束跑一次 `tests/run.sh` 全绿 + `luacheck` 无新增告警。
