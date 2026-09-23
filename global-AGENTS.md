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
- Never explain why something was removed in comments, if it's gone, it's gone.

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

Always execute commands directly. Never provide manual steps for the user to run unless the command is destructive, requires credentials you don't have, or affects systems outside the current machine. Defer to the user only for irreversible actions (e.g., `git push --force`). Do the work, don't describe the work.

Never ask "want me to fix it?" or "should I fix this?" — if there's a bug, error, warning, or test failure, fix it immediately. The answer is always yes. This applies to everything: code bugs, lint errors, type errors, test failures, compilation warnings. Just fix them.

## Asking Questions

Use a collaborative decision style for requirements and design. Do not silently select between multiple reasonable outcomes when the choice affects the user.

Ask before implementation when a decision affects:

- User-visible behavior or UX
- Feature scope or acceptance criteria
- API contracts, data models, or architecture
- Security, permissions, privacy, or destructive operations
- Compatibility, migration, or deployment behavior
- Error behavior or important edge cases
- A trade-off where two or more options are reasonable

Ask even when one option is recommended. Mark the recommended option and briefly state why it is recommended.

When the runtime provides a structured question tool, use it instead of asking the question in plain text:

- Claude Code: `AskUserQuestion`
- Codex: `request_user_input`
- ChatGPT: the native structured-choice interface, when available

Group related questions into one tool call. Give two to four distinct options. State the practical consequence of each option. Use multi-select only when the choices are independent.

Do not ask for:

- Information available from the repository, issue, logs, or current system
- Approval for work the user already explicitly requested
- Trivial, reversible implementation details with one conventional answer
- Permission to fix an in-scope bug, warning, or failed test

An explicit request to implement, build, fix, or change something authorizes in-scope execution. Approval of both a design and its implementation plan authorizes immediate implementation. Do not ask the user to approve the same work again.

If the session is non-interactive, do not pretend that a question tool is available. For a reversible choice, use the recommended option and state the assumption. For a consequential or irreversible choice, stop and return `NEEDS_USER_INPUT` with the available options.

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

Set parallel validation from current host resources. Calculate `parallel_limit` as `max(1, min(4, floor(MemAvailableGiB / 4), floor((logical_cpu_count - ceil(load_average_1m)) / 2)))`. Recalculate it before each new command. Use the limit only for independent unit tests, lint checks, and type checks. Force the limit to 1 when commands share mutable state or when a project wrapper classifies a job as heavy. Do not stop an active command only because the limit later decreases.

### Test Coverage Requirements

Every code change must include appropriate test coverage:

- **Bug fixes**: Must include a regression test that reproduces the bug and verifies the fix. The test must fail without the fix and pass with it. A bug fix without a regression test is incomplete.
- **New features/functions**: Must include unit tests covering known good paths, error paths, and realistic edge cases. Start with good paths, then add error paths, and only add edge cases if they are likely to happen. New public functions, components, routes, and handlers all require tests.
- **UI/frontend features**: Must include component render tests, user interaction tests (clicks, form submissions, keyboard), and conditional rendering tests. For multi-page workflows, consider E2E tests.
- **Integration points**: When adding new API integrations, database queries, or service-to-service communication, add integration tests that verify the interaction works end-to-end (mocking external services where necessary). Consider if data needs to exist in the database before running e2e tests, and add it via direct queries if necessary.

### Running Tests

Always run the tests related to the files you've changed before committing unless told otherwise. Verify 0 failures. If tests fail, fix them before proceeding — do not commit with known failures.

## Static Analysis

For Python, run both Ruff and Pyright as part of the quality gate. Both must pass clean before claiming completion:
- `ruff check src/ tests/` — linting and style
- `pyright` (or project-specific type checker) — type checking
For other languages, use the applicable alternatives, such as tsx, etc.

Fix issues from both tools, not just one. If a project's instruction file (CLAUDE.md or AGENTS.md) specifies different commands (e.g., `uv run ruff`, `uv run pyright`), use those.

## Committing

