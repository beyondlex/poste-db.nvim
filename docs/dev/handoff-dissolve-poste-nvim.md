# Handoff — 2026-09-13（第二份）：解散 poste.nvim 共享 Lua，拆散进各 sibling

> 写给下一个 AI agent。任务一句话：**把 `lua/poste/` 的共享 Lua 按实际用途
> vendor 进 4 个真正依赖它的 sibling 仓库，poste.nvim 转型为纯 Rust CLI 仓库。**
> 本文档自包含；所有论断在写作时（poste-db@`2eb6909`、poste.nvim@`5b3759e`）
> 逐条验证过，环境事实可复跑。
>
> 阅读顺序：本文档 → 目标仓库的 `AGENTS.md` → `LEARNINGS.md`（poste-db 有）。
> 执行前必读第 8 节「坑与禁令」。

## 0. 为什么做这件事（决策史，不要重新论证）

1. poste 插件家族原本是 hub-and-spoke：`poste.nvim` 持共享 Lua + Rust 二进制，
   sibling 依赖它。实践中 redis 改共享层两次炸到 db（statusline 全局槽位竞争、
   `poste_state.connection` 互踩），2026-09-13 前半段做了「方案 C：收紧共享层」
   （契约硬化 + 契约测试 + 删死模块，见第 2 节 commit 清单）。
2. 之后维护者明确了产品愿景：**各 poste-*.nvim 是独立演进的项目，要发布到
   GitHub 让社区参与**。这个前提下 hub 的成本（跨仓库 PR、发版同步、装一个
   功能装两个插件、issue/星标摊薄）超过共享 1.9k 行 Lua 的收益。
3. 实测依赖图（grep 全部仓库核实）：真正依赖 poste.nvim 的只有 **poste-db、
   poste-redis、poste-mail、poste-es** 四家；poste-http/mq/ai/gtd/ui 零依赖。
   所以决策为「方案 D：拆散共享 Lua，poste.nvim 只保留 Rust CLI + 发布管线」。
4. **不要**在执行中重新讨论方案 C vs D。决策已定。若发现不可行的阻塞点，
   停下来向维护者报告，不要自行改方案。

## 1. 世界快照（任务完成后的状态，2026-09-13 收尾时改写）

### 1.1 接手时（逐条核对过，与本节开头所述一致）

| Checkout | 分支 | HEAD | 工作区 |
|---|---|---|---|
| `~/code/github/poste.nvim` | `main` | `5b3759e` docs: rewrite README | 干净 |
| `~/code/github/poste-db.nvim` | `main` | `2eb6909` feat(dataset): dedicated highlight groups for the search char layer | 干净 |
| `~/code/github/poste-redis.nvim` | `main` | `f7ce663` refactor(state): stop writing/reading poste_state.connection | 干净 |
| `~/code/github/poste-mail.nvim` | `main` | `793a3b1` docs: 2026-09-13 review record | 干净 |
| `~/code/github/poste-es.nvim` | `main` | `d63b7fe` refactor(state): stop writing poste_state.connection | 干净 |

### 1.2 完成后（迁移已落地，全部不 push 不打 tag）

| Checkout | 分支 | HEAD | 工作区 |
|---|---|---|---|
| `~/code/github/poste.nvim` | `main` | `ee681c8` refactor(core): dissolve the shared lua layer; pure Rust CLI repo (family dissolution) | 干净 |
| `~/code/github/poste-db.nvim` | `main` | `ad0d7dc` refactor(poste-db): vendor shared lua from poste.nvim (family dissolution) | 见下方交接文档说明 |
| `~/code/github/poste-redis.nvim` | `main` | `0538053` refactor(poste-redis): vendor shared lua from poste.nvim (family dissolution) | 干净 |
| `~/code/github/poste-mail.nvim` | `main` | `ce36029` refactor(poste-mail): drop the poste.statusline shared dependency (family dissolution) | 干净 |
| `~/code/github/poste-es.nvim` | `main` | `d4317ab` refactor(poste-es): vendor shared lua from poste.nvim (family dissolution) | 干净 |

- db 仓库在迁移提交（`ad0d7dc`）之外另有一笔本交接文档的 docs 提交；其余四仓工作区干净。
- 各迁移仓库的验收（§6）全部通过：grep 三连归零、测试套件全绿
  （db ~1290 断言 / redis 27 spec / es 24 spec / mail 全绿）、luacheck 0 警告、
  headless 冒烟（plugin 加载 + `:Poste*` 命令 + `:checkhealth` 二进制探测/版本）正常。
