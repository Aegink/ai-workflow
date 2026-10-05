#!/bin/sh
# SessionStart 钩子 —— 每次新会话开始时，把「工作流契约 + 项目状态」强制注入上下文。
#
# 挂载方式见 docs/hooks.md。Claude Code 会在会话启动时把 JSON 从 stdin 传入，
# 脚本把 additionalContext 输出到 stdout，内容会直接进入模型上下文。
#
# 设计要点：不依赖模型的自觉——契约和状态是"被塞进去的"，不是"被要求去读的"。

set -u

# ---------- 定位项目根 ----------
PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ]; then
  INPUT_CWD=$(cat 2>/dev/null | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  PROJ="${INPUT_CWD:-$PWD}"
fi
[ -d "$PROJ" ] || PROJ="$PWD"
cd "$PROJ" 2>/dev/null || true

# ---------- 会话标记（供 stop.sh 判断本次会话是否更新过 state） ----------
MARK="${TMPDIR:-/tmp}/aiwf-$(printf '%s' "$PROJ" | cksum | awk '{print $1}').mark"
rm -f "${MARK}.done"
: > "$MARK" 2>/dev/null || true

# ---------- 拼装注入内容 ----------
CTX=""
if [ -f AGENTS.md ]; then
  CTX="===== 工作流契约 AGENTS.md（必须遵守）=====
$(cat AGENTS.md)"
else
  CTX="===== 警告：本目录没有 AGENTS.md =====
请提示用户先运行 ai-workflow 的 install.sh 部署工作流契约。"
fi

if [ -f .aiworkflow/state.md ]; then
  CTX="$CTX

===== 项目状态 .aiworkflow/state.md（唯一事实源）=====
$(cat .aiworkflow/state.md)"
else
  CTX="$CTX

===== 项目状态：缺失 =====
本目录还没有 .aiworkflow/state.md。
按启动协议，你的第一件事是创建它（模板见 AGENTS.md 第 4 节），填写目标与当前阶段，
然后再向用户汇报。不要在没有状态文件的情况下开始写代码。"
fi

if [ -f .aiworkflow/handoff.md ]; then
  CTX="$CTX

===== 上次交接 .aiworkflow/handoff.md =====
$(cat .aiworkflow/handoff.md)"
fi

CTX="$CTX

===== 启动协议（现在执行）=====
1) 用不超过 5 行汇报：项目目标 / 当前阶段 / 上次进度 / 遗留风险 / 建议下一步。
2) 停下等用户确认后再动手。
3) 若用户指令明显是 L0 级（单文件、低风险、一次性），可直接执行，但结束时必须更新 state.md。"

# ---------- JSON 转义并输出（逐字符转义，对 busybox awk 也可靠）----------
ESC=$(printf '%s' "$CTX" | awk 'BEGIN{ORS=""}
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
}')
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESC"
exit 0
