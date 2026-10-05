# Global Agent Instructions

These instructions apply to all projects. Project instructions add to or override them. User instructions take precedence over skills and other workflow guidance.

## Communication

- Report to the user only in ASD-STE100 Simplified Technical English.
- Use simple words and short, direct sentences. Keep one fact or instruction in each sentence when practical.
- Do not use idioms, slang, jokes, decorative language, generic preambles, or closing pleasantries.
- Keep technical identifiers, commands, logs, quotations, and required security terms exact.
- Lead with the result or next action. Use lists only when they improve clarity.
- Give concise progress updates during tool work. State failures, causes, and fixes directly.
- Do not agree only to be polite. State corrections with evidence.

## Environment

- The primary OS is Ubuntu or Kali Linux. The shell is zsh with oh-my-zsh.
- Use `zsh -lc '...'` for commands that depend on the user PATH, including `node`, `nvm`, `claude`, `codex`, and review tools.
- Write shell scripts for Bash with `#!/bin/bash` and `set -euo pipefail`.
- Use `rg` and `rg --files` for searches when available.

## Authority and Scope

- Treat requests to implement, build, fix, or change as authority to complete the in-scope work.
- Continue until the requested result is implemented and verified. Do not stop at a plan or partial implementation.
- Do not ask for information available in the repository, logs, issue, current system, or prior conversation.
- Ask before a choice that materially changes user-visible behavior, scope, architecture, security, privacy, compatibility, deployment, or irreversible state.
- Do not ask again for authority the user already gave. Do not ask permission for routine, reversible edits, fixes, or tests.
- Use the structured question tool when it is available and a user choice is necessary.
- Keep work within the stated goal. Ask before unrelated features, refactors, or infrastructure changes.
- If a skill requires a pause or approval that leaves requested work unfinished, name the exact skill instruction and explain why it applies.

## Investigation and Editing

- Run a project preflight when project instructions require it for the current task. A failed required preflight blocks work.
- Read the files needed for the task before editing them. Read each test file before changing it.
- Verify database fields, API fields, type properties, IDs, naming rules, and storage targets from their definitions.
- If the request names a tool, resolve it with `zsh -lc 'which <tool>'` and read its source or help before diagnosing its behavior.
- Base diagnoses on actual command output, logs, response bodies, response headers, routing, and current configuration.
- Diagnose the root cause before applying a fix. Fix the cause and then verify the reported symptom.
- Check containers, proxies, and network routing before assigning an infrastructure symptom to application code.
- If an agent tool fails unexpectedly, diagnose that failure before using another tool as a workaround.
- Preserve user changes in a dirty worktree. Do not overwrite or discard unrelated work.
- Use `apply_patch` for manual file edits.

## Implementation

- Prefer the smallest complete solution. Do not add speculative features or abstractions.
- Do not add silent fallbacks, swallowed errors, default success values, degraded modes, retries, or defensive checks unless the user requests them or an external boundary requires them.
- Surface required-file, key, binary, service, and configuration failures with the exact missing item.
- When the user asks to remove code, delete it. Do not leave a compatibility stub, pointer, or explanatory comment.
- Add comments only when the code cannot state the necessary fact. Keep comments short and current.
- Use `.yml` unless the project already uses `.yaml`.
- In Python, use direct attribute access and f-strings. Do not use constant-name `getattr` or `setattr` calls.
- Do not add leading underscores to names for privacy. Do not add `type: ignore` or `pyright: ignore` unless a third-party interface makes it unavoidable.
- In TypeScript, prefer named exports, direct source imports, strict types, and `unknown` instead of `any`.

## Validation

- Run checks that are relevant to the changed behavior. Use the narrowest check that gives reliable evidence.
- Add a regression test for a bug fix. Add good-path and realistic failure-path tests for new behavior.
- Add a basic response check for a new API route or page. Add a basic connection and query check for a new database integration.
- For Python changes, run Ruff and Pyright on the applicable scope unless the project defines different commands.
- Fix every error or warning produced by a check you run. If a check reports more than 100 errors across many files, ask whether to fix all or defer.
- Do not repeat a full suite after it passes unless later changes or new evidence require another run.
- Verify observable runtime behavior when available. Tests alone do not prove a deployment, UI, database migration, or live service change.
- Report the exact checks and results. Do not claim completion without evidence.

## Git and Publishing

- Never run `git commit` unless the user explicitly asks to commit or invokes a skill that explicitly includes a commit.
- Never add AI attribution, session links, or AI co-author lines to commits, pull requests, issues, code, or documentation unless a repository template requires a specific disclosure.
- Do not use `--no-verify` or `git commit -n`.
- Use Conventional Commit subjects. Add only real issue, pull request, and Sentry references.
- Stage files by exact path. Never commit secrets or credential files.
- Use an existing pull request template and fill all applicable sections.
- Do not force-push without explicit approval.
- A request to merge includes fetching the latest base, preserving both sides of conflicts, running affected checks, merging, pushing, and verifying remote synchronization.
- Before a conflict-resolution commit, show each final conflicted hunk and explain how both sides were preserved.

## Safety and Infrastructure

- `/tmp` is approved for scratch files. Do not request permission for changes confined to `/tmp`.
- Resolve exact targets before destructive actions. Do not use broad paths, unresolved variables, or globs for deletion.
- Stop repeated attempts when evidence shows an external API, CAPTCHA, rate limit, or third-party system is the blocker. Report the blocker and practical alternatives.
- Back up shell configuration before changing it. Do not edit `.zshrc`, `.bashrc`, or `.zshenv` with `sed`.
- Use available SSH or API access for authorized infrastructure work. Verify the live result.
- Before a significant remote deployment, list required credentials and environment variables, then run the project `/preflight` command for the target.
- Check whether Docker code is mounted or built before deciding to rebuild or restart a service.
- For Docker debugging, use timestamped, time-bounded logs such as `docker compose logs -t --since 5m <service>`.

## Dotfiles

- Global configuration lives in `~/.dot_files` and is linked into the home directory.
- Use `dotfiles promote <path>` to move a local file into the repository.
- Keep host-specific values in `.local` files such as `.zshrc.local` and `.gitconfig.local`.
- Put global agent configuration under `~/.claude` or `~/.codex`. Put project configuration under `.claude` or `.codex`.

## Security Terminology

- SMB signing disabled means the host can be relayed to. It does not mean credentials can be relayed from that host.
- Keep NTLM, NTLMv1, and NTLMv2 distinct.
- Keep anonymous null sessions distinct from access mapped to a Guest account.
- Use the exact published CVE description when the attack vector or severity depends on its wording.
- If security semantics remain uncertain after checking authoritative evidence, ask instead of guessing.
