# poste-db.nvim 架构审查报告 — 坏味道与 UI 渲染选型

> 审查方式：以「高级架构师」视角对全仓 39,493 行 Lua 做三路并行深审（db_browser 子系统、dataset buffer/UI 子系统、核心执行链路）+ 对每个关键结论的独立 grep/读码复核。本报告聚焦**架构坏味道**，与 [review-report.md](./review-report.md)（P0-P3 功能缺陷/安全/测试）互补，不重复其内容。
>
> 所有问题均标注 `file:line`；引用行号基于 2026-08-30 的 `ai` 分支工作区。
>
> 配套执行依据：[refactor-agent-guide.zh.md](./refactor-agent-guide.zh.md)（既有重构指南）+ 本报告第 6 节路线图。

## 目录

- [1. 总体结论](#1-总体结论)
- [2. 坏味道清单](#2-坏味道清单)
  - [S1 上帝函数](#s1-上帝函数)
  - [S2 UI 原语碎片化（本次核心）](#s2-ui-原语碎片化)
  - [S3 状态碎片化与多真相源](#s3-状态碎片化与多真相源)
  - [S4 七种异步模型并存](#s4-七种异步模型并存)
  - [S5 纯逻辑重复](#s5-纯逻辑重复)
  - [S6 死代码与空壳抽象](#s6-死代码与空壳抽象)
  - [S7 生命周期泄漏与 require 副作用](#s7-生命周期泄漏与-require-副作用)
  - [S8 越界耦合](#s8-越界耦合)
  - [S9 命名混淆](#s9-命名混淆)
  - [S10 配置三通道](#s10-配置三通道)
- [3. UI 渲染要不要上 nui-components.nvim？](#3-ui-渲染要不要上-nui-componentsnvim)
- [4. 已实施的重构（本次）](#4-已实施的重构本次)
- [5. 未实施但已论证的项（按收益排序）](#5-未实施但已论证的项按收益排序)
- [6. 重构路线图（后续 phase）](#6-重构路线图后续-phase)

---

## 1. 总体结论

模块化目录划分（`buffer/`、`db_browser/`、`completion/`、`introspect/`、`nav/`、`import/`、`ai/`）和 `format.lua` 作为纯布局引擎的设计是合格的骨架；`ident.lua`、`constants.lua`、`float_window.lua` 说明共享原语的意识存在。但骨架上的肌肉长歪了，欠账集中在四类：

1. **UI 原语碎片化**：同一件事（开一个浮窗）在全仓有 **4 套基础设施**（手写 `nvim_open_win` ×9 处、`poste.dialog`、`introspect.show_float`、几乎无人用的自有 `float_window.lua`）和 **2 套表单框架**。这不是「缺一个 UI 框架」，是「原语没沉淀」——**不需要引入 nui-components.nvim，先把自己家 9 处手写浮窗收敛到一个原语模块**（结论详见第 3 节）。
2. **上帝函数**：6 个 200-457 行的函数各自揉合 5-15 种职责，其中 `sql_runner.run_sql_request`（457 行、~15 种职责）与 `buffer.render_dataset`（220 行、渲染管线存在 5 个变体）是最重的两座山。
3. **状态多真相源**：dataset 状态散在 4 个存储（`dataset.D`、`state.lua`、`poste.state`、`vim.b` buffer 变量），光标/连接上下文/tab 数据各有 2-3 份手工同步的拷贝；db_browser 的树是「无主的共享可变状态」，9 个文件原地改写节点。
4. **异步模型 7 种并存**：没有统一的执行入口，竞态防护（epoch/exec_seq）是调用者自觉而不是框架保证。

另一个横切观察：**重构留下的空壳**（`context_client.lua` 整模块死代码、`invalidate_sep_cache` 空桩、`HEADER_LINES=0` 贯穿 29 处的无效参数、`clear_panel(seq)` 忽略参数）说明历次 refactor 拆出了 seam 却没清场。每做完一步拆分，应把壳删掉。

---

## 2. 坏味道清单

### S1 上帝函数

| 函数 | 位置 | 行数 | 揉合的职责 |
|---|---|---|---|
| `M.run_sql_request` | `sql_runner.lua:176-632` | 457 | 二进制查找、键位注入、visual/normal 语句提取、history 记录、spinner 放置、URL 解析、DML 守卫、session/exec-file 路由、on_response 内多 tab 渲染 + SET 前导过滤 + DDL 缓存失效 + 诊断失效 + edit_commit 日志 + db_browser 刷新，三路日志 |
| `M.render_dataset` | `buffer/init.lua:506-725` | 220 | 陈旧守卫、JSON decode、tab 分配、窗口创建、22 个窗口选项、autocmd 生命周期、winbar、光标、历史侧栏刷新。**且渲染管线存在 5 个变体**：`render_dataset_layout`/`render_dataset_legacy`/`render_active_tab`(267-306)/`finalize_rendered_page`(421-444)/空白面板分支(362-373, 403-410) |
| `setup_browser_buffer` | `db_browser/init.lua:220-584` | 365 | buffer 工厂 + 14 个键位 + 在 `p`（粘贴）键位闭包里塞了 168 行的 yank→clone→paste 管线 |
| `M.open` | `db_browser/forms_advanced.lua:159-507` | 349 | 表单状态 + 渲染 + 焦点 + 编辑 + 提交 + 键位，12 层内嵌函数 |
| `fetch_children` | `db_browser/async.lua:109-400` | 292 | 按节点类型分发，table 分支嵌套 5-6 层 |
| `start_batch_drop` | `db_browser/operations.lua:992-1205` | 214 | 进度 UI + 串行 job 调度 + 取消 + 汇总 + 父节点刷新 |

### S2 UI 原语碎片化

**全仓浮窗创建方式普查**（每处均为独立实现的 buf 创建 + 尺寸计算 + `pcall` 容错 + 窗口选项 + 关闭函数）：

| 浮窗 | 位置 | 基础设施 | 备注 |
|---|---|---|---|
| raw mode 表格 | `buffer/nav_raw.lua:35-82` | 手写 `nvim_open_win` | 含 title-pcall 回退、8 个窗口选项、4 组键位 |
| 单元格预览 | `buffer/nav_preview.lua:56-113` | 手写 | 自带一套尺寸算法（与 `float_window.centered_dimensions` 平行演进） |
| 吸顶表头 | `buffer/header.lua:159-178` | 手写 | enter=false，后续 `nvim_win_set_config` 复用窗口 |
| 历史侧栏 | `buffer/history.lua:168-197` | 手写 | relative="win" 锚定 dataset 窗口 |
| 搜索提示窗 | `buffer/search.lua:134-151` | **`float_window.open_centered`** | 共享 helper 的唯一消费者 |
| SQL 日志查看器 | `log_viewer.lua:571-598` | 手写 | 还在用已废弃的 `nvim_buf_set_option`/`nvim_win_set_option` API |
| 浏览器简单表单 | `db_browser/forms.lua:143-191` | 手写 | 边框用文本字符手画（`forms.lua:56,78`） |
| 浏览器高级表单 | `db_browser/forms_advanced.lua:226-233` | `poste.dialog` | — |
| 右键菜单 | `db_browser/context_menu.lua:165-236` | 手写 | 边框同样是文本手画（`:110,127`），WinLeave 关闭自己实现 |
| flash 提示条 | `db_browser/flash.lua:51-78` | 手写 | enter=false + winhl |
| 确认/进度/汇总对话框 ×6 | `db_browser/copy.lua:662-742`、`operations.lua:853-1086`、`forms_advanced` | `poste.dialog` | — |
| 列/表/DDL 信息浮窗 | `introspect/ui.lua` | `show_float` | — |

结论性证据：

- 共享原语 `float_window.lua`（73 行）**只有 1 个消费者**（search.lua）；4/6 个 dataset 浮窗绕过它。
- `pcall(nvim_open_win)` + 失败去 title 重试的幂等片段复制了 3 份：`float_window.lua:56-61`、`nav_preview.lua:100-105`、`nav_raw.lua:57-60`。
- **进度条渲染**（`█/░`、20 格、百分比）在 `operations.lua:1007-1051` 与 `copy.lua:759-815` 近逐行重复；**50 字符错误换行切块**在 `copy.lua:693-698` 与 `operations.lua:1078-1083` 重复；`uv` spinner 各写一份（`copy.lua:864-876`）。
- **两套表单框架并存**：`forms.lua`（扁平字段）与 `forms_advanced.lua`（分区/列表）维护着平行的 render/refresh/键位/编辑机制。
- **7 个模块在 require 时各自注册高亮 + ColorScheme autocmd**：`icons.lua:104-105`、`copy.lua:23-24`、`forms.lua:20-21`、`forms_advanced.lua:17-18`、`context_menu.lua:89-90`、`flash.lua:21-22`、`operations.lua:989-990`——没有统一的主题所有者（dataset 侧有 `highlights/theme.lua`，db_browser 侧没有）。

### S3 状态碎片化与多真相源

**dataset 状态 4 个存储**：

1. `dataset.lua` 模块级 `D`（buffer/window/tabpage、tabs、30 字段的匿名 tab 结构 `dataset.lua:174-199`、autocmd id、`search_ns`——注释声称"no poste deps"但生命周期 id 也塞在这）；
2. `state.lua`（`cell`、`last_dataset`、`context`、`_hide_*` 开关）；
3. `poste.state`（外部宿主：`last_response.body`、`state.log`，40 个文件依赖）；
4. `vim.b` buffer 变量（`nav_ui.lua:99-102` 写 `poste_db_context`/`poste_db_conn`，statusline 读）。

**双真相源实例**：

- **光标**：`tab.cursor`（dataset.lua:182）vs `sql_state.cell`（state.lua:14-17）。仅在 `save/apply_tab_state`（buffer/init.lua:248-263）手工同步；`nav.move_cell` 只改 cell（nav.lua:52-53），search 跳转只改 cell（search.lua:120-121），page.lua 对两者各自独立 clamp（:46-51 vs :99-104）——不同步即错位。
- **tab 数据**：`tab.data` vs `sql_state.last_dataset`（buffer/init.lua:262, 551 双写；后者只有 `ai/init.lua:137,195` 读）。
- **连接上下文**：`layout._conn_name/_database`（buffer/init.lua:450-460 与 :582-593 同文件写两遍）vs `sql_state.context`（nav_ui.lua:62-63 读）vs `vim.b.poste_db_context`（statusline 读）——一个事实三份拷贝。
- **db_browser 树是无主共享可变状态**：`make_context`（db_browser/init.lua:208-218）把 `root_nodes`/`line_to_node`/`multi_select`/`source_buf` 的**活引用**交给 6 个模块，9 个文件原地改写 `node.children/expanded/loading/epoch`（actions.lua:82-104/207-220、operations.lua:337-350/906-919/1100-1106、init.lua:193-204/438-447/463-488/890-903、schema_create.lua:182-185、db_create.lua:162-165、async.lua:111-115/145-146）；「children=nil → expanded=false → loading=true → 重渲染 → fetch → expanded=true → 重渲染」的刷新舞步复制了 **12+ 处**，`for i,n in ipairs(map) do line_to_node[i]=n end` 复制了 **27 处**。
- **隐式全局通道**：`_G.poste_search_info`（actions.lua:345,391,411,423 写 → tree.lua:346 读，同子系统却走 `_G`）；`sql_state.db_browser.connection` 被 init.lua:618/689/839 写、被 async.lua:129 和 util.lua:8,19 **静默回读**——任何没有 `meta.connection` 的节点行为取决于"上一个浏览的连接"。

### S4 七种异步模型并存

| 模式 | 位置 | 数量 |
|---|---|---|
| `poste.cli.run_async` | exec_run.lua:339、introspect/exec.lua:12、db_browser actions.lua:508、operations.lua:202、connections.lua:434、async.lua:64 | 6 |
| 裸 `vim.fn.jobstart` | session_conn.lua:201、file_exec.lua:375（还是 shell 串拼的第三种形态）、semantic_diagnostics.lua:394,430、copy.lua:198、completion/data.lua:323,416,484,613 | 11 |
| `vim.system` + 立即 `:wait()`（名为 async 实为同步阻塞） | completion/init.lua:143-146（补全热路径 2s）、introspect/init.lua:149-154（5s）、nav/handlers.lua:85、exec_run.lua:267-269（30s）、source_format.lua:288 | 5 |
| 长驻 `chansend` session 管道 | session_conn.lua:268,288 | 2 套实现 |
| `vim.uv` 直用 | 定时/统计（file_exec、edit_commit、copy spinner 等） | — |
| 阻塞 `io.popen` | commands.lua:53、health.lua:33（重复的 binary --version 探测） | 2 |
| `poste-db/async.lua`（15s 超时包装） | 全仓唯一消费者是 db_browser/async.lua:5 | 1 |

后果：stderr 缓冲、JSON pcall decode（db_browser 内 17 处）、`vim.schedule` 编组、错误通知各写一遍；epoch/exec_seq 竞态防护是调用者美德而非框架保证（`render_dataset` 的 exec_seq 守卫有两个入口不传，`clear_panel(seq)` 干脆忽略参数——已在本轮修复）。

### S5 纯逻辑重复

- **标识符引用 3 份**：`ident.lua:3-47`（正主）vs `copy.lua:26-32 quote` / `:38-57 quote_value` vs `catalog.lua:16-19 esc_quote`——方言语义相同（值引用细节略有分叉，见 S8/P0-3）。
- **单元格几何 3 份**：`format.lua:326-348 col_starts`（权威）vs `buffer/render.lua:82-105`（重新推导 padded 位置，带魔法 `+2`）vs `buffer/header.lua:19-44`（逐字符重扫）；`│` 分隔符扫描 3 份：`highlights/render.lua:23-37`、`:61-82`（近乎逐行复制的 fallback）、`header.lua:19-44`。
- **宽度/截断 4 份**：`util.truncate_displaywidth` vs `nav_ui.lua:35-45` vs `history.lua:32-42` vs `format.lua:29-37`。
- **连接串缩短 2 份**：`nav_ui.lua:47-52 format_conn_short` vs `format.lua:76-103 parse_connection_short`（后者死代码）。
- **`format_bytes` 2 份且输出不一致**：`actions.lua:440-446`（`kB`，2 位小数）vs `copy.lua:564-570`（`KB`，1 位小数）——同名不同输出，典型漂移。
- **`schema_create.lua` 与 `db_create.lua` 约 60% 互为克隆**：`execute_sql`（127-173 vs 108-153，46 行近逐行）与 `refresh_database/refresh_target`（175-199 vs 155-179，仅 node_type 不同）。
- **completion/data.lua 四个 `ensure_*`**（:281, :366, :452, :524）各自复制 in-flight callbacks + epoch 守卫 + jobstart 脚手架。
- **响应信封解码 2 份**：`session_conn.lua:62-99` vs `exec_run.lua:126-198`（含 `norm_affected` 双份）；`sql_conn.lua:78-79` 注释自证「Preserve copy.lua's original semantics」——靠人肉同步的 fork。
- **ai/ 内部**：可用性守卫逐字复制 5 份（ai/init.lua:55-59, 69-72, 101-104, 132-135, 206-209）；`introspect()` 包装逐字复制 2 份（mentions.lua:65-74 vs schema.lua:21-30）；`SKIP_DATABASES` 与 `db_browser/async.lua:163-167` 重复。
- **winbar 选中计数循环**：`tree.lua:355-363` vs `statusline.lua:108-116`。
- **浮窗子窗口清扫**（关掉锚在 dataset 窗口上的所有子浮窗、跳过 history 侧栏）：`buffer/init.lua:735-748`、`:772-781`、`header.lua:86-99` 三份。

### S6 死代码与空壳抽象

| 项 | 位置 | 状态 |
|---|---|---|
| `context_client.lua` 整模块（173 行，jobstart + JSON-RPC + 指数退避） | 全仓 | **零 require**（含测试）；补全热路径却仍在用同步 `vim.system:wait()`——为解决问题而建的抽象被弃养 |
| `format.M.render_row_with_starts` | format.lua:799-805 | 零消费者 |
| `format.parse_connection_short` 局部函数 | format.lua:76-103 | 死代码（带 luacheck 压制注释） |
| `format.M.normalize_type` 导出 | format.lua:472 | 导出无人用（内部 :214,:543 在用）→ 应降为 local |
| `catalog.M.parse_size_rows` | catalog.lua:230-244 | 零消费者；`M.sizes` 反而内联重写了同样的解析 |
| `flash.M.close` 导出 | flash.lua:81-83 | 零消费者（内部 close local 另有） |
| `_G.poste_db_copy_cancel_last` | copy.lua:1105 | 只写不读 |
| `invalidate_sep_cache` 空桩 | highlights/render.lua:84 + init.lua:15 + buffer/init.lua:531 + editor/nav.lua:116 | 空函数被 4 处「调用」——缓存早已移除，调用是仪式 |
| `state.pagination` | state.lua 默认值 + session.lua:32 | 生产只写不读（reset） |
| `M.clear_panel(seq)` 的 seq 参数 | buffer/init.lua:731 | 参数被忽略（已修） |
| `HEADER_LINES = 0` | icons.lua:36，贯穿 tree/actions 等 29 处 `buf_line - HEADER_LINES` | 恒为 0 的无效减法，抽象已死参数还活着 |
| 4 个孤儿高亮组 | `PosteDbBrowserHeader/Separator/Table/KeyHint`（icons.lua） | 定义并注册 override，但无任何 apply |
| `notify.M.error` | notify.lua:27-29 | 门面函数零消费者——19 处调用点绕过门面裸调 `vim.notify` |
| `_test` 表泄漏进生产热路径 | ai/schema.lua:96 读 `M._test.MAX_EXPAND` | 测试缝出现在自动注入路径上 |

### S7 生命周期泄漏与 require 副作用

- **每次渲染泄漏 2 个全局 autocmd**：`buffer/init.lua:684-688`（VimResized）与 `:695-701`（WinClosed）重新创建前**不删除旧 id**（对比 resize/scroll 在 :667-674 正确轮换）；`M.close()`（:758-791）删除了 3 个 id 却**漏删 `winclose_autocmd_id`**。渲染 N 次泄漏 2N 个全局回调，close 之后阴魂不散（已修）。
- **共享防抖定时器跨 buffer 竞争**：`sql_runner.lua:25` 模块级单例 `_cursor_moved_timer` 被所有 SQL buffer 的 CursorMoved 回调共用。
- **require 即副作用**：`statement_indicator.lua:132` require 时创建用户命令 `PosteDbBoundary`；`insert_hint.lua:2`、`log_viewer.lua:7` require 时创建 namespace；S2 所列 7 个 db_browser 模块 require 时注册高亮 + ColorScheme autocmd。测试或偶然 require 都会触发全局注册。
- **`statusline.lua` 篡改第三方全局配置**：整体替换 mini.statusline 的 `section_fileinfo`（:70-76）并**全量覆写 `config.content.active`**（:78-106，把 mini 内部常量重新打字一遍，上游一改即静默错位）；lualine 走 `get_config()`→注入→`setup(cfg)` 回灌（:116-138）。且 `get_ctx_color`（:4-52）在**每次 statusline 渲染**时调 `nvim_set_hl`。
- **monkey-patch 第三方**：`operations.lua:266-274` 运行期翻转 dressing 的 `input.enabled`；`db_browser/completion.lua:113-150` 猴补 blink.cmp provider 表与 `completion.enabled`。

### S8 越界耦合

- `db_browser/actions.lua:251-270` 直接 `require("poste-db.buffer")` 渲染数据集，且**必须理解** `state.last_response.body` 的 fallback 语义才能写对调用（注释自证「otherwise falls back to state.last_response.body (only the sql_runner path updates it)」）。
- **双向依赖**：sql_runner.lua:572-574 → `db_browser.init`（refresh_by_conn/is_open）；db_browser/actions → exec_run/format → …形成环。
- **require 环**：`copy.lua:1166-1167` → async、→ db_browser/init；`sql_conn.lua:9-12` → db_browser/init 只为拿 `get_search_dir()`（应做参数）。
- **`db_browser/async` 成了事实上的公共数据层**：import.lua:3、ai/commands.lua:53、ai/mentions.lua:66、ai/schema.lua:22 都 require 浏览器的私有树抓取内部。
- **ai/ 绕过防腐层**：`completion/` 有 `adapter.lua` 包装 blink；`ai/` 却直接 require poste-ai 的私有子模块（`poste-ai.chat.mention` init.lua:80、`chat.window` :84,125,183,232、`chat.scope` :91）。
- **schema_create/db_create 阻塞内省**：`db_create.lua:38-59 fetch_roles` 在打开表单前同步跑一次 SQL（阻塞 UI）；`nav/handlers.lua:85-88` 在 handler 里 5 秒阻塞 `:wait()`。

### S9 命名混淆

「nav」一名三义：`nav/`（SQL 源码 buffer 的 go-to-definition）、`buffer/nav*.lua`（8 个文件，数据集单元格导航）、`editor/nav.lua`（单元格编辑导航）。另外 `poste-db/async.lua` 与 `db_browser/async.lua` 同名不同物，前者几乎无人用。

### S10 配置三通道

`config.lua` 表（9 个模块直读 11 处）+ `compat.opt("...")` 读 `g:` 全局（~25 处 × 12 文件）+ `vim.b.poste_db_*` buffer 变量（statusline 传输通道）。debug 开关有两个真相源（`config.config.debug` 管 commands.lua:182，`compat.opt("debug")` 管补全模块）——`setup{debug=true}` 只点亮一半。键位解析两层（config.lua:141-149 先查兄弟插件 poste.state 的 keymaps）。

---

## 3. UI 渲染要不要上 nui-components.nvim？

**结论：现在不引入；先完成内部原语统一（本次已实施），将来若表单/向导复杂度继续涨，可作为可选软依赖接在 `ui/` 适配层后面。**

### 3.1 组件映射分析

nui-components.nvim（grapp-dev，构建于 nui.nvim 之上）提供：Layout、Text/Paragraph、TextBox、TextInput、Select、MultiSelect、Tree、Spinner、Progress、Tabs、Notification 等，配 signal 响应式状态模型。把本仓 UI 逐块对上去：

| 本仓 UI 块 | 规模 | nui-components 映射 | 判断 |
|---|---|---|---|
| **dataset 网格**（buffer/* 11 个文件 + format.lua + highlights/*，约 4,000 行） | 最大头 | **无对应组件**。这是普通 buffer 上的电子表格：逐字符渲染、extmark 高亮、单元格编辑提交、分页、winbar。任何树/文本组件都表达不了 | 引入库也帮不了 60% 的 UI |
| **db_browser 树**（tree.lua + init.lua + async.lua，约 1,700 行） | 次大头 | Tree 组件能覆盖渲染/导航/展开的**管道部分**（约 tree.lua 的 415 行里的 1/3） | 但 12 处异步刷新舞步、epoch、多选、搜索 extmark、右键菜单分发是业务逻辑，照样要写；重写风险高、收益中 |
| **表单**（forms.lua 313 行 + forms_advanced.lua 509 行） | 中 | **最佳匹配**：TextInput/Select/MultiSelect 直接对应字段类型，signal 状态能消掉 forms_advanced.M.open 的 349 行手写状态机 | 真正的潜在收益点，但要重写两套框架合一 |
| **进度/确认/汇总**（copy + operations，约 400 行） | 中 | Spinner/Progress 文本组件对口 | 收益真实但量小 |
| **预览/菜单/侧栏/flash**（7 处浮窗） | 小 | Popup 类可用，但这些都已能被**自己 100 行的原语**覆盖 | 用不上框架 |

### 3.2 为什么现在不引入

1. **病灶是重复，不是缺框架**。9 处手写浮窗的样板（buf 创建、title-pcall 回退、窗口选项、q/Esc、WinLeave）收敛到一个 `float_window.open()` 原语即可消除——这正是本次实施的重构（见第 4 节）。一个 ~150 行的内部模块解决了 nui-components 能解决的那 20%，剩下 80% 它也解决不了。
2. **依赖策略成本**。本仓唯一硬依赖是 poste.nvim，AI 是可选软依赖（`pcall(require, "poste-ai")`，缺了静默降级）。引入 nui-components 意味着 **nui.nvim + nui-components 两个新依赖且强联动**（前者高频更新 API，后者是单维护者年轻项目，版本锁定与上游漂移风险都转嫁到本仓）。
3. **headless 测试变复杂**。本仓测试是 plenary headless 裸跑；nui-components 组件实例化即开窗、依赖 signal 调度，现有 46 个 spec 的测试姿势要整体改造。
4. **响应式状态模型对本仓主场景是杀鸡牛刀**。对话框大多是「开窗→一次性渲染→关闭」的命令式流程；真正多字段联动的只有 forms_advanced 一处。

### 3.3 何时值得回头考虑

- 如果 `forms_advanced` 的分区/列表/子编辑继续长出向导式多步流程（signal 模型开始显著省代码）；
- 或者未来要统一的 spinner/进度 UI 遍布更多子系统。

届时推荐姿势是**可选软依赖 + 适配层后端**：把第 4 节落地的 `float_window.lua` 原语层当作 seam，`ui/backend_nui.lua` 用 `pcall(require, "nui-components")` 实现同一接口，缺失时回落到内置后端——与本仓对 poste-ai 的可选集成完全同构，用户装了就升级体验，没装不坏。

---

## 4. 已实施的重构（本次）

> 原则沿用 [refactor-agent-guide.zh.md](./refactor-agent-guide.zh.md)：小步、行为保持、测试先行；每批独立可回滚。全量 `tests/run.sh` 通过。

### 批次 1 — UI 浮窗原语统一（对应 S2）

- `float_window.lua` 扩展为通用浮窗原语：新增 `M.open(opts)`（buf 创建/lines 写入/尺寸计算或显式定位/title-pcall 回退/窗口选项表/键位表/WinLeave 自动关闭）与 `M.bind_keys(buf, maps)`；`centered_dimensions`/`open_centered` 保持原 API 与测试不变。
- 迁移 8 处手写浮窗到统一原语：`buffer/nav_raw.lua`、`buffer/nav_preview.lua`（开窗部分）、`buffer/header.lua`（创建部分，config 复用路径保留）、`buffer/history.lua`、`db_browser/flash.lua`、`db_browser/forms.lua`（WinLeave 编辑守卫保留为 `on_winleave` 回调）、`db_browser/context_menu.lua`、`log_viewer.lua`（顺带改用现行 `nvim_set_option_value` API）。
- 消除 3 份重复的 title-pcall 回退与 2 套平行尺寸算法中可收敛的部分（`nav_preview` 保留其环绕高度算法，但 buf/开窗/选项走原语）。

### 批次 2 — 生命周期泄漏修复（对应 S7）

- `buffer/init.lua`：VimResized/WinClosed 重建前轮换删除旧 id；`M.close()` 补删 `winclose_autocmd_id`；新增回归测试断言重复渲染不累积全局 autocmd。
- `M.clear_panel(seq)`：删除被忽略的 seq 死参数，调用点 `sql_runner.lua:272` 同步更新。
- 移除 `invalidate_sep_cache` 空桩及其全部 4 处仪式性调用。

### 批次 3 — 死代码清理（对应 S6）

- 删除 `context_client.lua` 整模块（零 require，附热路径说明迁移到报告）。
- `format.lua`：删除 `render_row_with_starts`、`parse_connection_short`；`normalize_type` 降为 local。
- 删除 `catalog.parse_size_rows`、`flash.M.close`、`_G.poste_db_copy_cancel_last` 写点、`state.pagination`（含 session.lua reset 与 state_spec 断言同步）。

### 批次 4 — 重复逻辑合并（对应 S5）

- `copy.lua` 的 `quote()` → `ident.quote()`（调用点均为单一标识符，语义等价且继承点号拆分与转义）；`actions.lua` 与 `copy.lua` 的 `format_bytes` 合并为 `db_browser/util.format_bytes`（采用两位小数版本，`copy` 侧的 `%.1f KB` 外观输出随之统一，报告记录该变化）。
- `schema_create.lua`/`db_create.lua`：提取 `db_browser/util.run_ddl_and_refresh()` 与 `refresh_subtree()`（node_type 参数化），两文件各删 ~90 行克隆。
- `ai/init.lua`：5 份可用性守卫合并为 `ensure_available()`；`ai/mentions.lua`/`ai/schema.lua` 的 `introspect()` 包装提到 `ai/introspect.lua`（新小模块）复用。

---

## 5. 未实施但已论证的项（按收益排序）

1. **状态单一真相源**（S3）：`tab.cursor` 与 `sql_state.cell` 合一（cell 作为唯一写点，tab.cursor 变成 save/apply 时的投影）；连接上下文三份合一；`last_dataset` 砍掉（ai 直接读 tab）。风险中，需先补光标行为的 characterisation test。
2. **db_browser 树状态收权**（S3）：把「children/expanded/loading 突变 + 渲染 + line_map 回写」收进 `tree.lua` 的 `M.invalidate_and_fetch(node, context)`，替换 12 处舞步与 27 处拷贝循环；`make_context` 收窄为只读视图。
3. **sql_runner.run_sql_request 拆分**（S1）：`on_response` 内多 tab 渲染循环 → `sql_runner/response.lua`；DML 守卫/history/spinner 各归其位；entry 只留编排。遵循 harness 的 wrapper-先行策略。
4. **补全热路径去同步**（S4）：`completion/init.lua:143` 的同步 `vim.system:wait()` 换成复活或重写 `context_client` 的异步协议（或彻底删协议改 debounce），并把缓存键里的全文扫描（cache_key → resolve_full_context）降为增量。
5. **statusline 停止篡改第三方**（S7）：mini.statusline 改为通过其公开的 section 注册机制（或至少只 patch `section_fileinfo`，不覆写 `content.active`）；hl 组按连接缓存。
6. **异步收敛**（S4）：`async.lua` 升级为唯一 job 入口（统一 epoch/超时/stderr 清洗/JSON decode），copy.lua 裸 jobstart 与 completion/data 的 4 份脚手架迁入。
7. **工程基建**（review-report P3 复述）：`.luacheckrc` + `.stylua.toml` + CI——S6 里一半的死代码是 lint 能自动拦住的。

---

## 6. 重构路线图（后续 phase）

| Phase | 目标 | 验收标准 |
|---|---|---|
| P-A（本次） | UI 原语统一 + 泄漏修复 + 死代码清场 | 8 处浮窗走单一原语；渲染不泄漏 autocmd；`tests/run.sh` 绿 |
| P-B | 状态单一真相源（第 5 节 1） | 光标/上下文各只剩一个写点；tab 切换/翻页/搜索跳转行为不变（新 characterisation tests） |
| P-C | db_browser 树收权（第 5 节 2） | 刷新舞步唯一实现；`node_type` 分发集中在 tree 层 |
| P-D | sql_runner 拆分（第 5 节 3） | `run_sql_request` < 150 行且只做编排；response 渲染独立可测 |
| P-E | 异步收敛 + 补全热路径去同步（第 5 节 4/6） | 唯一 job 入口带 epoch/超时；补全触发无阻塞 `:wait()` |
| P-F | 表单框架合一（视 P-A 后的残留量决定是否引入可选 nui-components 后端） | forms.lua 退役，forms_advanced 独立承担；`M.open` < 100 行 |

---

*architecture review — 2026-08-30*
