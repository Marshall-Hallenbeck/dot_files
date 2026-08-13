#!/bin/bash
# Agent coordination for GitHub issues. Multiple agents can work one repository
# in parallel; a claim comment plus the `in-progress` label tells other agents
# an issue is taken and by which session. Works in any repo with `gh` auth.
#
# Usage:
#   claim-issue.sh check <issue>              # print active claim, exit 3 if one exists
#   claim-issue.sh claim <issue>              # post session-info comment + add in-progress label
#   claim-issue.sh release <issue> [reason]   # remove in-progress label + post release comment
set -euo pipefail

CLAIM_MARKER='<!-- agent-session-claim -->'
RELEASE_MARKER='<!-- agent-session-release -->'
LABEL='in-progress'

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

[[ $# -ge 2 ]] || usage
action="$1"
issue="$2"
[[ "$issue" =~ ^[0-9]+$ ]] || usage

repo_root="$(git rev-parse --show-toplevel)"

session_info() {
    SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CODEX_SESSION_ID:-unknown}}"
    AGENT_KIND="${AI_AGENT:-unknown}"
    HOST="$(hostname)"
    BRANCH="$(git branch --show-current)"
    WORKTREE_PATH="$repo_root"
    WORKTREE_ID="none"
    RUNTIME_MODE="unknown"
    # Optional per-project worktree runtime (e.g. Turin's Tavern); absent elsewhere.
    if [[ -x "$repo_root/scripts/worktree-env.sh" ]]; then
        local status_json
        status_json="$("$repo_root/scripts/worktree-env.sh" status --json)"
        WORKTREE_ID="$(jq -r '.id // "none"' <<<"$status_json")"
        RUNTIME_MODE="$(jq -r '.mode // "unknown"' <<<"$status_json")"
    fi
}

# The newest claim/release marker comment decides the current state: a claim
# that no later release follows is active. Paginate: `gh issue view --json
# comments` caps at 100 comments and would silently miss newer claims.
active_claim() {
    local repo
    repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
    gh api --paginate --slurp "repos/$repo/issues/$issue/comments" | jq -r '
        [add[] | select(.body | contains("agent-session-"))] | last // empty
        | select(.body | contains("agent-session-claim")) | .body'
}

case "$action" in
check)
    claim="$(active_claim)"
    if [[ -n "$claim" ]]; then
        echo "Issue #$issue has an active agent claim:"
        echo "$claim"
        exit 3
    fi
    echo "Issue #$issue has no active agent claim."
    ;;
claim)
    session_info
    body="$(
        cat <<EOF
$CLAIM_MARKER
🤖 **Agent session claim** — this issue is being worked on.

| Field | Value |
| --- | --- |
| Session | \`$SESSION_ID\` |
| Agent | \`$AGENT_KIND\` |
| Host | \`$HOST\` |
| Branch | \`$BRANCH\` |
| Worktree | \`$WORKTREE_PATH\` |
| Worktree runtime | \`$WORKTREE_ID\` (mode \`$RUNTIME_MODE\`) |
| Claimed at | $(date -u +%Y-%m-%dT%H:%M:%SZ) |

Other agents: do not start this issue. Re-check with \`claim-issue.sh check $issue\`.
EOF
    )"
    gh issue comment "$issue" --body "$body"
    gh label create "$LABEL" --description "An agent is actively working on this" --color "F9D0C4" 2>/dev/null || true
    gh issue edit "$issue" --add-label "$LABEL"
    echo "Claimed issue #$issue (session $SESSION_ID on $HOST, branch $BRANCH)."
    ;;
release)
    session_info
    reason="${3:-work finished}"
    body="$(
        cat <<EOF
$RELEASE_MARKER
🏁 **Agent session released** — $reason.

Session \`$SESSION_ID\` on \`$HOST\` (branch \`$BRANCH\`) is no longer working on this issue.
EOF
    )"
    gh issue comment "$issue" --body "$body"
    gh issue edit "$issue" --remove-label "$LABEL"
    echo "Released issue #$issue."
    ;;
*)
    usage
    ;;
esac