- `~/code/github/poste-for-db` worktree 未触碰；全部提交未 push 未打 tag，推送与发版由维护者执行。
- **发布提示**：pre-dissolution 的 sibling checkout 硬 require `lua/poste` 模块
  （如 `poste.state`），poste.nvim `ee681c8` 已删这些模块——五个仓库应协调一次推送。

- `~/code/github/poste-for-db` 是 poste.nvim 的 worktree（未发布的 Rust 方言
  分支模式），本任务**不碰**。
- 所有提交一律**不 push 不打 tag**——推送与发版由维护者亲手做。

## 2. 已完成的铺垫（不要重做）

本会话在方案 C 阶段落地的，全部保留并直接被方案 D 继承：

- poste.nvim `909e4e4`：`lua/poste/statusline.lua` provider 契约硬化（注册校验、
  同名重注册原位替换、unregister、非 string text/hl 防御、hl 的 `%` 转义），
  `tests/poste/statusline_spec.lua` 17 用例（含 db 式+redis 式双 provider 共存）。
  **迁移各家 statusline 时，这份 spec 是 scope-guard 测试的参考实现。**
- poste.nvim `676c227`：AGENTS.md 写入共享面契约（state 所有权规则、statusline
  单一所有者、semver 纪律）；新增 `lua/poste/version.lua`；删除零调用的
  `state/event.lua`、`async/promise.lua`（连同 spec）。**这两个死模块不要
  vendor——它们已确认全生态零调用。**
- poste-redis `f7ce663` / poste-es `d63b7fe`：拆除对共享 `poste_state.connection`
  的写/读（redis picker 改读自家 `redis_state.context.connection`）。
- poste-db `7340bd7`：docs 链接契约文档（迁移完成后此章节要改写，见 5.5）。
- poste.nvim `5c665b5`（clippy 全清零）、`1ffb0e0`（MIT LICENSE、release.yml
  加 aarch64-linux、CI clippy `-D warnings` + Lua plenary job）、`5b3759e`
  （README 按真实子命令重写，内含截图占位）。
- db 侧质量基线：luacheck 全仓 0 警告（CI gate `lua plugin ftplugin tests`
  四目录）、1276 个测试用例全绿。

## 3. 目标架构

### 3.1 poste.nvim 转型后是什么

- **保留**：`crates/`（poste-core / poste-exec / poste-cli）、`.github/workflows/`
  （CI + release 多平台产物 + checksum）、Rust 测试、`docs/schema.md`（新增，
  见 3.3）、README（改写为 CLI-first）。
- **最终删除**：`lua/poste/` 其余全部、`tests/poste/`、`.luacheckrc`、
  `plugin/poste-core.lua` 的自动安装行为。收尾时机见 5.6。
- release 资产 URL 不变（`beyondlex/poste.nvim`），各 sibling 的 installer
  继续指向它。

### 3.2 各 sibling 吞下的模块清单

共享层现状 12 个文件共 1896 行（`lua/poste/`，poste.nvim@`5b3759e`）：

| 模块 | 行数 | 内部 `poste.*` 依赖 | 拆散去向 |
|---|---|---|---|
| `state.lua` | 116 | 无 | **合并**进各家已有 `state.lua`（见 4.1 通用流程 A3） |
| `cli.lua` | 115 | 懒加载 `poste.state`（函数体内） | 新文件 `<plugin>.cli` |
| `util.lua` | 80 | 无 | **合并**进各家已有 `util.lua` |
| `error.lua` | 51 | 顶层 `require("poste.state")` | 新文件 `<plugin>.error`，改指自家 state |
| `constants.lua` | 10 | 无 | **合并**进各家已有 `constants.lua` |
| `install.lua` | 317 | 无（自带 REPO 常量） | 裁剪为新文件 `<plugin>.install`（见 4.1 A4） |
| `select.lua` | 259 | 无 | 新文件 `<plugin>.select` |
| `layout.lua` | 362 | 懒加载 `poste.state` | 新文件 `<plugin>.layout`，改指自家 state |
| `dialog.lua` | 177 | 无 | 新文件 `<plugin>.dialog` |
| `indicators.lua` | 176 | 顶层 `require("poste.constants")` | 新文件 `<plugin>.indicators`，改指自家 constants |
| `statusline.lua` | 194 | 无 | **不 vendor**——各家已有 90% 实现，拆除共享调用（见 4.1 A5，本任务最微妙处） |
| `core.lua` / `version.lua` | 39 | state | 不 vendor（各家 setup 自己管；version 概念随拆散作废） |

