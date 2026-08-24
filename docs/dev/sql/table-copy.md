# Table Copy — 表复制功能设计

## 概述

在 DB Browser 中多选表，跨数据库/跨连接复制表结构和数据。

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

### 作用域限制

多选模式**只能在单个 database 内**进行选择。跨 db 选择的行为：

- 进入多选时，记录 `source_db`（当前所在的 database 节点）
- 当光标移到**不同 database** 内的 table 上时，按 `<Tab>` 无操作
- 当光标移到**不同 connection** 内的 table 上时，按 `<Tab>` 无操作
- 只有当前选中的 `source_db` 下的 table 可被选中或取消
- 按 `p` 时，目标 database 必须是**不同**的 database 或 connection（禁止复制到自身）

### 视觉标记

使用 `●` (U+25CF) 表示已选中，`○` (U+25CB) 表示未选中但处于多选模式。

```
  ●  authors 7       ← 选中
  ○  categories 7    ← 未选中（多选模式中）
  ○  comments 10     ← 未选中（多选模式中）
  ○  post_tags 5     ← 未选中（多选模式中）
```

非多选模式时，不显示 `○`，恢复常规 marker（展开/折叠箭头）。

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
| `p` | 光标在 database 节点上 | 触发复制 |

### 同服务器 vs 跨服务器

**同服务器**（同一 connection，不同 database）：
- `INSERT INTO tgt_db.tgt_table SELECT * FROM src_db.src_table;`

**跨服务器**（不同 connection）：
- 先用 `SELECT * FROM src_table` 从源查询数据
- 解析 JSON 结果，生成批量 INSERT 语句
- 在目标连接上执行 INSERT

初期优先实现**同服务器**复制，跨服务器后续扩展。

## Dialect 约束

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

```
┌───────────── 复制表 ─────────────┐
│                                    │
│  源: maria-dev.blog  (mysql)       │
│  目标: my-blog.inventory (mysql)   │
│  状态: ✅ dialect 一致，可复制     │
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

dialect 不一致时：

```
┌───────────── 复制表 ─────────────┐
│                                    │
│  源: maria-dev.blog  (mysql)       │
│  目标: my-pg.inventory (postgres)  │
│  状态: ❌ dialect 不同，无法复制   │
│                                    │
│  按 [q] 关闭                       │
└────────────────────────────────────┘
```

## SQL 语句的 Dialect 感知

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

```
copy_tables(source_node, target_node, selected_tables)
  │
  ├─ 1. 解析 source/target 的 connection, database, dialect
  │
  ├─ 2. 对每张表循环：
  │     ├─ a. poste introspect <src_conn> --type ddl
  │     │     --table <name> --database <src_db>
  │     │     → 获取 CREATE TABLE DDL
  │     │
  │     ├─ b. 表名冲突检测
  │     │     poste run <tgt_conn> "SHOW TABLES LIKE '<name>'"
  │     │     → 存在则加 _copy 后缀，重复则 _copy2, _copy3...
  │     │
  │     ├─ c. 建表
  │     │     poste run <tgt_conn> --database <tgt_db>
  │     │     执行修改后的 DDL（替换表名）
  │     │
  │     └─ d. 复制数据
  │           poste run <tgt_conn> --database <tgt_db>
  │           "INSERT INTO <tgt_table> SELECT * FROM <src_db>.<src_table>"
  │
  └─ 3. 汇总结果
```

## UI 组件

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