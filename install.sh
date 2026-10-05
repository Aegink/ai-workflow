#!/bin/sh
# 把通用 AI 工作流契约部署进任意项目目录。
#
# 用法：
#   sh install.sh [项目目录] [--force] [--no-hooks] [--skill]
#   （不带参数 = 在当前目录部署）
#
#   --force      覆盖已存在的 AGENTS.md（默认不覆盖，避免弄丢你改过的规则）
#   --no-hooks   不安装 Claude Code 钩子（默认安装）
#   --skill      额外安装到 Minis 技能目录 /var/minis/skills/ai-workflow/

set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="."
FORCE=0
HOOKS=1
SKILL=0

for a in "$@"; do
  case "$a" in
    --force)    FORCE=1 ;;
    --no-hooks) HOOKS=0 ;;
    --skill)    SKILL=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    -*) echo "未知参数: $a" >&2; exit 1 ;;
    *)  TARGET="$a" ;;
  esac
done

TARGET="$(cd "$TARGET" 2>/dev/null && pwd || { mkdir -p "$TARGET" && cd "$TARGET" && pwd; })"
echo "▶ 部署到: $TARGET"

# ---------- 1) 主契约 ----------
if [ -f "$TARGET/AGENTS.md" ] && [ "$FORCE" -ne 1 ]; then
  echo "  · AGENTS.md 已存在，跳过（加 --force 可覆盖）"
else
  cp "$SRC/AGENTS.md" "$TARGET/AGENTS.md"
  echo "  ✓ AGENTS.md"
fi

# ---------- 2) 各工具约定路径 → 软链到 AGENTS.md（单一事实源）----------
link_to_agents() {
  _l="$1"; _depth="$2"
  mkdir -p "$(dirname "$TARGET/$_l")"
  _up=""; _i=0
  while [ "$_i" -lt "$_depth" ]; do _up="../$_up"; _i=$((_i+1)); done
  ln -sf "${_up}AGENTS.md" "$TARGET/$_l"
  echo "  ✓ $_l -> AGENTS.md"
}
link_to_agents "CLAUDE.md" 0
link_to_agents "GEMINI.md" 0
link_to_agents ".github/copilot-instructions.md" 1
link_to_agents ".windsurf/rules/ai-workflow.md" 2
link_to_agents ".cursor/AGENTS.md" 1

# Cursor 规则需要自带 frontmatter，无法软链，用生成
mkdir -p "$TARGET/.cursor/rules"
{
  printf -- '---\n'
  printf 'description: 通用 AI 工作流契约（六阶段 + Gate + 落盘）——任何任务开始前必须遵守\n'
  printf 'alwaysApply: true\n'
  printf -- '---\n\n'
  cat "$SRC/AGENTS.md"
} > "$TARGET/.cursor/rules/ai-workflow.mdc"
echo "  ✓ .cursor/rules/ai-workflow.mdc (alwaysApply)"

# ---------- 3) 状态目录 ----------
mkdir -p "$TARGET/.aiworkflow"
for f in state.md spec.md tasks.md decisions.md handoff.md; do
  if [ ! -f "$TARGET/.aiworkflow/$f" ]; then
    cp "$SRC/scaffold/$f" "$TARGET/.aiworkflow/$f"
    echo "  ✓ .aiworkflow/$f"
  else
    echo "  · .aiworkflow/$f 已存在，保留"
  fi
done

# ---------- 4) 钩子（真正的硬门禁）----------
if [ "$HOOKS" -eq 1 ]; then
  mkdir -p "$TARGET/.aiworkflow/hooks"
  for h in session-start.sh pre-tool-use.sh stop.sh; do
    cp "$SRC/hooks/$h" "$TARGET/.aiworkflow/hooks/$h"
    chmod +x "$TARGET/.aiworkflow/hooks/$h"
  done
  echo "  ✓ .aiworkflow/hooks/{session-start,pre-tool-use,stop}.sh"

  mkdir -p "$TARGET/.claude"
  if [ -f "$TARGET/.claude/settings.json" ]; then
    echo "  ! .claude/settings.json 已存在，未覆盖。请手工把 $SRC/hooks/settings.template.json 里的 hooks 段合并进去。"
  else
    cp "$SRC/hooks/settings.template.json" "$TARGET/.claude/settings.json"
    echo "  ✓ .claude/settings.json（Claude Code 钩子已启用）"
  fi
  echo "    └ 其余工具（Cursor / Copilot / Gemini CLI 等）无钩子能力，靠自动加载规则生效。"
fi

# ---------- 5) 可选：装成 Minis 技能 ----------
if [ "$SKILL" -eq 1 ]; then
  D=/var/minis/skills/ai-workflow
  mkdir -p "$D"
  cat > "$D/SKILL.md" <<EOF
---
name: ai-workflow
description: 通用六阶段 AI 工作流（Brainstorm/Design/Plan/Execute/Verify/Ship + Gate + 落盘）。凡开始一个新项目、接手一个仓库、切换不同项目、或希望 AI 按固定工程纪律而非随意生成代码时使用。暗语：参考工作流skill、按六阶段来。
---

# 通用 AI 工作流

完整契约（每次使用前先完整阅读）：
\`$SRC/AGENTS.md\`

脚手架模板：\`$SRC/scaffold/\`
部署到新项目：\`sh $SRC/install.sh <项目目录>\`
钩子说明：\`$SRC/docs/hooks.md\`

核心：拿到任务先定级 L0–L3；每阶段有硬门禁（Gate）；结论必须落盘到项目里的 \`.aiworkflow/\`，不依赖记忆。

方法来源：czm《从 AI 写代码到 AI 工作流 · 一次需求的两条命，和救回它的六个阶段》
https://czm15053.github.io/ai-workflow-six-stages/
EOF
  echo "  ✓ Minis 技能: $D/SKILL.md"
fi

echo
echo "✅ 完成。新会话开始时 AI 会自动读到 AGENTS.md；装了钩子的话契约和状态会被强制注入。"