各 sibling 需要的集合（**以本文第 5 节的逐仓库 require 清单为准，那是 grep
实测，不是估计**）：

- **poste-mail**：只拆 statusline 共享调用。它已有 `compat/select.lua`
  （vendor 自 poste.select）与 `compat/promise.lua`，无需再吞。
- **poste-es**：state-lite、util、indicators、select（guarded 调用）、
  dialog（guarded 调用）、installer。
- **poste-redis**：state-lite、cli、util、select（guarded）、indicators
  （guarded ×4）、installer。
- **poste-db**：全部——state-lite、cli、util、error、constants 合并、
  select、layout、dialog、indicators、installer。

### 3.3 不可拆的核：二进制契约

`poste` 是全家共用的一个二进制（SQL/Redis/MQ 执行器都在里面），**不拆**。
拆散后唯一的跨仓库契约是：

1. 各子命令的 stdin/stdout NDJSON schema（`exec-file`、`session`、
   `redis-exec`、`redis-session`、`mq-exec`、`mq-session`、`introspect`、
   `context`、`connection`）；
2. `--connection` 接受 Lua 侧已解析的 URL（不是名字）、`--env`、
   `--database` 参数语义；
3. 连接名 → URL 的解析规则（`connections.toml` + `{{var}}`，Lua 侧
   `resolve_connection_url` 与 Rust `ConnectionConfig::to_url()` 是镜像实现，
   **两边不得单独漂移**）。

在 poste.nvim 新增 `docs/schema.md` 把以上写成文档；sibling 的 health check
记录实测的最低二进制版本（各家 health.lua 已有二进制探测，加版本断言即可）。

### 3.4 statusline 共存规则（作用域纪律，不可协商）

拆散后没有共享协调层，db 与 redis 同会话共存时靠**每家守自己的作用域**：

- 每家的 mini.statusline 包装（`content.active` + `section_fileinfo`）必须
  **scope-guard**：仅当当前 buffer/window 属于本插件（如 db 判
  `vim.b.poste_db_context ~= nil`、dataset window 句柄匹配）才渲染自家
  context，否则**原样调用捕获的 original**。
- 原理：多家各自包装时链式组合——db 的包装在非 db buffer 上 fall through
  到它捕获的 original（即 redis 的包装），redis 同理。链不会打架的前提是
  **每家都无条件 fall through**。09-12/09-13 的雷（redis window 压 db
  buffer、`%` 未转义炸全家重绘）全部源于有人无条件抢全局槽位。
- 放弃「全局兜底档」（在任何 buffer 显示当前连接）。若维护者将来明确提出
  需求，方案是 20 行 first-wins 握手（`vim.g.poste_statusline_owner`，
  先装者得，后者注册 provider 进前者），届时再做。
- 各家 legacy 回退路径（现名 `legacy_mini_wiring`）本就有 `%` 转义、resolve
  pcall——拆散后它升级为唯一路径，迁移时逐项核对：包装幂等（自家 guard
  flag 防重装）、`%` 在 text 与 hl 双转义、resolve 不存在/出错时静默跳过。

## 4. 通用流程（每个仓库相同，先读一遍再动手）

**A1. 拷贝即冻结。** vendor 一律从 poste.nvim@`5b3759e` **逐字拷贝**，只允许
两类改动：(a) 文件头注释加一行来源标注 `-- vendored from poste.nvim@5b3759e
lua/poste/<name>.lua`；(b) 修改 `require("poste.*")` 为本地模块名。**禁止**
顺手重构、重命名函数、改逻辑、去「重复代码」。

**A2. require 改名映射**（机械替换，无例外）：