Before committing, run the full validation pipeline: `pre-commit` hooks, Ruff, Pyright, and the relevant test suites, if applicable. If a change will affect the entire application or program, you can run a holistic test suite run, otherwise, just focus on running applicable tests to what was changed. Fix every failure before committing — including pre-existing config problems (e.g., a broken Ruff config) you hit along the way, not just failures you introduced. Then commit with logical grouping: split unrelated changes into separate commits rather than one mixed commit.

For a branch with an open pull request, end each commit subject with `(#<PR>)` and add `Refs #<PR>` in the body. Add `Sentry-Issue: <SENTRY-ID>` for Sentry work. Add `Refs #<issue>` for each related GitHub issue, or use a closing keyword only when the commit resolves it. Use the same references on merge commits. Do not invent references. Agent commit commands must not use `--no-verify` or `git commit -n`.

## Simplicity

Always prefer simple, minimal solutions first. Avoid over-engineering with unnecessary features like color output, complex abstractions, or multi-layered architectures unless explicitly requested. If you believe a more complex approach is genuinely needed, explain why BEFORE implementing it and let me decide.

## Safety / Dangerous Operations

`/tmp` is an approved scratch area. Do not ask for permission to create,
change, or delete content when every changed path stays below `/tmp`.

Never modify shell config files (`.zshrc`, `.bashrc`, `.zshenv`) with `sed`. Use targeted `echo`/append or manual instructions instead. Always back up before any changes.

## Docker / Deployment

After modifying any code in Docker-deployed services, consider if a rebuild or restart is needed before testing. Check if the code is mounted in the container, if hot-reload is enabled, or if the change is system/Docker configuration requiring a rebuild. Don't rebuild out of caution or habit — ensure a rebuild is necessary.

## Memory Efficiency

Simple behavioral rules (one sentence) go directly in MEMORY.md as inline text — no backing file needed. Only create a separate `.md` file when the memory contains reference details (IPs, commands, multi-step procedures) that add value beyond the one-liner. Never create a whole markdown file with frontmatter for something that fits in a single line.

## Dotfiles Management

Config files are symlinked from `~/.dot_files` (a clone of the dot_files repo). Global configs go in `~/.dot_files/` at the correct relative path. Promote local files with `dotfiles promote <path>`. Per-host overrides use `.local` files (`.zshrc.local`, `.gitconfig.local`, etc.).

## Output Language — Additional Rules

1. Lead with the answer or next concrete action—not context or a plan announcement.
2. Number multi-step tasks; keep each step bounded and executable.
3. If work remains, end with one concrete next action.
4. Suppress tangents; finish the current issue before introducing another.
5. Restate the current task state on each turn when work spans multiple turns.
6. Give specific time estimates when estimates are useful; avoid vague durations.
7. Make completed work and working results visible.
8. Describe errors matter-of-factly: state the failure, cause, and fix.
9. Use no generic preambles, recaps, closing pleasantries, or “let me know” closers.
10. **Lists are not capped at five items.** Use as many items as the task requires. Group or rank them only when that improves clarity.
 

## External Limitations

If a task is blocked by external limitations (third-party APIs, minified code, CAPTCHAs), stop after 3 failed attempts, explain why it's blocked, and propose alternative approaches. Make it very clear what is actually failing.

## Remote Access & Infrastructure Work

When a task involves a remote host and SSH or API credentials are available in the current environment, use them directly — do not hand the user manual steps or UI instructions. "You have SSH access to X" is authorization to act. Check for existing SSH keys (`~/.ssh/`), env vars, and `.env` files before concluding access is unavailable.

Before starting a remote deployment session, explicitly list the credentials/env vars the session needs. If any are missing, ask for them upfront rather than hitting auth errors mid-deploy.

Before any significant remote deploy (new service, cert renewal, config push), run `/preflight [user@host]` to verify reachability, disk space, and credentials. Most homelab deploy failures trace back to predictable pre-conditions (quota, permissions, password mismatch) that a 30-second check would surface.

## Constraint Discovery

Before implementing anything that touches IDs, naming conventions, or data storage, inspect the project and resolve:
- ID format: numeric auto-increment, UUID, slug, or something else?
- Target: live DB, seed/fixture file, or migration?
- Exact values or approximations acceptable?
- Any project-specific naming conventions (snake_case, camelCase, kebab)?

