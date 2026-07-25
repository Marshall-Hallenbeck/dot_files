#!/bin/bash
# Regression tests for the Claude Code hook scripts. Feeds each hook the stdin
# JSON Claude Code actually sends and asserts its behavior. Runs standalone (no
# Docker) — it exercises the repo's hook scripts directly. Guards against the
# whole class of bugs these hooks had (reading nonexistent env vars instead of
# stdin, wrong jq paths, and the MultiEdit blind spot).
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/../.claude/hooks" && pwd)"
PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

decision() { jq -r '.hookSpecificOutput.permissionDecision // "allow"'; }

echo "── guard-fallback-patterns.sh ──"
out=$(echo '{"tool_input":{"new_string":"x = a || []"}}' | bash "$HOOKS_DIR/guard-fallback-patterns.sh" | decision)
check "Edit fallback -> ask" "ask" "$out"
out=$(echo '{"tool_input":{"content":"x = a ?? {}"}}' | bash "$HOOKS_DIR/guard-fallback-patterns.sh" | decision)
check "Write fallback -> ask" "ask" "$out"
out=$(echo '{"tool_input":{"edits":[{"new_string":"safe"},{"new_string":"x = a || []"}]}}' | bash "$HOOKS_DIR/guard-fallback-patterns.sh" | decision)
check "MultiEdit fallback -> ask (regression)" "ask" "$out"
out=$(echo '{"tool_input":{"new_string":"x = compute(a)"}}' | bash "$HOOKS_DIR/guard-fallback-patterns.sh")
check "clean content -> allow (silent)" "" "$out"

echo "── post-edit-lint.sh ──"
tmpdir=$(mktemp -d)
# A bash file with an unquoted var (SC2086) so shellcheck has something to flag.
cat > "$tmpdir/t.sh" <<'BADSH'
#!/bin/bash
echo $X
BADSH
if echo "{\"tool_input\":{\"file_path\":\"$tmpdir/t.sh\"}}" | bash "$HOOKS_DIR/post-edit-lint.sh" | grep -q SC2086; then res=ran; else res=silent; fi
check "shell file -> shellcheck runs" "ran" "$res"
out=$(echo "{\"tool_input\":{\"file_path\":\"$tmpdir/note.md\"}}" | bash "$HOOKS_DIR/post-edit-lint.sh")
check "non-code file -> skip (silent)" "" "$out"
rm -rf "$tmpdir"

echo "── save-insights-reminder.sh ──"
out=$(echo '{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"a ★ Insight block"}' | bash "$HOOKS_DIR/save-insights-reminder.sh")
decision=$(echo "$out" | jq -r '.decision // "allow"')
reason=$(echo "$out" | jq -r '.reason // empty')
check "unsaved insight -> block stop" "block" "$decision"
if echo "$reason" | grep -q "not saved"; then res=explained; else res=missing; fi
check "unsaved insight -> explain block" "explained" "$res"
out=$(echo '{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"★ Insight saved to learned-insights"}' | bash "$HOOKS_DIR/save-insights-reminder.sh")
check "saved insight -> silent" "" "$out"
out=$(echo '{"hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"a ★ Insight block"}' | bash "$HOOKS_DIR/save-insights-reminder.sh")
check "active stop hook -> avoid continuation loop" "" "$out"

echo "── inject-insights-index.sh ──"
out=$(echo '{"source":"startup"}' | bash "$HOOKS_DIR/inject-insights-index.sh" | jq -r '.hookSpecificOutput.hookEventName // "none"')
check "emits SessionStart index" "SessionStart" "$out"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