| 旧 | 新 |
|---|---|
| `require("poste.state")` / `pcall(require, "poste.state")` | `require("<plugin>.state")`（函数已合并进去） |
| `require("poste.cli")` | `require("<plugin>.cli")` |
| `require("poste.util")` | `require("<plugin>.util")` |
| `require("poste.select")` | `require("<plugin>.select")` |
| `require("poste.dialog")` | `require("<plugin>.dialog")` |
| `require("poste.layout")` | `require("<plugin>.layout")` |
| `require("poste.constants")` | `require("<plugin>.constants")` |
| `require("poste.indicators")` | `require("<plugin>.indicators")` |
| `pcall(require, "poste.statusline")` | 删除该分支，legacy 路径升为唯一路径 |
| `pcall(require, "poste.core")` / plugin 顶部的 poste.state guard | 删除（自家模块必然存在） |

**A3. state-lite 合并。** 把 `poste.state.lua` 的这些**逐字**并入各家已有的
`lua/<plugin>/state.lua`（四家都有）：

- `find_poste_binary()`（64-92 行）。唯一必改点：`debug.getinfo` 的 source
  匹配 `^(.+/)lua/poste/` → `^(.+/)lua/<plugin>/`。
- `apply_highlight_overrides()`（94-103 行）。
- `get_keymap()` / `format_key_string()` / `format_keymap()`（32-62 行）。
  注意：redis/es/db 的 `config.lua` 里有 `pcall(require, "poste.state")` 读
  共享 keymaps 的透传逻辑（redis:185、es:110、db:150 附近）——迁移时删除
  透传，keymaps 只读本插件 config。
- `log()`（105-114 行）。若自家 state 已有同名/同职责函数，**保留自家版**
  并核对语义后丢弃 poste 版，冲突要在提交信息里写明。
- config 默认值并进各家 `config.lua`：`log_file`（`stdpath("cache") ..
  "/poste.log"`，可改成 `<plugin>.log`）、`highlights = {}`、
  `poste_binary`（`stdpath("data") .. "/poste/bin/poste"`，保持不变——二进制
  是全家的，装一次全家可用）。
- `current_env` 默认 `"dev"`：db/redis 只读（本会话已核实无人写共享层）。

**A4. installer 裁剪。** 从 `install.lua`（317 行）裁出：`detect_platform`、
`binary_path`、`archive_ext`、`download_url`、`checksum_url`、checksum 校验、
`download`、extract、`ensure`（234 行起）。`REPO = "beyondlex/poste.nvim"`
**保持不变**。各家 `setup()` 首次调用 `ensure()`；幂等 guard 从
`vim.g.poste_core_setup_done` 换成 `vim.g.poste_<plugin>_setup_done`。
`vim.g.poste_binary` 全局覆盖**保留**（README/AGENTS 已承诺）。

**A5. statusline 拆除**（按 3.4 的规则）。每家删 `pcall(require,
"poste.statusline")` 分支，把 legacy 路径升为唯一路径，补 scope-guard 与
幂等 guard，然后**仿照 `poste.nvim/tests/poste/statusline_spec.lua` 给自家
写最小 spec**：至少断言 (a) 自家 buffer 渲染 context；(b) 非自家 buffer
fall through（调用链不断）；(c) `%` 转义；(d) 二次 setup 不重复包装。

**A6. 测试桩改名。** `tests/` 里所有 `package.loaded["poste.xxx"]` 桩键改为
`["<plugin>.xxx"]`（db 的精确分布见 5.4；其余仓库自行
`grep -rn 'package.loaded\["poste\.' tests/`）。stub 的**内容**（函数签名、
返回值）不变，只改模块键名。

**A7. 提交纪律。** 一个仓库一笔提交（信息模板见第 7 节）；不 push；
迁移改动绝不与仓库里已有的未提交工作混合。

## 5. 迁移步骤（严格按此顺序：先易后难，用 mail 验证模式）

### 5.1 poste-mail（最简单，先用它把流程跑通）

实测全部依赖：`lua/poste-mail/statusline.lua:145` 的
`pcall(require, "poste.statusline")`，仅此一处。

1. 按 A5 拆除该分支：mail 的 statusline.lua 已有完整 legacy 路径
   （provider 解析 + `legacy_mini_wiring` + lualine 注入，178 行），升为唯一
   路径 + scope-guard + 幂等 guard + 补 spec。
2. **不需要** vendor select/installer/state——mail 现在不 require 它们。
   但检查：mail 的 `compat/select.lua` 是否被自家代码引用（若是，无需改动，
   它本来就在）。
