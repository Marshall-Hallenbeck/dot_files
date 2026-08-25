#!/bin/bash
# Stop hook: refuse to end a session in a linked git worktree that still holds
# unpublished work.
#
# An audit of parallel agent sessions found the dominant way work is lost is not
# a bad merge but a session that runs its tests green and never commits: the
# worktree is deleted weeks later with the work still only in its working tree.
# Committed-and-pushed work has never been lost. This hook closes that gap.
#
# It gates linked worktrees only. The primary checkout is where a human keeps
# long-lived local edits, and blocking there would fire on every session.
#
# Hook input is JSON on STDIN. When .stop_hook_active is true this hook has
# already blocked once, so it must pass to avoid a loop.
set -uo pipefail

input=$(cat)
# Without parseable input there is no .stop_hook_active to honour, so blocking
# could loop forever. Nothing to guard either way.
jq -e . >/dev/null 2>&1 <<< "$input" || exit 0
[ "$(jq -r '.stop_hook_active // false' <<< "$input")" = "true" ] && exit 0

cwd=$(jq -r '.cwd // empty' <<< "$input")
[ -n "$cwd" ] || cwd="$PWD"
[ -d "$cwd" ] || exit 0

git_dir=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
# Same value means the primary checkout, not a linked worktree.
[ "$git_dir" = "$common_dir" ] && exit 0

branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
[ -n "$branch" ] || exit 0

# A worktree somebody else is actively working in is not abandoned work. A
# subagent gets its own checkout and the main session can land in it just by
# inspecting it, so without this the gate blocks one session for another
# session's in-flight branch. A live process with its cwd inside the tree is
# the ownership signal; EnterWorktree does not take a git worktree lock, so
# there is nothing else to read.
self_pid=$$
for cwd_link in /proc/[0-9]*/cwd; do
    pid=${cwd_link#/proc/}
    pid=${pid%/cwd}
    [ "$pid" = "$self_pid" ] && continue
    target=$(readlink "$cwd_link" 2>/dev/null) || continue
    case "$target" in
        "$cwd" | "$cwd"/*) exit 0 ;;
    esac
done

dirty=$(git -C "$cwd" status --porcelain 2>/dev/null)

base=""
for candidate in origin/main origin/master; do
    if git -C "$cwd" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
        base="$candidate"
        break
    fi
done

unpushed=""
if [ -n "$base" ]; then
    unpushed=$(git -C "$cwd" rev-list --count "${base}..HEAD" 2>/dev/null)
fi

# Commits that exist only here are fine once a pull request carries them.
has_pr="no"
if [ "${unpushed:-0}" != "0" ] && command -v gh >/dev/null 2>&1; then
    if [ -n "$(cd "$cwd" && timeout 20 gh pr list --head "$branch" --state open --json number -q '.[].number' 2>/dev/null)" ]; then
        has_pr="yes"
    fi
fi

problems=()
[ -n "$dirty" ] && problems+=("$(printf '%s\n' "$dirty" | grep -c '' | tr -d ' ') uncommitted file(s) in $cwd")
[ "${unpushed:-0}" != "0" ] && [ "$has_pr" = "no" ] &&
    problems+=("$unpushed commit(s) on '$branch' that are not on $base and carry no open pull request")

[ ${#problems[@]} -eq 0 ] && exit 0

reason="Do not end here — this linked worktree holds unpublished work:
"
for problem in "${problems[@]}"; do
    reason+="  - ${problem}
"
done
reason+="
Publish it before stopping: stage by name, commit with a Conventional Commits
message, 'git push -u origin ${branch}', and open a pull request. If the work is
genuinely not worth keeping, delete the files or reset the branch and say so
explicitly. Do not leave it in the working tree — a worktree that is removed
takes uncommitted work with it, unrecoverably.

If you have already decided this state is correct and intend to leave it, say so
in your response and stop again; this hook does not fire twice in a row."

jq -cn --arg reason "$reason" '{decision:"block",reason:$reason}'
