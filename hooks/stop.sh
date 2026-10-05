#!/bin/sh
# Stop 钩子 —— 会话结束前检查「结束协议」是否执行（state.md 有没有被更新）。
#
# 三种模式（写在 .aiworkflow/state.md 里，机器可读）：
#   - 结束协议: off      → 不检查
#   - 结束协议: remind   → 本次会话没更新 state.md 就提示一次（默认，不阻塞）
#   - 结束协议: enforce  → 阻塞结束，强制模型先更新 state.md 再收尾
#
# 防死循环：Claude Code 因 Stop 钩子继续后会再传 stop_hook_active=true，此时直接放行。

set -u

INPUT=$(cat 2>/dev/null || printf '')

case "$INPUT" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ]; then
  PROJ=$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi
[ -n "$PROJ" ] && [ -d "$PROJ" ] || PROJ="$PWD"
cd "$PROJ" 2>/dev/null || true

STATE=".aiworkflow/state.md"
[ -f "$STATE" ] || exit 0

MODE=$(sed -n 's/^[-*[:space:]]*结束协议[[:space:]]*[:：][[:space:]]*\([^[:space:]]*\).*/\1/p' "$STATE" 2>/dev/null | head -1)
[ -n "$MODE" ] || MODE="remind"
[ "$MODE" = "off" ] && exit 0

MARK="${TMPDIR:-/tmp}/aiwf-$(printf '%s' "$PROJ" | cksum | awk '{print $1}').mark"
[ -f "$MARK" ] || exit 0
[ -f "${MARK}.done" ] && exit 0

# state.md 比本次会话标记新 → 已经更新过，放行
if [ "$STATE" -nt "$MARK" ]; then exit 0; fi

if [ "$MODE" = "enforce" ]; then
  cat >&2 <<'EOF'
工作流 Gate：本次会话还没有更新 .aiworkflow/state.md。
按结束协议，请先更新 state.md（进度 / 下一步 / 未决问题 / 最后更新），
若有新决策追加到 decisions.md，若工作未完成再更新 handoff.md，然后再结束。
EOF
  exit 2
fi

: > "${MARK}.done" 2>/dev/null || true
printf '{"systemMessage":"[工作流提醒] 本次会话还没更新 .aiworkflow/state.md。按结束协议，请补上进度、下一步与最后更新时间——下一个新会话靠它接手。"}\n'
exit 0
