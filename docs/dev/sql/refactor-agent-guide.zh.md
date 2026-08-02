# poste-sql.nvim 重构执行指南

> 面向 AI agent 的重构作业说明。目标不是“重写”，而是按最小风险路径拆分、去重、补护栏。

## 0. 背景

这份指南对应 [`docs/dev/archived/code-review-report.md`](../archived/code-review-report.md) 中列出的主要问题：

- 过大的模块
- 重复代码
- magic constants / magic strings
- `nav.lua` 的深层嵌套分支
- `buffer.lua` / `buffer_nav.lua` / `introspect.lua` 的 UI 耦合

## 0.1 当前进度

> 更新时间：2026-08-02。下面这份状态是按当前 `refactor-sql-rewrite` 分支整理的，方便后续 AI agent 接着干。

### 已完成

- Phase 0: 关键回归测试护栏已补齐，相关 helper / behavior spec 都已落地。
- Phase 1: 常量与小 helper 已抽出，`constants.lua`、`util.lua` 已在用。
- Phase 2: `buffer.lua` 的渲染路径已经拆成 helper，`buffer_render.lua` 已落地并有测试。
- Phase 3: `buffer_nav.lua` 的 UI 耦合已拆出大块：
  - `buffer_nav_ui.lua`
  - `buffer_nav_preview.lua`
  - `buffer_nav_raw.lua`
  - `buffer_nav_sort.lua`
  - `buffer_nav_state.lua`
  - `buffer_nav_cell.lua` 已补 column yank 收集 helper
  - `buffer_nav_cell.lua` 也接管了 cell highlight 的应用动作
  - `buffer_nav_cell.lua` 也接管了 cell yank 文本准备
  - `buffer_nav_cell.lua` 也接管了 cell highlight toggle
  - `buffer_nav_ui.lua` 已拆出 status winbar 左右半边 helper
  - `buffer_nav_ui.lua` 已拆出 pending changes 文案 helper 和纯 winbar 拼接 helper
  - `buffer_page.lua` / `buffer_search.lua` 已直接调用 `buffer_nav_ui.lua`
  - `buffer_nav.lua` 已不再转发 `format_conn_short()`，只保留导航动作本身
- Phase 4: `nav.lua` 的分支路由已拆出 `nav_route.lua`，执行逻辑仍在 `nav_handlers.lua`。
- Phase 5: `introspect.lua` 的 job / context 路由已拆出：
  - `introspect_job.lua`
  - `introspect_exec.lua`
  - `introspect_route.lua`
  - `introspect_context.lua`
  - `introspect_ui.lua`
  - `introspect_column.lua`
  - `introspect_table.lua`
  - `introspect_detect.lua`
  - `introspect_target.lua`
  - 文本构造仍在 `introspect_helpers.lua`。
- Phase 6: `init.lua` 的 SQL 执行路径已完成拆分：
  - `sql_runner.lua`
  - `init.lua` 现在只保留 setup / 兼容转发
  - `completion_handlers.lua`
  - `dml.lua`
  - `highlights_theme.lua`
  - `highlights_render.lua`

### 仍未完成

- Phase 5 还有收尾空间：
  - `introspect.lua` 仍然承担 `show_table_ddl()` 的入口路由。
  - `introspect_detect.lua` / `introspect_target.lua` 已拆出检测与目标映射。
  - 后面还可以继续把 shell 组装、动作分发、fallback 执行再切细。

### 已写入的测试

- `tests/sql/sql_buffer_render_spec.lua`
- `tests/sql/sql_buffer_nav_ui_spec.lua`
- `tests/sql/sql_buffer_nav_preview_spec.lua`
- `tests/sql/sql_buffer_nav_raw_spec.lua`
- `tests/sql/sql_buffer_nav_sort_spec.lua`
- `tests/sql/sql_nav_route_spec.lua`
- `tests/sql/sql_introspect_job_spec.lua`
- `tests/sql/sql_introspect_exec_spec.lua`
- `tests/sql/sql_introspect_route_spec.lua`
- `tests/sql/sql_introspect_context_spec.lua`
- `tests/sql/sql_introspect_ui_spec.lua`
- `tests/sql/sql_introspect_column_spec.lua`
- `tests/sql/sql_introspect_table_spec.lua`

## 1. 总目标

1. 降低模块复杂度，让每个文件只负责一类职责。
2. 把可复用的逻辑提到更小、更稳定的 helper。
3. 先补测试，再改实现，保证每一步可验证。
4. 尽量保持现有对外行为不变，避免一次性破坏用户体验。

## 2. 非目标

- 不是一次性清理所有历史债务。
- 不是统一所有 UI 风格。
- 不是把 SQL 模板“去字符串化”。
- 不是修改 `poste.nvim` 的共享基础设施，除非当前仓库无法自洽。

## 3. 工作原则

### 3.1 先测再改

AI agent 在改动任何高风险逻辑前，必须先补最小化回归测试。

优先级如下：

1. 纯函数 / helper
2. 结果格式化
3. 关键 UI 状态转换
4. async / job 回调

### 3.2 小步提交

每一步只做一类变化：

- 先抽常量
- 再抽 helper
- 再拆大函数
- 最后再移动文件

不要在同一个 diff 里同时做“重命名 + 抽函数 + 改逻辑 + 移动文件”。

### 3.3 保持兼容

如果必须保留旧入口，先加 wrapper，再迁移调用点，最后删除旧实现。

### 3.4 不越界

默认只改 `poste-sql.nvim` 仓库内文件。

只有在“当前仓库无法独立完成”时，才考虑改 `poste.nvim`，并且必须先说明理由。

