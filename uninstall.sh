#!/bin/sh
# 从项目目录移除由 install.sh 部署的文件。
# 用法：sh uninstall.sh [项目目录] [--all]
#
#   默认：只删软链和生成的规则文件，保留 AGENTS.md 与 .aiworkflow/（你的真实资料）
#   --all：连 AGENTS.md、.claude/settings.json、.aiworkflow/hooks/ 一起删
#
# .aiworkflow/ 里的 state/spec/tasks/decisions/handoff 永远不动——那是项目资料。

set -e
TARGET="."
ALL=0
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    -*) echo "未知参数: $a" >&2; exit 1 ;;
    *) TARGET="$a" ;;
  esac
done
TARGET="$(cd "$TARGET" && pwd)"
echo "▶ 从 $TARGET 移除工作流文件"

rem() { [ -e "$TARGET/$1" ] && rm -f "$TARGET/$1" && echo "  ✗ $1"; return 0; }

rem "CLAUDE.md"
rem "GEMINI.md"
rem ".github/copilot-instructions.md"
rem ".windsurf/rules/ai-workflow.md"
rem ".cursor/AGENTS.md"
rem ".cursor/rules/ai-workflow.mdc"

if [ "$ALL" -eq 1 ]; then
  rm -rf "$TARGET/.aiworkflow/hooks"
  echo "  ✗ .aiworkflow/hooks/"
  rem ".claude/settings.json"
  rem "AGENTS.md"
fi

echo "✅ 完成（.aiworkflow/ 下的 state/spec/tasks/decisions/handoff 已保留）"
