# poste-ai.nvim：poste 家族 AI 助手插件规划

## 一、总体评估（你觉得如何）

**可行，且与现有架构契合度出乎意料地高。** 你描述的三个场景都能落到现成模块上：

| 场景 | 现成对接点 |
|---|---|
| `@my-blog/blog` 查询并出结果 | `connections.lua`（连接枚举/URL 解析）+ `executor.execute` → `buffer.render_dataset`（结果进 dataset） |
| `@test.sql(2-5)` 判断 SQL 对错 | 通用文件引用引擎 + 语句文本直接注入 prompt；AI 回复后可调用 `run_sql` 类接口验证 |
| "怎么导出" 这类功能问答 | system prompt 注入 poste-db 功能知识（命令/快捷键/导出流程），V1 即可覆盖 |

已有可复用地基：`context_client.lua`（长驻 JSON-line 子进程客户端，流式客户端的最佳模板）、`poste.dialog`/`poste.layout`/`poste.select` UI 积木、blink 补全 adapter 模式（照搬给 @引用补全）、`completion/data.lua` 的 schema 缓存、keymap/config/测试/CI 全套惯例。

**核心建议**：
1. **三层架构**：通用层（新仓库 `poste-ai.nvim`：聊天窗口、markdown 渲染、流式客户端、@引用引擎、context 注册 API）→ context 接入层（`poste-db.nvim` 加 `lua/poste-db/ai/`；以后 `poste-http.nvim` 照做）→ 家族共享 infra 不动。
2. **分阶段**：V1 用"上下文注入 + 回复代码块动作键"覆盖全部三个场景，V2 再上真正的工具调用 agent 循环。这样每阶段都可发布可用版本。
3. **安全第一**：AI 产生的 SQL 执行默认只读放行、DML/DDL 走确认（复用现有 drop-confirm 模式）；连接凭据永不进入 prompt（只传名字/方言/schema），API key 只走 env var，日志复用 `log.lua` 的 redaction。

## 二、主要难点（提前认知）

1. **SSE 流式解析**：curl `-N` 子进程 + jobstart（`stdout_buffered=false`）逐行回调，要自己处理半行缓冲、chunk 边界、取消（`jobstop`）。无现成库，需 fixture 驱动的测试。
2. **markdown 增量渲染**：流式输出时不能整屏重画（闪烁）。方案：extmarks 增量渲染 + 节流 flush（~50ms 合并），treesitter markdown parser 做基础高亮，代码块/标题/列表做 extmark 装饰；表格 V1 先纯文本渲染；提供"渲染态 ⇄ 源码态"切换键方便复制。
3. **滚动跟随**：流式时自动滚到底，但用户向上翻阅后要停止跟随（光标位置检测），这是聊天 UI 的经典细节。
4. **@引用解析歧义**：`@my-blog/blog` 与文件路径、含特殊字符的连接名冲突；规则定为：context 注册的 mention 模式优先，兜底按文件路径解析；补全列表里标注类型。
5. **异步编排防卡死**：回调风格 + `vim.schedule` 重入 + pcall 包裹 + epoch/seq 防 stale（全家族既有模式）；流式中断/退出时必须清理 `_busy`（LEARNINGS 里的教训）。
6. **上下文体积**：schema 全量注入会爆 token。V1 策略：只注入被提及库的表名+列名+注释摘要（复用 `completion/data.lua` 缓存），设字符预算截断；列级细节留给对话追问（V2 变成工具）。

## 三、新仓库结构 `../poste-ai.nvim`

```
lua/poste-ai/
  init.lua            -- setup(opts), M.register_context(name, spec)  ← 核心 API
  config.lua          -- providers/model/ui/keymaps；get_keymap 惯例
  state.lua           -- 会话状态、active context、streaming/busy 状态
  commands.lua        -- :PosteAIChat :PosteAIModel :PosteAISessions :PosteAICancel
  health.lua
  provider/
    registry.lua      -- provider adapter 注册与归一化（消息/工具/结束原因统一形状）
    openai.lua        -- OpenAI 兼容 chat completions（V1 唯一 adapter；DeepSeek/Qwen/Ollama/vLLM 通吃）
    sse.lua           -- curl -N SSE 逐行解析器（独立纯函数，重点测试对象）
  chat/
    window.lua        -- 侧栏 split（仿 db_browser，默认右侧 50 列）：上方会话 buffer `poste://chat`，下方输入 buffer `poste://chat_input`
    render.lua        -- markdown 增量渲染（treesitter markdown + extmarks）
    stream.lua        -- 流式 append、tail-follow、取消
    session.lua       -- 多会话管理，持久化 stdpath("data")/poste-ai/sessions/
    mention.lua       -- @引用引擎：解析 + 补全；通用文件引用 @path(l1-l2) 内置
    actions.lua       -- 回复代码块动作键（复制 / 追加到 buffer / 交给 context 执行）
  context_api.lua     -- context 契约：mention 匹配/补全、system prompt 片段、代码块处理器、命令
