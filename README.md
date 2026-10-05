# AI Workflow — 通用六阶段 AI 工作流契约

**让任何 AI（编码 Agent / 聊天模型）在你切换项目、开启新会话时，自动按同一套工程纪律工作。**

解决两个具体问题：

- **新对话记不住** → 不靠记忆，靠 `.aiworkflow/state.md` 落盘。新会话读文件接上。
- **长记忆变混乱** → 铁律「口头确认不算，落盘才算；同一事实只存一处」。

```
Brainstorm → Design → Plan → Execute → Verify → Ship
   需求澄清    方案设计    任务规划    实现执行    验证审查    交付沉淀
```

---

## 快速开始

```sh
git clone https://github.com/Aegink/ai-workflow.git
cd ai-workflow
sh install.sh /path/to/your-project
```

部署后你的项目里会多出这些：

```
your-project/
├── AGENTS.md                           ← 契约真身（唯一事实源，改规则只改它）
├── CLAUDE.md              -> AGENTS.md ← 软链
├── GEMINI.md              -> AGENTS.md
├── .github/copilot-instructions.md  -> AGENTS.md
├── .windsurf/rules/ai-workflow.md   -> AGENTS.md
├── .cursor/AGENTS.md                -> AGENTS.md
├── .cursor/rules/ai-workflow.mdc       ← alwaysApply: true（Cursor 用）
├── .claude/settings.json               ← Claude Code 钩子（硬门禁）
└── .aiworkflow/
    ├── state.md          ← 项目唯一事实源：目标 / 阶段 / 进度 / 下一步
    ├── spec.md           ← 需求规则 + 方案设计
    ├── tasks.md          ← 垂直切片 + 验收标准
    ├── decisions.md      ← 决策记录（含"为什么"）
    ├── handoff.md        ← 交接（引用而非复制）
    └── hooks/            ← 三个钩子脚本
```

参数：`--force` 覆盖已有 AGENTS.md · `--no-hooks` 不装钩子 · `--skill` 装到 Minis 技能目录。

---

## 「强制」的真相（重要）

**没有任何文件能强制一个纯聊天模型。** 真正起作用的是：**这个工具会不会把文件自动塞进每次请求的上下文**。

| 层级 | 手段 | 强制力 | 覆盖工具 |
|---|------|--------|---------|
| ★★★★ | 工具钩子（本仓库提供 `SessionStart` / `PreToolUse` / `Stop`） | **硬门禁，能真正拦住工具调用** | Claude Code 等支持 hooks 的 Agent |
| ★★★ | `.cursor/rules/*.mdc` + `alwaysApply: true` | 每次请求都注入 | Cursor |
| ★★★ | `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` | 会话启动自动加载 | Codex、Claude Code、Copilot、Gemini CLI、Windsurf… |
| ★★☆ | 自定义指令 / Project Instructions | 常驻但长对话会漂移 | ChatGPT / Claude 网页版 |
| ★☆☆ | 每次对话里贴一遍 | 会忘 | 任意 |

所以本仓库同时提供三档：

1. **有钩子的 Agent** → 用 `.claude/settings.json`（★★★★，真拦截）
2. **会自动加载规则的 Agent** → 用 `AGENTS.md` / `.cursor/rules`（★★★，自动注入）
3. **纯聊天 AI** → 把 [`chat-instructions.md`](chat-instructions.md) 粘进「自定义指令」（★★☆，一次粘贴长期生效）

---

## 契约要点

### 1. 启动协议 —— 每次新会话第一件事

读 `AGENTS.md` → 读 `.aiworkflow/state.md` → 5 行汇报（目标/阶段/进度/风险/下一步）→ **停下等确认**。
**NEVER** 没读 state.md 就写代码；**NEVER** 凭"我记得上回"开工。

### 2. 任务分级 —— 小任务不用走满六段

