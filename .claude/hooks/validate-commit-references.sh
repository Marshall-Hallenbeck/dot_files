#!/bin/bash
# Install and run native Git message hooks for agent-created commits.
# commit-msg validates normal commits. prepare-commit-msg adds references to
# sequencer commits because Git does not run commit-msg for cherry-pick/revert.
set -euo pipefail

MODE="agent"
WORKDIR="$PWD"
MESSAGE_FILE=""
MESSAGE=""
MESSAGE_SOURCE=""
CONTEXT_TTL_SECONDS=300
SCISSORS_MARKER="# ------------------------ >8 ------------------------"
PR_NUMBER="${COMMIT_REFERENCE_PR:-}"
SENTRY_ISSUES="${COMMIT_REFERENCE_SENTRY:-}"
GITHUB_ISSUES="${COMMIT_REFERENCE_ISSUES:-}"

if [ -n "${COMMIT_REFERENCE_PR+x}" ] ||
    [ -n "${COMMIT_REFERENCE_SENTRY+x}" ] ||
    [ -n "${COMMIT_REFERENCE_ISSUES+x}" ]; then
    CONTEXT_EXPLICIT=true
else
    CONTEXT_EXPLICIT=false
fi

run_preserved_hook() {
    local hook_name preserved_hook

    hook_name=$(basename "$0")
    case "$hook_name" in
        commit-msg|prepare-commit-msg|applypatch-msg)
            preserved_hook="$(dirname "$0")/$hook_name.reference-guard-previous"
            if [ -x "$preserved_hook" ]; then
                "$preserved_hook" "$@"
            fi
            ;;
    esac
}

deny() {
    local reason="$1"

    if [ "$MODE" = "commit-msg" ] ||
        [ "$MODE" = "prepare-commit-msg" ] ||
        [ "$MODE" = "applypatch-msg" ] ||
        [ "$MODE" = "install" ]; then
        printf 'Commit reference enforcement failed: %s\n' "$reason" >&2
        exit 1
    fi

    jq -n --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $reason
        }
    }'
    exit 0
}

parse_sentry_issues() {
    local input

    input=$(cat)
    {
        printf '%s\n' "$input" |
            grep -oE 'Sentry-Issue:[[:space:]]*[A-Z][A-Z0-9_-]*-[A-Z0-9]+' |
            sed -E 's/^Sentry-Issue:[[:space:]]*//' || true
        printf '%s\n' "$input" |
            grep -oE '\[[A-Z][A-Z0-9_-]*-[A-Z0-9]+\]\(https://[^)]*sentry\.io/issues/[^)]*\)' |
            sed -E 's/^\[([^]]+)\].*/\1/' || true
    } |
        sort -u |
        paste -sd ' ' - || true
}

parse_github_issues() {
    grep -oiE '(refs|closes|fixes|resolves)[[:space:]]+#[0-9]+' |
        grep -oE '#[0-9]+' |
        tr -d '#' |
        sort -u |
        paste -sd ' ' - || true
}

context_cache_is_fresh() {
    local branch="$1" checked_at now

    checked_at=$(git -C "$WORKDIR" config \
        --get "branch.$branch.referenceCheckedAt" 2>/dev/null || true)
    [[ "$checked_at" =~ ^[0-9]+$ ]] || return 1
    now=$(date +%s)
    [ $((now - checked_at)) -lt "$CONTEXT_TTL_SECONDS" ]
}

load_cached_context() {
    local branch="$1"

    [ -n "$PR_NUMBER" ] ||
        PR_NUMBER=$(git -C "$WORKDIR" config --get "branch.$branch.referencePr" 2>/dev/null || true)
    [ -n "$SENTRY_ISSUES" ] ||
        SENTRY_ISSUES=$(git -C "$WORKDIR" config --get "branch.$branch.sentryIssues" 2>/dev/null || true)
    [ -n "$GITHUB_ISSUES" ] ||
        GITHUB_ISSUES=$(git -C "$WORKDIR" config --get "branch.$branch.relatedIssues" 2>/dev/null || true)
}

