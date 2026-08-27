# Table Copy & Yank/Paste — 表复制与 Yank/Paste

## 概述

在 DB Browser 中进行表/视图/数据库的复制，支持两种交互模式：

1. **多选模式**（原始功能）：展开源数据库，按 `<Tab>` 进入多选，选中表后按 `p` 在目标数据库上粘贴。
2. **Yank/Paste 模式**（新增）：在表/视图/数据库/PG schema 节点上按 `y` 记录源对象，然后在目标数据库按 `p` 粘贴。
   - 复制内容包含表结构、数据、索引、视图、触发器、存储过程/函数。
   - 显示数据量 MB 提示；同名冲突时弹窗输入新名（默认原名加 `_copy` 后缀）。

## 交互流程

```
1. 在 DB Browser 中展开源数据库，看到表列表
2. 按 <Tab> 进入多选模式，选中当前表，光标移到下一行
3. 按 j/k 上下导航，按 <Tab> toggle 选中/取消
4. 按 <Esc> 退出多选模式，清除所有选中状态，回到普通导航
5. 光标移到目标 database 节点，按 p 触发复制
6. 弹出确认对话框 → 确认 → 进度窗口 → 结果汇总
```

## 多选模式规则

### 进入/退出

| 操作 | 行为 |
|------|------|
| 在 table 节点上按 `<Tab>` | 进入多选模式，选中该表，`●` 标记，光标移到下一行 |
| 在非 table 节点上按 `<Tab>` | 无操作 |
| 已处于多选模式，在 table 上按 `<Tab>` | toggle 选中状态，光标移到下一行 |
| 按 `<Esc>` | 退出多选模式，清除所有选中，恢复普通导航 |
| 展开/折叠/导航等操作（h/l/CR） | 不退出多选模式，用户可继续浏览 |

### 多选模式规则

> 多选模式保留原有的作用域限制（仅在单个 database 内），确认对话框与进度显示保持不变。
> 新增功能均通过 Yank/Paste 模式提供，不破坏多选现有语义。

## 架构

### 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `lua/poste-db/db_browser/copy.lua` | **新增** | 复制编排逻辑、进度管理 |
| `lua/poste-db/db_browser/init.lua` | 修改 | 多选状态、Tab/Esc/p 键位 |
| `lua/poste-db/db_browser/tree.lua` | 修改 | `flatten_tree` 支持选中标记渲染 |
| `lua/poste-db/db_browser/icons.lua` | 修改 | 添加 `SELECTED`/`UNSELECTED` 图标常量 |

### 状态管理（`db_browser/init.lua`）

```lua
-- 新增全局状态
local multi_select = {
  active = false,       -- 是否处于多选模式
  source_db = nil,      -- 选中所在 database 节点（限制作用域）
  selected = {},        -- { [table_node] = true }
}
```

### 键位注册

| 键 | 条件 | 行为 |
|----|------|------|
| `<Tab>` | 光标在 table 节点上 | 进入/切换多选，选中/取消 |
| `<Esc>` | 多选模式中 | 退出多选，清除所有选中 |
| `y` | 光标在 table/view/database/schema/connection 节点上 | Yank（记录）该对象为源 |
| `p` | 光标在 database 或 SQLite connection 节点上 | 粘贴（优先多选，其次 yank 寄存器） |

### Yank/Paste 流程

```
1. 在 DB Browser 中定位到要复制的节点（table/view/database/PG schema 或 SQLite 连接）。
2. 按 y 记录对象为源；状态栏提示 "Yanked … (press p on a database to paste)"。
3. 将光标移到目标 database 节点（或 SQLite 连接节点）。
4. 按 p：
   - 如果处于多选模式且有选中项，走多选复制流程。
   - 否则，从 yank 寄存器读取源对象：
     * 表/视图级别 → 粘贴该表/视图（支持同库就地复制）。
     * 数据库/Schema 级别 → 粘贴该下所有表、视图、触发器、存储过程/函数。
   - 确认对话框显示源/目标、条目数、数据量 MB、改名映射。
   - 同名冲突弹窗（默认 <名>_copy）→ 用户可自定义或自动追加后缀。
   - 进度窗口顺序执行（表 → 视图 → 触发器 → 例程），完成后显示汇总。
```

### 多选模式规则

**同服务器**（同一 connection，不同 database）：
- `INSERT INTO tgt_db.tgt_table SELECT * FROM src_db.src_table;`

