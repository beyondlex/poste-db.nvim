# LEARNINGS

> Agent 踩坑实录。每条都来自本仓库真实发生过的错误（2026-08 架构重构会话），
> 不是泛泛的最佳实践。动手前扫一遍，同类错误不要犯第二次。
>
> 配套 harness：`.opencode/skills/sql-audit-harness/`（证据规则）、
> `sql-refactor-harness`（留壳/Lua 陷阱）、`sql-architecture-harness`（原语入口）。

## 1. 审计 hearsay 不是证据

**发生了什么**：子代理审计报告的多个"死代码/坏味道"结论经复核是错的——

- `format.format_number` 被判死代码，实际有 `sql_format_bigint_spec` 覆盖；
- `state._hide_header_float` / `_hide_row_numbers` 被判"写了没人读的死状态"，
  实际是**用户可从外部设置的隐藏开关**（"只读未写"≠死）；
- `nav_cell.toggle_cell_highlight` 生产零调用但有测试，属"仅测试暴露面"，
  删除是产品决策不是清理；
- 光标双真相源（`tab.cursor` vs `sql_state.cell`）被判"结构性漂移"，
  逐点枚举读写点后发现双写仅 3 处且同步点全部正确——最终结论修订为"暂不做"。

**约束**：子代理产出 = 假设。任何要写进报告或据此动手的论断，必须自己
grep + 读码复核并在报告中标注 verified / inferred。结论被推翻时显式写修订
记录，不要静默改写。

## 2. 0 命中的 grep 先怀疑 grep 自己

**发生了什么**：shell 循环里 `grep -c "$m\."`，当 `$m` 是 `D\.` 时实际模式
变成 `D\.\.`，匹配 0 次 → 误判 `dataset` require 无用 → 删掉 →
`D.T()` 在运行时报 `attempt to index global 'D' (a nil value)`。全量测试抓住。

**约束**：以"0 命中"为由的删除，必须先打印模式、对照真实调用形态
（`D.T()` 要匹配 `D\.T`；`M.x` / local 别名 / 方法调用 / `_test` 导出都要各查一遍），
删除后跑 `tests/run.sh`。grep 是必要条件，不是充分条件。

## 3. `M.x` 降级 local：先查所有调用点的词法位置

**发生了什么**：`format.lua` 把 `M.normalize_type` 改成 local，但
`is_numeric_column`（约 180 行）在定义（约 438 行）之前调用 →
`attempt to call global 'normalize_type' (a nil value)`，套件 2 例失败。
这就是 AGENTS.md「Local function forward declaration」规则的变体——
坑不在定义与调用相邻时，而在两者相距几百行时。

**约束**：`M.x` → local 前，grep 全部调用点；任一调用在定义之前，
要么前置声明 `local x`，要么把定义整体上移到首个调用之前。

## 4. `and f() or f` 的 nil 陷阱

**发生了什么**：`db_browser/theme.lua` 第一版写
`type(spec) == "function" and spec() or spec`，operations 的 spec 函数按
设计返回 nil（"已定义则跳过"）→ `and spec()` 得 nil → 表达式回落到 `spec`
本身（函数）→ 函数被传给 `nvim_set_hl` → `Expected Lua table`，
整棵 require 链炸掉且报错位置在链的最外层，极难定位。

**约束**：中间结果可能为 nil/false 时禁止 `and-or` 取值惯用法，用显式 if。
依赖链上的 require 错误会报在最外层 require 处——看到"loop or previous
error loading module 'X'"时，真错误在 X 的加载过程里，不在引用它的地方。

## 5. 重构要清场：壳留在原地就是没做完

**发生了什么**：历次 refactor 留下一批空壳，本次全部清理——
`invalidate_sep_cache()` 空函数 + 4 处仪式性调用、`clear_panel(seq)` 被忽略
的参数、`context_client.lua` 173 行零引用模块、`HEADER_LINES = 0` 贯穿
29 处的无效减法。这些壳的存在说明"拆出 seam"和"删旧路径"被当成了两件事。

