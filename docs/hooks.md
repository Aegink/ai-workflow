# 钩子：把 Gate 变成真闸门

`AGENTS.md` 是一份**约定**——模型读了、也说要遵守，但你无法保证它真遵守。
钩子是**机制**——在工具调用真正执行之前拦截，模型无法用推理绕过。

这是本套件里唯一 ★★★★ 级的强制手段。

---

## 一、装了哪三个钩子

| 钩子事件 | 脚本 | 触发时机 | 干什么 |
|---|---|---|---|
| `SessionStart` | `session-start.sh` | 新会话 / resume / clear / compact | 把 **契约 + 项目状态 + 上次交接** 拼成 JSON 注入上下文，并附上"现在执行启动协议"的指令 |
| `PreToolUse` | `pre-tool-use.sh` | 写文件类工具执行前 | 检查 `.aiworkflow/state.md`，按「实现许可」开关决定放行还是**拒绝** |
| `Stop` | `stop.sh` | 模型准备结束回合时 | 检查本次会话是否更新过 `state.md`，按「结束协议」开关提示或阻塞 |

安装位置：

```
<项目>/.aiworkflow/hooks/session-start.sh
<项目>/.aiworkflow/hooks/pre-tool-use.sh
<项目>/.aiworkflow/hooks/stop.sh
<项目>/.claude/settings.json          ← 挂载点
```

---

## 二、为什么这样设计

### SessionStart：把"要求去读"变成"已经被塞进来"

放一个 `AGENTS.md` 在仓库里，模型**可能**会读，也可能跳过。
`SessionStart` 钩子的输出会直接进入模型上下文——**它不需要决定去读，因为内容已经在里面了**。

注入的内容依次是：

1. `AGENTS.md` 全文
2. `.aiworkflow/state.md` 全文（没有则明确告知"缺失，先创建"）
3. `.aiworkflow/handoff.md`（若存在）
4. 一段"启动协议（现在执行）"的指令

### PreToolUse：Gate 的物理形态

判定顺序（先命中先返回）：

| # | 条件 | 结果 |
|---|---|---|
| 1 | 目标路径含 `.aiworkflow/` | ✅ 放行（状态文件本身永远可写） |
| 2 | 工具不是写入类（非 Write/Edit/MultiEdit/NotebookEdit/Bash） | ✅ 放行 |
| 3 | 项目里没有 `.aiworkflow/state.md` | ❌ **拒绝**：启动协议未执行 |
| 4 | `state.md` 里「实现许可」不是 `yes` | ❌ **拒绝**：Gate 未通过 |
| 5 | 其余 | ✅ 放行 |

拒绝时返回：

```json
{"hookSpecificOutput":{
  "hookEventName":"PreToolUse",
  "permissionDecision":"deny",
  "permissionDecisionReason":"工作流 Gate：当前阶段为「Design」，实现许可为 no，禁止修改源码文件（…）。请先完成 Design 阶段的门禁并把 state.md 的「实现许可」改为 yes；仅允许写 .aiworkflow/ 内的文件。"
}}
```

这段理由会回到模型面前。它想继续，唯一出路是**真的去过 Gate**，或者向用户说明为什么应该把开关改为 `yes`——两种都是我们想要的行为。

### `Bash` 也管

只禁 `Write`/`Edit` 是纸糊的——用 `bash` 加个 `>` 重定向就绕过去了。
所以在「实现许可为 no」时，`pre-tool-use.sh` 也会检查 Bash 命令里是否出现

```
>  >>  tee  sed -i  cp  mv  rm
```

命中即拒绝。**开关打开（`yes`）时不对 Bash 做任何限制**，不影响正常开发。

### Stop：结束协议不是口号

Workflow 里最容易被跳过的一步是"收尾更新状态"。`stop.sh` 拿会话开始时留下的时间戳标记和 `state.md` 的修改时间比较：

- 更新过 → 放行
- 没更新 → 按 `state.md` 的「结束协议」设置处理

| 值 | 行为 |
|---|---|
| `off` | 不检查 |
| `remind`（默认） | 显示一条 systemMessage 提醒，**不阻塞**；每个会话最多一次 |
| `enforce` | **阻塞结束**，模型必须先更新 `state.md` 才能收尾 |

防死循环：因 Stop 钩子被要求继续后，再次触发时会带 `stop_hook_active: true`，脚本见到即放行。

---

## 三、配置

`install.sh` 会写 `<项目>/.claude/settings.json`：

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear|compact",
        "hooks": [{ "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.aiworkflow/hooks/session-start.sh" }] }
    ],
    "PreToolUse": [
      { "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash",
        "hooks": [{ "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.aiworkflow/hooks/pre-tool-use.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.aiworkflow/hooks/stop.sh" }] }
    ]
  }
}
```

如果项目里已有 `.claude/settings.json`，`install.sh` **不会覆盖**，只提示你把上面 `hooks` 段合并进去。

---

## 四、日常怎么用

**开始一个 L2/L3 任务时**，在 `state.md` 里：

```markdown
- 当前阶段：Design
- 实现许可：no
```

模型立刻失去写源码的能力，只能讨论、只能写 `.aiworkflow/` 下的文件。

**Gate 通过、准备实现时**：

```markdown
- 当前阶段：Execute
- 实现许可：yes
```

**想强制每次会话都收尾**：`- 结束协议：enforce`

---

## 五、边界与已知限制

- **只有支持 hooks 的 Agent 才有这一层。** Cursor / Copilot / Gemini CLI 目前没有等价的可靠拦截，它们只到 ★★★（自动加载规则）。
- **脚本用 POSIX sh + grep/sed/awk**，不依赖 `jq`，macOS 与 Linux 都能跑。
- **JSON 解析是轻量级的**（正则取字段），不是完整 JSON parser。字段顺序或转义异常时可能取不到值——取不到时脚本**一律放行**（fail-open），不会误伤。
- **Bash 检测是启发式的**：只认最常见的几种写法。它拦的是"顺手绕过"，不是恶意规避。
- **不要用钩子代替人。** 它保证流程被走，不保证结论是对的。

---

## 六、自己写钩子的通用套路

1. 从 stdin 读 JSON，取 `tool_name` / `tool_input` / `cwd` / `hook_event_name`。
2. 用 `$CLAUDE_PROJECT_DIR`（没有就用 `cwd`）定位项目根，`cd` 过去。
3. 判定。
4. 输出：
   - 放行 → `exit 0`
   - 拒绝（结构化）→ 输出 `hookSpecificOutput.permissionDecision = "deny"` 的 JSON，`exit 0`
   - 拒绝（简单）→ `exit 2`，理由写 stderr
5. 脚本务必 `chmod +x`。