3. 跑 mail 自己的测试套件（`tests/run.sh` 若存在；没有就 `luacheck` +
   手工冒烟 `:checkhealth poste-mail`）。
4. 完成后 mail 对 poste.nvim 的依赖归零。

### 5.2 poste-es

实测依赖（grep 核实的调用点）：

- `lua/poste-es/health.lua:21` `pcall(require, "poste.state")`（存在性检查）
- `lua/poste-es/env.lua:6-7` `state` + `putil`（注意 `putil` 是 poste.util 的
  别名）
- `lua/poste-es/connections.lua:9` `putil`；`:256` `pcall(require, "poste.select")`
- `lua/poste-es/config.lua:110` `pcall(require, "poste.state")`（keymap 透传，删）
- `lua/poste-es/danger.lua:70` `pcall(require, "poste.dialog")`
- `lua/poste-es/highlights.lua:4` `state`
- `lua/poste-es/runner.lua:10` `require("poste.indicators")`
- `plugin/poste-es.lua:3` `pcall(require, "poste.state")` guard（删）

动作：vendor state-lite（合并进 `lua/poste-es/state.lua`）、util（合并进
`lua/poste-es/util.lua`，注意与 `putil` 别名共存或顺手统一命名——**只允许**
把 require 行换成本地路径，别名本身不动）、indicators、select、dialog、
installer（es 的 setup 接 ensure）。health.lua:21 的存在性检查改为探测
二进制 + 版本。es 的 danger.lua/connections.lua 用 pcall 是「可选增强」
语义（dialog/select 缺席时降级）——拆散后自家模块必然存在，pcall 可改直接
require，但这是唯一允许的语义简化，提交信息里注明。

### 5.3 poste-redis

实测依赖：

- `lua/poste-redis/statusline.lua:216` `pcall(require, "poste.statusline")`
- `lua/poste-redis/session_conn.lua:136` `require("poste.cli").binary()`（内联调用）
- `lua/poste-redis/health.lua:21` `pcall(require, "poste.state")`
- `lua/poste-redis/config.lua:185` `pcall(require, "poste.state")`（keymap 透传，删）
- `lua/poste-redis/connections.lua:4,6` `state`、`util`；`:393,434`
  `pcall(require, "poste.select")`
- `lua/poste-redis/commands.lua:75` `state`
- `lua/poste-redis/runner.lua:9,74,161,193,221` `state` + indicators（guarded ×4）
- `lua/poste-redis/highlights.lua:4` `state`（`apply_highlight_overrides` 消费方）
- `lua/poste-redis/exec_run.lua:10` `cli`
- `plugin/poste-redis.lua:3` `pcall(require, "poste.state")` guard（删）

动作：vendor state-lite、cli、util、select、indicators、installer；statusline
按 A5。indicators 的 guarded pcall（runner.lua ×4）同样可改直接 require
（注明）。runner.lua 对 indicators 的 pcall 传参核对一遍——它调用的是
`set_indicator`/`clear_all` 一类，vendor 后签名不变。

### 5.4 poste-db（最大，最后做）

实测依赖（**db 独有 error.lua/constants.lua/layout.lua/dialog.lua 消费**）：

- `state`：26 处直接 require（`sql_runner.lua:4`、`statement_indicator.lua:2`、
  `session.lua:25`、`session_conn.lua:11`、`connections.lua:4`、
  `context.lua:3`、`commands.lua:1`、`log.lua:1`、`file_exec.lua:1`、
  `sql_runner/response.lua:9`、`semantic_diagnostics.lua:12`、
  `explain.lua:113`、`introspect/job.lua:17`、`edit_commit/init.lua:58,159`、
  `exec_run.lua:13`、`introspect/init.lua:7`、`completion/init.lua:7`、
  `completion/data.lua:4`、`completion/handlers.lua:8`、
  `db_browser/async.lua:1`、`db_browser/theme.lua:13`、`buffer/init.lua:4`、
  `buffer/nav.lua:4`、`import/execute.lua:1`、`highlights/theme.lua:2`）
- `cli`：`connections.lua:3`、`async.lua:1`、`statement.lua:6`、
  `exec_run.lua:12`、`introspect/exec.lua:2`、`db_browser/actions.lua:4`、
  `db_browser/copy.lua:1`、`db_browser/operations.lua:3`