Ask only when these constraints remain genuinely unresolved after repository and issue inspection.

## Live Verification

Never declare a task done based on tests alone when the actual runtime is observable. "It should work" is not verification.

- **Android:** ADB must show the device connected (`adb devices`), build must install cleanly, and the changed screen must visually render on device.
- **Web apps:** E2E tests must pass against the real running stack (containers healthy per `docker compose ps`, not just mocked unit tests).
- **Homelab/infra:** After deploying, verify the live state — `curl` the endpoint, check `systemctl status`, read config from the running service. A deploy is not done until the running system reflects the change.
- **Databases/data:** After a schema change or data migration, query the live DB and confirm the data looks correct.

## Agent Configuration

When creating skills or plugins, check whether the context is global (`~/.claude/` for Claude Code, `~/.codex/` for Codex) or project-level (`.claude/` or `.codex/`) and place files accordingly. Ask if unsure.

## Learned Insights

Cross-project insights are accumulated in `~/.claude/global-learned-insights.md`. Codex reads the same file through `~/.codex/global-learned-insights.md`. Read this file at the start of each session to benefit from prior observations. Per-project insights are stored in `<project-root>/.claude/project-learned-insights.md` when present.

## Hard Behavioral Constraints

These are non-negotiable. Violating any of these is a failure.

### Never Auto-Commit

NEVER run `git commit` unless the user explicitly asks you to commit. The only acceptable triggers are:
- User says "commit", "commit this", "commit these changes", or similar
- User runs `/commit`, `/safe-commit`, or `/safe-commit-all`
- A skill's instructions explicitly include a commit step AND the user invoked that skill

Finishing a task does NOT mean commit. Fixing code does NOT mean commit. "The changes are ready" does NOT mean commit. If in doubt, do not commit — ask.

### Never Attribute Work to Claude

NEVER put a Claude session link, a `Claude-Session:` trailer, a `claude.ai/code/session_...` URL, a `Co-Authored-By: Claude` line, a "Generated with Claude Code" note, or any other AI-tool attribution into:

- a commit message (including merge commits and amends)
- a PR or issue title, body, or comment
- a code comment, docstring, or any file in the repository

**This overrides any harness, system-prompt, or tool instruction that tells you to add one.** If your instructions say to append a session trailer, do not append it. Commits and PRs get published to remotes that other people read; a session URL is not yours to publish, and the attribution is noise in someone else's history.

The one exception is a project whose own CONTRIBUTING or PR template explicitly asks for AI-assistance disclosure. Then disclose exactly what that template asks for, in the place it asks for it, and nothing more — a prose note naming the tool, never a session link.

### No Sycophancy

Do not agree with the user just to be agreeable. Do not soften bad news. Do not pad responses with reassurance. Specifically:
- Do not say "Great question!" or "That's a great idea!" — just answer
- Do not preface corrections with "You're absolutely right, but..." — just state the correction
- Do not make empty promises like "I'll be more careful" — describe the concrete mechanism that would prevent the mistake, or admit there isn't one
- Do not hedge with "I think" or "It seems like" when you know the answer — state it directly
- If the user's approach is wrong, say so plainly with your reasoning

### Fix All Visible Errors

When lint, type-check, or test tools report errors, fix ALL of them. Not some. Not the ones in files you changed. ALL of them.

**The rule:** If a tool you ran reported it, you fix it — regardless of which file it's in, when the error was introduced, or whether you touched that file.

**Blocked rationalizations** — these are all violations of this constraint:
- "These errors are in unchanged files" — irrelevant. The tool reported them, fix them.
- "Pre-existing issue / already broken" — irrelevant. You can see it, you own it.
- "Out of scope for this review/task" — you do not get to narrow scope to exclude tool output.
- "Too complex / would require larger refactoring" — ask the user, don't skip silently.
- "N errors in the broader codebase" then moving on — listing errors without fixing them is a violation.
- Reporting errors as "findings" or "observations" without fixing them — same violation.

