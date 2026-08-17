

<!-- Source: .ruler/AGENTS.md -->

# Global Agent Instructions

These principles apply to ALL projects. Project-specific instruction files (CLAUDE.md, AGENTS.md) override or extend these.

## Output Language

- Report to the user only in ASD-STE100 Simplified Technical English.
- Use approved, simple words and short, direct sentences.
- Use one meaning for each word. Do not use idioms, slang, jokes, metaphors, or decorative language.
- Put one instruction or fact in each sentence when practical.
- Keep technical identifiers, code, commands, logs, quoted text, and required product terms exact. Explain them in Simplified Technical English.
- Do not change the technical accuracy or the necessary security terminology to make the text simpler.

## Environment & Preferences

- Primary OS: Ubuntu or Kali Linux (Debian-based)
- Shell: zsh with oh-my-zsh
- Primary use cases: security tooling, full-stack web development, infrastructure automation
- Shell scripts: bash (`#!/bin/bash` with `set -euo pipefail`)

## Mandatory Operating Rules

### Investigation and editing

- Before any investigation, state internally in one sentence what the user asks and which system, binary, or file the request concerns.
- If the request names a tool or command, run `zsh -lc 'which <tool>'` and read the resolved source or `<tool> --help` before you propose a cause. Do not guess.
- Read every file before you edit it. This rule is strict for test files.
- Diagnose an error from the actual response body, response headers, command output, logs, and current configuration. Do not assert a root cause without that evidence. Do not blame quota after the user says quota is available unless current provider evidence proves a quota error.

### Error handling and removals

- Hard-fail on every error. Do not add silent fallback paths, catches that swallow errors, success defaults, placeholder values, or “continue anyway” behavior.
- If a required file, key, binary, service, or configuration is missing, throw or exit nonzero with a clear message that names the exact item.
- When the user says to remove code or a TODO, delete it. Do not replace it with a pointer, explanatory comment, compatibility stub, or dead wrapper.

### Shell and project preflight

- Use `zsh -lc '...'` for commands that depend on the user's PATH, including `node`, `nvm`, `claude`, `codex`, and review tools. A Bash login shell does not represent the user's interactive PATH.
- If a project defines a preflight skill or command, every main session and subagent must run it before investigation or work. Any failure blocks work.

### Merge conflicts and review scope

- Never discard upstream or remote changes when you resolve a merge conflict. Integrate the intent of both sides.
- Before a conflict-resolution commit, show the user the final resolution for every conflicted hunk and explain how each side was preserved.
- When the user asks to fix review findings, fix every finding, including warnings. Do not declare a finding out of scope. Ask before you defer an item.

### Direct infrastructure access

- When SSH or API access exists for Home Assistant, homelab servers, Plex, Sonarr, Radarr, or GitLab, use that access to make and verify the requested change. Do not defer to manual UI steps.

## Debugging

When investigating issues, verify the actual infrastructure routing (e.g., Docker containers and networking, nginx, reverse proxies) BEFORE assuming the problem is in application code. Check how URLs are routed at the infrastructure level first.

When testing or debugging, focus on the actual reported symptom. Do not try random exploratory fixes — diagnose the root cause first, then apply a single targeted fix. Explain the underlying cause, then fix *that* — not the symptom. Target the real cause, not its surface effect: remove the duplicate compose file rather than just killing the stale container; rely on an existing flow's guarantee rather than adding a redundant guard.

When your own tooling breaks — e.g., the Bash tool returns exit code 1 or 2 with no output — STOP and diagnose the root cause before reaching for Serena MCP or other shell workarounds. A broken tool is itself a root-cause problem; working around it hides the failure instead of fixing it.

## Execution Style

Always execute commands directly. Never provide manual steps for the user to run unless the command is destructive, requires credentials you don't have, or affects systems outside the current machine. Defer to the user only for irreversible actions (e.g., `git push --force`). Do the work — don't describe the work.

Never ask "want me to fix it?" or "should I fix this?" — if there's a bug, error, warning, or test failure, fix it immediately. The answer is always yes. This applies to everything: code bugs, lint errors, type errors, test failures, compilation warnings. Just fix them.

## Asking Questions

Ask a clarifying question only when unresolved ambiguity would materially change the result and cannot be resolved from the repository, issue, prior user choices, or established project conventions. An explicit request to implement, build, fix, or change something authorizes in-scope execution; do not ask the user to approve that same work again.

- Ambiguous requirements or feature scope
- Unclear implementation approach (multiple reasonable options)
- Uncertainty about intended behavior or edge cases
- File placement, naming, or architectural decisions that aren't obvious
- Whether to add defensive checks, guards, or safety measures
- Whether to fix source code vs test assertions
- Anything where a wrong assumption would waste effort or produce the wrong result

Make repository-backed, reversible, in-scope decisions autonomously. Ask before destructive actions, meaningful scope expansion, or choices that remain genuinely blocking after investigation.

## Planning & Approach

For any task involving more than 2 file changes, outline the approach in numbered steps. If the user explicitly requested implementation, building, fixing, or changing, that request is approval to execute the plan; proceed without another approval checkpoint. Wait only when the user requested planning/review without implementation, a genuinely blocking product choice remains, or the next action is destructive or outside the authorized scope.

Before creating any plan, complete a codebase grounding phase. Do not skip this.