plugin/poste-ai.lua  -- 入口
tests/run.sh          -- plenary，模式照抄 poste-db（sibling rtp、minimal_init）
```

context 契约（`register_context` 的 spec）：
- `mention = { match(str) → ref|nil, complete(prefix) → candidates }`
- `system_prompt(refs) → string`（拿到底 mention 解析结果后注入知识）
- `codeblock = { lang 匹配, execute(text, ref), confirm_policy }`
- 可选 `commands`（context 专属命令）

## 四、Phase 1：通用层 MVP（poste-ai.nvim）

1. 脚手架：仓库结构、`stylua.toml`/`.editorconfig`/luacheck 照抄、`git init`（首次提交由你决定）、CI workflow 照抄 poste-db。
2. config/state：`providers = { default = { base_url, api_key_env = "OPENAI_API_KEY", model } }`；API key 只从 env 读；可选项目级 `ai.toml`（走 `poste.util.find_file_upwards` + `{{var}}` 替换惯例）。
3. `provider/sse.lua` + `provider/openai.lua`：`curl -N -sS` + jobstart 无缓冲；半行缓冲；`vim.json.decode` pcall；stream delta 累积；`jobstop` 取消；错误（401/429/5xx body）解析成可读消息。
4. `chat/window.lua`：会话 buffer（`poste://chat`）+ 输入 buffer（`poste://chat_input`）双 buffer 布局；winbar 显示 provider/model/会话名；keymap 走 `get_keymap("chat_window"/"chat_input")`。
5. `chat/render.lua` + `markdown`：V1 支持 标题/列表/行内代码/围栏代码块（带语言高亮）/分隔线/引用；表格降级为等宽文本；渲染/源码切换键。
6. `chat/stream.lua`：增量 append + tail-follow + `Esc` 取消 + busy 状态与指示（复用 spinner 帧）。
7. `chat/session.lua`：会话列表/切换/删除/重命名，落盘 JSON。
8. `chat/mention.lua`：V1 内置通用文件引用 `@相对路径(2-5)`（visual select 时自动生成），输入 buffer 内 `vim.fn.complete` 补全。
9. `health.lua`：nvim ≥ 0.10、curl 可用、treesitter markdown parser、provider 配置存在（不回显 key）。
10. 测试：sse 解析（半行/多 chunk/断流 fixture）、markdown 渲染快照、session 持久化、mention 解析、openai adapter（mock chunk 序列）、window 冒烟。

## 五、Phase 2：poste-db context 接入

新增 `lua/poste-db/ai/`（命名遵守家族规范：`poste_db_ai*` 命名空间、`PosteDb*` 命令、高亮 `PosteDbAi*`）：

1. `init.lua`：`setup()` 末尾 `pcall(require, "poste-ai")` 成功则 `register_context("db", spec)`——poste-ai 不在时静默跳过，保持零强依赖。
2. `mentions.lua`：`@连接名/库名[/schema.表名]` 的 match + 补全（数据源 `connections.list_connections` + `completion/data.lua` 的表/列缓存）。
3. `system_prompt.lua`：三段组成——(a) poste-db 功能知识（所有命令/快捷键/导出流程/浏览器操作，精炼自文档，单一来源文件维护）；(b) 当前 mention 的连接摘要（名字/方言/host，**无凭据**）；(c) 被提及库的 schema 概要（表/列/注释，字符预算截断）。
4. `actions.lua`（代码块动作）：对回复中的 ```sql 块提供 `<CR>`=执行（SELECT 直接过；DML/DDL 弹确认，复用现有 confirm 模式）→ `executor.execute` → `buffer.render_dataset` 进 dataset；`gy`=复制；`ga`=追加到当前 sql buffer。
5. 快捷入口：poste_sql buffer visual 模式 `<leader>aa`「问 AI 这段 SQL」→ 打开聊天并预填 `@文件名(l1-l2) `；命令 `:PosteDbChat`。
6. 文档同步：`docs/dev/sql/README.md` 命名表与文档链接表加条目；`.opencode/skills/sql/SKILL.md` 文件索引加 `ai/` 段；AGENTS.md 补一句 poste-ai 可选依赖。

## 六、Phase 3：V2 预告（本次不实现）

- 工具调用 agent 循环 `tools/loop.lua`：SSE 里 tool_call 参数分片累积、max_iters 防失控、每步状态显示在聊天流、可取消。
- 内置工具桥：`list_connections` / `introspect_schema` / `run_readonly_sql` / `execute_sql(需确认)` / `open_db_browser` / `feature_help`；权限策略可配（读自动、写确认）。
- Anthropic adapter；poste-http context（@请求文件、run request 工具）。

## 七、测试与验证

- poste-ai.nvim：上述 Phase 1 第 10 点全部落在 `tests/`，`tests/run.sh` 输出格式与 poste-db 一致；headless 跑测试注意设 `XDG_CACHE_HOME`/`XDG_STATE_HOME`（poste-http 的教训）。
- poste-db.nvim：`tests/sql/ai_mentions_spec.lua`、`ai_system_prompt_spec.lua`、`ai_actions_spec.lua`（stub executor/render 验证调用与确认逻辑）、`ai_register_spec.lua`（poste-ai 缺失时不报错）。
- 手工验收脚本：三个场景各一条冒烟路径（配 mock/真实 provider 各一遍）。

## 八、风险与缓解

| 风险 | 缓解 |
|---|---|
| SSE 半行/粘包解析 bug | 解析器做成纯函数 + chunk 序列 fixture 全覆盖 |
| 流式渲染闪烁/卡顿 | extmarks 增量 + 50ms 节流 flush；大段落合并后重绘 |
| schema 注入过大 | 只注入提及库摘要 + 字符预算；细节留给追问/V2 工具 |
| key 泄露 | 仅 env var；prompt 不含凭据；日志复用 redaction |
| agent 循环卡死（V2） | max_iters + 超时 + busy 强制清理路径 + 可取消 |

实施顺序即 Phase 1 → Phase 2，每阶段结束跑全量测试并更新文档索引。