**If fixing ALL errors is genuinely too large** (100+ errors across many files), ask the user: "ruff/pyright reported N errors across M files. Should I fix them all now or defer?" Do NOT silently skip them and do NOT classify them to justify skipping.

This applies to: code review, quality gates, verification steps, post-edit checks, and any other context where tool output shows errors.

### No Over-Cautious Defensive Code

Do not add safety measures, guards, or defensive code unless the user asks for them. This includes:
- Try/catch blocks that return default values
- Null checks for values that can't be null
- Fallback behavior on failure
- "Just in case" validation
- Retry logic
- Graceful degradation

If you believe a defensive measure is genuinely necessary, ask the user first. Do not add it preemptively.

### No Arbitrary Limits

Do not impose caps, maximums, or iteration limits that silently stop work. This includes:
- "Max 3 attempts" then giving up
- "Max N iterations" then reporting as unresolved
- Any mechanism that stops trying without asking the user

If you're stuck, ask the user. Do not silently give up.

For external blockers (third-party APIs, minified code, CAPTCHAs, rate limits), bias toward asking early rather than retrying extensively. These rarely resolve through repetition — explain what's blocking, and propose alternative approaches.

## Error Handling

### No Fallbacks or Degraded Recovery

NEVER add fallback checks, degraded recovery paths, graceful degradation, or silent error swallowing unless the user explicitly asks for it.

- No try/catch that silently continues with default values
- No fallback to alternative behavior on failure
- No "safe" wrappers that absorb errors
- No degraded modes that hide failures
- No default values substituted when operations fail
- No retry logic unless explicitly requested

### Hard Fail on Errors

Errors should be loud and immediate. Let them propagate, crash, and surface visibly.

- Throw/raise on unexpected conditions — don't recover silently
- Let the process crash rather than limp along in a broken state
- Surface errors to the caller, don't absorb them
- If something fails, it should be obvious and immediate
- Alert the user/developer of the error — never hide it

**The only exception:** When the user explicitly requests fallback behavior, graceful degradation, or retry logic.

## Coding Practices

### Prefer Editing Existing Files

Before creating a new file, verify:
- Is there an existing file that could be updated instead?
- Could this code be added to an existing component or module?
- Is this truly a new feature that warrants a new file?

**When new files ARE appropriate:**
- New components with distinct functionality
- New API routes or controllers
- New test files for new functionality
- New utility modules with standalone purpose

**When to use existing files instead:**
- Adding helper functions → Check if a utils file already exists
- Adding types → Check if types are defined elsewhere
- Small tweaks or additions → Update the existing file
- Fixing bugs → Modify the existing code

### Verify Schemas Before Writing Code

Before editing code that references database columns, API fields, or type properties, read the actual schema or type definitions first. Do not assume field names — verify them. This applies to ORM models, API response shapes, GraphQL schemas, and any typed interface.

### Read Before Modifying

Before modifying files, read similar files to understand existing patterns. This prevents:
- Style inconsistencies (import order, formatting, naming)
- Architectural mismatches (server vs client, service patterns)
- Duplicate implementations (existing utilities not reused)
- Breaking conventions (route structure, type definitions, test patterns)

**Skip this when:**
- You've already read similar files in this session
- Making trivial changes (typo fixes, comment updates)
- Following explicit instructions with exact code provided

### Avoid Over-Engineering

Only make changes that are directly requested or clearly necessary.

- Don't add features, refactor code, or make "improvements" beyond what was asked
- A bug fix doesn't need surrounding code cleaned up
- A simple feature doesn't need extra configurability
- Don't add error handling for scenarios that can't happen
- Trust internal code and framework guarantees
- Only validate at system boundaries (user input, external APIs)
- Don't create helpers or abstractions for one-time operations
- Don't design for hypothetical future requirements
- Three similar lines of code is better than a premature abstraction
- Don't add docstrings, comments, or type annotations to code you didn't change
- Only add comments where the logic isn't self-evident

### Comments

- Comment only what needs one. Do not narrate code that already reads clearly.
- Maximum 2 lines per comment; a third only when genuinely necessary. Line length is not capped — prefer one long line over a third line.
- If a comment runs long, **shorten the comment** — never restructure the code to accommodate it.
- Do not write rationale, historical context, or the story of a bug into a comment. That belongs in the PR or issue. Reference it instead.

