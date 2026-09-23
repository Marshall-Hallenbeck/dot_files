#!/bin/bash
# Regression tests for scripts/dotfiles. Runs standalone (no Docker).
#
# AI_REMOTE_CONTROL_PATHS is a hand-maintained list, and both `dotfiles status`
# and `dotfiles feature-enable` read it. A tracked Remote Control file left out
# of the list is reported MISSING on every host that never enabled the feature,
# and feature-enable never deploys it.
set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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

echo "── AI_REMOTE_CONTROL_PATHS coverage ──"

# Ground truth from git, independent of the list under test: the Remote Control
# feature owns everything this repo tracks under .config/systemd/ and .local/.
tracked=$(cd "$REPO_DIR" && git ls-files .config/systemd .local | sort)

# Read both lists without running the script, which would need a real $HOME.
# AI_REMOTE_CONTROL_PATHS includes AGENT_SYNC_PATHS through Bash expansion.
agent_sync_list=$(sed -n '/^AGENT_SYNC_PATHS=(/,/^)/p' "$REPO_DIR/scripts/dotfiles" \
    | sed '1d;$d' | tr -d ' ')
# shellcheck disable=SC2016  # Match the literal array expansion in the source.
remote_control_list=$(sed -n '/^AI_REMOTE_CONTROL_PATHS=(/,/^)/p' "$REPO_DIR/scripts/dotfiles" \
    | sed '1d;$d' | grep -vF '"${AGENT_SYNC_PATHS[@]}"' | tr -d ' ')
listed=$(printf '%s\n%s\n' "$agent_sync_list" "$remote_control_list" | sort -u)

check "no tracked Remote Control file is unregistered" "" \
    "$(comm -23 <(echo "$tracked") <(echo "$listed") | tr '\n' ' ' | sed 's/ $//')"
check "no registered path is missing from the repo" "" \
    "$(comm -13 <(echo "$tracked") <(echo "$listed") | tr '\n' ' ' | sed 's/ $//')"

echo "── migrate-local-state ──"
migrate_home=$(mktemp -d)
migrate_dotfiles="$migrate_home/.dot_files"
mkdir -p "$migrate_dotfiles/.claude" "$migrate_home/.claude/rules" "$migrate_home/.codex" "$migrate_home/.local/bin"
printf '# global\n' >"$migrate_dotfiles/global-AGENTS.md"
printf 'kept\n' >"$migrate_dotfiles/.claude/other.md"
ln -s "$migrate_dotfiles/.claude/global-CLAUDE.md" "$migrate_home/.claude/CLAUDE.md"
ln -s "$migrate_dotfiles/.codex/AGENTS.md" "$migrate_home/.codex/AGENTS.md"
ln -s "$migrate_dotfiles/.claude/rules/docker.md" "$migrate_home/.claude/rules/docker.md"
printf 'host rule\n' >"$migrate_home/.claude/rules/host.md"
ln -s "$migrate_dotfiles/.claude/other.md" "$migrate_home/.claude/rules/live.md"
ln -s "$migrate_dotfiles/.local/bin/agent-sync" "$migrate_home/.local/bin/agent-sync"
HOME="$migrate_home" DOTFILES_DIR="$migrate_dotfiles" bash "$REPO_DIR/scripts/migrate-local-state" >/dev/null
for instructions in .claude/CLAUDE.md .codex/AGENTS.md; do
    check "dangling $instructions relinked to global-AGENTS.md" "$migrate_dotfiles/global-AGENTS.md" \
        "$(readlink "$migrate_home/$instructions")"
done
check "dangling rule link removed" "absent" "$([ -L "$migrate_home/.claude/rules/docker.md" ] && echo present || echo absent)"
check "host-local rule file kept" "host rule" "$(cat "$migrate_home/.claude/rules/host.md")"
check "live rule link kept" "kept" "$(cat "$migrate_home/.claude/rules/live.md")"
check "dangling agent-sync link removed" "absent" "$([ -L "$migrate_home/.local/bin/agent-sync" ] && echo present || echo absent)"
rm -rf "$migrate_home"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