**约束**：抽取 seam 与删除旧壳在**同一批 commit** 内完成。挑一个 seam 时
先问：它的旧壳还在吗？

## 6. 合并重复实现 = 替别人选行为，要把增量说清

**发生了什么**（都是有意为之并已记录在 commit/报告里）：

- 两份 `format_bytes` 输出不同（`kB`/2 位小数 vs `KB`/1 位小数）→ 统一取一版；
- 四份补全抓取脚手架的退出语义不同 → 统一采用 ensure_columns 版，
  顺带修复另外三份「job 0 退出 + 空 stdout → 回调永久悬挂」的潜在缺陷；
- flash 的高亮组并入统一主题后，获得了它原本没有的用户 override 支持。

**约束**：去重不是纯搬移。逐项列出行为增量（输出格式、失败值、新能力），
写进 commit message；用户可见的输出变化（如 `kB`→`KB`）必须显式声明。

## 7. 模块间搬代码：先枚举闭包捕获，再动手

**发生了什么（做对了的样例）**：`sql_runner` 的 `on_response`/`on_error`
两个 ~200 行闭包拆到 `sql_runner/response.lua` 时，先把捕获的上游变量
全部列成显式 `deps` 表（`exec_seq` 这类活状态以 getter 传入），搬移才是
纯文本级、零行为风险的。

**约束**：跨模块搬移前，把闭包捕获的每个上游变量写下来，逐个变成 deps
字段或参数。捕获表本身就是该函数的依赖清单，拆完还可以顺手删掉供体模块
不再需要的 require。

## 8. `package.loaded` 桩的捕获时机

**发生了什么（做对了的样例）**：`sql_sql_runner_spec` 在 require
`poste-db.sql_runner` **之前**桩掉 `poste.state`、`poste.indicators` 等。
给 sql_runner 拆出的新模块如果顶层 require 这些依赖，会拿到同样的桩；
但如果顶层 require 的是**没被桩的模块**（如 `poste-db.context`），会真的加载。
后者当时被刻意保持为惰性 require。

**约束**：给被桩 spec 覆盖的模块加新的顶层 require 前，先看 spec 桩了什么、
桩是 require 前安装的吗？未桩的依赖一律惰性 require 到函数体内。

## 9. UX 可见的框架迁移不在 headless 会话里做

**发生了什么（做对了的样例）**：`forms.lua` 退役并入 `forms_advanced`
会把 operations 的三个对话框换成另一套表单框架——焦点、编辑流、取消语义
都没有测试覆盖，headless 跑不出来的东西就不能算验证过。已deferred 并在
报告中写明迁移路径。

**约束**：改用户可见 UX 的重构需要"真实会话验证"这一步。headless 套件
全绿 ≠ 可以迁。做不了真机验证就 defer 并文档化，不要硬迁。

## 10. 与用户未提交工作共存

**发生了什么**：会话开始时工作区有用户 WIP（sql_runner 指示器逻辑），
会话中途又出现了新的用户编辑（connections.toml、mysql-test.sql）。

**约束**：动手前 `git status`；用户 WIP 单独成 commit（如实描述其内容），
自己的重构分批 commit，绝不混在一个 diff 里。会话中随时可能冒出新的用户
编辑——收尾时如发现不认识的改动，不要动它。

## 11. tree-sitter 误报过滤器：同一构造有多种 recovery 形状

