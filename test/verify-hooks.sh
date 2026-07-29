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

echo "── validate-commit-references.sh ──"
commit_hook="$HOOKS_DIR/validate-commit-references.sh"
commit_tmp=$(mktemp -d)
trap 'rm -rf "$commit_tmp"' EXIT

new_test_repo() {
    local repo

    repo=$(mktemp -d "$commit_tmp/repo.XXXXXX")
    git -C "$repo" init -q -b main
    git -C "$repo" config user.name "Hook Test"
    git -C "$repo" config user.email "hook-test@example.com"
    printf 'initial\n' >"$repo/fixture.txt"
    git -C "$repo" add fixture.txt
    git -C "$repo" commit -qm "chore: initial"
    printf '%s\n' "$repo"
}

stage_change() {
    local repo="$1"

    printf 'change\n' >>"$repo/fixture.txt"
    git -C "$repo" add fixture.txt
}

repo=$(new_test_repo)
if COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    bash "$commit_hook" --install "$repo" >/dev/null 2>&1 &&
    [ "$(readlink -f "$repo/.git/hooks/commit-msg")" = "$(readlink -f "$commit_hook")" ] &&
    [ "$(readlink -f "$repo/.git/hooks/prepare-commit-msg")" = "$(readlink -f "$commit_hook")" ] &&
    [ "$(readlink -f "$repo/.git/hooks/applypatch-msg")" = "$(readlink -f "$commit_hook")" ]; then
    res=installed
else
    res=missing
fi
check "installer creates all native message hooks" "installed" "$res"

preserve_repo=$(new_test_repo)
legacy_log="$commit_tmp/legacy-hook.log"
{
    printf '#!/bin/bash\n'
    printf 'printf "legacy\\n" >>%q\n' "$legacy_log"
} >"$preserve_repo/.git/hooks/commit-msg"
chmod +x "$preserve_repo/.git/hooks/commit-msg"
COMMIT_REFERENCE_PR=203 bash "$commit_hook" --install "$preserve_repo" >/dev/null
stage_change "$preserve_repo"
if COMMIT_REFERENCE_PR=203 git -C "$preserve_repo" commit \
    -m "fix: keep legacy validation (#203)" \
    -m "Refs #203" >/dev/null 2>&1 &&
    [ -x "$preserve_repo/.git/hooks/commit-msg.reference-guard-previous" ] &&
    grep -Fxq "legacy" "$legacy_log"; then
    res=preserved
else
    res=missing
fi
check "installer chains an existing commit-msg hook" "preserved" "$res"

managed_repo=$(new_test_repo)
mkdir -p "$managed_repo/.githooks"
printf '#!/bin/bash\nexit 0\n' >"$managed_repo/.githooks/commit-msg"
chmod +x "$managed_repo/.githooks/commit-msg"
git -C "$managed_repo" add .githooks/commit-msg
git -C "$managed_repo" commit -qm "test: add managed hook"
git -C "$managed_repo" config core.hooksPath .githooks
managed_hook_hash=$(git -C "$managed_repo" hash-object .githooks/commit-msg)
COMMIT_REFERENCE_PR=203 bash "$commit_hook" --install "$managed_repo" >/dev/null
if [ -f "$managed_repo/.githooks/commit-msg" ] &&
    [ ! -L "$managed_repo/.githooks/commit-msg" ] &&
    [ "$managed_hook_hash" = "$(git -C "$managed_repo" hash-object .githooks/commit-msg)" ] &&
    [ -z "$(git -C "$managed_repo" status --short)" ]; then
    res=preserved
else
    res=changed
fi
check "installer leaves project-managed hook paths unchanged" "preserved" "$res"