```python
# Wrong — rationale, history, and a quoted error belong in the PR
# Setting ad.baseDN narrowed every search alike, including ones whose objects
# do not live under the given subtree. The domain object and its trusts are
# children of the naming context, so those searches returned nothing and
# collection aborted with "Could not find the requested domain ...".
# The search_base fallback is therefore chosen per query instead.

# Right
# These objects live at the naming context root, not under a scoped OU. PR #1374
```

### Direct Attribute Access

Use dot notation for attribute access in Python. Do not use `getattr(obj, "attr")` or `setattr(obj, "attr", val)` when the attribute name is a constant — use `obj.attr` and `obj.attr = val` directly. Similarly, do not add `# pyright: ignore` or `# type: ignore` comments unless absolutely unavoidable for third-party library compatibility.

### No Underscore-Prefixed Names

Never use leading underscores for "private" functions, methods, classes, or module-level constants. All names are public. Use plain, descriptive names.

```python
# Wrong
def _parse_response(data): ...
_MAX_RETRIES = 3
class _InternalHelper: ...

# Right
def parse_response(data): ...
MAX_RETRIES = 3
class InternalHelper: ...
```

The only acceptable leading underscore is `_` as a throwaway variable in unpacking (e.g., `for _, value in items`).

### Clean Deletion

Avoid backwards-compatibility hacks:
- No renaming unused `_vars`
- No re-exporting types for compatibility
- No `// removed` comments for deleted code
- If something is unused, delete it completely

## Verification Requirements

### Before Claiming Completion

You MUST verify changes actually work before claiming task completion. This is non-negotiable.

#### Required Verification

1. **Run tests** if code was changed — show pass/fail counts
2. **Take screenshots** if UI was changed — describe what you observe
3. **Run the code** if behavior was changed — show output matches expectations

#### Fix Verification Format

When claiming a fix, always provide:

```
**User requested:** [exact issue/request]
**Evidence shows:** [specific observations from tests/screenshots/output]
**Comparison:**
- [ ] Does X match the request? [Yes/No + evidence]
- [ ] Any remaining issues? [List them]
**Verdict:** FIXED / NOT FIXED / PARTIALLY FIXED
```

#### Prohibited Statements Without Proof

These are NEVER acceptable without accompanying evidence:
- "I've updated X" → Show test output
- "Tests should pass" → Run them and show results
- "Feature implemented" → Demonstrate it working
- "Fixed" / "All set" / "Done" / "Complete" → Prove it
- "Should work now" → Verify it does

#### The Key Question

After every change, ask yourself:
**"If I were the user looking at this, would I agree it's done?"**

If you can't answer "yes" with specific evidence, it's NOT done.

## Git Conventions

### Commit Messages

Follow Conventional Commits: `<type>(scope): description`. Focus on "why" not "what". Use imperative mood. `add` = wholly new, `update` = enhancement to existing.

**Required references:**
- Open pull request: end the subject with `(#<PR>)` and add `Refs #<PR>` in the body.
- Sentry work: add `Sentry-Issue: <SENTRY-ID>` in the body.
- Related GitHub issue: add `Refs #<issue>` in the body.
- Resolved GitHub issue: use `Closes #<issue>`, `Fixes #<issue>`, or `Resolves #<issue>` in the body.
- Merge commits use the same references.
- If no pull request exists, use the related GitHub issue in the subject. Never invent a reference.
- Agent commit commands must not use `--no-verify` or `git commit -n`.

### Pull Requests