**发生了什么**：给 `ts_stmt.find_error_nodes` 补 mssql/clickhouse 误报过滤时，
`STRING_AGG(x, ', ') WITHIN GROUP (ORDER BY y)` 一个构造在树上留下
**三种** ERROR 形状，取决于上下文：① `GROUP (ORDER BY y) AS z`（head 被
invocation 吞掉，多列 select 时）；② `STRING_AGG(x, ', ') WITHIN`
（invocation + 孤立 WITHIN，末列时）；③ 残片 `o.status`（伪 `GROUP (...)`
invocation 内的限定列，已有 bare-word 过滤只匹配 `^[%w_]+$` 覆盖不到）。
第一版过滤器只覆盖 ①，套件跑出 ②③。另外 `syntax.lua` 的去红高亮是
`find_error_nodes` 的**手写镜像**（`KNOWN_CONSTRUCT_MARKERS` +
`CONSTRUCT_KEYWORDS`），新过滤器不同步它就会出现"诊断没了但还红着"；
本次 OFFSET/FETCH 着色缺失就是因为 `CONSTRUCT_KEYWORDS` 里没有这几个词。

**约束**：加误报过滤器前先用探针脚本（headless nvim 解析目标 SQL、dump 全部
ERROR 节点的 text/parent/祖先链）确认形状，同构造多形状各配一条规则；每个
过滤器配一对测试（误报被吞 + 真实错误 `SELECT * FORM users` 仍要报）。
同步改 `syntax.lua` 的两个表；改动含结构判定的（prev/next sibling）至少在
两个方向各验一次——临时 stash 修复跑新测试，确认真能抓到原 bug。

## 12. 种子脚本的时序 bug 在首次 init 时不可见

**发生了什么**：`playground/init/clickhouse/01-playground.sql` 先 INSERT 进
`events_raw`、后建 `TO events_daily` 型物化视图——TO 型 MV 只聚合**创建之后**
的插入，首次 init 没有任何报错，但 `events_daily` 永远是空的
（`countMerge(cnt)` 查询返回 0 行）。同一文件还有第二个时序坑：顶层 DROP
清单漏了 `events_raw`，首次 init 一切正常，重跑才炸 TABLE_ALREADY_EXISTS。

**约束**：新方言种子落盘后，立即对真实容器 `docker exec -i ... < seed.sql`
**完整重跑一遍**（不只验首次 init），再抽验每张表的行数 > 0；涉及 MV/CTAS/
触发器类"由数据驱动"的对象时，把建对象和灌数据的先后顺序当显式测试点。

## 13. gsub 字面查找必须 pesc；特征测试用全串 equals

**发生了什么**：给拆分出的 `copy_ddl.lua` 补特征测试，一次抓到三个潜伏
bug：① `rename_seq_reference`（copy_ddl.lua:93）把 `nextval('...')` 直接当
`gsub` 的 pattern——括号是魔法字符，**从未匹配过**，复制出的表 DEFAULT 仍指
向旧序列（同服务器靠旧序列存在侥幸可用，计数器却已错乱；跨服务器 DDL 直接
失败）；② `rename_routine_in_def` mysql 分支（copy_ddl.lua:159）`sub(1,
open)` 多含一个反引号又手拼一个，产出 `` ``proc_copy`` ``——MySQL 把双反引
号解析成转义的字面反引号，DDL 无效；③ `prepare_table_ddl` 对 schema 限定
的 nextval 引用再拼一次 schema 前缀，`CREATE SEQUENCE "public"."public".…`
与改写后的 DEFAULT 指向不一致。三者都在生产路径上存活了很久，因为拆分前
没有任何测试，且 ①③ 的损坏形态（"旧值仍在" / "多一层前缀"）不报错。

**约束**：`gsub/gmatch/match` 的 needle 里含 `(` `)` `'` `%` `-` 等字符时
必须 `vim.pesc`（replacement 侧转义 `%%`）；判定"替换/重写生效"要断言旧值
**不再出现**（`select(2, gsub(...))` 计数或全串 equals），不能只 matches 新
值——`matches("``proc_copy`\\(`")` 就放过过 ② 的双反引号。给"纯函数"补测试
时优先全串 equals，子串 matches 只用于宽松冒烟。

---

*Latest: 2026-09-06 db_browser 拆分 + copy_ddl 特征测试（gsub pesc/双反引号/
双 schema 前缀三个潜伏 bug）会话。
新增条目时保持同一格式：发生了什么（带 file:line）→ 约束（可执行的检查动作）。*
