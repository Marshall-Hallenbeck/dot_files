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

# Read the list without running the script, which would need a real $HOME.
listed=$(sed -n '/^AI_REMOTE_CONTROL_PATHS=(/,/^)/p' "$REPO_DIR/scripts/dotfiles" \
    | sed '1d;$d' | tr -d ' ' | sort)

check "no tracked Remote Control file is unregistered" "" \
    "$(comm -23 <(echo "$tracked") <(echo "$listed") | tr '\n' ' ' | sed 's/ $//')"
check "no registered path is missing from the repo" "" \
    "$(comm -13 <(echo "$tracked") <(echo "$listed") | tr '\n' ' ' | sed 's/ $//')"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