- `util`：`connections.lua:7`、`health.lua:108`、`introspect/init.lua:8`、
  `introspect/exec.lua:3`、`completion/data.lua:579`、`db_browser/async.lua:423`、
  `nav/handlers.lua:3`、`db_browser/copy.lua:2`
- `select`：`connections.lua:8`、`buffer/search.lua:390`
- `dialog`：`file_exec.lua:2`、`help.lua:3`、`db_browser/copy_progress.lua:6`、
  `db_browser/forms_advanced.lua:1`、`db_browser/ops_drop.lua:28,258,449`、
  `buffer/nav_ui.lua:266`、`import/preview.lua:1`、`import/execute.lua:6`
- `layout`：`file_exec.lua:3`、`db_browser/forms_advanced.lua:2`、
  `db_browser/ops_drop.lua:29,440`
- `indicators`：`sql_runner.lua:7`、`sql_runner/response.lua:12`
- `constants`：`db_browser/copy_progress.lua:7`
- `statusline`：`statusline.lua:153` `pcall`（A5）
- `config.lua:150` keymap 透传（删）；`health.lua:21` poste.state 存在性
  检查（改为二进制探测 + 最低版本断言，见 3.3）；`plugin/poste-db.lua:3`
  `pcall(require, "poste.core")` guard（删）

测试桩改名分布（`package.loaded["poste.xxx"]`，共 12 个 spec 文件 40 处）：
`sql_sql_runner_spec` 10、`sql_file_exec_spec` 9、`sql_introspect_exec_spec` 4、
`sql_connections_spec` 3、`sql_context_spec` 3、`sql_executor_spec` 3、
`sql_nav_spec` 3、`sql_buffer_init_spec`/`sql_diagnostics_spec`/
`sql_edit_commit_spec`/`sql_introspect_job_spec`/`sql_semantic_diagnostics_spec`
各 1。只改键名不改桩内容。

**验收前**必须跑全量：`./tests/run.sh`（预期 ~1276 用例 0 失败）、
`luacheck lua plugin ftplugin tests`（0 警告——db 的 CI gate 是四目录）。

### 5.5 全部 sibling 完成后的文档同步

- db：`AGENTS.md` 的 "Shared infra + family contracts" 引用行、
  `docs/dev/sql/README.md` 的 "Shared infra (poste.nvim) contracts" 章节——
  改写为「自包含；跨仓库契约只剩二进制 schema（poste.nvim/docs/schema.md）」。
  `AGENTS.md` Key Facts 里 `require("poste.state") must succeed` 一句删除。
- 各家 README 的依赖声明、`:checkhealth` 文案同步。

### 5.6 poste.nvim 收尾（最后一步，全部 sibling 验收通过后执行）

1. `lua/` 收缩为兼容 stub：仅留 `lua/poste/core.lua`（`setup()` 空实现 +
   指向新文档的注释）与 `plugin/poste-core.lua`（调用它）——防止旧配置里
   `require("poste").setup()` 报错。四个 sibling 全部发布自包含版本并度过
   一个发布周期后，整目录删除。
2. `lua/poste/statusline.lua` 与 `tests/poste/` 在全部 sibling 发布自包含
   版本后删除。
3. 新增 `docs/schema.md`（内容见 3.3）。
4. README 再次改写：CLI-first（家族表格缩为「sibling 仓库各自独立」一段）。
5. `cargo test --workspace` + clippy `-D warnings` 保持全绿（本任务不改
   Rust，理论上不受影响，改完必须复跑确认）。

## 6. 每仓库完成的验收标准（全过才算完成）

1. `grep -rn 'require("poste\.' lua/ plugin/ ftplugin/` → 0 条。
2. `grep -rn "pcall(require, \"poste\." lua/ plugin/` → 0 条。
3. `grep -rn 'package.loaded\["poste\.' tests/` → 0 条。
4. 该仓库 `./tests/run.sh` 全绿（无套件的仓库：luacheck 0 + `:checkhealth`
   冒烟）。
5. `luacheck` 0 警告（db 必须 `lua plugin ftplugin tests` 四目录全 0——CI gate）。
6. 手工冒烟（有 UI 的仓库）：本插件 dataset/browser 正常打开；statusline
   context 只在本插件 buffer/window 渲染；`:PosteDb*` / `:PosteRedis*` 命令
   正常；二进制缺失时 health 报告可读。