**跨服务器**（不同 connection）：
- 先用 `SELECT * FROM src_table` 从源查询数据
- 解析 JSON 结果，生成批量 INSERT 语句
- 在目标连接上执行 INSERT

初期优先实现**同服务器**复制，跨服务器后续扩展。

## 复制内容范围

| 对象类型 | 复制内容 | 说明 |
|---------|---------|------|
| Base Table | DDL + 索引 + 序列(PG) + 数据 | 复制结构后按同库/跨库策略复制数据 |
| View | DDL | 从源提取 SELECT body 后在目标重建，支持改名 |
| Trigger | DDL | 在目标重建，引用同名表（不自动适配改名） |
| Procedure/Function | DDL | 按源 dialect 获取完整语句后重建；同名冲突不弹窗（失败显示在汇总） |

### 复制顺序

1. 所有 Base Tables（含数据）→ 确保依赖它们的视图可重建
2. 所有 Views
3. 所有 Triggers
4. 所有 Procedures/Functions

## 同服务器 vs 跨服务器

### 复制限制

| 场景 | 支持 | 说明 |
|------|------|------|
| 同 dialect 复制 | ✅ 完整支持 | MySQL→MySQL, PG→PG, SQLite→SQLite |
| 异 dialect 复制 | ❌ 拒绝 | 建表时弹出错误提示，不做隐式转换 |

确定约束的原因：

- **DDL 不兼容** — 同一张表的 DDL 在不同 dialect 中差异巨大（类型名、语法、选项）。例如 MySQL 的 `AUTO_INCREMENT` 在 PG 中是 `SERIAL`，SQLite 又不同。`poste introspect --type ddl` 返回的是源 dialect 的原始 DDL，直接用在目标 dialect 上会报错。
- **类型映射缺失** — 目前 Rust 端没有跨 dialect 的类型映射表，引入后维护成本高。
- **用户预期** — 跨 dialect 复制常需要手动调整 schema（类型、索引、约束），自动复制容易静默丢精度。

如果需要跨 dialect 复制，用户应手动在 SQL 源文件中写好兼容的 DDL 和 INSERT 语句后执行。

### 确认对话框中的 dialect 提示

在确认对话框中明确显示 source/target 的 dialect，让用户感知差异：

## Dialect 约束

复制过程中生成的每一条 SQL 语句都必须根据目标 dialect 做正确的标识符引用。

### 标识符引用规则

由 `lua/poste-db/table_ops.lua` 中的 `quote()` 函数处理（已实现）：

| Dialect | 引用符 | 示例 |
|---------|--------|------|
| mysql | `` ` `` | `` `table_name` `` |
| postgres | `"` | `"table_name"` |
| sqlite | `"` | `"table_name"` |

### 各步骤的 Dialect 处理

**DDL 获取**（步骤 a）：
- 直接调用 `poste introspect --type ddl`，返回源 dialect 的原始 CREATE TABLE
- 不做跨 dialect 转换，仅在目标 dialect 相同时使用

**建表**（步骤 c）：
- 用目标 dialect 的引用符包裹表名
- 去掉源 DDL 中可能包含的 dialect 特有选项（如 MySQL 的 `ENGINE=InnoDB AUTO_INCREMENT=...`）。但 `SHOW CREATE TABLE` 返回的 DDL 通常包含这些选项，在目标 dialect 也是 MySQL 时这些选项是合法的，可以保留。

**复制数据**（步骤 d）：
- 同服务器同 dialect：`INSERT INTO <tgt_quote>tgt_db</tgt_quote>.<tgt_quote>tgt_table</tgt_quote> SELECT * FROM <src_quote>src_db</src_quote>.<src_quote>src_table</src_quote>`
- 跨服务器同 dialect：先用 `SELECT *` 从源查询，再生成批量 INSERT 到目标，标识符用目标 dialect 引用

**表名冲突检测**（步骤 b）：
- 检测语句用目标 dialect 的语法：
  - MySQL: `` SHOW TABLES LIKE '<name>' ``
  - PG: `SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '<name>')`
  - SQLite: `SELECT name FROM sqlite_master WHERE type='table' AND name='<name>'`

## 复制流程（`copy.lua`）

## 数据量提示与警告

- 确认对话框显示总数据量（MySQL/PG/SQLite 估算）。
- 跨服务器且总大小 > 100 MB 时，显示警告，提示可能较慢。