| 级别 | 判据 | 走哪几段 |
|---|---|---|
| **L0** | 单文件、低风险、一次性 | 直接做 |
| **L1** | 单模块小改 | 轻澄清 → 执行 → 验证 |
| **L2** | 多文件 / 改接口数据 | 澄清 → 设计 → 拆分 → 执行 → 验证 |
| **L3** | 跨仓库 / 权限·资金·隐私 / 长周期 | **六段全走** |

拿不准就上一级；升档由 AI 主动提出，**不许自行降档**。

### 3. 六阶段的硬门禁（Gate）

| 阶段 | 核心问题 | Gate（MUST NOT 越过） |
|---|---|---|
| Brainstorm | 我们理解的是同一个问题吗？ | 关键取舍未确认 → **禁止实现** |
| Design | 需求怎样进入现有系统？ | Spec 未成型 → **禁止拆任务** |
| Plan | 怎样拆成可独立验证的工作？ | 拆分未经确认 → **禁止开工** |
| Execute | 怎样在短反馈里安全实现？ | 无"失败→通过"证据 → **禁止推进** |
| Verify | 有什么证据证明做对了？ | 有 Blocker → **禁止发布** |
| Ship | 系统和下一位接手者准备好了吗？ | 交接缺失 → **不算完成** |

### 4. 行为红线（摘要）

不确认不动手 · 一次一问 · **事实自查、决策交人** · 不确定就停下问，不许猜着补全 ·
不擅自扩大范围 · 不自我批准 · 短反馈优先 · 证据冲突就回退 · 落盘优先于记忆 · 只引用不复制。

完整版见 [`AGENTS.md`](AGENTS.md)。

---

## 钩子：把 Gate 变成真闸门

三个钩子（详见 [`docs/hooks.md`](docs/hooks.md)）：

| 钩子 | 作用 |
|---|---|
| `session-start.sh` | 每次会话开始，把 **契约 + 项目状态 + 交接** 强制注入上下文 |
| `pre-tool-use.sh` | 写文件前检查 `.aiworkflow/state.md`：没有状态文件、或「实现许可: no」时**直接拒绝**写入 |
| `stop.sh` | 会话结束前检查 state.md 有没有更新（`off` / `remind` / `enforce` 三档） |

关键开关（机器可读，写在 `state.md`）：

```markdown
- 实现许可：no            # no = 钩子拦截一切非 .aiworkflow/ 的写入
- 结束协议：enforce        # 未更新 state.md 就不许结束
```

于是 **Brainstorm / Design / Plan 阶段想偷偷开写，模型也过不去** —— 它不能用"我觉得讨论够了"绕过。

---

## 测试

```sh
sh tests/hooks.test.sh
```

覆盖钩子的全部判定分支（Gate 拦截 / 上下文注入 / 结束协议 / 防死循环 / fail-open），
共 21 项断言，只用 POSIX sh + python3 校验 JSON，无其他依赖。

---

## 设计来源

六阶段框架与「Artifact / Gate / Skill」三件约束的组织方式，参考了 czm 的长文
《[从 AI 写代码到 AI 工作流 · 一次需求的两条命，和救回它的六个阶段](https://czm15053.github.io/ai-workflow-six-stages/)》，
以及文中提到的 Matt Pocock stage skills、OpenSpec、Superpowers、Trellis、GSD、BMAD、OMC 等开源实践。

本仓库是**工具实现**：把那些纪律落成可部署、可强制的文件与钩子；不是那篇文章的转载。
设计取舍见 [`docs/design-notes.md`](docs/design-notes.md)。

核心命题一句话：**Agent = Model + Harness**。模型提供智能，能不能可靠用起来，取决于模型之外那层工程环境。

---

## 卸载

```sh
sh uninstall.sh /path/to/your-project          # 只删软链和生成物
sh uninstall.sh /path/to/your-project --all    # 连钩子和 AGENTS.md 一起删
```

`.aiworkflow/` 里的 `state/spec/tasks/decisions/handoff` **永远不会被删** —— 那是你的项目资料。

---

## License

MIT