refresh_context() {
    local branch="$1"
    local requested_head_ref="${2:-}"
    local upstream head_ref pr_json pr_body discovered_sentry discovered_issues
    local candidate
    local -a candidates=()

    command -v gh >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1

    upstream=$(git -C "$WORKDIR" for-each-ref \
        --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null || true)
    head_ref="$requested_head_ref"
    [ -n "$head_ref" ] || head_ref="$branch"
    [ -n "$head_ref" ] || return 0
    candidates+=("$head_ref")
    if [ "$branch" != "$head_ref" ]; then
        candidates+=("$branch")
    fi
    upstream="${upstream#*/}"
    if [ -n "$upstream" ] &&
        [ "$upstream" != "$head_ref" ] &&
        [ "$upstream" != "$branch" ]; then
        candidates+=("$upstream")
    fi

    PR_NUMBER=""
    pr_body=""
    for candidate in "${candidates[@]}"; do
        if ! pr_json=$(
            cd "$WORKDIR"
            gh pr list --state open --head "$candidate" --limit 1 \
                --json number,body 2>/dev/null
        ); then
            return 1
        fi
        printf '%s' "$pr_json" |
            jq -e 'type == "array"' >/dev/null 2>&1 || return 1
        PR_NUMBER=$(printf '%s' "$pr_json" | jq -r '.[0].number // empty')
        pr_body=$(printf '%s' "$pr_json" | jq -r '.[0].body // empty')
        [ -z "$PR_NUMBER" ] || break
    done

    git -C "$WORKDIR" config \
        "branch.$branch.referenceCheckedAt" "$(date +%s)"
    if [ -z "$PR_NUMBER" ]; then
        git -C "$WORKDIR" config --unset-all "branch.$branch.referencePr" 2>/dev/null || true
        git -C "$WORKDIR" config --unset-all "branch.$branch.sentryIssues" 2>/dev/null || true
        git -C "$WORKDIR" config --unset-all "branch.$branch.relatedIssues" 2>/dev/null || true
        SENTRY_ISSUES=""
        GITHUB_ISSUES=""
        return 0
    fi

    discovered_sentry=$(printf '%s\n' "$pr_body" | parse_sentry_issues)
    discovered_issues=$(printf '%s\n' "$pr_body" | parse_github_issues)
    discovered_issues=$(printf '%s\n' "$discovered_issues" |
        tr ' ' '\n' |
        grep -vx "$PR_NUMBER" |
        paste -sd ' ' - || true)

    git -C "$WORKDIR" config "branch.$branch.referencePr" "$PR_NUMBER"
    if [ -n "$discovered_sentry" ]; then
        git -C "$WORKDIR" config "branch.$branch.sentryIssues" "$discovered_sentry"
        SENTRY_ISSUES="$discovered_sentry"
    else
        git -C "$WORKDIR" config --unset-all "branch.$branch.sentryIssues" 2>/dev/null || true
        SENTRY_ISSUES=""
    fi
    if [ -n "$discovered_issues" ]; then
        git -C "$WORKDIR" config "branch.$branch.relatedIssues" "$discovered_issues"
        GITHUB_ISSUES="$discovered_issues"
    else
        git -C "$WORKDIR" config --unset-all "branch.$branch.relatedIssues" 2>/dev/null || true
        GITHUB_ISSUES=""
    fi
}

resolve_ref_context() {
    local object="$1"
    local ref branch head_ref remote

    while IFS= read -r ref; do
        case "$ref" in
            refs/heads/*)
                branch="${ref#refs/heads/}"
                head_ref="$branch"
                ;;
            refs/remotes/*)
                remote="${ref#refs/remotes/}"
                [[ "$remote" = */HEAD ]] && continue
                branch="${remote#*/}"
                head_ref="$branch"
                ;;
            *)
                continue
                ;;
        esac

        PR_NUMBER=""
        SENTRY_ISSUES=""
        GITHUB_ISSUES=""
        load_cached_context "$branch"
        if ! context_cache_is_fresh "$branch"; then
            refresh_context "$branch" "$head_ref" || true
            load_cached_context "$branch"
        fi
        if [ -n "$PR_NUMBER$SENTRY_ISSUES$GITHUB_ISSUES" ]; then
            return 0
        fi
    done < <(
        git -C "$WORKDIR" for-each-ref --format='%(refname)' \
            --points-at "$object" refs/heads refs/remotes
    )

    return 1
}

resolve_branch_context() {
    local branch="$1"
    local head_ref="${2:-}"

    PR_NUMBER=""
    SENTRY_ISSUES=""
    GITHUB_ISSUES=""
    load_cached_context "$branch"
    if ! context_cache_is_fresh "$branch"; then
        refresh_context "$branch" "$head_ref" || true
        load_cached_context "$branch"
    fi
    [ -n "$PR_NUMBER$SENTRY_ISSUES$GITHUB_ISSUES" ]
}

