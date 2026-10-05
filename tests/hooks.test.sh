#!/bin/sh
# 钩子行为测试。用法：sh tests/hooks.test.sh
# 依赖：POSIX sh、python3（仅用于校验 JSON 合法性）

set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t aiwf)"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1（期望 $3，得到 $2）"; fi; }

valid_json() {
  printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
}

# ---------- 准备 ----------
sh "$SRC/install.sh" "$T" >/dev/null
export CLAUDE_PROJECT_DIR="$T"
cd "$T"

run_pre() { printf '%s' "$1" | sh .aiworkflow/hooks/pre-tool-use.sh; }
write_json() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$T"; }
bash_json()  { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$T"; }

echo
echo "▶ PreToolUse · Gate 拦截"

# 1 无 state.md → 拒绝
rm -f .aiworkflow/state.md
OUT=$(run_pre "$(write_json "$T/src/a.py")")
case "$OUT" in *deny*) ok "无 state.md 时写源码 → 拒绝";; *) bad "无 state.md 时写源码 → 拒绝";; esac
valid_json "$OUT" && ok "拒绝理由是合法 JSON" || bad "拒绝理由是合法 JSON"

# 2 有 state.md，实现许可 no → 拒绝
cat > .aiworkflow/state.md <<'EOF'
- 当前阶段：Design
- 实现许可：no
EOF
OUT=$(run_pre "$(write_json "$T/src/a.py")")
case "$OUT" in *deny*Design*) ok "实现许可=no 时写源码 → 拒绝（带阶段名）";; *) bad "实现许可=no 时写源码 → 拒绝";; esac
valid_json "$OUT" && ok "拒绝理由仍是合法 JSON" || bad "拒绝理由仍是合法 JSON"

# 3 → 但 .aiworkflow/ 内放行
OUT=$(run_pre "$(write_json "$T/.aiworkflow/spec.md")")
check ".aiworkflow/ 内始终放行" "$OUT" ""

# 4 → Bash 写文件也拦
OUT=$(run_pre "$(bash_json 'echo hi > /tmp/x.txt')")
case "$OUT" in *deny*) ok "实现许可=no 时 Bash 重定向 → 拒绝";; *) bad "实现许可=no 时 Bash 重定向 → 拒绝";; esac
OUT=$(run_pre "$(bash_json 'sed -i s/a/b/ f.txt')")
case "$OUT" in *deny*) ok "实现许可=no 时 sed -i → 拒绝";; *) bad "实现许可=no 时 sed -i → 拒绝";; esac

# 5 → 只读 Bash 不拦
OUT=$(run_pre "$(bash_json 'ls -la')")
check "实现许可=no 时只读 Bash 放行" "$OUT" ""

# 6 实现许可 yes → 放行
cat > .aiworkflow/state.md <<'EOF'
- 当前阶段：Execute
- 实现许可：yes
EOF
OUT=$(run_pre "$(write_json "$T/src/a.py")")
check "实现许可=yes 时写源码放行" "$OUT" ""
OUT=$(run_pre "$(bash_json 'echo hi > /tmp/x.txt')")
check "实现许可=yes 时 Bash 放行" "$OUT" ""

# 7 没有许可行 → fail-open
printf -- '- 当前阶段：Execute\n' > .aiworkflow/state.md
OUT=$(run_pre "$(write_json "$T/src/a.py")")
check "缺少许可行时 fail-open 放行" "$OUT" ""

echo
echo "▶ SessionStart · 上下文注入"
rm -f .aiworkflow/state.md
OUT=$(printf '{"cwd":"%s"}' "$T" | sh .aiworkflow/hooks/session-start.sh)
valid_json "$OUT" && ok "注入内容是合法 JSON" || bad "注入内容是合法 JSON"
case "$OUT" in *"state.md"*) ok "缺失状态时给出创建提示";; *) bad "缺失状态时给出创建提示";; esac
case "$OUT" in *"启动协议"*) ok "包含启动协议指令";; *) bad "包含启动协议指令";; esac
case "$OUT" in *"通用 AI 工作流契约"*) ok "包含契约正文";; *) bad "包含契约正文";; esac

printf -- '- 当前阶段：Plan\n- 实现许可：no\n' > .aiworkflow/state.md
OUT=$(printf '{"cwd":"%s"}' "$T" | sh .aiworkflow/hooks/session-start.sh)
valid_json "$OUT" && ok "有状态时注入仍是合法 JSON" || bad "有状态时注入仍是合法 JSON"
case "$OUT" in *"当前阶段：Plan"*) ok "项目状态被注入";; *) bad "项目状态被注入";; esac

echo
echo "▶ Stop · 结束协议"
MARK="${TMPDIR:-/tmp}/aiwf-$(printf '%s' "$T" | cksum | awk '{print $1}').mark"
printf -- '- 结束协议：enforce\n' > .aiworkflow/state.md
sleep 1; : > "$MARK"; sleep 1; touch .aiworkflow/state.md
printf '{"cwd":"%s","stop_hook_active":false}' "$T" | sh .aiworkflow/hooks/stop.sh >/dev/null 2>&1
check "state.md 已更新 → 放行" "$?" "0"

: > "$MARK"; sleep 1
printf '{"cwd":"%s","stop_hook_active":false}' "$T" | sh .aiworkflow/hooks/stop.sh >/dev/null 2>&1
check "enforce 且未更新 → 阻塞(exit 2)" "$?" "2"

printf '{"cwd":"%s","stop_hook_active":true}' "$T" | sh .aiworkflow/hooks/stop.sh >/dev/null 2>&1
check "stop_hook_active 时放行（防死循环）" "$?" "0"

printf -- '- 结束协议：off\n' > .aiworkflow/state.md
: > "$MARK"; sleep 1
printf '{"cwd":"%s","stop_hook_active":false}' "$T" | sh .aiworkflow/hooks/stop.sh >/dev/null 2>&1
check "off 模式不检查" "$?" "0"

echo
echo "──────────────────────────────"
printf '  通过 %d · 失败 %d\n' "$PASS" "$FAIL"
rm -rf "$T"
[ "$FAIL" -eq 0 ]