## 4. 推荐重构顺序

### Phase 0: 建测试护栏

先补以下测试，不改实现或只做最小补丁：

| 目标 | 建议测试文件 | 重点 |
|------|--------------|------|
| `buffer.lua` 渲染 | `tests/sql/sql_buffer_spec.lua` | header 提取、分页、raw mode |
| `buffer_nav.lua` 行为 | `tests/sql/sql_buffer_nav_spec.lua` | sort / yank / winbar / dirty guard |
| `nav.lua` 导航 | `tests/sql/sql_nav_spec.lua` | `@connection`、`@database`、table / alias 分支 |
| `introspect.lua` helper | `tests/sql/sql_introspect_spec.lua` | 文本格式化、列表构造 |
| 新 helper | `tests/sql/sql_util_spec.lua` | separator 扫描、UTF-8 截断 |

测试策略：

- 先写 characterisation test，记录当前行为
- 再把 bug 修成“目标行为”
- 每个 phase 结束后运行 `tests/run.sh`

### Phase 1: 常量与小 helper

优先处理报告中的“可低风险抽离项”。

建议动作：

- 提取重复错误文案常量
- 提取 page size、port defaults、left padding、stderr 截断上限
- 抽出 UTF-8 / separator helper

建议新增模块：

- `lua/poste-sql/constants.lua`
- `lua/poste-sql/util.lua`

规则：

- 常量只放“跨模块共享”的值
- 不要把局部语义很强但只用一次的值强行抽走

### Phase 2: `buffer.lua` 拆渲染路径

目标：

- 把 `render_dataset()` 拆成两个可独立测试的函数
- 把 header 提取 / padding 逻辑抽成共享 helper

建议结构：

- `render_dataset_layout()`
- `render_dataset_legacy()`
- `extract_and_pad_header()`

验收点：

- 新旧路径输出一致
- 分页切换不改变状态语义
- header float / winbar 仍然能更新

### Phase 3: `buffer_nav.lua` 去 UI 耦合

目标：

- 把 winbar、预览浮窗、yank、sort 这几类逻辑拆开
- 把重复字符串和浮窗参数收敛

建议动作：

- 抽 `build_status_winbar()` 的数据依赖
- 抽浮窗创建 helper
- 消除重复的 dirty guard 文案

验收点：

- `sort_by_current_col()` 的行为不变
- `toggle_raw_mode()` 可恢复
- `show_search()` 与 `preview_cell()` 仍能正常关闭

### Phase 4: `nav.lua` 拆分导航分支

目标：

- 把 `goto_definition()` 拆成小 handler
- 每个 handler 只处理一种上下文

建议拆法：

- `handle_connection_directive()`
- `handle_database_directive()`
- `handle_table_reference()`
- `handle_dot_column()`

验收点：

- 连接指令、数据库指令、表引用、列引用都能跳转
- 分支逻辑从“单函数深嵌套”变成“路由 + handler”

### Phase 5: `introspect.lua` 与 job 包装

目标：

- 把 float UI 与数据/命令逻辑分开
- 能复用 `cli.run_async()` 的地方尽量不要继续手写 `vim.fn.jobstart`

建议动作：

- 抽 `introspect_ui.lua`
- 抽通用 float helper
- 统一 stderr 收集与错误展示

验收点：

- 列信息、表列表、DDL 仍可打开
- 错误信息不丢失

### 后续候选

如果后面还要继续拆，可以从这些方向再看：

- `init.lua` → `sql_runner.lua`
- `edit_commit.lua` → `dml.lua`
- `completion.lua` → `completion_handlers.lua`
- `highlights.lua` 的色彩与渲染职责分离

## 5. 具体执行规则

### 5.1 每次改动前先确认

AI agent 在动手前应该先回答这三个问题：

1. 这个改动属于哪个 phase？
2. 这个改动的回归点是什么？
3. 这一步是否可以单独回滚？

### 5.2 只在边界清楚时抽公共模块

公共模块必须满足至少一个条件：

- 被 2 个以上模块稳定复用
- 逻辑无明显副作用
- 测试可以独立覆盖

### 5.3 先保留 wrapper

如果重构会影响外部调用点，先保留旧函数名一段时间，例如：

- `M.update_winbar()` 包一层共享实现
- `M.render_dataset()` 包一层新路径分发

### 5.4 不要“优化顺手手”

如果某个函数正在改逻辑，不要顺手做：

- 大规模命名改动
- 无关格式化
- 无关文件移动

这些会让回归定位困难。

## 6. 验收标准

一个 phase 只有在满足下面条件时才算完成：

1. 新增或更新了对应测试
2. `tests/run.sh` 通过，或明确说明跳过原因
3. 行为变化有文档记录
4. 没有引入新的 TODO/临时补丁

## 7. 推荐的提交粒度

建议按下面的粒度出改动：

1. 测试补丁
2. 常量 / helper 抽取
3. 函数拆分
4. 调用点迁移
5. 旧代码删除

不要把 2-5 合并成一个大提交。

## 8. 需要特别注意的文件

高风险优先级从高到低：

1. `lua/poste-sql/nav.lua`
2. `lua/poste-sql/buffer.lua`
3. `lua/poste-sql/buffer_nav.lua`
4. `lua/poste-sql/introspect.lua`
5. `lua/poste-sql/edit_commit.lua`
6. `lua/poste-sql/completion.lua`

## 9. 推荐的执行命令

```bash
tests/run.sh
```

如果只测单个文件，优先用现有的 plenary / headless 入口，不要额外引入新的测试框架。