resolve_rebase_context() {
    local git_dir state_file head_name branch

    git_dir=$(git -C "$WORKDIR" rev-parse --absolute-git-dir 2>/dev/null || true)
    [ -n "$git_dir" ] || return 1
    for state_file in \
        "$git_dir/rebase-merge/head-name" \
        "$git_dir/rebase-apply/head-name"; do
        [ -f "$state_file" ] || continue
        head_name=$(<"$state_file")
        case "$head_name" in
            refs/heads/*)
                branch="${head_name#refs/heads/}"
                resolve_branch_context "$branch" "$branch" && return 0
                ;;
        esac
    done
    return 1
}

rebase_in_progress() {
    local git_dir

    git_dir=$(git -C "$WORKDIR" rev-parse --absolute-git-dir 2>/dev/null || true)
    [ -n "$git_dir" ] &&
        {
            [ -d "$git_dir/rebase-merge" ] ||
                [ -f "$git_dir/rebase-apply/rebasing" ]
        }
}

resolve_context() {
    local branch object object_ref

    $CONTEXT_EXPLICIT && return 0
    git -C "$WORKDIR" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
    branch=$(git -C "$WORKDIR" branch --show-current)
    if [ -z "$branch" ]; then
        if resolve_rebase_context; then
            return 0
        fi
        object=$(git -C "$WORKDIR" rev-parse -q --verify HEAD 2>/dev/null || true)
        if [ -n "$object" ]; then
            resolve_ref_context "$object" || true
        fi
        return 0
    fi

    if resolve_branch_context "$branch"; then
        return 0
    fi

    for object_ref in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
        object=$(git -C "$WORKDIR" rev-parse -q --verify "$object_ref" 2>/dev/null || true)
        if [ -n "$object" ] && resolve_ref_context "$object"; then
            return 0
        fi
    done
}

resolve_hook_path() {
    local hook_name="$1" git_path raw_hook_path hook_dir

    git_path=$(git -C "$WORKDIR" rev-parse --git-path "hooks/$hook_name")
    if [[ "$git_path" = /* ]]; then
        raw_hook_path="$git_path"
    else
        raw_hook_path="$WORKDIR/$git_path"
    fi
    hook_dir=$(dirname "$raw_hook_path")
    mkdir -p "$hook_dir"
    hook_dir=$(cd "$hook_dir" && pwd -P)
    printf '%s/%s\n' "$hook_dir" "$(basename "$raw_hook_path")"
}

install_hook() {
    local hook_name hook_path preserved_hook validator_path current_target branch
    local configured_hooks_path git_dir configured_hook external_hooks_valid
    local -a hook_names=(commit-msg prepare-commit-msg applypatch-msg)

    git -C "$WORKDIR" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
    validator_path=$(readlink -f "$0")
    configured_hooks_path=$(git -C "$WORKDIR" config --get core.hooksPath 2>/dev/null || true)
    if [ -n "$configured_hooks_path" ]; then
        git_dir=$(git -C "$WORKDIR" rev-parse --absolute-git-dir)
        configured_hook=$(git -C "$WORKDIR" rev-parse \
            --path-format=absolute --git-path hooks/commit-msg)
        case "$configured_hook" in
            "$git_dir"/*) ;;
            *)
                if [ "$MODE" = "agent" ]; then
                    external_hooks_valid=true
                    for hook_name in "${hook_names[@]}"; do
                        hook_path=$(resolve_hook_path "$hook_name")
                        if [ ! -L "$hook_path" ] ||
                            [ "$(readlink -f "$hook_path" || true)" != "$validator_path" ]; then
                            external_hooks_valid=false
                            break
                        fi
                    done
                    if $external_hooks_valid; then
                        return 0
                    fi
                    deny "The repository manages core.hooksPath outside Git metadata. Add commit-reference validation to its managed hooks."
                fi
                return 0
                ;;
        esac
    fi

    for hook_name in "${hook_names[@]}"; do
        hook_path=$(resolve_hook_path "$hook_name")
        preserved_hook="$hook_path.reference-guard-previous"
        if [ -L "$hook_path" ]; then
            current_target=$(readlink -f "$hook_path" || true)
            if [ "$current_target" != "$validator_path" ] &&
                { [ -e "$preserved_hook" ] || [ -L "$preserved_hook" ]; }; then
                deny "Cannot preserve $hook_name because the backup path exists: $preserved_hook"
            fi
        elif [ -e "$hook_path" ] &&
            { [ -e "$preserved_hook" ] || [ -L "$preserved_hook" ]; }; then
            deny "Cannot preserve $hook_name because the backup path exists: $preserved_hook"
        fi
    done

    for hook_name in "${hook_names[@]}"; do
        hook_path=$(resolve_hook_path "$hook_name")
        preserved_hook="$hook_path.reference-guard-previous"
        current_target=""
        if [ -L "$hook_path" ]; then
            current_target=$(readlink -f "$hook_path" || true)
        fi
        if [ "$current_target" = "$validator_path" ]; then
            continue
        fi
        if [ -e "$hook_path" ] || [ -L "$hook_path" ]; then
            mv "$hook_path" "$preserved_hook"
        fi
        if [ ! -e "$hook_path" ] && [ ! -L "$hook_path" ]; then
            ln -s "$validator_path" "$hook_path"
        fi
    done

    if ! $CONTEXT_EXPLICIT; then
        branch=$(git -C "$WORKDIR" branch --show-current)
        if [ -n "$branch" ]; then
            load_cached_context "$branch"
            if ! context_cache_is_fresh "$branch" &&
                ! refresh_context "$branch"; then
                load_cached_context "$branch"
            fi
        fi
    fi
}

line_exists() {
    local expected="$1" validation_message

    validation_message="${MESSAGE%%"$SCISSORS_MARKER"*}"
    grep -Fxq -- "$expected" <<<"$validation_message"
}

issue_reference_exists() {
    local issue_number="$1" keyword

    for keyword in Refs Closes Fixes Resolves; do
        if line_exists "$keyword #$issue_number"; then
            return 0
        fi
    done
    return 1
}

append_automatic_references() {
    local subject subject_reference temp_file references_file
    local issue_number sentry_id line
    local inserted=false

    if ! git -C "$WORKDIR" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 &&
        ! git -C "$WORKDIR" rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 &&
        ! git -C "$WORKDIR" rev-parse -q --verify REVERT_HEAD >/dev/null 2>&1 &&
        ! rebase_in_progress; then
        if [ "$MODE" != "prepare-commit-msg" ] ||
            [ "$MESSAGE_SOURCE" != "message" ] ||
            [[ "${MESSAGE%%$'\n'*}" != Revert\ \"* ]] ||
            ! grep -Eq '^This reverts commit [0-9a-f]{40}\.$' <<<"$MESSAGE"; then
            return 0
        fi
    fi

    subject="${MESSAGE%%$'\n'*}"

    subject_reference="$PR_NUMBER"
    if [ -z "$subject_reference" ]; then
        subject_reference="${GITHUB_ISSUES%% *}"
    fi

    if [ -n "$subject_reference" ] && [[ ! "$subject" =~ \(#${subject_reference}\)$ ]]; then
        subject="$subject (#$subject_reference)"
    fi

    references_file=$(mktemp "${MESSAGE_FILE}.references.XXXXXX")
    {
        if [ -n "$PR_NUMBER" ] && ! line_exists "Refs #$PR_NUMBER"; then
            printf 'Refs #%s\n' "$PR_NUMBER"
        fi
        for issue_number in $GITHUB_ISSUES; do
            if ! issue_reference_exists "$issue_number"; then
                printf 'Refs #%s\n' "$issue_number"
            fi
        done
        for sentry_id in $SENTRY_ISSUES; do
            if ! line_exists "Sentry-Issue: $sentry_id"; then
                printf 'Sentry-Issue: %s\n' "$sentry_id"
            fi
        done
    } >"$references_file"

    temp_file=$(mktemp "${MESSAGE_FILE}.codex.XXXXXX")
    {
        printf '%s\n' "$subject"
        while IFS= read -r line || [ -n "$line" ]; do
            if ! $inserted && [ "$line" = "$SCISSORS_MARKER" ]; then
                if [ -s "$references_file" ]; then
                    printf '\n'
                    cat "$references_file"
                    printf '\n'
                fi
                inserted=true
            fi
            printf '%s\n' "$line"
        done < <(tail -n +2 "$MESSAGE_FILE")
        if ! $inserted && [ -s "$references_file" ]; then
            printf '\n'
            cat "$references_file"
        fi
    } >"$temp_file"
    rm "$references_file"
    mv "$temp_file" "$MESSAGE_FILE"
    MESSAGE=$(<"$MESSAGE_FILE")
}

analyze_shell_command() {
    local command_text="$1"

    python3 - "$WORKDIR" 3<<<"$command_text" <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys

initial_cwd = os.path.abspath(sys.argv[1])
command_text = os.fdopen(3).read()
result = {
    "mutation": False,
    "nestedShellMutation": False,
    "noVerify": False,
    "referenceOverride": False,
    "unsafeOverride": False,
    "targets": [],
}

def strip_heredoc_bodies(text):
    def skip_quoted(line, index, quote):
        index += 1
        while index < len(line):
            if quote == '"' and line[index] == "\\" and index + 1 < len(line):
                index += 2
                continue
            if line[index] == quote:
                return index + 1
            index += 1
        return index

    def skip_arithmetic(line, index, opening_length):
        depth = 2
        index += opening_length
        while index < len(line) and depth > 0:
            if line[index] in {"'", '"'}:
                index = skip_quoted(line, index, line[index])
                continue
            if line[index] == "\\" and index + 1 < len(line):
                index += 2
                continue
            if line[index] == "(":
                depth += 1
            elif line[index] == ")":
                depth -= 1
            index += 1
        return index

    def find_heredocs(line):
        found = []
        index = 0

        while index < len(line):
            character = line[index]
            if character in {"'", '"'}:
                index = skip_quoted(line, index, character)
                continue
            if character == "\\" and index + 1 < len(line):
                index += 2
                continue
            if line.startswith("$((", index):
                index = skip_arithmetic(line, index, 3)
                continue
            if line.startswith("((", index):
                index = skip_arithmetic(line, index, 2)
                continue
            if character == "#" and (
                index == 0 or line[index - 1].isspace() or line[index - 1] in ";&|()"
            ):
                break
            if line.startswith("<<<", index):
                index += 3
                continue
            if not line.startswith("<<", index):
                index += 1
                continue

            word_index = index + 2
            strip_tabs = False
            if word_index < len(line) and line[word_index] == "-":
                strip_tabs = True
                word_index += 1
            while word_index < len(line) and line[word_index] in " \t":
                word_index += 1

            delimiter = []
            word_started = False
            while (
                word_index < len(line)
                and not line[word_index].isspace()
                and line[word_index] not in ";&|()<>"
            ):
                word_started = True
                if line[word_index] in {"'", '"'}:
                    quote = line[word_index]
                    end = skip_quoted(line, word_index, quote)
                    delimiter.append(line[word_index + 1 : max(word_index + 1, end - 1)])
                    word_index = end
                    continue
                if line[word_index] == "\\" and word_index + 1 < len(line):
                    delimiter.append(line[word_index + 1])
                    word_index += 2
                    continue
                delimiter.append(line[word_index])
                word_index += 1

            if word_started:
                found.append(("".join(delimiter), strip_tabs))
            index = max(word_index, index + 2)

        return found

    def mask_arithmetic(line):
        characters = list(line)
        index = 0

        while index < len(line):
            character = line[index]
            if character in {"'", '"'}:
                index = skip_quoted(line, index, character)
                continue
            if character == "\\" and index + 1 < len(line):
                index += 2
                continue
            if line.startswith("$((", index):
                end = skip_arithmetic(line, index, 3)
            elif line.startswith("((", index):
                end = skip_arithmetic(line, index, 2)
            else:
                index += 1
                continue
            for position in range(index, end):
                if characters[position] not in "\r\n":
                    characters[position] = " "
            index = end

        return "".join(characters)

    output = []
    pending = []

    for line in text.splitlines(keepends=True):
        if pending:
            delimiter, strip_tabs = pending[0]
            candidate = line.rstrip("\r\n")
            if strip_tabs:
                candidate = candidate.lstrip("\t")
            if candidate == delimiter:
                pending.pop(0)
            if line.endswith(("\n", "\r")):
                output.append("\n")
            continue

        masked_line = mask_arithmetic(line)
        output.append(masked_line)
        pending.extend(find_heredocs(masked_line))

    return "".join(output)

command_text = strip_heredoc_bodies(command_text)

try:
    lexer = shlex.shlex(command_text, posix=True, punctuation_chars=";&|()\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    tokens = list(lexer)
except ValueError:
    result["parseError"] = True
    print(json.dumps(result))
    raise SystemExit

segments = []
segment = []
scope_stack = [0]
scope_parents = {0: None}
next_scope = 1
for token in tokens:
    if token and all(character in ";&|()\n" for character in token):
        if segment:
            segments.append((segment, scope_stack[-1]))
            segment = []
        for character in token:
            if character == "(":
                scope_parents[next_scope] = scope_stack[-1]
                scope_stack.append(next_scope)
                next_scope += 1
            elif character == ")" and len(scope_stack) > 1:
                scope_stack.pop()
    else:
        segment.append(token)
if segment:
    segments.append((segment, scope_stack[-1]))

scope_cwds = {0: initial_cwd}
scope_unsafe = {0: False}
mutations = {"commit", "merge", "cherry-pick", "revert", "am", "rebase", "pull"}
assignment = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
git_mutation = re.compile(
    r"(?<![A-Za-z0-9_])git(?:[^A-Za-z0-9_]|$).*?\b"
    r"(?:commit|merge|cherry-pick|revert|am|rebase|pull)\b"
    r"|prepare-merge-ready-pr\.sh",
    re.DOTALL,
)

def commit_uses_short_no_verify(arguments):
    for argument in arguments:
        if not re.fullmatch(r"-[^-]+", argument):
            continue
        for option in argument[1:]:
            if option == "n":
                return True
            if option in "CcFmtSu":
                break
    return False

def commit_uses_long_no_verify(arguments):
    return any(
        argument == "--no-verify"
        or (
            len(argument) >= len("--no-veri")
            and "--no-verify".startswith(argument)
        )
        for argument in arguments
    )

def expand_git_alias(target, subcommand, arguments):
    seen = set()

    while subcommand not in mutations:
        if subcommand in seen:
            break
        seen.add(subcommand)
        try:
            completed = subprocess.run(
                ["git", "-C", target, "config", "--get", f"alias.{subcommand}"],
                check=False,
                capture_output=True,
                text=True,
            )
        except OSError:
            break
        if completed.returncode != 0:
            break

        alias_value = completed.stdout.rstrip("\r\n")
        if alias_value.startswith("!"):
            if git_mutation.search(alias_value):
                return subcommand, arguments, True
            break
        try:
            alias_words = shlex.split(alias_value)
        except ValueError:
            break
        if not alias_words:
            break
        subcommand = alias_words[0]
        arguments = alias_words[1:] + arguments

    return subcommand, arguments, False

def initialize_scope(scope):
    if scope in scope_cwds:
        return
    parent_scope = scope_parents[scope]
    initialize_scope(parent_scope)
    scope_cwds[scope] = scope_cwds[parent_scope]
    scope_unsafe[scope] = scope_unsafe[parent_scope]

for words, scope in segments:
    initialize_scope(scope)
    cwd = scope_cwds[scope]
    cwd_unsafe = scope_unsafe[scope]
    index = 0
    unsafe_environment = False
    while index < len(words) and assignment.match(words[index]):
        name = words[index].split("=", 1)[0]
        if name in {"GIT_DIR", "GIT_WORK_TREE"} or name.startswith("GIT_CONFIG_"):
            unsafe_environment = True
        if name.startswith("COMMIT_REFERENCE_"):
            result["referenceOverride"] = True
        index += 1

    while index < len(words):
        wrapper = os.path.basename(words[index])
        if wrapper in {"builtin", "command"}:
            index += 1
            while index < len(words) and words[index].startswith("-"):
                index += 1
            continue
        if wrapper == "env":
            index += 1
            while index < len(words):
                token = words[index]
                if token == "--":
                    index += 1
                    break
                if assignment.match(token):
                    name = token.split("=", 1)[0]
                    if name in {"GIT_DIR", "GIT_WORK_TREE"} or name.startswith("GIT_CONFIG_"):
                        unsafe_environment = True
                    if name.startswith("COMMIT_REFERENCE_"):
                        result["referenceOverride"] = True
                    index += 1
                    continue
                if token in {"-C", "--chdir"} and index + 1 < len(words):
                    index += 1
                    target = os.path.expanduser(words[index])
                    cwd_unsafe = cwd_unsafe or "$" in target or "`" in target
                    cwd = os.path.abspath(os.path.join(cwd, target))
                    index += 1
                    continue
                if token.startswith("--chdir="):
                    target = os.path.expanduser(token.split("=", 1)[1])
                    cwd_unsafe = cwd_unsafe or "$" in target or "`" in target
                    cwd = os.path.abspath(os.path.join(cwd, target))
                    index += 1
                    continue
                if token.startswith("-C") and token != "-C":
                    target = os.path.expanduser(token[2:])
                    cwd_unsafe = cwd_unsafe or "$" in target or "`" in target
                    cwd = os.path.abspath(os.path.join(cwd, target))
                    index += 1
                    continue
                if token in {"-u", "--unset"} and index + 1 < len(words):
                    name = words[index + 1]
                    if name.startswith("COMMIT_REFERENCE_"):
                        result["referenceOverride"] = True
                    index += 2
                    continue
                if token.startswith("--unset="):
                    name = token.split("=", 1)[1]
                    if name.startswith("COMMIT_REFERENCE_"):
                        result["referenceOverride"] = True
                    index += 1
                    continue
                if token == "--argv0" and index + 1 < len(words):
                    index += 2
                    continue
                if token.startswith("--argv0="):
                    index += 1
                    continue
                if token in {"-S", "--split-string"} and index + 1 < len(words):
                    split_words = shlex.split(words[index + 1])
                    words[index : index + 2] = split_words
                    continue
                if token.startswith("--split-string="):
                    split_words = shlex.split(token.split("=", 1)[1])
                    words[index : index + 1] = split_words
                    continue
                if token.startswith("-S") and token != "-S":
                    split_words = shlex.split(token[2:])
                    words[index : index + 1] = split_words
                    continue
                if token.startswith("-"):
                    index += 1
                    continue
                break
            continue
        if wrapper == "sudo":
            index += 1
            options_with_values = {
                "-C", "--chdir", "-D", "--close-from", "-g", "--group",
                "-h", "--host", "-p", "--prompt", "-R", "--chroot",
                "-T", "--command-timeout", "-u", "--user",
            }
            while index < len(words):
                token = words[index]
                if token == "--":
                    index += 1
                    break
                if assignment.match(token):
                    name = token.split("=", 1)[0]
                    if name.startswith("COMMIT_REFERENCE_"):
                        result["referenceOverride"] = True
                    if name in {"GIT_DIR", "GIT_WORK_TREE"} or name.startswith("GIT_CONFIG_"):
                        unsafe_environment = True
                    index += 1
                    continue
                if token in options_with_values and index + 1 < len(words):
                    index += 2
                    continue
                if token.startswith("-"):
                    index += 1
                    continue
                break
            continue
        if wrapper == "nice":
            index += 1
            while index < len(words) and words[index].startswith("-"):
                if words[index] in {"-n", "--adjustment"} and index + 1 < len(words):
                    index += 2
                else:
                    index += 1
            continue
        if wrapper == "timeout":
            index += 1
            while index < len(words) and words[index].startswith("-"):
                if words[index] in {"-k", "--kill-after", "-s", "--signal"} and index + 1 < len(words):
                    index += 2
                else:
                    index += 1
            if index < len(words):
                index += 1
            continue
        if wrapper in {"nohup", "time"}:
            index += 1
            while index < len(words) and words[index].startswith("-"):
                index += 1
            continue
        break

    if index >= len(words):
        continue

    executable = os.path.basename(words[index])
    if executable in {"export", "unset"}:
        for token in words[index + 1 :]:
            name = token.split("=", 1)[0]
            if name.startswith("COMMIT_REFERENCE_"):
                result["referenceOverride"] = True
        continue
    if executable == "cd":
        index += 1
        if index < len(words) and words[index] == "--":
            index += 1
        if index < len(words):
            target = os.path.expanduser(words[index])
            scope_unsafe[scope] = (
                target == "-" or "$" in target or "`" in target
            )
            scope_cwds[scope] = os.path.abspath(os.path.join(cwd, target))
        else:
            scope_unsafe[scope] = True
        continue
    if executable in {"popd", "pushd"}:
        scope_unsafe[scope] = True
        continue

    if executable == "eval":
        nested_command = " ".join(words[index + 1 :])
        if git_mutation.search(nested_command):
            result["nestedShellMutation"] = True
        continue

    if executable in {"bash", "dash", "sh", "zsh"}:
        shell_arguments = words[index + 1 :]
        nested_command = None
        for argument_index, argument in enumerate(shell_arguments):
            if argument == "-c" or (
                re.fullmatch(r"-[A-Za-z]+", argument)
                and "c" in argument[1:]
            ):
                if argument_index + 1 < len(shell_arguments):
                    nested_command = shell_arguments[argument_index + 1]
                break
            if not argument.startswith("-"):
                break
        if nested_command and git_mutation.search(nested_command):
            result["nestedShellMutation"] = True
        continue

    if executable == "prepare-merge-ready-pr.sh":
        result["mutation"] = True
        if cwd not in result["targets"]:
            result["targets"].append(cwd)
        continue
    if executable != "git":
        continue

    index += 1
    target = cwd
    unsafe_override = unsafe_environment or cwd_unsafe
    while index < len(words):
        token = words[index]
        if token == "-C" and index + 1 < len(words):
            index += 1
            target_argument = os.path.expanduser(words[index])
            unsafe_override = unsafe_override or "$" in target_argument or "`" in target_argument
            target = os.path.abspath(os.path.join(target, target_argument))
        elif token.startswith("-C") and token != "-C":
            target_argument = os.path.expanduser(token[2:])
            unsafe_override = unsafe_override or "$" in target_argument or "`" in target_argument
            target = os.path.abspath(os.path.join(target, target_argument))
        elif token == "-c" and index + 1 < len(words):
            index += 1
            if words[index].split("=", 1)[0].lower() == "core.hookspath":
                unsafe_override = True
        elif token.startswith("-c") and token != "-c":
            if token[2:].split("=", 1)[0].lower() == "core.hookspath":
                unsafe_override = True
        elif token == "--config-env" and index + 1 < len(words):
            index += 1
            if words[index].split("=", 1)[0].lower() == "core.hookspath":
                unsafe_override = True
        elif token.startswith("--config-env="):
            if token.removeprefix("--config-env=").split("=", 1)[0].lower() == "core.hookspath":
                unsafe_override = True
        elif token in {"--git-dir", "--work-tree"}:
            unsafe_override = True
            index += 1
        elif token.startswith("--git-dir=") or token.startswith("--work-tree="):
            unsafe_override = True
        elif token.startswith("-"):
            pass
        else:
            break
        index += 1

    if index >= len(words):
        continue

    subcommand = words[index]
    arguments = words[index + 1 :]
    subcommand, arguments, shell_alias_mutation = expand_git_alias(
        target, subcommand, arguments
    )
    if shell_alias_mutation:
        result["nestedShellMutation"] = True
        continue
    if subcommand not in mutations:
        continue
    if subcommand in {"merge", "pull"} and "--ff-only" in arguments:
        continue
    if subcommand in {"merge", "cherry-pick", "revert", "am", "rebase"} and any(
        argument in {"--abort", "--quit"} for argument in arguments
    ):
        continue
    result["mutation"] = True
    result["unsafeOverride"] = result["unsafeOverride"] or unsafe_override
    result["noVerify"] = (
        result["noVerify"] or commit_uses_long_no_verify(arguments)
    )
    if subcommand == "commit" and commit_uses_short_no_verify(arguments):
        result["noVerify"] = True
    if target not in result["targets"]:
        result["targets"].append(target)

print(json.dumps(result))
PY
}

contains_nested_git_mutation() {
    local command_text="$1"

    grep -zEq \
        'git([^[:alnum:]_]|$).*(commit|merge|cherry-pick|revert|am|rebase|pull)([^[:alnum:]_]|$)|prepare-merge-ready-pr\.sh' \
        <<<"$command_text"
}

if [ "${1:-}" = "--install" ]; then
    MODE="install"
    if [ -n "${2:-}" ]; then
        WORKDIR="$2"
    else
        input=$(cat || true)
        WORKDIR=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
        [ -n "$WORKDIR" ] || WORKDIR="$PWD"
    fi
    install_hook
    exit 0
fi

run_preserved_hook "$@"

if [ "$#" -gt 0 ]; then
    if [ "$(basename "$0")" = "prepare-commit-msg" ]; then
        MODE="prepare-commit-msg"
    elif [ "$(basename "$0")" = "applypatch-msg" ]; then
        MODE="applypatch-msg"
    else
        MODE="commit-msg"
    fi
    MESSAGE_FILE="$1"
    MESSAGE_SOURCE="${2:-}"
    [ -f "$MESSAGE_FILE" ] || deny "The commit message file does not exist: $MESSAGE_FILE"
    MESSAGE=$(<"$MESSAGE_FILE")
else
    command -v jq >/dev/null 2>&1 || deny "jq is required."
    input=$(cat)
    tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
    command_text=$(printf '%s' "$input" | jq -r '
        if (.tool_input | type) == "string" then
            .tool_input
        else
            .tool_input.command // .tool_input.cmd // .tool_input.code // empty
        end
    ')
    WORKDIR=$(printf '%s' "$input" | jq -r '
        if (.tool_input | type) == "object" then
            .tool_input.workdir // .tool_input.cwd // .cwd // empty
        else
            .cwd // empty
        end
    ')
    [ -n "$WORKDIR" ] || WORKDIR="$PWD"

    if [[ "$tool_name" =~ ^functions\.exec$ ]] &&
        contains_nested_git_mutation "$command_text"; then
        deny "Run Git mutation commands through a direct shell tool so commit references can be enforced."
    fi
    command -v python3 >/dev/null 2>&1 || deny "python3 is required."
    command_analysis=$(analyze_shell_command "$command_text")
    if [ "$(printf '%s' "$command_analysis" | jq -r '.parseError // false')" = "true" ]; then
        if contains_nested_git_mutation "$command_text"; then
            deny "The shell command cannot be parsed safely for Git mutation enforcement."
        fi
        exit 0
    fi
    if [ "$(printf '%s' "$command_analysis" | jq -r '.nestedShellMutation // false')" = "true" ]; then
        deny "Run Git mutation commands directly instead of through a nested shell."
    fi
    if [ "$(printf '%s' "$command_analysis" | jq -r '.mutation')" != "true" ]; then
        exit 0
    fi
    if [ "$(printf '%s' "$command_analysis" | jq -r '.referenceOverride // false')" = "true" ]; then
        deny "Agent Git mutation commands must not override commit-reference context."
    fi
    if [ "$(printf '%s' "$command_analysis" | jq -r '.unsafeOverride')" = "true" ]; then
        deny "Agent Git mutation commands must not override Git hook or repository paths."
    fi
    if [ "$(printf '%s' "$command_analysis" | jq -r '.noVerify')" = "true" ]; then
        deny "Agent Git mutation commands must not use --no-verify or git commit -n."
    fi
    while IFS= read -r target_workdir; do
        [ -n "$target_workdir" ] || continue
        WORKDIR="$target_workdir"
        install_hook
    done < <(printf '%s' "$command_analysis" | jq -r '.targets[]')
    exit 0
fi

resolve_context
[ -n "$PR_NUMBER$SENTRY_ISSUES$GITHUB_ISSUES" ] || exit 0

append_automatic_references

if [ "$MODE" = "prepare-commit-msg" ] &&
    [ "$MESSAGE_SOURCE" != "message" ] &&
    [ "$MESSAGE_SOURCE" != "commit" ]; then
    exit 0
fi

missing=()
subject="${MESSAGE%%$'\n'*}"
subject_reference="$PR_NUMBER"
[ -n "$subject_reference" ] || subject_reference="${GITHUB_ISSUES%% *}"

if [ -n "$subject_reference" ] && [[ ! "$subject" =~ \(#${subject_reference}\)$ ]]; then
    missing+=("subject suffix (#$subject_reference)")
fi
if [ -n "$PR_NUMBER" ] && ! line_exists "Refs #$PR_NUMBER"; then
    missing+=("Refs #$PR_NUMBER")
fi
for sentry_id in $SENTRY_ISSUES; do
    if ! line_exists "Sentry-Issue: $sentry_id"; then
        missing+=("Sentry-Issue: $sentry_id")
    fi
done
for issue_number in $GITHUB_ISSUES; do
    if ! issue_reference_exists "$issue_number"; then
        missing+=("Refs #$issue_number")
    fi
done

if [ "${#missing[@]}" -gt 0 ]; then
    required=$(printf '%s, ' "${missing[@]}")
    required="${required%, }"
    deny "The commit message requires: $required."
fi