7. 一笔提交，信息模板：
   `refactor(<plugin>): vendor shared lua from poste.nvim (family dissolution)`
   正文列出 vendor 的模块与来源 commit、require 改名数、statusline 处理方式、
   测试结果。

## 7. 全局完成定义

- 5.1–5.6 全部完成且各自验收通过。
- 四个 sibling 的 `grep poste\.` 三连全部归零。
- poste.nvim `docs/schema.md` 存在且覆盖 3.3 列出的子命令。
- 本文档第 1 节快照表更新为完成后的状态（agent 收尾时改写此节）。
- **汇报给维护者**：每个仓库的 commit 哈希清单 + 冒烟结果 + 遗留事项。
  维护者决定何时 push / 打 tag 发版。

## 8. 坑与禁令（违反任何一条 = 返工）

1. **vendor = 逐字拷贝**。只改 require 行与文件头来源标注。发现「bug」或
   「可优化」：记录到提交信息或汇报，不顺手修——语义漂移会让四份拷贝无法
   互相印证。
2. **不 push、不打 tag、不动 Rust**。Rust 侧本任务零改动；`poste-for-db`
   worktree 不碰。
3. **statusline 禁止无条件渲染**（3.4 的 scope-guard 是硬规则）。拆散后最
   危险的回归就是某家把全局槽位又抢回来。
4. **Lua forward declaration**（db AGENTS.md「Lua Pitfalls」）：合并 state/util
   函数时，若函数 A 调用文件内后定义的函数 B，B 必须先 `local B` 声明。
   合并后跑 luacheck 会抓到漏网（`is never accessed` / undefined）。
5. **`and f() or f` 不是三元**（db AGENTS.md）——拷贝时保持原样即可，别
   「简化」。
6. **plenary 单 spec 直调在本环境 flaky**（cache_loader 偶发
   `module not found`）——验证永远用 `./tests/run.sh` 全量。
7. **环境事实**（继承自 `docs/dev/sql/handoff.md` 2026-09-05 交接）：
   db 的 `tests/run.sh` 硬依赖兄弟 checkout `../poste.nvim`（rtp）——迁移 db
   时 poste.nvim 的 `lua/` 还在（收尾是最后一步），不受影响；本机 crates.io
   直连不通，Rust 依赖走 `.cargo/config.toml` 的 rsproxy 镜像（仅
   `poste-for-db` worktree 有此配置；若需在 poste.nvim 主仓构建而失败，加
   同款配置，**不要提交**）。
8. **db 的二进制解析顺序是文档承诺**：`vim.g.poste_binary` → poste config →
   cwd/rtp 旁 `target/{debug,release}/poste` → PATH。vendor 的
   `find_poste_binary` 只许改 source 匹配前缀（A3），其余行为逐字保留。
9. **不重写 vendored 模块的测试**：`poste.nvim/tests/poste/` 里的 spec 是
   参考实现（尤其 statusline_spec 的双 provider 共存用例），迁移时**仿照**
   给各家写自家 scope 的最小 spec，不是照搬文件。
10. 遇到本文档与现实冲突（文件行号漂移、模块被别人改了）：以现实为准，
    在汇报中注明偏差；影响方案的，停下来问维护者。

## 9. 相关文档索引

| 文档 | 用途 |
|---|---|
| 各仓库 `AGENTS.md` | 仓库纪律；poste.nvim 的「Shared-Surface Contracts」章节在拆散后需改写 |
| `poste-db/docs/dev/sql/handoff.md`（2026-09-05） | 上一份交接；第 8.7 条环境事实源自它 |
| `poste-db/LEARNINGS.md` | agent 教训台账 |
| `poste-db/docs/REVIEW-2026-09-*.md`（7 份）、`poste.nvim/REVIEW-2026-09-*.md`（6 份） | 历史缺陷台账；vendor 的模块里包含这些轮次修掉的 bug，逐字拷贝即继承 |
| `poste.nvim/tests/poste/statusline_spec.lua` | scope-guard 测试的参考实现 |
| `poste.nvim/AGENTS.md`（本会话重写） | 契约原文；拆散后 statusline/state 两节作废，API 稳定性一节转为二进制 schema 纪律 |
