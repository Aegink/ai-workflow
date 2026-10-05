#!/bin/sh
# PreToolUse 钩子 —— 工作流 Gate 的硬闸。
#
# 在写文件类工具（Write / Edit / MultiEdit / NotebookEdit）以及可能写文件的 Bash 命令
# 真正执行之前拦截，按 .aiworkflow/state.md 里机器可读的开关决定放行还是拒绝。
#
# 规则（按顺序判定）：
#   1. 目标在 .aiworkflow/ 内            → 放行（状态文件本身永远可写）
#   2. 非写入类工具                      → 放行
#   3. 没有 .aiworkflow/state.md         → 拒绝（启动协议未执行）
#   4. state.md 里「实现许可: no」        → 拒绝（Gate 未通过，只允许讨论）
#   5. 其余                              → 放行
#
# 拒绝 = 模型无法用"我觉得可以了"绕过。这是本套件里唯一真正的强制。

set -u

INPUT=$(cat 2>/dev/null || printf '')

# ---------- 定位项目根 ----------
PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ]; then
  PROJ=$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi
[ -n "$PROJ" ] && [ -d "$PROJ" ] || PROJ="$PWD"
cd "$PROJ" 2>/dev/null || true

STATE=".aiworkflow/state.md"

# ---------- 工具与目标 ----------
TOOL=$(printf '%s' "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

FILE_PATH="-"
case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    FILE_PATH=$(printf '%s' "$INPUT" \
      | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
      | sed 's/^[^:]*:[[:space:]]*"//; s/"$//')
    ;;
  Bash)
    # 只在"闸门关闭"时收紧；正常阶段不干扰 Bash
    CMD=$(printf '%s' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1)
    ;;
  *)
    exit 0 ;;
esac
[ -n "${FILE_PATH:-}" ] || FILE_PATH="-"

# ---------- 拒绝 / 放行 ----------
json_escape() {
  printf '%s' "$1" | awk 'BEGIN{ORS=""}
  {
    out=""
    n=length($0)
    for(i=1;i<=n;i++){
      c=substr($0,i,1)
      if(c=="\\")      out=out "\\\\"
      else if(c=="\"") out=out "\\\""
      else if(c=="\t") out=out "\\t"
      else if(c=="\r") out=out ""
      else             out=out c
    }
    printf "%s\\n", out
  }'
}

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "$1")"
  exit 0
}

# 1) .aiworkflow/ 内一律放行
case "$FILE_PATH" in
  *".aiworkflow/"*|".aiworkflow/"*) exit 0 ;;
esac

# 3) 必须先有状态文件（Bash 写命令同样受此约束）
if [ ! -f "$STATE" ]; then
  deny "工作流 Gate：项目里没有 .aiworkflow/state.md，启动协议未执行。请先创建 state.md（模板见 AGENTS.md 第 4 节），再写代码。"
fi

# 4) 实现许可开关（缺省视为 yes，避免对老项目误伤；只有显式 no 才收紧）
PERM=$(sed -n 's/^[-*[:space:]]*实现许可[[:space:]]*[:：][[:space:]]*\([^[:space:]]*\).*/\1/p' "$STATE" 2>/dev/null | head -1)
[ -z "$PERM" ] && exit 0
case "$PERM" in
  yes|YES|Yes|是|allow|on|1) exit 0 ;;
esac

PHASE=$(sed -n 's/^[-*[:space:]]*当前阶段[[:space:]]*[:：][[:space:]]*\(.*\)$/\1/p' "$STATE" 2>/dev/null | head -1)
[ -n "$PHASE" ] || PHASE="未知"

if [ "$TOOL" = "Bash" ]; then
  case "${CMD:-}" in
    *">"*|*"tee "*|*"sed -i"*|*"cp "*|*"mv "*|*"rm "*)
      deny "工作流 Gate：当前阶段为「${PHASE}」，实现许可为 no，禁止通过 Bash 写文件。请先在 state.md 中把「实现许可」改为 yes（意味着 Design/Plan 的 Gate 已通过），或把讨论结果落盘到 .aiworkflow/ 下。" ;;
  esac
  exit 0
fi

deny "工作流 Gate：当前阶段为「${PHASE}」，实现许可为 no，禁止修改源码文件（${FILE_PATH}）。请先完成 ${PHASE} 阶段的门禁并把 state.md 的「实现许可」改为 yes；仅允许写 .aiworkflow/ 内的文件。"
exit 0