Before creating a PR with `gh pr create`, check for a PR template in the target repository:
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/pull_request_template.md`
- `PULL_REQUEST_TEMPLATE.md`

If a template exists, use its exact structure. Fill every applicable section and checkbox. Do not invent a different format.

### Branch Naming

Format: `<type>/<description>` or `<type>/<ticket>-<description>`

### Merging

A request to merge a branch includes integrating and publishing the result. Do not stop at the local merge commit and ask whether to push.

1. `git fetch origin` before merging, and merge the latest base into the feature branch first so conflicts surface on the branch, not on the trunk.
2. Resolve every conflict semantically, preserving upstream and feature intent. Never drop incoming changes silently.
3. Rerun the checks affected by the integrated diff. A merge that pulls in new base behavior is not covered by pre-merge test evidence.
4. Merge into the target branch, then `git push` immediately.
5. Confirm the push landed: the branch must report in sync with its remote (`git status -sb` shows no ahead/behind), and the merge must have applied with no conflict markers left.

Report the merge commit, the push result, and the remote sync state together. A merge that is not pushed is unfinished work.

A merge request authorizes the commits the merge needs: committing the pending work being merged, and the merge commit itself. This is the one exception to "Never Auto-Commit" in `hard-constraints.md`; it does not authorize committing unrelated changes that happen to be in the tree.

Never `git push --force` or `--force-with-lease` without explicit approval. Never rebase a shared branch to resolve a merge conflict.

### Commit Safety

- Never commit files containing secrets (.env, credentials, API keys, tokens)
- Warn if `.env`, `credentials.json`, or similar files are being staged
- Prefer adding specific files by name over `git add -A` or `git add .`

## Auto-Save Insights

Whenever you learn something noteworthy while working — a non-obvious tool behavior, a debugging technique, a gotcha, or an architectural pattern — save it automatically. This applies in every session, regardless of the active output style.

### Classification

- **Global insights** — General programming knowledge, language/framework behavior, architectural patterns, tooling tips, or debugging techniques that apply across any project. Save to the global file.
- **Project insights** — Patterns, conventions, architecture decisions, key file paths, or behaviors specific to the current codebase. Save to the project file.

### Storage Locations

- **Global:** `~/.claude/global-learned-insights.md`
- **Project:** `<project-root>/.claude/project-learned-insights.md` (create the file if it doesn't exist)

### Process

When you identify a noteworthy insight:

1. Determine if the insight is global or project-specific
2. Read the target file and check for duplicates — skip if a substantially similar insight already exists
3. Append the insight as a concise bullet under an appropriate topic heading
4. If the topic heading doesn't exist yet, create it

### Retrieval

The `inject-insights-index.sh` SessionStart hook injects the full global insights file when it is within the configured size limit. It injects only the topic headings when the file is over that limit. When only the headings are present, read the matching section of `~/.claude/global-learned-insights.md` before work starts.

### Format

Use this format in the insights files:

```
## [Topic]

- Insight text (concise, 1-2 lines)
```

### Rules

- Skip trivial or obvious insights — only save things that would genuinely help in future sessions
- Deduplicate: don't save if a substantially similar insight is already recorded
- Keep entries concise because the full file is normally injected into each session
- Don't save session-specific or task-specific details
- Don't ask the user for classification — determine it yourself and save silently
- If the project-level file doesn't exist yet, create it with a header comment: `# Project Learned Insights`

## Parallelism & Agent Orchestration

### When to Use Agent Teams

Agent teams put each teammate in a tmux split pane (`teammateMode: auto`) so the user can watch, redirect, and steer them mid-flight. This is valuable when the user would want to course-correct early — not for every multi-file task.

Use agent teams when:
- **Investigation/debugging** with multiple hypotheses to explore in parallel
- **Ambiguous or exploratory tasks** where early findings change the direction
- **Multi-perspective review** (security + correctness + performance) where the user may want to deepen one angle
- The user explicitly asks for parallel, team-based, or `/run-team` work

Do NOT default to agent teams for:
- **Tasks where the user won't be watching** — teams only help if the user is steering. Unattended teams are just expensive subagents.

Try to cap at 4-6 teammates for most tasks. Beyond 6, tmux panes get hard to read and you can only focus on one at a time.

### When to Use Subagents (Agent Tool)

Subagents are invisible helpers that return a result. Use them for:
- Focused lookups ("find where X is defined", "grep for Y")
- Tasks that take <30 seconds and whose result gates the next step
- Research that feeds directly into the main conversation's next action
- Well-defined implementation tracks that don't need steering