## 架构

### 文件清单

| 文件 | 变更 | 说明 |
|------|------|------|
| `lua/poste-db/db_browser/copy.lua` | **大改** | 引入任务化进度引擎、冲突弹窗、size 聚合、view/trigger/routine 执行器；保留 `M.copy_tables` 以兼容多选。 |
| `lua/poste-db/db_browser/init.lua` | **新增/改** | yank 寄存器集成、y 键位、p 双分派逻辑。 |
| `lua/poste-db/db_browser/yank.lua` | **新增** | yank 寄存器，单一槽。 |
| `lua/poste-db/db_browser/sql_conn.lua` | **新增** | 从 copy.lua 抽取 run_sql_on_conn 与解码函数。 |
| `lua/poste-db/db_browser/catalog.lua` | **新增** | 三方言目录查询（views/triggers/routines/size）与 DDL 提取。 |
| `lua/poste-db/help.lua` | **改** | yank_node、copy_tables 描述。 |
| `lua/poste-db/db_browser/tree.lua` | 不变 | 已有的多选 UI。 |
| `lua/poste-db/db_browser/icons.lua` | 不变 | 已有的标记。 |

### 核心依赖

- `poste/cli.lua` — `run_async`（通过 sql_conn 封装）
- `poste/dialog.lua` — 确认/进度/结果浮窗
- `poste/state.lua` — 配置读取
- `poste-db/connections.lua` — 连接解析
- `poste-db/db_browser/async.lua` — 目录与 yank 枚举用的后台查询
- 现有 `poste introspect --type ddl/table_info` 和 `poste run`（无需改动 Rust）

## 数据量估算

| Dialect | SQL | 说明 |
|---------|-----|------|
| MySQL | SELECT TABLE_NAME, COALESCE(DATA_LENGTH+INDEX_LENGTH,0) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() | 表总大小；视图返回 0 或 NULL（不影响汇总）。 |
| PostgreSQL | SELECT c.relname AS name, n.nspname AS schema, CASE WHEN c.relkind IN ('r','p') THEN pg_total_relation_size(c.oid) ELSE 0 END AS bytes FROM pg_class c JOIN pg_namespace n ... WHERE c.relkind IN ('r','p','v','m') AND n.nspname NOT IN ... | 仅统计表；视图返回 0。 |
| SQLite | SELECT name, SUM(pgsize) FROM dbstat WHERE name NOT LIKE 'sqlite_%' GROUP BY name（可选） | dbstat 编译可选；失败则不显示大小（不影响复制）。 |

### 确认对话框

```
┌───────────── 复制表 ─────────────┐
│                                    │
│  源: maria-dev.blog                │
│  目标: my-blog.inventory           │
│                                    │
│  选中表 (4):                       │
│    ● authors                       │
│    ● categories                    │
│    ● comments                      │
│    ● post_tags                     │
│                                    │
│  [y] 确认复制  [n] 取消            │
└────────────────────────────────────┘
```

- 表名超过 5 个时显示 `+N more`

### 进度窗口

```
┌─────────── 正在复制 ────────────┐
│                                  │
│  [████████░░░░░░░░░]  3/8 (37%) │
│                                  │
│  正在复制: authors               │
│  源: maria-dev.blog              │
│  目标: my-blog.inventory         │
│                                  │
│  ✓ authors     (12 rows, 45ms)   │
│  ✓ categories  (8 rows, 32ms)   │
│  ⟳ comments    (正在复制...)     │
│  ◻ post_tags   (等待中)          │
│                                  │
│  [q] 关闭  [Esc] 取消            │
└──────────────────────────────────┘
```

### 结果汇总

```
┌─────────── 复制完成 ────────────┐
│                                  │
│  成功: 3  |  失败: 1            │
│                                  │
│  ✘ post_tags                    │
│    ERROR: Duplicate entry '...'  │
│    for key 'PRIMARY'             │
│                                  │
│  [q] 关闭                        │
└──────────────────────────────────┘
```

## 依赖

- `poste/cli.lua` — `run_async` 调用 CLI
- `poste/dialog.lua` — 确认/进度/结果浮窗
- `poste/state.lua` — 配置读取
- `poste-db/connections.lua` — `get_connection_config` 获取 dialect
- 现有 `poste introspect --type ddl` 和 `poste run` 命令（无需改动 Rust）