out=$(jq -n \
    --arg cwd "$managed_repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git merge --abort"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
check "managed hook paths do not block merge abort" "" "$out"
out=$(jq -n \
    --arg cwd "$managed_repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git merge --ff-only feature"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
check "managed hook paths do not block fast-forward-only merges" "" "$out"
out=$(jq -n \
    --arg cwd "$managed_repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git pull --ff-only"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
check "managed hook paths do not block fast-forward-only pulls" "" "$out"

external_hook_repo=$(new_test_repo)
external_hook_dir=$(mktemp -d "$commit_tmp/external-hooks.XXXXXX")
for hook_name in commit-msg prepare-commit-msg applypatch-msg; do
    ln -s "$commit_hook" "$external_hook_dir/$hook_name"
done
git -C "$external_hook_repo" config core.hooksPath "$external_hook_dir"
out=$(jq -n \
    --arg cwd "$external_hook_repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git merge feature"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
check "active validators in an external hook path stay allowed" "" "$out"

session_repo=$(new_test_repo)
if printf '%s\n' "{\"cwd\":\"$session_repo\"}" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" --install >/dev/null 2>&1 &&
    [ "$(readlink -f "$session_repo/.git/hooks/commit-msg")" = "$(readlink -f "$commit_hook")" ]; then
    res=installed
else
    res=missing
fi
check "session input installs the hook in its cwd" "installed" "$res"

target_repo=$(new_test_repo)
out=$(printf '%s\n' "{\"cwd\":\"$session_repo\",\"tool_input\":{\"cmd\":\"git -C $target_repo commit -m test\"}}" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
if [ -z "$out" ] &&
    [ "$(readlink -f "$target_repo/.git/hooks/commit-msg")" = "$(readlink -f "$commit_hook")" ]; then
    res=installed
else
    res=missing
fi
check "git -C installs the hook in the target repository" "installed" "$res"

cd_target_repo=$(new_test_repo)
out=$(printf '%s\n' "{\"cwd\":\"$session_repo\",\"tool_input\":{\"cmd\":\"cd $cd_target_repo && git commit -m test\"}}" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
if [ -z "$out" ] &&
    [ "$(readlink -f "$cd_target_repo/.git/hooks/commit-msg")" = "$(readlink -f "$commit_hook")" ] &&
    [ "$(readlink -f "$cd_target_repo/.git/hooks/prepare-commit-msg")" = "$(readlink -f "$commit_hook")" ]; then
    res=installed
else
    res=missing
fi
check "cd then git commit installs hooks in the target repository" "installed" "$res"

pushd_target_repo=$(new_test_repo)
out=$(jq -n \
    --arg cwd "$session_repo" \
    --arg cmd "pushd $pushd_target_repo >/dev/null && git commit -m test" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "unresolved directory-stack changes cannot select the wrong repository" "deny" "$out"

compound_target_repo=$(new_test_repo)
compound_input=$(jq -n \
    --arg cwd "$session_repo" \
    --arg cmd "cd $compound_target_repo && git add fixture.txt && git commit -m test" \
    '{cwd: $cwd, tool_input: {cmd: $cmd}}')
out=$(printf '%s\n' "$compound_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
if [ -z "$out" ] &&
    [ "$(readlink -f "$compound_target_repo/.git/hooks/commit-msg")" = "$(readlink -f "$commit_hook")" ]; then
    res=installed
else
    res=missing
fi
check "compound cd command installs hooks in the target repository" "installed" "$res"

subshell_repo=$(new_test_repo)
subshell_target_repo=$(new_test_repo)
subshell_input=$(jq -n \
    --arg cwd "$subshell_repo" \
    --arg cmd "(cd $subshell_target_repo); git commit -m test" \
    '{cwd: $cwd, tool_input: {cmd: $cmd}}')
out=$(printf '%s\n' "$subshell_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
if [ -z "$out" ] &&
    [ "$(readlink -f "$subshell_repo/.git/hooks/commit-msg")" = "$(readlink -f "$commit_hook")" ] &&
    [ ! -e "$subshell_target_repo/.git/hooks/commit-msg" ]; then
    res=installed
else
    res=wrong-target
fi
check "subshell directory changes do not escape their scope" "installed" "$res"

quoted_target_repo=$(mktemp -d "$commit_tmp/repo with spaces.XXXXXX")
git -C "$quoted_target_repo" init -q -b main
git -C "$quoted_target_repo" config user.name "Hook Test"
git -C "$quoted_target_repo" config user.email "hook-test@example.com"
quoted_input=$(jq -n \
    --arg cwd "$session_repo" \
    --arg cmd "git -C \"$quoted_target_repo\" commit -m test" \
    '{cwd: $cwd, tool_input: {cmd: $cmd}}')
out=$(printf '%s\n' "$quoted_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
if [ -z "$out" ] &&
    [ "$(readlink -f "$quoted_target_repo/.git/hooks/commit-msg")" = "$(readlink -f "$commit_hook")" ] &&
    [ "$(readlink -f "$quoted_target_repo/.git/hooks/prepare-commit-msg")" = "$(readlink -f "$commit_hook")" ]; then
    res=installed
else
    res=missing
fi
check "quoted git -C path installs hooks in the target repository" "installed" "$res"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git commit --no-verify -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "agent hook denies --no-verify commits" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git commit --no-veri -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "agent hook denies abbreviated --no-verify commits" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git -c core.hooksPath=/dev/null commit -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "agent hook denies native hook overrides" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "HOOKS=/dev/null git --config-env=core.hooksPath=HOOKS commit -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "agent hook denies config-env hook overrides" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "COMMIT_REFERENCE_PR= git commit -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "agent hook denies commit-reference context overrides" "deny" "$out"
out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "env -u COMMIT_REFERENCE_PR git commit -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "env cannot unset commit-reference context" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git commit -an"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "agent hook denies combined no-verify options" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git commit -uno -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
check "valid combined commit options stay allowed" "" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git commit -Ssigningkey -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
check "attached signing keys stay allowed" "" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git commit -tnewtemplate -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
check "attached commit templates stay allowed" "" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    --arg cmd $'git add fixture.txt\ngit commit --no-verify -m test' \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "newline-separated commits cannot bypass the guard" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    --arg cmd $'cat >/tmp/reference-hook-heredoc <<'\''EOF'\''\nunmatched " quote\nEOF\ngit commit --no-verify -m test' \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "shell parse errors cannot bypass the guard" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "/usr/bin/env git commit --no-verify -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "absolute env wrappers cannot bypass the guard" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    --arg cmd "bash -c 'git commit --no-verify -m test'" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "nested shell commands cannot bypass the guard" "deny" "$out"

for wrapped_cmd in \
    "sudo git commit --no-verify -m test" \
    "nice git commit --no-verify -m test" \
    "nice env git commit --no-verify -m test" \
    "timeout 5 git commit --no-verify -m test" \
    "eval 'git commit --no-verify -m test'"; do
    out=$(jq -n \
        --arg cwd "$repo" \
        --arg cmd "$wrapped_cmd" \
        '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
        COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
    check "command wrappers cannot hide Git mutations: $wrapped_cmd" "deny" "$out"
done

out=$(jq -n \
    --arg cwd "$repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "target=/tmp/repo; git -C \"$target\" commit -m test"}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "agent hook rejects unresolved repository targets" "deny" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    --arg cmd "printf '%s\\n' 'git commit --no-verify'" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "quoted Git examples do not trigger the agent guard" "" "$out"

out=$(jq -n \
    --arg cwd "$repo" \
    --arg cmd $'cat >example.sh <<EOF\ngit commit --no-verify -m test\nEOF' \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "Git examples in heredoc bodies do not trigger the agent guard" "" "$out"

quoted_heredoc_marker_cmd=$(printf '%s\n' \
    "printf '%s\\n' '<<EOF'" \
    "git commit --no-verify -m test")
out=$(jq -n \
    --arg cwd "$repo" \
    --arg cmd "$quoted_heredoc_marker_cmd" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "quoted heredoc text cannot hide a later Git mutation" "deny" "$out"

arithmetic_shift_cmd=$(printf '%s\n' \
    "value=\$((1 << 2))" \
    "git commit --no-verify -m test")
out=$(jq -n \
    --arg cwd "$repo" \
    --arg cmd "$arithmetic_shift_cmd" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "arithmetic shift syntax cannot break later Git mutation checks" "deny" "$out"

env_target_repo=$(new_test_repo)
out=$(jq -n \
    --arg cwd "$repo" \
    --arg cmd "env -C $env_target_repo git commit --no-verify -m test" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: $cmd}}' |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "env -C cannot bypass the agent guard" "deny" "$out"

nested_input=$(jq -n \
    --arg cwd "$repo" \
    --arg code 'await tools.exec_command({cmd: "git commit -m test"});' \
    '{tool_name: "functions.exec", cwd: $cwd, tool_input: $code}')
out=$(printf '%s\n' "$nested_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "Codex functions.exec cannot hide Git mutations" "deny" "$out"

dynamic_nested_input=$(jq -n \
    --arg cwd "$repo" \
    --arg code 'const command = "git " + "commit --no-verify -m test"; await tools.exec_command({cmd: command});' \
    '{tool_name: "functions.exec", cwd: $cwd, tool_input: $code}')
out=$(printf '%s\n' "$dynamic_nested_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "Codex functions.exec cannot build hidden Git mutations" "deny" "$out"

continued_nested_input=$(jq -n \
    --arg cwd "$repo" \
    --arg code $'const command = `git \\\ncommit --no-verify -m test`; await tools.exec_command({cmd: command});' \
    '{tool_name: "functions.exec", cwd: $cwd, tool_input: $code}')
out=$(printf '%s\n' "$continued_nested_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "Codex functions.exec line continuations cannot hide Git mutations" "deny" "$out"

large_nested_input=$(python3 - "$repo" <<'PY'
import json
import sys

print(json.dumps({
    "tool_name": "functions.exec",
    "cwd": sys.argv[1],
    "tool_input": "await tools.exec_command({cmd: \"git commit --no-verify -m test\"});\n"
        + ("x" * 300000),
}))
PY
)
out=$(printf '%s\n' "$large_nested_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "large Codex functions.exec calls cannot bypass Git mutation checks" "deny" "$out"

nested_rebase_input=$(jq -n \
    --arg cwd "$repo" \
    --arg code 'await tools.exec_command({cmd: "git rebase main"});' \
    '{tool_name: "functions.exec", cwd: $cwd, tool_input: $code}')
out=$(printf '%s\n' "$nested_rebase_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "Codex functions.exec cannot hide Git rebases" "deny" "$out"

rebase_repo=$(new_test_repo)
git -C "$rebase_repo" switch -qc feature
rebase_input=$(jq -n \
    --arg cwd "$rebase_repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git rebase main"}}')
out=$(printf '%s\n' "$rebase_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
if [ -z "$out" ] &&
    [ "$(readlink -f "$rebase_repo/.git/hooks/prepare-commit-msg")" = "$(readlink -f "$commit_hook")" ]; then
    res=installed
else
    res=missing
fi
check "agent hook prepares rewritten rebase commits" "installed" "$res"

pull_repo=$(new_test_repo)
pull_input=$(jq -n \
    --arg cwd "$repo" \
    --arg target "$pull_repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: ("git -C " + $target + " pull")}}')
out=$(printf '%s\n' "$pull_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
if [ -z "$out" ] &&
    [ "$(readlink -f "$pull_repo/.git/hooks/prepare-commit-msg")" = "$(readlink -f "$commit_hook")" ]; then
    res=installed
else
    res=missing
fi
check "agent hook prepares pull-created commits" "installed" "$res"

alias_repo=$(new_test_repo)
git -C "$alias_repo" config alias.ci commit
alias_input=$(jq -n \
    --arg cwd "$repo" \
    --arg target "$alias_repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: ("git -C " + $target + " ci -m test")}}')
out=$(printf '%s\n' "$alias_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook")
if [ -z "$out" ] &&
    [ "$(readlink -f "$alias_repo/.git/hooks/commit-msg")" = "$(readlink -f "$commit_hook")" ]; then
    res=installed
else
    res=missing
fi
check "Git commit aliases install the native hooks" "installed" "$res"

git -C "$alias_repo" config alias.unsafe 'commit --no-verify'
alias_input=$(jq -n \
    --arg cwd "$alias_repo" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {cmd: "git unsafe -m test"}}')
out=$(printf '%s\n' "$alias_input" |
    COMMIT_REFERENCE_PR=203 bash "$commit_hook" | decision)
check "Git aliases cannot hide --no-verify" "deny" "$out"

stage_change "$repo"
if COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    git -C "$repo" commit --no-verify \
        -m "fix(auth): bypass hooks" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "prepare hook rejects missing references with --no-verify" "deny" "$res"

if COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    git -C "$repo" commit -m "fix(auth): reject invalid tokens" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "native hook rejects missing references" "deny" "$res"

if COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    git -C "$repo" commit \
        -m "fix(auth): reject invalid tokens (#203)" \
        -m "Refs #203" \
        -m "Sentry-Issue: TOTAL_TAVERN-H" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "native hook accepts exact PR and Sentry references" "allow" "$res"

large_message="$commit_tmp/large-message"
{
    printf 'fix(auth): keep a large body valid (#203)\n\n'
    printf 'Refs #203\n'
    head -c 300000 /dev/zero | tr '\0' x
    printf '\n'
} >"$large_message"
if COMMIT_REFERENCE_PR=203 bash "$commit_hook" "$large_message" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "large commit bodies keep an early valid reference" "allow" "$res"

scissors_repo=$(new_test_repo)
COMMIT_REFERENCE_PR=203 bash "$commit_hook" --install "$scissors_repo" >/dev/null
scissors_message="$commit_tmp/scissors-message"
{
    printf 'fix(auth): reject invalid tokens (#203)\n\n'
    printf '# ------------------------ >8 ------------------------\n'
    printf 'Refs #203\n'
} >"$scissors_message"
stage_change "$scissors_repo"
if GIT_EDITOR=true COMMIT_REFERENCE_PR=203 \
    git -C "$scissors_repo" -c commit.cleanup=scissors commit \
        -e -F "$scissors_message" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "references below a scissors marker do not validate" "deny" "$res"

stage_change "$repo"
if COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    git -C "$repo" commit \
        -m "fix(auth): reject invalid tokens (#203)" \
        -m "Refs #2030" \
        -m "Sentry-Issue: TOTAL_TAVERN-HACK" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "native hook rejects reference prefixes" "deny" "$res"
git -C "$repo" reset -q HEAD fixture.txt
git -C "$repo" restore fixture.txt

issue_repo=$(new_test_repo)
COMMIT_REFERENCE_ISSUES=187 bash "$commit_hook" --install "$issue_repo" >/dev/null
stage_change "$issue_repo"
if COMMIT_REFERENCE_ISSUES=187 git -C "$issue_repo" commit \
    -m "fix(pick-ban): keep the active tab (#187)" \
    -m "Refs #187" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "issue-only context requires the issue subject and trailer" "allow" "$res"

sentry_repo=$(new_test_repo)
COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H bash "$commit_hook" --install "$sentry_repo" >/dev/null
stage_change "$sentry_repo"
if COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H git -C "$sentry_repo" commit \
    -m "fix(sentry): filter expected input" \
    -m "Sentry-Issue: TOTAL_TAVERN-HACK" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "Sentry-only context rejects a prefixed issue ID" "deny" "$res"
message_file="$commit_tmp/message"
printf '%s\n\n%s\n' \
    "fix(sentry): filter expected input" \
    "Sentry-Issue: TOTAL_TAVERN-H" >"$message_file"
if COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H git -C "$sentry_repo" commit \
    -F "$message_file" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "native hook validates a message supplied with -F" "allow" "$res"

if COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H git -C "$sentry_repo" commit \
    --amend --no-edit >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "native hook permits amend with an already valid message" "allow" "$res"

amend_repo=$(new_test_repo)
COMMIT_REFERENCE_PR=203 bash "$commit_hook" --install "$amend_repo" >/dev/null
stage_change "$amend_repo"
if COMMIT_REFERENCE_PR=203 git -C "$amend_repo" commit \
    --amend --no-edit --no-verify >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "prepare hook rejects an untagged no-verify amend" "deny" "$res"

merge_repo=$(new_test_repo)
git -C "$merge_repo" switch -qc feature
stage_change "$merge_repo"
git -C "$merge_repo" commit -qm "fix: feature"
git -C "$merge_repo" switch -q main
COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    bash "$commit_hook" --install "$merge_repo" >/dev/null
if COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    git -C "$merge_repo" merge --no-ff --no-edit feature >/dev/null 2>&1; then
    merge_message=$(git -C "$merge_repo" log -1 --format=%B)
    if printf '%s\n' "$merge_message" | grep -Eq '^Merge .+ \(#203\)$' &&
        printf '%s\n' "$merge_message" | grep -Fxq "Refs #203" &&
        printf '%s\n' "$merge_message" | grep -Fxq "Sentry-Issue: TOTAL_TAVERN-H"; then
        res=tagged
    else
        res=missing
    fi
else
    res=failed
fi
check "default merge commits receive exact references" "tagged" "$res"

scissors_merge_repo=$(new_test_repo)
git -C "$scissors_merge_repo" switch -qc feature
stage_change "$scissors_merge_repo"
git -C "$scissors_merge_repo" commit -qm "fix: feature"
git -C "$scissors_merge_repo" switch -q main
COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    bash "$commit_hook" --install "$scissors_merge_repo" >/dev/null
git -C "$scissors_merge_repo" merge --no-ff --no-commit feature >/dev/null
scissors_merge_message="$commit_tmp/scissors-merge-message"
{
    printf 'Merge branch '\''feature'\''\n\n'
    printf '# ------------------------ >8 ------------------------\n'
    printf '# merge comments\n'
} >"$scissors_merge_message"
(
    cd "$scissors_merge_repo" || exit
    COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
        .git/hooks/prepare-commit-msg "$scissors_merge_message" merge >/dev/null
)
refs_line=$(grep -nFx "Refs #203" "$scissors_merge_message" | cut -d: -f1)
marker_line=$(grep -nFx \
    "# ------------------------ >8 ------------------------" \
    "$scissors_merge_message" | cut -d: -f1)
if [ -n "$refs_line" ] && [ -n "$marker_line" ] &&
    [ "$refs_line" -lt "$marker_line" ]; then
    res=before
else
    res=after
fi
check "automatic references are inserted before the scissors marker" "before" "$res"
git -C "$scissors_merge_repo" merge --abort >/dev/null

sequence_repo=$(new_test_repo)
git -C "$sequence_repo" switch -qc feature
stage_change "$sequence_repo"
git -C "$sequence_repo" commit -qm "fix(auth): add sequence change"
sequence_sha=$(git -C "$sequence_repo" rev-parse HEAD)
git -C "$sequence_repo" switch -q main
COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    bash "$commit_hook" --install "$sequence_repo" >/dev/null
if COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    git -C "$sequence_repo" cherry-pick "$sequence_sha" >/dev/null 2>&1; then
    sequence_message=$(git -C "$sequence_repo" log -1 --format=%B)
    if printf '%s\n' "$sequence_message" | grep -Eq '^fix\(auth\): add sequence change \(#203\)$' &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Refs #203" &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Sentry-Issue: TOTAL_TAVERN-H"; then
        res=tagged
    else
        res=missing
    fi
else
    res=failed
fi
check "cherry-pick commits receive exact references" "tagged" "$res"

if COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H \
    git -C "$sequence_repo" revert --no-edit HEAD >/dev/null 2>&1; then
    sequence_message=$(git -C "$sequence_repo" log -1 --format=%B)
    if printf '%s\n' "$sequence_message" | grep -Eq '^Revert .+ \(#203\)$' &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Refs #203" &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Sentry-Issue: TOTAL_TAVERN-H"; then
        res=tagged
    else
        res=missing
    fi
else
    res=failed
fi
check "revert commits receive exact references" "tagged" "$res"

fake_bin=$(mktemp -d "$commit_tmp/bin.XXXXXX")
cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
jq -n '[{
    number: 203,
    body: "Fixes [TOTAL_TAVERN-H](https://marshall-hallenbeck.sentry.io/issues/123/)\nRefs [JS-1](https://marshall-hallenbeck.sentry.io/issues/124/)\nRefs #187\nCVE-2025-1234\nREACT-NATIVE-1A"
}]'
EOF
chmod +x "$fake_bin/gh"
discovery_repo=$(new_test_repo)
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$discovery_repo" >/dev/null
discovered_pr=$(git -C "$discovery_repo" config --get branch.main.referencePr || true)
discovered_sentry=$(git -C "$discovery_repo" config --get branch.main.sentryIssues || true)
discovered_issues=$(git -C "$discovery_repo" config --get branch.main.relatedIssues || true)
check "PR discovery stores the exact PR" "203" "$discovered_pr"
check "PR discovery stores only linked Sentry IDs" "JS-1 TOTAL_TAVERN-H" "$discovered_sentry"
check "PR discovery stores related GitHub issues" "187" "$discovered_issues"

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
if [ -n "${HOOK_GH_COUNT_FILE:-}" ]; then
    printf 'x' >>"$HOOK_GH_COUNT_FILE"
fi
jq -n '[{number: 203, body: "No external references"}]'
EOF
chmod +x "$fake_bin/gh"
cache_repo=$(new_test_repo)
cache_count="$commit_tmp/gh-count"
HOOK_GH_COUNT_FILE="$cache_count" PATH="$fake_bin:$PATH" \
    bash "$commit_hook" --install "$cache_repo" >/dev/null
stage_change "$cache_repo"
HOOK_GH_COUNT_FILE="$cache_count" PATH="$fake_bin:$PATH" \
    git -C "$cache_repo" commit \
        -m "fix: use cached PR context (#203)" \
        -m "Refs #203" >/dev/null
cache_calls=$(wc -c <"$cache_count" | tr -d ' ')
check "commit hooks reuse the recent GitHub lookup" "1" "$cache_calls"

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$fake_bin/gh"
stale_cache_repo=$(new_test_repo)
COMMIT_REFERENCE_PR=203 bash "$commit_hook" --install "$stale_cache_repo" >/dev/null
git -C "$stale_cache_repo" config branch.main.referencePr 203
git -C "$stale_cache_repo" config branch.main.referenceCheckedAt 0
stage_change "$stale_cache_repo"
if PATH="$fake_bin:$PATH" git -C "$stale_cache_repo" commit \
    -m "fix: missing cached reference" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "failed refresh keeps stale cached PR enforcement" "deny" "$res"

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
if [[ " $* " = *" --head feature "* ]]; then
    jq -n '[{
        number: 203,
        body: "Fixes [TOTAL_TAVERN-H](https://marshall-hallenbeck.sentry.io/issues/123/)\nRefs #187"
    }]'
else
    printf '[]\n'
fi
EOF
chmod +x "$fake_bin/gh"
upstream_repo=$(new_test_repo)
git -C "$upstream_repo" remote add origin https://example.invalid/repo.git
git -C "$upstream_repo" update-ref refs/remotes/origin/main HEAD
git -C "$upstream_repo" switch -qc feature
git -C "$upstream_repo" branch --set-upstream-to origin/main >/dev/null
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$upstream_repo" >/dev/null
upstream_pr=$(git -C "$upstream_repo" config --get branch.feature.referencePr || true)
check "PR discovery retries the local branch after an upstream miss" "203" "$upstream_pr"

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
if [[ " $* " = *" --head feature "* ]]; then
    jq -n '[{number: 203, body: "No external references"}]'
elif [[ " $* " = *" --head main "* ]]; then
    jq -n '[{number: 999, body: "No external references"}]'
else
    printf '[]\n'
fi
EOF
chmod +x "$fake_bin/gh"
local_branch_repo=$(new_test_repo)
git -C "$local_branch_repo" remote add origin https://example.invalid/repo.git
git -C "$local_branch_repo" update-ref refs/remotes/origin/main HEAD
git -C "$local_branch_repo" switch -qc feature
git -C "$local_branch_repo" branch --set-upstream-to origin/main >/dev/null
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$local_branch_repo" >/dev/null
local_branch_pr=$(git -C "$local_branch_repo" config --get branch.feature.referencePr || true)
check "PR discovery checks the local branch before its upstream" "203" "$local_branch_pr"

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
if [[ " $* " = *" --head feature "* ]]; then
    jq -n '[{
        number: 203,
        body: "Fixes [TOTAL_TAVERN-H](https://marshall-hallenbeck.sentry.io/issues/123/)\nRefs #187"
    }]'
else
    printf '[]\n'
fi
EOF
chmod +x "$fake_bin/gh"
source_merge_repo=$(new_test_repo)
git -C "$source_merge_repo" switch -qc feature
stage_change "$source_merge_repo"
git -C "$source_merge_repo" commit -qm "fix: source feature"
git -C "$source_merge_repo" switch -q main
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$source_merge_repo" >/dev/null
if PATH="$fake_bin:$PATH" git -C "$source_merge_repo" merge \
    --no-ff --no-edit feature >/dev/null 2>&1; then
    merge_message=$(git -C "$source_merge_repo" log -1 --format=%B)
    if printf '%s\n' "$merge_message" | grep -Eq '^Merge .+ \(#203\)$' &&
        printf '%s\n' "$merge_message" | grep -Fxq "Refs #203" &&
        printf '%s\n' "$merge_message" | grep -Fxq "Refs #187" &&
        printf '%s\n' "$merge_message" | grep -Fxq "Sentry-Issue: TOTAL_TAVERN-H"; then
        res=tagged
    else
        res=missing
    fi
else
    res=failed
fi
check "merge commits use the source branch PR context" "tagged" "$res"

source_pick_repo=$(new_test_repo)
git -C "$source_pick_repo" switch -qc feature
stage_change "$source_pick_repo"
git -C "$source_pick_repo" commit -qm "fix: source pick"
source_pick_sha=$(git -C "$source_pick_repo" rev-parse HEAD)
git -C "$source_pick_repo" switch -q main
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$source_pick_repo" >/dev/null
if PATH="$fake_bin:$PATH" git -C "$source_pick_repo" cherry-pick \
    "$source_pick_sha" >/dev/null 2>&1; then
    sequence_message=$(git -C "$source_pick_repo" log -1 --format=%B)
    if printf '%s\n' "$sequence_message" | grep -Eq '^fix: source pick \(#203\)$' &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Refs #203" &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Refs #187" &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Sentry-Issue: TOTAL_TAVERN-H"; then
        res=tagged
    else
        res=missing
    fi
else
    res=failed
fi
check "cherry-picks discover the source branch PR context" "tagged" "$res"

rebase_context_repo=$(new_test_repo)
git -C "$rebase_context_repo" switch -qc feature
printf 'feature\n' >"$rebase_context_repo/feature.txt"
git -C "$rebase_context_repo" add feature.txt
git -C "$rebase_context_repo" commit -qm "fix: rebase feature"
git -C "$rebase_context_repo" switch -q main
printf 'main\n' >"$rebase_context_repo/main.txt"
git -C "$rebase_context_repo" add main.txt
git -C "$rebase_context_repo" commit -qm "fix: move main"
git -C "$rebase_context_repo" switch -q feature
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$rebase_context_repo" >/dev/null
if PATH="$fake_bin:$PATH" git -C "$rebase_context_repo" rebase main >/dev/null 2>&1; then
    sequence_message=$(git -C "$rebase_context_repo" log -1 --format=%B)
    if printf '%s\n' "$sequence_message" | grep -Eq '^fix: rebase feature \(#203\)$' &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Refs #203" &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Refs #187" &&
        printf '%s\n' "$sequence_message" | grep -Fxq "Sentry-Issue: TOTAL_TAVERN-H"; then
        res=tagged
    else
        res=missing
    fi
else
    res=failed
fi
check "rebases keep the original branch PR context" "tagged" "$res"

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
if [[ " $* " = *" --head alpha-source "* ]]; then
    jq -n '[{
        number: 147,
        body: "Fixes [SOURCE-1](https://example.sentry.io/issues/147/)"
    }]'
elif [[ " $* " = *" --head feature-pr "* ]] ||
    [[ " $* " = *" --head feature "* ]]; then
    jq -n '[{
        number: 203,
        body: "Fixes [TOTAL_TAVERN-H](https://example.sentry.io/issues/203/)"
    }]'
else
    printf '[]\n'
fi
EOF
chmod +x "$fake_bin/gh"
target_merge_repo=$(new_test_repo)
git -C "$target_merge_repo" switch -qc alpha-source
stage_change "$target_merge_repo"
git -C "$target_merge_repo" commit -qm "fix: alpha source"
git -C "$target_merge_repo" switch -qc feature-pr main
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$target_merge_repo" >/dev/null
if PATH="$fake_bin:$PATH" git -C "$target_merge_repo" merge \
    --no-ff --no-edit alpha-source >/dev/null 2>&1; then
    merge_message=$(git -C "$target_merge_repo" log -1 --format=%B)
    if printf '%s\n' "$merge_message" | grep -Eq '^Merge .+ \(#203\)$' &&
        printf '%s\n' "$merge_message" | grep -Fxq "Refs #203" &&
        printf '%s\n' "$merge_message" | grep -Fxq "Sentry-Issue: TOTAL_TAVERN-H" &&
        ! printf '%s\n' "$merge_message" | grep -q '#147\|SOURCE-1'; then
        res=tagged
    else
        res=wrong-context
    fi
else
    res=failed
fi
check "merge commits prefer the current branch PR context" "tagged" "$res"

detached_repo=$(new_test_repo)
git -C "$detached_repo" switch -qc feature
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$detached_repo" >/dev/null
git -C "$detached_repo" switch -q --detach
stage_change "$detached_repo"
if PATH="$fake_bin:$PATH" git -C "$detached_repo" commit \
    -m "fix: detached change" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "detached HEAD resolves the pointed PR branch context" "deny" "$res"
git -C "$detached_repo" reset -q HEAD fixture.txt
git -C "$detached_repo" restore fixture.txt

am_source_repo=$(new_test_repo)
git -C "$am_source_repo" switch -qc patch
stage_change "$am_source_repo"
git -C "$am_source_repo" commit -qm "fix: untagged patch"
git -C "$am_source_repo" format-patch -1 --stdout >"$commit_tmp/untagged.patch"
am_target_repo=$(new_test_repo)
git -C "$am_target_repo" switch -qc feature
COMMIT_REFERENCE_PR=203 bash "$commit_hook" --install "$am_target_repo" >/dev/null
if COMMIT_REFERENCE_PR=203 git -C "$am_target_repo" am \
    "$commit_tmp/untagged.patch" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "applypatch hook rejects an untagged git am commit" "deny" "$res"
git -C "$am_target_repo" am --abort >/dev/null 2>&1 || true

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
jq -n '[{number: 203, body: "No external references"}]'
EOF
chmod +x "$fake_bin/gh"
git -C "$discovery_repo" config --unset-all branch.main.referenceCheckedAt 2>/dev/null || true
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$discovery_repo" >/dev/null
discovered_sentry=$(git -C "$discovery_repo" config --get branch.main.sentryIssues || true)
discovered_issues=$(git -C "$discovery_repo" config --get branch.main.relatedIssues || true)
check "PR refresh clears a removed Sentry ID" "" "$discovered_sentry"
check "PR refresh clears a removed GitHub issue" "" "$discovered_issues"

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
printf '[]\n'
EOF
chmod +x "$fake_bin/gh"
git -C "$discovery_repo" config --unset-all branch.main.referenceCheckedAt 2>/dev/null || true
PATH="$fake_bin:$PATH" bash "$commit_hook" --install "$discovery_repo" >/dev/null
discovered_pr=$(git -C "$discovery_repo" config --get branch.main.referencePr || true)
check "PR refresh clears a closed PR" "" "$discovered_pr"

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$fake_bin/gh"
offline_repo=$(new_test_repo)
git -C "$offline_repo" switch -qc feature/offline
COMMIT_REFERENCE_PR='' bash "$commit_hook" --install "$offline_repo" >/dev/null
stage_change "$offline_repo"
if PATH="$fake_bin:$PATH" git -C "$offline_repo" commit \
    -m "fix: permit offline local work" >/dev/null 2>&1; then
    res=allow
else
    res=deny
fi
check "GitHub lookup failure does not block a context-free commit" "allow" "$res"

out=$(printf '%s\n' "{\"cwd\":\"$repo\",\"tool_input\":{\"cmd\":\"git merge --abort\"}}" |
    COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H bash "$commit_hook")
check "merge abort is not blocked" "" "$out"
out=$(printf '%s\n' '{"tool_input":{"cmd":"npm test"}}' |
    COMMIT_REFERENCE_PR=203 COMMIT_REFERENCE_SENTRY=TOTAL_TAVERN-H bash "$commit_hook")
check "non-Git command stays silent" "" "$out"

dotfiles_root="$(cd "$(dirname "$0")/.." && pwd)"
claude_hook=$(jq -r '
    .hooks.PreToolUse[]
    | select(.matcher == "Bash")
    | .hooks[]
    | select(.command | contains("validate-commit-references.sh"))
    | .command
' "$dotfiles_root/.claude/settings.json")
expected_hook="\$HOME/.claude/hooks/validate-commit-references.sh"
check "Claude loads commit-reference hook" "$expected_hook" "$claude_hook"
claude_session_hook=$(jq -r '
    .hooks.SessionStart[]
    | .hooks[]
    | select(.command | contains("validate-commit-references.sh --install"))
    | .command
' "$dotfiles_root/.claude/settings.json")
check "Claude installs the native hook at session start" \
    "$expected_hook --install" "$claude_session_hook"
codex_hook=$(jq -r '
    .hooks.PreToolUse[]
    | select(.matcher | contains("exec_command"))
    | .hooks[]
    | select(.command | contains("validate-commit-references.sh"))
    | .command
' "$dotfiles_root/.codex/hooks.json")
check "Codex loads commit-reference hook" "$expected_hook" "$codex_hook"
codex_nested_hook=$(jq -r '
    .hooks.PreToolUse[]
    | select(.matcher | contains("functions\\.exec"))
    | .hooks[]
    | select(.command | contains("validate-commit-references.sh"))
    | .command
' "$dotfiles_root/.codex/hooks.json")
check "Codex checks nested functions.exec calls" "$expected_hook" "$codex_nested_hook"
codex_session_hook=$(jq -r '
    .hooks.SessionStart[]
    | .hooks[]
    | select(.command | contains("validate-commit-references.sh --install"))
    | .command
' "$dotfiles_root/.codex/hooks.json")
check "Codex installs the native hook at session start" \
    "$expected_hook --install" "$codex_session_hook"
installer_pattern="link_file \"\$DOTFILES_DIR/.codex/hooks.json\" ~/.codex/hooks.json"
if grep -Fq "$installer_pattern" "$dotfiles_root/install_environment.sh"; then
    res=linked
else
    res=missing
fi
check "installer links Codex hook configuration" "linked" "$res"
installer_pattern="link_file \"\$DOTFILES_DIR/.codex/AGENTS.md\" ~/.codex/AGENTS.md"
if grep -Fq "$installer_pattern" "$dotfiles_root/install_environment.sh"; then
    res=linked
else
    res=missing
fi
check "installer links Codex global instructions" "linked" "$res"

trust_checker="$dotfiles_root/.codex/verify-hook-trust.py"
fake_codex_dir=$(mktemp -d "$commit_tmp/fake-codex.XXXXXX")
cat >"$fake_codex_dir/codex" <<'EOF'
#!/bin/bash
read -r _initialize
printf '%s\n' '{"id":0,"result":{"userAgent":"test","codexHome":"/tmp","platformFamily":"unix","platformOs":"linux"}}'
read -r _initialized
read -r _hooks_list
jq -nc --arg status "${FAKE_CODEX_TRUST_STATUS:-trusted}" '{
    id: 1,
    result: {
        data: [{
            cwd: "/tmp",
            hooks: [
                {
                    source: "user",
                    command: "$HOME/.claude/hooks/validate-commit-references.sh",
                    enabled: true,
                    trustStatus: $status
                },
                {
                    source: "user",
                    command: "$HOME/.claude/hooks/validate-commit-references.sh --install",
                    enabled: true,
                    trustStatus: $status
                }
            ],
            warnings: [],
            errors: []
        }]
    }
}'
EOF
chmod +x "$fake_codex_dir/codex"
if FAKE_CODEX_TRUST_STATUS=trusted PATH="$fake_codex_dir:$PATH" \
    python3 "$trust_checker" "$dotfiles_root" >/dev/null 2>&1; then
    res=trusted
else
    res=failed
fi
check "Codex trust verifier accepts exact trusted hooks" "trusted" "$res"
if FAKE_CODEX_TRUST_STATUS=modified PATH="$fake_codex_dir:$PATH" \
    python3 "$trust_checker" "$dotfiles_root" >/dev/null 2>&1; then
    res=allowed
else
    res=blocked
fi
check "Codex trust verifier rejects changed hooks" "blocked" "$res"

if grep -Fq '.codex/verify-hook-trust.py' "$dotfiles_root/install_environment.sh" &&
    grep -Fq 'codex --no-alt-screen' "$dotfiles_root/install_environment.sh"; then
    res=verified
else
    res=missing
fi
check "installer stops for Codex hook trust review" "verified" "$res"

if grep -Fq 'Refs #<PR>' "$dotfiles_root/.claude/skills/fix-tests/SKILL.md" &&
    grep -Fq 'Sentry-Issue: <SENTRY-ID>' "$dotfiles_root/.claude/skills/fix-tests/SKILL.md"; then
    res=present
else
    res=missing
fi
check "fix-tests commit workflow requires traceability references" "present" "$res"

if grep -Fq 'git commit --allow-empty -m "<message> (#<PR>)"' \
    "$dotfiles_root/.claude/skills/safe-commit-all/SKILL.md"; then
    res=present
else
    res=missing
fi
check "empty checkpoint workflow requires the open PR reference" "present" "$res"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