1. **Discovery** — Use Grep and Glob to find all files relevant to the area. List every file found.
2. **Fact extraction** — For each relevant file, read it and extract: exported functions/types with exact signatures, key business logic (status transitions, validation rules, enum values), existing abstractions and helpers, and current test coverage.
3. **Fact document** — Create a structured summary with sections: Existing Types & Interfaces, Current Behavior (with `file:line` citations), Existing Abstractions Available for Reuse, Current Test Coverage & Gaps. For explicit implementation requests, use this as an internal grounding artifact or concise progress update without pausing execution.
4. **Plan with citations** — Create the implementation plan from the fact document. Every assertion must include a `[file:line]` citation. Flag any assumption that cannot be verified with `UNVERIFIED`. For explicit implementation requests, begin execution immediately after the plan unless a blocking condition above applies.
5. **Diff preview** — For each planned change, show the specific before/after for affected lines so the user can validate behavioral correctness.

Stay focused on the stated goal. If you think work should extend beyond the original request, or if the goal is ambiguous, ask before acting — do not pursue tangential fixes, refactors, or improvements unprompted.

When continuing a multi-phase plan from a prior session, resume execution directly at the next incomplete chunk. Do NOT re-summarize prior work or ask clarifying questions unless you hit a genuine blocker.

## Code Style

- Use `.yml` extension (not `.yaml`) for YAML files unless the project already uses `.yaml`.
- Use dot notation for attribute access in Python. Do not use `getattr`/`setattr` patterns or `pyright: ignore`/`type: ignore` comments unless absolutely unavoidable for third-party library compatibility.
- For Python, use f-strings for string interpolation. Do not use `str.format()` or concatenation.

## Testing

When developing an API or web application, there should always be the most simple checks that each endpoint or page is responding at a basic level. For example, if you create a new API route, add a smoke test that hits the route and checks for a 200 response. This ensures the route is wired up correctly before adding more complex tests. Loading the homepage of a web app and checking for a 200 with no console errors is another example of a simple smoke test. For databases, ensure there is a test that can connect to the database and perform a simple query. These basic checks catch fundamental issues early.

### Test Coverage Requirements

Every code change must include appropriate test coverage:

- **Bug fixes**: Must include a regression test that reproduces the bug and verifies the fix. The test must fail without the fix and pass with it. A bug fix without a regression test is incomplete.
- **New features/functions**: Must include unit tests covering happy path, error paths, and edge cases. New public functions, components, routes, and handlers all require tests.
- **UI/frontend features**: Must include component render tests, user interaction tests (clicks, form submissions, keyboard), and conditional rendering tests. For multi-page workflows, consider E2E tests.
- **Integration points**: When adding new API integrations, database queries, or service-to-service communication, add integration tests that verify the interaction works end-to-end (mocking external services where necessary).

### Running Tests

Always run the full test suite after multi-file changes and before committing. Verify 0 failures. If tests fail, fix them before proceeding — do not commit with known failures.

## Static Analysis

For Python, run both Ruff and Pyright as part of the quality gate. Both must pass clean before claiming completion:
- `ruff check src/ tests/` — linting and style
- `pyright` (or project-specific type checker) — type checking
For other languages, use the applicable alternatives, such as tsx, etc.

Fix issues from both tools, not just one. If a project's instruction file (CLAUDE.md or AGENTS.md) specifies different commands (e.g., `uv run ruff`, `uv run pyright`), use those.

## Committing

Before committing, run the full validation pipeline: `pre-commit` hooks, Ruff, Pyright, and the test suite. Fix every failure before committing — including pre-existing config problems (e.g., a broken Ruff config) you hit along the way, not just failures you introduced. Then commit with logical grouping: split unrelated changes into separate commits rather than one mixed commit.

For a branch with an open pull request, end each commit subject with `(#<PR>)` and add `Refs #<PR>` in the body. Add `Sentry-Issue: <SENTRY-ID>` for Sentry work. Add `Refs #<issue>` for each related GitHub issue, or use a closing keyword only when the commit resolves it. Use the same references on merge commits. Do not invent references. Agent commit commands must not use `--no-verify` or `git commit -n`.

## Simplicity

Always prefer simple, minimal solutions first. Avoid over-engineering with unnecessary features like color output, complex abstractions, or multi-layered architectures unless explicitly requested. If you believe a more complex approach is genuinely needed, explain why BEFORE implementing it and let me decide.

## Safety / Dangerous Operations

Never modify shell config files (`.zshrc`, `.bashrc`, `.zshenv`) with `sed`. Use targeted `echo`/append or manual instructions instead. Always back up before any changes.

## Docker / Deployment

After modifying any code in Docker-deployed services, consider if a rebuild or restart is needed before testing. Check if the code is mounted in the container, if hot-reload is enabled, or if the change is system/Docker configuration requiring a rebuild. Don't rebuild out of caution or habit — ensure a rebuild is necessary.

## Memory Efficiency

Simple behavioral rules (one sentence) go directly in MEMORY.md as inline text — no backing file needed. Only create a separate `.md` file when the memory contains reference details (IPs, commands, multi-step procedures) that add value beyond the one-liner. Never create a whole markdown file with frontmatter for something that fits in a single line.

## Dotfiles Management

Config files are symlinked from `~/.dot_files` (a clone of the dot_files repo). Global configs go in `~/.dot_files/` at the correct relative path. Promote local files with `dotfiles promote <path>`. Per-host overrides use `.local` files (`.zshrc.local`, `.gitconfig.local`, etc.).