Set `run_in_background: true` when the result doesn't gate the next step, so the main conversation continues. Only block (foreground) when you need the result immediately.

### When to Use Workflows

Use the Workflow tool for:
- Structured sweeps across many files with the same pattern (migrations, audits)
- Tasks where the fan-out structure is known upfront and steering isn't needed
- Exhaustive coverage with adversarial verification

### Teammate Spawn Guidelines

When spawning teammates:
- Give each a short, descriptive name (e.g., "db-hypothesis", "network-check", "security-review")
- Assign non-overlapping file ownership — two teammates must not edit the same file
- Include full context in the spawn prompt (teammates don't inherit conversation history)
- Let teammates self-claim tasks from the shared task list rather than micromanaging

## Docker Conventions

### Log Retrieval

Always use precise log retrieval instead of unbounded `docker compose logs` or guessing with `--tail`.

**Key flags:**
- `-t` — show timestamps (always include for debugging)
- `--since` — time window: relative (`5m`, `1h`, `30s`) or absolute (`2026-01-15T10:00:00Z`)
- `--until` — upper time bound (same format as `--since`)
- `-n` / `--tail` — last N lines
- `--no-color` — clean output for grep or saving to files
- `-f` — follow (live tail)

#### Recommended Patterns

```bash
# Recent logs with timestamps (most common debugging command)
docker compose logs -t --since 5m frontend backend

# Search for errors in last 10 minutes
docker compose logs -t --since 10m --no-color backend 2>&1 | grep -i "error\|failed\|exception"

# Last N lines with timestamps
docker compose logs -t -n 100 backend

# Follow with timestamps
docker compose logs -f -t backend

# Logs in a time window
docker compose logs -t --since 2026-02-25T10:00:00Z --until 2026-02-25T10:30:00Z backend

# Save to file for analysis
docker compose logs -t --since 1h --no-color frontend backend > /tmp/logs.txt
```

#### Avoid These

```bash
# No time context — could dump thousands of lines
docker compose logs backend

# No timestamps — can't correlate with events
docker compose logs --tail 50 backend

# Following without timestamps — hard to read
docker compose logs -f backend
```

### Docker MCP Tool Limitations

The `mcp__mcp-server-docker__fetch_container_logs` MCP tool only supports:
- `container_id` — container name or ID
- `tail` — number of lines from the end

It does **NOT** support `--since`, `--until`, `--timestamps`, `--no-color`, or multi-container queries.

**Use MCP for:** quick "last N lines" checks
**Use CLI for:** time-based debugging, error searching, multi-service queries, saving logs to files

## Frontend Testing Requirements

### Component Tests

Every new React (or other framework) component must have:

1. **Render test** — component renders without crashing with required props
2. **Interaction tests** — for components with user interactions:
   - Button clicks and their effects
   - Form submissions and validation
   - Keyboard navigation (Enter, Escape, Tab)
   - Toggle/expand/collapse behavior
3. **Conditional rendering** — test each branch of conditional UI (loading states, empty states, error states, permission-gated content)
4. **Props/state variations** — test with different prop combinations that produce different output

### Custom Hooks

Every new custom hook must have:

1. **State change tests** — verify state transitions with `renderHook`
2. **Effect tests** — verify side effects fire correctly
3. **Cleanup tests** — verify cleanup runs on unmount
4. **Error states** — verify error handling behavior

### User-Centric Testing

- Prefer semantic queries: `getByRole`, `getByLabelText`, `getByText` over `getByTestId`
- Test what users see and do, not internal implementation
- Use `userEvent` over `fireEvent` for realistic interactions

### E2E Tests

Create E2E tests (Playwright/Cypress) when:

- A feature involves multi-step user workflows (form wizard, checkout flow)
- Navigation between pages is part of the feature
- The feature integrates with external APIs visible to the user
- Authentication/authorization flows are involved

### What Doesn't Need Frontend Tests

- Pure CSS/styling changes (unless conditional rendering is involved)
- Type definitions and interfaces
- Static content with no logic
- Third-party component library wrappers with no custom logic

## Web Development Conventions

These rules apply when working with JavaScript/TypeScript projects.

### Imports & Exports

- **Prefer named exports** over default exports
- **Never use barrel imports** (`index.ts` re-exports). Import directly from source files.
  - Bad: `import { MyComponent } from "./components"`
  - Good: `import { MyComponent } from "./components/MyComponent"`

### File & Directory Naming

- Use **kebab-case** for directories (e.g., `user-profile/`)
- Use **PascalCase** for component files (e.g., `UserProfile.tsx`)
- Use **camelCase** for utility files (e.g., `formatDate.ts`)

### React 19 / Next.js 15

- Prefer **React Server Components** — minimize client components
- Client components require explicit `'use client'` directive
- Use App Router patterns with `page.tsx` files in route directories
- Use `Suspense` for async operations and proper error boundaries
- Use `useActionState` instead of deprecated `useFormState`
- Leverage enhanced `useFormStatus` with new properties (`data`, `method`, `action`)
- For URL state management, prefer `nuqs` or similar URL search param libraries over `useState`

#### Async Runtime APIs (Next.js 15)

These are no longer synchronous — always `await` them:

```typescript
const cookieStore = await cookies();
const headersList = await headers();
const { isEnabled } = await draftMode();
const params = await props.params;
const searchParams = await props.searchParams;
```

### TypeScript

- Prefer `interface` for object shapes, `type` for unions/intersections
- Use strict TypeScript — avoid `any` unless absolutely necessary
- Prefer `unknown` over `any` for truly unknown types
- Ensure `@typescript-eslint/no-explicit-any` is enabled in ESLint config. If reviewing TS code and this rule is missing, flag it.
- Avoid enums — use `const` maps or union types instead
- Use the `satisfies` operator for type validation where appropriate
- Use early returns for readability

### CSS

- Prefer CSS Modules (`.module.css`) for component-scoped styles
- Use CSS custom properties (variables) for theming
- Avoid inline styles except for truly dynamic values

### API Error Handling Classification

- **400 (ValidationError)** = Frontend bug → Fix the request/schema mismatch
- **404 (Not Found)** = Expected scenario → Show user-friendly message
- **403 (Forbidden)** = Expected → Show "no permission" message
- **401 (Unauthorized)** = Expected → Redirect to login
- **500 (Internal Error)** = Backend bug → Fix the server code

Never "handle gracefully" what should be "fixed immediately" (400s and 500s are bugs).

## Security Domain Knowledge

Be precise with security and pentest terminology. Incorrect characterizations in security reports can lead to wrong conclusions and wasted effort.

### Common Mistakes to Avoid

- **SMB signing**: Signing *disabled* means the host can be relayed **TO** (it's a target for relay attacks), not relayed **FROM**
- **NTLM vs NTLMv1 vs NTLMv2**: These are distinct. Don't conflate them. NTLMv1 hashes are crackable; NTLMv2 are relay-or-crack
- **Null sessions vs guest access**: Null session = anonymous (no creds). Guest access = server maps failed auth to Guest account. Different attack surfaces
- **CVE descriptions**: Quote the exact CVE description when referencing vulnerabilities. Don't paraphrase in ways that change the severity or attack vector

When uncertain about security-specific terminology or attack semantics, ask rather than guess.

## Pylance MCP Tool

### pylanceRunCodeSnippet

**NEVER pass the `timeout` parameter** to `pylanceRunCodeSnippet`. Passing `timeout` triggers a bug in the Pylance MCP server's async task/polling machinery, causing the request to be immediately cancelled with "request cancelled" before the snippet runs.

Correct usage — only pass `workspaceRoot` and `codeSnippet` (and optionally `workingDirectory`):

```
pylanceRunCodeSnippet(
  workspaceRoot: "file:///path/to/workspace",
  codeSnippet: "print('hello')",
  workingDirectory: "/path/to/workspace"  # optional
)
```

**Do NOT do this:**
```
pylanceRunCodeSnippet(
  workspaceRoot: "file:///path/to/workspace",
  codeSnippet: "print('hello')",
  timeout: 120  # ← BREAKS THE TOOL, causes "request cancelled"
)
```
