# Global Learned Insights

Accumulated knowledge from working across projects. Auto-maintained by Claude.

## SQLAlchemy Patterns

- When adding a FK to an existing model that's mocked with `SimpleNamespace` in tests, every mock instance needs the new attribute added (typically `=None`). Regex-based replacement across test files is efficient for this.

## Claude Code Parallelism Mechanisms

- Three parallelism levels: **Subagents** (Agent tool, invisible helper returning a result), **Agent Teams** (full independent sessions in tmux panes, user can interact with each), **Workflows** (scripted JS orchestration, deterministic fan-out, no mid-flight steering). Choose by steerability needs, not task size.
- `run_in_background: true` on the Agent tool is the middle ground — the main conversation continues, but the subagent can't be steered. Use for independent lookups that don't gate the next step.
- `teammateMode: "auto"` in settings.json enables tmux split panes when running inside tmux, falling back to in-process agent panel otherwise. Default changed from `"auto"` to `"in-process"` in v2.1.179.

- Background subagents that kick off a long test via run_in_background and then "wait for the completion notification" fall into a stop-loop: they yield the turn and fire a task-notification with no result, repeatedly, making no progress. Fix by messaging the agent to run the check in the FOREGROUND within one turn with the Bash `timeout` set high (up to 600000 ms / 10 min) — enough to cover slow bootstraps (e.g. Strapi integration bootstrap routinely >5 min) so the run completes in a single turn.
- `isolation: "worktree"` agents cannot free host memory (worktree-env `gc` needs the primary checkout). When many run in parallel and hit the `up` memory-budget guard, run `./scripts/worktree-env.sh gc --apply` from the primary checkout to reclaim merged/disposable worktree runtimes; it only removes MERGED worktrees, so in-flight `agent-*` branches are untouched.

## Claude Code Skills vs Agents

- Skills are prompt templates (directory with SKILL.md) injected into the main conversation -- they run as the main Claude instance, can interact with the user mid-execution, and inherit all available tools. Best for orchestration and interactive workflows.
- Agents are isolated subprocesses (single .md file with YAML frontmatter including explicit `tools` list) that run autonomously and return a single result. Best for parallel execution and autonomous work. Cannot interact with the user mid-task.
- Colon-based namespace in skill directory names (e.g., `bb:full-sweep`) groups related skills in the `/` completion menu and makes them visually distinct from other skills.
- Skill discovery requires `<skills-dir>/<name>/SKILL.md`. A flat `.claude/skills/<name>.md` is NOT loaded, even with valid frontmatter — it is only a document you can Read. Symptom: `Skill(<name>)` returns `Unknown skill`. To share one canonical skill across Claude and another runtime, symlink both `SKILL.md` and `references/` into a real `<name>/` directory. Newly added skills register live, without a session restart.

- Skills are prompt templates (directory with SKILL.md) injected into the main conversation -- they run as the main Claude instance, can interact with the user mid-execution, and inherit all available tools. Best for orchestration and interactive workflows.
- Agents are isolated subprocesses (single .md file with YAML frontmatter including explicit `tools` list) that run autonomously and return a single result. Best for parallel execution and autonomous work. Cannot interact with the user mid-task.
- Colon-based namespace in skill directory names (e.g., `bb:full-sweep`) groups related skills in the `/` completion menu and makes them visually distinct from other skills.

## Next.js App Router / React SSR

- App Router `not-found.tsx` is rendered inside the active layouts, so it must return segment UI only; returning `<html>`, `<head>`, or `<body>` creates nested documents and hydration failures. Only `global-not-found.tsx` owns the full document shell.
- Next.js `loading.tsx` creates Suspense boundaries that permanently mask client-side rendering failures. If a client component fails inside a loading.tsx Suspense, React silently shows the fallback forever with zero console errors. Remove loading.tsx from pages where the component handles its own loading state (`{!data && <Skeleton />}`).

- `useSearchParams()` causes SSR suspension. Combined with Suspense boundaries in Turbopack dev mode, client-side resolution can fail silently. Replace with `useState(() => new URLSearchParams(window.location.search))` only when Suspense interaction is problematic (i.e., `loading.tsx` exists and masks failures).
- Conversely, `useState(() => window.location.search)` breaks on client-side navigation — the initializer only runs on mount, so navigating between the same route with different query params (e.g., `/findings` → `/findings?scan_run_id=447`) leaves state stale. Use `useSearchParams()` when the component needs to react to URL param changes without remounting. Safe in pages without `loading.tsx` / `Suspense` boundaries.

## PostgreSQL Large Table Performance

- `ORDER BY col LIMIT N` without an index on `col` forces a full table scan + sort (O(n)). Adding a B-tree index enables index scan that stops after N rows. On 12M rows: 8s → 0.2ms.

- `COUNT(*)` on 12M+ rows takes 3.5s even with index-only scan. Use `pg_class.reltuples` for instant approximate counts on unfiltered queries; exact COUNT only for filtered queries where indexes reduce the scan.

- B-tree indexes scan in reverse. `CREATE INDEX ON tbl (col)` works for both `ORDER BY col ASC` and `DESC`. DESC in index definition only matters for multi-column indexes with mixed sort orders.

## AG Grid React v35 Custom Filters

- AG Grid React v35 passes `CustomFilterProps` (with `model`/`onModelChange`) to custom filter components, not `IFilterParams` (with `filterChangedCallback`). The old `forwardRef` + `useImperativeHandle` pattern is replaced by the `useGridFilter` hook from `ag-grid-react`. If upgrading from older AG Grid, custom filter components must be rewritten to use the controlled component API.

## Claude Code Model/Effort Inheritance

- Subagents inherit the parent session's model and effort level by default. Creating "-max" or "-team" variants of skills that just add "use Opus Max Effort" text is redundant and causes drift — the duplicate falls behind as the canonical version evolves.
- The `model` field in agent frontmatter overrides inheritance. Setting `model: haiku` on an agent means it ALWAYS uses Haiku regardless of session. Omit the field (or use `inherit`) to respect the session model.
- Prompt-level instructions like "Create a team of Opus 4.6 Max Effort agents" are suggestions Claude tries to honor, not enforced configuration. For deterministic model selection, use agent frontmatter `model` field or the Agent tool's `model` parameter.

## Claude Code Hooks

- Hook input is delivered via **stdin**, not environment variables. The format is `{"tool_name":"...","tool_input":{...},"session_id":"...","cwd":"...","hook_event_name":"..."}`. Access the command with `jq -r '.tool_input.command'`. `CLAUDE_TOOL_INPUT` env var does not exist.
- `set -u` (nounset) in hook scripts will crash on any env var that isn't set by Claude Code. Use `${VAR:-}` syntax or avoid referencing env vars you haven't verified exist.
- Hooks under the same `matcher` entry in settings.json share a single stdin pipe. The first hook to read (via `cat`, `jq`, etc.) consumes it — subsequent hooks get empty stdin. Design hooks to be self-contained or place each in its own matcher entry if they all need the input.
- Tool fields are nested under `.tool_input.*` — a PostToolUse file hook reads `.tool_input.file_path`, NOT top-level `.file_path`. A hook keying off the wrong path silently no-ops (empty → early exit) with no error.
- The PreToolUse payload does NOT contain the user's prompt — you cannot gate a PreToolUse hook on "did the user ask for this." To make a detected pattern a conscious choice, emit `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"..."}}` (prompts the user) instead of a hard `exit 2` block.
- The Stop payload does NOT contain the assistant's response text — it's in the transcript at `.transcript_path` (JSONL). Last assistant text: `jq -rs 'map(select(.type=="assistant"))|last|.message.content|map(select(.type=="text")|.text)|join("\n")'`.
- A hook reading a nonexistent env var (`CLAUDE_TOOL_INPUT`, `CLAUDE_USER_PROMPT`, `CLAUDE_STOP_RESPONSE`) is silently dead: the var is empty, the hook early-exits, and nothing warns you. Symptom of a dead post-edit hook: the linter/formatter you expect to auto-run after a Write/Edit simply doesn't.
- Claude Code reads hooks ONLY from `settings.json` (`~/.claude/`, `.claude/settings.json`, `.claude/settings.local.json`). A `.claude/hooks.json` file is inert no matter how valid it looks — Codex has `.codex/hooks.json`, but Claude has no equivalent standalone path. Cheapest proof a hook is dead: check the mtime of an artifact it writes, or note that its SessionStart output never reaches context.

- Hook input is delivered via **stdin**, not environment variables. The format is `{"tool_name":"...","tool_input":{...},"session_id":"...","cwd":"...","hook_event_name":"..."}`. Access the command with `jq -r '.tool_input.command'`. `CLAUDE_TOOL_INPUT` env var does not exist.
- `set -u` (nounset) in hook scripts will crash on any env var that isn't set by Claude Code. Use `${VAR:-}` syntax or avoid referencing env vars you haven't verified exist.
- Hooks under the same `matcher` entry in settings.json share a single stdin pipe. The first hook to read (via `cat`, `jq`, etc.) consumes it — subsequent hooks get empty stdin. Design hooks to be self-contained or place each in its own matcher entry if they all need the input.
- Tool fields are nested under `.tool_input.*` — a PostToolUse file hook reads `.tool_input.file_path`, NOT top-level `.file_path`. A hook keying off the wrong path silently no-ops (empty → early exit) with no error.
- The PreToolUse payload does NOT contain the user's prompt — you cannot gate a PreToolUse hook on "did the user ask for this." To make a detected pattern a conscious choice, emit `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"..."}}` (prompts the user) instead of a hard `exit 2` block.
- The Stop payload does NOT contain the assistant's response text — it's in the transcript at `.transcript_path` (JSONL). Last assistant text: `jq -rs 'map(select(.type=="assistant"))|last|.message.content|map(select(.type=="text")|.text)|join("\n")'`.
- A hook reading a nonexistent env var (`CLAUDE_TOOL_INPUT`, `CLAUDE_USER_PROMPT`, `CLAUDE_STOP_RESPONSE`) is silently dead: the var is empty, the hook early-exits, and nothing warns you. Symptom of a dead post-edit hook: the linter/formatter you expect to auto-run after a Write/Edit simply doesn't.

## Claude Code Permissions

- Bash allow/deny patterns use colon-star syntax: `Bash(cmd:*)` matches `cmd` + any args (e.g. `Bash(git log:*)`, `Bash(ruff check:*)`). `Bash(cmd *)` is the EQUIVALENT space form (docs: "`Bash(ls:*)` matches the same commands as `Bash(ls *)`"); `:*` is only recognized at the END of a pattern, so `Bash(git:* push)` treats the colon literally and matches nothing. Multi-word prefixes work and a short prefix blankets subcommands — `Bash(docker:*)` already covers `docker compose logs ...`.
- `*` may appear at ANY position, not only the end: `Bash(* --version)`, `Bash(git * main)`. This matters for flag gates — `Bash(git push --force:*)` is prefix-only and does NOT catch `git push origin main --force`; add `Bash(git push * --force*)` as well. Same hole for `--no-verify` and any other trailing flag.
- **Rule TYPE beats settings SCOPE: deny > ask > allow, evaluated in that order no matter which file each rule came from.** A user-level `ask` in `~/.claude/settings.json` prompts even when a project `.claude/settings.json` allow matches the same command, so a project can never opt out of a global ask. Symptom: "Yes, don't ask again" never sticks, because it writes an allow rule that loses the same comparison every time. Diagnose repeated prompts by grepping the GLOBAL `ask`/`deny` lists, not the project allow list.
- PreToolUse hooks cannot rescue that: "a matching ask rule still prompts even when the hook returned `allow`". Hooks work only in the blocking direction — `exit 2` stops the call before permission rules are evaluated, so a hook CAN veto an allow rule.
- `defaultMode: "auto"` runs commands that match no rule at all, so an unlisted command is quieter than an explicitly-allowed one that a global `ask` also matches.
- Wrappers `timeout`/`time`/`nice`/`nohup`/`stdbuf`/`command`/`builtin`/`noglob` are stripped before matching; `npx`, `docker exec`, `devbox run`, `mise exec` are NOT — so `Bash(devbox run *)` grants `devbox run rm -rf .`. `watch`/`setsid`/`ionice`/`flock` and `find -exec`/`-delete` always prompt and cannot be prefix-allowed.
- Many read-only commands never prompt (no allowlist entry needed): `cat`/`ls`/`grep`/`find`/`head`/`tail`/`wc`/`cut`/`sort`/`diff`, all git read subcommands (`git log/diff/status/show/branch`), gh read subcommands, `docker ps/images/logs/inspect`. Worth allowlisting only the read-only tools OUTSIDE that set: `objdump`/`nm`/`readelf`/`ping`/`dig`, etc.
- When cwd is the home directory, the "project" `.claude/settings.json` path resolves to the global `~/.claude/settings.json` — they're the same file. `settings.local.json` holds machine-specific grants and (in this setup) is symlinked into `~/.dot_files`, so it IS dotfiles-tracked despite the usual "local = gitignored" convention.

- Bash allow/deny patterns use colon-star syntax: `Bash(cmd:*)` matches `cmd` + any args (e.g. `Bash(git log:*)`, `Bash(ruff check:*)`). The space form `Bash(cmd *)` is NOT the matcher. Multi-word prefixes work and a short prefix blankets subcommands — `Bash(docker:*)` already covers `docker compose logs ...`.
- Many read-only commands never prompt (no allowlist entry needed): `cat`/`ls`/`grep`/`find`/`head`/`tail`/`wc`/`cut`/`sort`/`diff`, all git read subcommands (`git log/diff/status/show/branch`), gh read subcommands, `docker ps/images/logs/inspect`. Worth allowlisting only the read-only tools OUTSIDE that set: `objdump`/`nm`/`readelf`/`ping`/`dig`, etc.
- When cwd is the home directory, the "project" `.claude/settings.json` path resolves to the global `~/.claude/settings.json` — they're the same file. `settings.local.json` holds machine-specific grants and (in this setup) is symlinked into `~/.dot_files`, so it IS dotfiles-tracked despite the usual "local = gitignored" convention.

## PostgreSQL JSONB Patterns

- GIN indexes on JSONB columns enable `?|` (any key exists), `@>` (contains), `?&` (all keys exist) operators. Use `postgresql_using="gin"` in SQLAlchemy Index definition.
- SQLAlchemy 2.0 has no built-in support for `?|` -- use `column.op("?|")(pg_array([...]))` with `from sqlalchemy.dialects.postgresql import array as pg_array`.

## Background Tasks / Polling

- Never use unbounded `until <condition>; do sleep N; done` in `run_in_background` commands. These run forever invisibly if the condition is never met. Use a bounded loop: `for i in $(seq 1 N); do <check> && break; sleep 5; done`.

## CLI Tool Behavior

- `searchsploit --strict` disables fuzzy version range expansion (e.g., "1.1" won't match "1.0 < 1.3"). The `-s` flag is the short form. Without it, a search for "Apache 2.4" returns every Apache exploit that mentions any version in the 2.x range.
- A formatter/linter run locally can disagree with CI purely because `node_modules` is stale relative to the lockfile. Prettier especially: 3.8.1 vs the lockfile's 3.9.6 reported 17 files as unformatted that were byte-identical to a clean `main`. **Never "fix" a mass formatting failure without first checking the tool version against the lockfile** — `prettier:write` with the stale binary would have rewritten every one of those untouched files and broken CI. Verify with `npx --yes prettier@<lockfile-version> --check` (CI uses `npm ci`, so the lockfile version is authoritative).

- `searchsploit --strict` disables fuzzy version range expansion (e.g., "1.1" won't match "1.0 < 1.3"). The `-s` flag is the short form. Without it, a search for "Apache 2.4" returns every Apache exploit that mentions any version in the 2.x range.

- `searchsploit --strict` disables fuzzy version range expansion (e.g., "1.1" won't match "1.0 < 1.3"). The `-s` flag is the short form. Without it, a search for "Apache 2.4" returns every Apache exploit that mentions any version in the 2.x range.
- `uv`/`rustup` (cargo-dist installers) append `. "$HOME/.local/bin/env"` (uv) or `. "$HOME/.cargo/env"` (rustup) to shell rc files and drop the sourced `env` file next to their binaries. If that `env` file is deleted, shell startup breaks with `no such file or directory`. Recreate it — the content is a stable cargo-dist template: a `case ":${PATH}:"` block that prepends the bin dir to PATH if not already present. `uv` has no command to regenerate it; copy the structure from an existing `~/.cargo/env`.

## Android

- `RenderEffect.createBlurEffect()` is API 31+ only. For premium content gating on minSdk 26, use alpha dimming + click-blocking overlay instead — same pattern Google's own apps use.
- `BottomSheetDialogFragment` subclasses must have a no-arg constructor. Use an interface on the host Activity (`requireActivity() as Listener`) for callbacks, not lambda constructors — they break on configuration changes.
- Android Emulator on ESXi requires nested virtualization (`nested_hv_enabled = true` in vSphere VM config, exposes `/dev/kvm` to guest). Without KVM, the emulator falls back to QEMU software emulation (~10x slower). Boot time with KVM: ~75s; without: minutes+.
- For headless emulator testing: `-no-window -no-audio -gpu swiftshader_indirect -no-snapshot-save -no-boot-anim`. Use `adb -a -P 5037 server nodaemon` as a systemd service to expose ADB on all interfaces for remote access from build hosts.

## Testing

- When a value has a formatter and a parser (dates, IDs, query strings), add a round-trip property test (`parse(format(x)) === x`) covering every formatter output shape. Teaching the formatter a new shape without updating the parser silently corrupts data on the next edit→save cycle.
- @testing-library/react only registers its automatic `cleanup()` when a global `afterEach` exists at import time — with Vitest that means `test.globals: true` in vitest.config; otherwise DOM leaks between tests.

- When a value has a formatter and a parser (dates, IDs, query strings), add a round-trip property test (`parse(format(x)) === x`) covering every formatter output shape. Teaching the formatter a new shape without updating the parser silently corrupts data on the next edit→save cycle.
- @testing-library/react only registers its automatic `cleanup()` when a global `afterEach` exists at import time — with Vitest that means `test.globals: true` in vitest.config; otherwise DOM leaks between tests.
- A concurrent `npm install` in the same checkout makes unrelated jest runs fail with `Cannot find module '<transitive dep>' from node_modules/<pkg>/build/index.js` — npm relinks `node_modules` while jest resolves. Diagnose with `ps aux | grep "[n]pm install"` plus `readlink /proc/<pid>/cwd`, wait for it to exit, then re-run. Common when several agents share one working tree.
- Playwright matches a positional test filter as a regex against the **absolute** file path, not the path relative to `testDir`. Inside a git worktree at `.claude/worktrees/fix-team-swiss-standings/`, `playwright test swiss-standings` matches every spec (the directory name contains the string) and silently runs the whole suite instead of one file. Symptom: `Running 657 tests` when you expected 9. Include `.spec` in the filter (`swiss-standings.spec.ts`) or use `--grep` on the test title. Verify with a filter that only matches the path, e.g. `playwright test worktrees --list` — if that returns everything, the path is the matcher.
- pytest collects any class named `Test*` present in a test module's namespace, including imported application classes — SQLAlchemy models named `TestRun`/`TestLog` emit `PytestCollectionWarning: cannot collect ... has a __init__ constructor`. Aliasing at each import site is fragile (every new test file reintroduces it); a `pytest_pycollect_makeitem` hook in conftest returning `[]` for classes whose `__module__` is the app package fixes it project-wide, and unlike setting `__test__ = False` it does not trip type checkers on enum classes.

## Docker Compose

- `docker compose` interpolates `$VAR`/`${VAR}` inside `command:`/`entrypoint:` blocks at parse time — embedded shell scripts silently lose their variables (unset vars become empty with only a warning). Escape every shell-runtime `$` as `$$`. `docker compose config` re-escapes surviving literals back to `$$` in its output, so asserting the `$$` form in rendered output plus zero "variable is not set" warnings makes a solid regression check.
- Compose `${VAR:?message}` hard-fails the deploy when a variable is unset/empty — use it for credentials instead of `${VAR:-default}`, which silently ships the default (e.g. Grafana admin/admin).
- Push a file into a running container without host SSH via the Docker/Portainer archive API: `PUT /containers/<id>/archive?path=<dir>` with a tar body AND `Content-Type: application/x-tar` (omitting the header → HTTP 400). `path` must be an existing dir; if it's a **read-write** bind mount the write lands on the host. A `:ro` mount blocks it (no host-side write path) — check the mount mode before assuming you can deploy config this way.
- `docker compose up -d <svc>` **adopts** an already-running container instead of replacing it. For a tmpfs-backed database container this silently makes state persistence depend on the host: ephemeral CI runners get a clean volume every run, a self-hosted/reused runner inherits the previous run's rows. That asymmetry looks exactly like "the suite passes on PRs but fails on main" while being pure fixture accumulation across runs. Use `up -d --force-recreate` when a container must start clean.

- `docker compose` interpolates `$VAR`/`${VAR}` inside `command:`/`entrypoint:` blocks at parse time — embedded shell scripts silently lose their variables (unset vars become empty with only a warning). Escape every shell-runtime `$` as `$$`. `docker compose config` re-escapes surviving literals back to `$$` in its output, so asserting the `$$` form in rendered output plus zero "variable is not set" warnings makes a solid regression check.
- Compose `${VAR:?message}` hard-fails the deploy when a variable is unset/empty — use it for credentials instead of `${VAR:-default}`, which silently ships the default (e.g. Grafana admin/admin).
- Push a file into a running container without host SSH via the Docker/Portainer archive API: `PUT /containers/<id>/archive?path=<dir>` with a tar body AND `Content-Type: application/x-tar` (omitting the header → HTTP 400). `path` must be an existing dir; if it's a **read-write** bind mount the write lands on the host. A `:ro` mount blocks it (no host-side write path) — check the mount mode before assuming you can deploy config this way.

- `docker compose` interpolates `$VAR`/`${VAR}` inside `command:`/`entrypoint:` blocks at parse time — embedded shell scripts silently lose their variables (unset vars become empty with only a warning). Escape every shell-runtime `$` as `$$`. `docker compose config` re-escapes surviving literals back to `$$` in its output, so asserting the `$$` form in rendered output plus zero "variable is not set" warnings makes a solid regression check.
- Compose `${VAR:?message}` hard-fails the deploy when a variable is unset/empty — use it for credentials instead of `${VAR:-default}`, which silently ships the default (e.g. Grafana admin/admin).
- Push a file into a running container without host SSH via the Docker/Portainer archive API: `PUT /containers/<id>/archive?path=<dir>` with a tar body AND `Content-Type: application/x-tar` (omitting the header → HTTP 400). `path` must be an existing dir; if it's a **read-write** bind mount the write lands on the host. A `:ro` mount blocks it (no host-side write path) — check the mount mode before assuming you can deploy config this way.
- Docker image tags allow only `[A-Za-z0-9_][A-Za-z0-9._-]{0,127}` — a `/` is rejected with "invalid tag format". Any scheme that interpolates a git branch into a tag breaks on ordinary `feature/foo` names. Sanitize with a regex substitution and append a short hash of the original so branches that normalise alike stay distinct.

## Prometheus

- `absent(metric)` alert rules fire PERMANENTLY when the metric's exporter was never deployed/scraped — an alert meant to detect an outage instead manufactures one, while non-absent() rules against missing metrics silently never fire. Keep alert rules and scrape jobs in sync (and lint for it).
- Standalone cAdvisor exposes no restart-count metric; detect restart loops with `changes(container_start_time_seconds{name=~".+"}[15m]) > N`.
- Hot-reload config/rules with SIGHUP (`docker kill -s HUP <ctr>`) — but only if Prometheus runs with `--web.enable-lifecycle`; otherwise `POST /-/reload` 403s and SIGHUP is the only in-place reload. A `docker restart` works too but drops the metrics series (gap). Run `promtool check config|rules` inside the container before reloading.
- A textfile-collector metric is absent until first written, so `absent(metric) for: 26h` (long `for:`) is bootstrap-safe — the first scheduled write clears it before the window — yet still fires if the series later vanishes. Pairs with value-based rules (`metric == 0`, staleness), which go blind when the series is absent entirely.
- GitLab Omnibus bundles its OWN node_exporter on `localhost:9100`; expose it on the LAN via `gitlab.rb` `node_exporter['listen_address']='0.0.0.0:9100'` instead of installing a second exporter (port clash). Do NOT set `node_exporter['flags']` to add one flag — it REPLACES Omnibus's whole default set (mountstats, runit, runit.servicedir), so leave the textfile dir at Omnibus's default `/var/opt/gitlab/node-exporter/textfile_collector`.

## VMware VCSA

- VCSA partitions storage into many small LVM volumes (`/storage/log` ~10G, `/storage/archive` ~49G). A single runaway log file can fill a partition and cascade into service failures. Always check `df -h` on the VCSA when SSO behaves inexplicably.
- The most dangerous VCSA logs aren't the ones covered by VMware's built-in rotation (rsyslog + imfile) — they're the Java stderr/stdout redirects (`*-runtime.log.stderr`) that bypass syslog entirely, have no size cap, and no rotation.
- When content-library loses STS cert trust (e.g. after MACHINE_SSL_CERT renewal that restarts some services but not content-library), it writes `UntrustedSslCertificateException` stack traces at ~3 GB/hour. Fix: `vmon-cli -r content-library`. Proactively restart it after any cert change.
- A full `/storage/log` breaks vCenter WebSSO login — vsphere-ui can't write SAML session state, producing "No matching request found for WebSSO response." The error is misleading (looks like SSO/cert misconfiguration, actually disk space).
- VMware services on VCSA 8.0 are managed by `vmon-cli`, not systemd directly. All vmware-*.service units show as "masked" in systemctl — this is normal. Use `/usr/lib/vmware-vmon/vmon-cli -s <svc>` for status.

## Claude Code Bash Tool

- Parallel Bash tool calls in one message share the same persistent working directory — a `cd` in one call leaks into its siblings (two parallel `npm run test` calls both ran in backend/). Give every call an absolute `cd` prefix when parallelizing.
- A wait loop like `until ! pgrep -f "jest --runInBand"; do sleep 30; done` never exits: the watcher's own command line contains the pattern, so `pgrep -f` matches itself. Symptom is a job that appears to run forever while `etime` on the "found" PIDs keeps resetting (you are seeing successive watchers, not one long process). Match the real process instead — `pgrep -f "node.*/\.bin/jest"`, or filter with `ps -eo args | grep -v "zsh -c"` — or poll for the output artifact (`until [ -s out.log ]`) rather than the process.
- Piping a long-running background command through `tail -N` buffers ALL output until it exits, so the task output file stays 0 bytes and gives no progress signal. Redirect to a log file (`> run.log 2>&1`) and tail the file separately when you need to watch progress.

- Parallel Bash tool calls in one message share the same persistent working directory — a `cd` in one call leaks into its siblings (two parallel `npm run test` calls both ran in backend/). Give every call an absolute `cd` prefix when parallelizing.

## Error Handling Refactors

- When narrowing a blanket `catch → 400` to a typed error class, audit every path that previously flowed through the catch: broad catches often mask genuinely broken code paths as plausible client errors (a "not found" 400 that was really an unresolvable id). Expect the narrowing to surface latent bugs — that's it working.

## Git Staging

- Once an insertion and a nearby deletion in the same file get entangled by diff minimization, hunk-level staging (`git apply --cached` on extracted hunks) can't separate them. Clean split: temporarily revert one change so the diff is pure, commit, re-apply, commit.

## Git Credential Helpers

- `GIT_ASKPASS` helpers run as child processes and read credentials from their environment — variables sourced from a file without `set -a`/`export` are invisible to them, so pushes fail auth even though the parent script sees the variable.

## Bash TSV Parsing

- Tab is an "IFS whitespace" character, so `IFS=$'\t' read` collapses consecutive tabs into one delimiter — an empty field in `jq @tsv` output silently shifts all later variables left. When extracting optional JSON fields into TSV, emit a non-empty sentinel (`// "none"`) and filter it out in bash.

## Claude Code Output Styles

- Native output styles were deprecated in Claude Code v2 — style plugins (e.g. `explanatory-output-style@claude-plugins-official`) now inject their instructions via a SessionStart hook (`hooks.json` → script → stdout becomes session context). No `outputStyle` settings key is involved; disabling the plugin in `enabledPlugins` removes the style. Local directory-source plugins can use the same mechanism for always-on custom styles.

## Claude Code Statusline

- Statusline stdin JSON exposes reasoning effort at `.effort.level` (`low`/`medium`/`high`/`xhigh`/`max`); the key is omitted entirely when the model has no effort parameter. Also available: `.fast_mode`, `.thinking.enabled`, `.rate_limits`, `.agent.name`, `.exceeds_200k_tokens`.

## Shell Script Extraction & set -e

- Line-number-based `sed -n 'A,Bp'` extraction (e.g. a test harness slicing a section out of another script) couples silently to the source's exact line layout. Inserting any line upstream shifts the range and can split a block — e.g. capture an `if` but not its `fi` — producing an unparseable fragment. Use marker-based extraction instead: `sed -n '/^### START MARKER/,/^# END MARKER/p' file | head -n -1`.
- `git clone git+https://...` is invalid: `git+https` is a pip/pipx URL scheme, not a git transport, so the clone fails. Without `set -euo pipefail` the failure is swallowed and later steps run against the missing dir (e.g. `uv tool install <dir>` on a dir that was never created) — also silently. A script that installs tools should have `set -euo pipefail`; then guard each install for idempotency (`command -v x || install x`, `[ -d dir ] || git clone ...`) so re-runs don't abort.
- zsh 5.9 handles `set -euo pipefail` correctly: empty-array expansion under `set -u` is safe, `cmd || fallback` survives under `set -e`, and a bare failing command aborts. Safe to add to a zsh script (unlike some older zsh set -e lore).
- `systemctl enable/start` aborts with "System has not been booted with systemd as init system" on any host where systemd isn't PID 1 (Docker containers, WSL-without-systemd). Under `set -e` this kills the whole install script. Guard service-enable with `if [ -d /run/systemd/system ]; then systemctl ...; fi` — a presence check, not error-masking. This is a portability bug static review misses (it only fails off-systemd) — running the install in a container surfaces it.
- Verifying symlinks: a whole-directory symlink (`~/.claude/skills -> repo/skills`) makes files INSIDE it real files, not symlinks — so a per-file `[ -L dir/file ]` check FAILS ("exists but not a symlink"). Verify the directory symlink itself (`[ -L dir ]`) plus that each file resolves (`[ -f dir/file ]`), not each file's link-ness.

- Line-number-based `sed -n 'A,Bp'` extraction (e.g. a test harness slicing a section out of another script) couples silently to the source's exact line layout. Inserting any line upstream shifts the range and can split a block — e.g. capture an `if` but not its `fi` — producing an unparseable fragment. Use marker-based extraction instead: `sed -n '/^### START MARKER/,/^# END MARKER/p' file | head -n -1`.
- `git clone git+https://...` is invalid: `git+https` is a pip/pipx URL scheme, not a git transport, so the clone fails. Without `set -euo pipefail` the failure is swallowed and later steps run against the missing dir (e.g. `uv tool install <dir>` on a dir that was never created) — also silently. A script that installs tools should have `set -euo pipefail`; then guard each install for idempotency (`command -v x || install x`, `[ -d dir ] || git clone ...`) so re-runs don't abort.
- zsh 5.9 handles `set -euo pipefail` correctly: empty-array expansion under `set -u` is safe, `cmd || fallback` survives under `set -e`, and a bare failing command aborts. Safe to add to a zsh script (unlike some older zsh set -e lore).
- `systemctl enable/start` aborts with "System has not been booted with systemd as init system" on any host where systemd isn't PID 1 (Docker containers, WSL-without-systemd). Under `set -e` this kills the whole install script. Guard service-enable with `if [ -d /run/systemd/system ]; then systemctl ...; fi` — a presence check, not error-masking. This is a portability bug static review misses (it only fails off-systemd) — running the install in a container surfaces it.
- Verifying symlinks: a whole-directory symlink (`~/.claude/skills -> repo/skills`) makes files INSIDE it real files, not symlinks — so a per-file `[ -L dir/file ]` check FAILS ("exists but not a symlink"). Verify the directory symlink itself (`[ -L dir ]`) plus that each file resolves (`[ -f dir/file ]`), not each file's link-ness.
- Under `set -e`, `cmd; EXIT_CODE=$?` never reaches the assignment: a non-zero `cmd` aborts the script first, so any `if [ $EXIT_CODE -eq 124 ]` timeout/error reporting below it is dead code (the exit status still propagates, so it looks fine from outside). Use `EXIT_CODE=0; cmd || EXIT_CODE=$?` to capture the status without tripping `set -e`.

## SSH Remote Scripting

- `ssh host 'bash -s' <<'EOF'` delivers the script over **stdin** — any inner command that reads stdin (`docker exec -i`, `psql` without `-c`, `read`) **swallows the rest of the script**; bash hits EOF and exits 0 mid-script with no error. Fix: drop `-i` from docker execs that don't consume stdin, add `< /dev/null` to stdin-hungry commands, and keep `-i` only where stdin is the intended data source (`docker exec -i ... pg_restore < dump`). For anything nontrivial, prefer `ssh host "command string"` or scp-then-execute over stdin scripts.

## zsh vs bash Scripting Gotchas

- In zsh, `path` is a special array tied to `PATH`; using `path` as a loop or local variable rewrites the command search path and can make ordinary commands suddenly report “command not found.” Use a different variable name such as `file_path`.
- zsh does NOT word-split unquoted `$VAR` (unlike bash). Storing a command line in a string (`CMD="sshpass -p $PASS ssh host"`) and invoking `$CMD` makes zsh treat the entire string as one command name — it fails AND the "command not found" error echoes the fully-expanded line, leaking any embedded secrets into the terminal/log. Wrap remote-command helpers in functions (or arrays), never command-strings.

- `long_running.sh | tee log` in zsh reports **tee's** exit code — a failing script looks like exit 0 (zsh doesn't default to pipefail). Prefix background/task runner pipelines with `set -o pipefail;` or task-completion notifications lie about success.

- zsh's `NOMATCH` also applies inside command substitutions: unquoted Git revisions such as `HEAD^` and SQL fragments such as `count(*)` can fail before the command runs. Quote glob-bearing arguments (`git rev-parse 'HEAD^'`) and keep SQL fully quoted (or use `COUNT(1)`).
- `${PIPESTATUS[0]}` is bash-only; zsh spells it lowercase `$pipestatus[1]` (1-indexed). In zsh the bash form silently expands to empty, so `echo "EXIT=${PIPESTATUS[0]}"` prints nothing rather than erroring — capture the exit code without a pipe when checking a linter/test command.

- nvm lazy-load stubs (`node()/npm()/npx()` calling a `nvm()` stub) commonly `unfunction nvm node npm npx` **before** verifying `$NVM_DIR/nvm.sh` loaded. Any shell that inherits the functions but not the `export NVM_DIR` (non-interactive tool shells) then fails the guard with the stubs already gone, emitting `nvm:3: command not found: nvm` on every node call — which pollutes stdout/stderr of linters and breaks output parsing. Fix: re-derive `: "${NVM_DIR:=$HOME/.nvm}"` inside the stub and check the file exists *before* unfunctioning.

## SQLite

- `sqlite3 db ".backup 'dest'"` uses the online backup API, which reads through the source connection — committed WAL frames ARE included. No prior `wal_checkpoint` is needed for backup correctness (checkpoint first only when copying the raw file directly).

## GitLab API

- Root admin PAT returns 401 on the merge endpoint if `root` isn't an explicit project member. Use `Sudo: <username>` header (requires `sudo` scope on the token) to impersonate a project owner for the merge call.
- The `/repository/commits` endpoint accepts an `actions` array with create/update/delete operations, applying all as a single atomic commit — useful for infrastructure changes that must land together.
- Portainer API (`/api/endpoints/{id}/docker/...`) proxies the full Docker Engine API. Create ephemeral containers with host bind mounts + tar archive upload (`PUT /containers/{id}/archive`) to write config files to the host filesystem when SSH is unavailable.

## Hermes Agent MCP Configuration

- `hermes mcp add --env` passes environment variables to the stdio subprocess, but if the connection test fails the env vars can end up as `args` entries instead of an `env:` block. Always verify the generated YAML after a failed connection test.
- When the current shell lacks the `docker` group (needs re-login), wrap the MCP command with `sg docker -c "..."` to acquire the group for that subprocess — avoids requiring a full session re-login.
- Hermes MCP servers configured via `hermes mcp add` that fail the connection test are saved as `enabled: false` — edit `~/.hermes/config.yaml` to set `enabled: true` after fixing the issue, or use `hermes mcp test <name>` to verify.
- Pre-warm the npx cache (`npx -y <pkg> --help`) before `hermes mcp add` for npx-based servers — first-run package download otherwise exceeds the 40s MCP connection-test timeout and the server saves as disabled.

## Hermes Mixture of Agents (MoA)

- MoA presets live under `moa:` in config.yaml (`default_preset`, `active_preset`, `presets.<name>` with `reference_models[]`, `aggregator`, temps, `max_tokens`). `active_preset: ''` = on-demand via `/moa <prompt>`; setting it to a preset name makes MoA the active mode for EVERY turn (expensive). `/moa` uses `default_preset`.
- MoA slots store only `{provider, model}` — `base_url` is dropped by `_clean_slot`. A local custom provider (e.g. Ollama at a LAN IP) therefore CANNOT be a MoA slot: `provider: custom` resolves via `resolve_runtime_provider` to OpenRouter with no key. Use natively-resolved providers (openai-codex, anthropic, ollama-cloud) instead. Verify any slot with `resolve_runtime_provider(requested=prov, target_model=model)` — check the returned `api_key` is non-empty before saving the preset.
- Hermes plugin pip deps install into its venv via `uv pip install --python ~/.hermes/hermes-agent/venv/bin/python <pkg>` (the venv has no `pip`). Hindsight local_embedded needs `hindsight-all` (not just `hindsight-client`/`hindsight-embed`) — the meta-package provides the `hindsight` module that `is_available()` imports.

## VMware ESXi Persistence & Recovery

- ESXi `/etc` is an in-RAM visorfs rebuilt each boot from the active bootbank's `state.tgz` (encrypted `local.tgz.ve` on 8.x — decrypt on-host with `crypto-util envelope extract --aad ESXConfiguration`). `/sbin/auto-backup.sh` (hourly) archives ONLY files with a filesystem-managed `.#<name>` branch-marker beside them, plus the ConfigStore DB. Files created via scp/shell get no marker, cannot be given one (`touch /etc/.../.#x` → Operation not permitted), and silently vanish on reboot. Persist through sanctioned interfaces instead: `esxcli system ssh key add` (SSH keys), `esxcli system account set` (passwords) — both land in the ConfigStore.
- ESXi upgrades stage the new image into the INACTIVE bootbank with a state snapshot from staging time, while hourly backups keep updating only the active bank. The upgrade reboot swaps banks and can resurrect months-old config (certs, passwords, authorized_keys). After any ESXi upgrade reboot, verify the served cert and re-push config before trusting automation against the host.
- Locked out of ESXi root (password reverted/unknown) while the host is still CONNECTED in vCenter: `docker run vmware/powerclicore` → `Connect-VIServer <vcenter>` → `Get-EsxCli -VMHost <host> -V2` → `$esxcli.system.account.set.Invoke(@{id="root";password=...;passwordconfirmation=...})` — esxcli passthrough runs over the vCenter→vpxa channel, no host creds needed. `sshpass` exit code 5 = wrong password (vs 255 = other SSH failure).
- Cert-revert forensics: a "self-signed" cert with an issuer of `CN=CA, DC=vsphere, DC=local` is VMCA-signed, and an OLD notBefore date proves a restored file (state/backup rollback) rather than fresh re-provisioning — a new VMCA push or hostd regen would be dated at event time.

## Strapi

- In a two-layer auth setup (route-level users-permissions + controller checks), the error TEXT identifies the denying layer: a bare `"Forbidden"` is Strapi's route-level `up_permissions` denial (role lacks the action entirely — fires before the controller runs); a specific message like "Cannot create leagues for this game" is the controller's Layer-2 denial. On a bare "Forbidden", compare `up_permissions`/`up_permissions_role_lnk` rows for the role before touching controller logic — the usual cause is an unapplied permission-seed SQL.
- Strapi v5 changed server config `proxy` from v4's boolean to an object — `proxy: { koa: true }` sets Koa's `app.proxy`; a v4-style `proxy: true` is **silently ignored**. Symptom behind a TLS-terminating reverse proxy: OAuth/grant endpoints 500 with "Cannot send secure cookie over unencrypted connection" (koa-session refuses the secure cookie because ctx.secure is false without trusted X-Forwarded-Proto). Invisible in dev (no TLS) — smoke-test the OAuth entry endpoint over HTTPS.
- The users-permissions admin "Enable sign-ups" advanced setting only gates `POST /api/auth/local/register`. OAuth provider flows (`/api/connect/<provider>` → `/api/auth/<provider>/callback`) create accounts unconditionally — to make a Strapi app invite-only, gate account creation inside the provider callback (custom provider override or users-permissions extension), not via the admin toggle.
- The v5 document service resolves a `documentId` through a `documentId -> id` map **cached on the request state** (`__documentServiceIdMap`, cleared only on publish/discard). So any code that rewrites `document_id` with raw SQL and then passes that new documentId back to the document service can get a *neighbouring* row's entity id. Classic symptom: a relation silently links to the wrong record, surfacing much later as an unexplained 403/404 rather than a setup error. Link tables store the integer id anyway — link by entity id when you have gone behind the document service's back, and assert the link landed where intended.
- **A plugin extension (`src/extensions/<plugin>/strapi-server.ts`) can be applied more than once in one process.** Strapi loads the application context several times (3x in an integration run) and each load gets the same require-cached plugin object, so a wrapper written as `const original = plugin.controllers.x; plugin.controllers.x = {...original, method}` wraps *its own output*. Harmless only if the wrapper is pure. It becomes a correctness bug the moment the wrapper **mutates the request body and then delegates** — the inner copy re-validates the already-transformed value and can reject what the outer copy just approved. Guard the application with a marker property and return early. Verify with a patch counter (`0,1,2` proves nesting), not by reasoning.
- Debugging rule that paid off here: when an authorization check denies something, log what the *check itself returned* before believing the error message. A 403 saying "you have not unlocked that" while the entitlement query returns a match means the denial came from a different layer than the message implies.

- Strapi's users-permissions plugin runs `syncPermissions()` on every bootstrap and DELETES any `up_permissions` row whose action is not `<api|plugin>::<x>.<controller>.<method>` for a method that exists on a loaded controller (`services/users-permissions.js`, `_.difference(permissionsFoundInDB, allActions)`). Synthetic "semantic" permissions (`user.manage-all`, `game.manage-formats`) therefore cannot survive a restart no matter how they are seeded — any permission check against one fails closed forever. Custom authorization needs either a real route/controller method or a role check, never an invented action string.

- Strapi v5 changed server config `proxy` from v4's boolean to an object — `proxy: { koa: true }` sets Koa's `app.proxy`; a v4-style `proxy: true` is **silently ignored**. Symptom behind a TLS-terminating reverse proxy: OAuth/grant endpoints 500 with "Cannot send secure cookie over unencrypted connection" (koa-session refuses the secure cookie because ctx.secure is false without trusted X-Forwarded-Proto). Invisible in dev (no TLS) — smoke-test the OAuth entry endpoint over HTTPS.
- The users-permissions admin "Enable sign-ups" advanced setting only gates `POST /api/auth/local/register`. OAuth provider flows (`/api/connect/<provider>` → `/api/auth/<provider>/callback`) create accounts unconditionally — to make a Strapi app invite-only, gate account creation inside the provider callback (custom provider override or users-permissions extension), not via the admin toggle.

- Koa (and therefore Strapi) error handling replaces the response **body** but keeps headers already set on the response. A middleware that sanitises a sensitive header (e.g. rewriting a token-bearing `Location`) as the last statement of its success path leaks that header on every throwing path — the error answer still carries the original value. Sanitise the header at the point the secret is observed, before any branch that can throw, not after the work succeeds.

## Cloud Provisioning (first-boot)

- Fresh Ubuntu VMs hold the dpkg lock for minutes after boot (cloud-init + unattended-upgrades). Any bootstrap script must `cloud-init status --wait` before apt operations and use `apt-get -o DPkg::Lock::Timeout=600` for the independently-timed unattended-upgrades runs.
- Let's Encrypt negative-caches NXDOMAIN per the zone's SOA minimum TTL (DigitalOcean zones: 1800s). If certbot runs before a freshly created DNS record propagates, retries keep failing with NXDOMAIN until the negative TTL expires — even after authoritative NS serve the record. Wait for `dig @<authoritative-ns>` to resolve BEFORE the first issuance attempt; after a failed attempt, wait out the full TTL (and mind the 5-failures/hour rate limit).

## DigitalOcean

- Projects are organizational folders only — no functional isolation. DNS records are domain-scoped, not project-scoped: any token with domain write access can add records to a domain regardless of which project holds it, and adding a subdomain A record never touches existing records. API tokens ARE team-scoped, so resources in a different *team* (vs project) need a separate token.
- App Platform (as of mid-2026) has no persistent volumes — container filesystems are wiped every deploy. Apps that write local files (e.g. Strapi's default upload provider) must move that state to Spaces/S3 before migrating. Ingress rules support both path-prefix and domain (authority) matching to route different hostnames to different components.

## GitHub CLI

- `gh` has no first-class sub-issue command. Link native sub-issues via GraphQL: fetch both issues' node IDs, then `gh api graphql -H "GraphQL-Features: sub_issues" -f query='mutation{addSubIssue(input:{issueId:"<parent>",subIssueId:"<child>"}){subIssue{number}}}'`. The parent issue then renders a sub-issue progress tracker.
- Strapi v5 content-API input validation rejects relation keys the caller cannot READ: writing a relation (e.g. a custom `created_by` → users-permissions user) through a validated body requires the caller's role to hold `find` on the TARGET content type, else 400 "Invalid key <field>". Revoking `plugin::users-permissions.user.find` from a role silently breaks every controller that injects user relations into `ctx.request.body` before `super.create()`. Service-level `strapi.documents().create()` calls bypass this validation.

- `gh` has no first-class sub-issue command. Link native sub-issues via GraphQL: fetch both issues' node IDs, then `gh api graphql -H "GraphQL-Features: sub_issues" -f query='mutation{addSubIssue(input:{issueId:"<parent>",subIssueId:"<child>"}){subIssue{number}}}'`. The parent issue then renders a sub-issue progress tracker.
- Before creating a PR with `gh pr create`, check for `.github/PULL_REQUEST_TEMPLATE.md` (or `pull_request_template.md`) in the repo. If one exists, use its exact structure — fill in each section, check the relevant checkboxes, and do not invent a custom format. The template is what maintainers expect and may enforce via CI.
- Strapi v5 content-API input validation rejects relation keys the caller cannot READ: writing a relation (e.g. a custom `created_by` → users-permissions user) through a validated body requires the caller's role to hold `find` on the TARGET content type, else 400 "Invalid key <field>". Revoking `plugin::users-permissions.user.find` from a role silently breaks every controller that injects user relations into `ctx.request.body` before `super.create()`. Service-level `strapi.documents().create()` calls bypass this validation.
- `gh pr checks --watch` exits immediately with `no checks reported on the '<branch>' branch` when the workflow run has not been *created* yet (busy runners / event lag) — it does not wait for runs to appear. Poll `gh run list --branch <branch>` (or the commit's check-suites API) until a run exists, then start `--watch`.

## GitHub Actions Self-Hosted Runners

- `svc.sh` does not exist in the runner tarball — it is generated by `config.sh` after successful registration. Registration tokens (from the UI or `gh api -X POST repos/<o>/<r>/actions/runners/registration-token`) expire after 1 hour but work standalone without gh CLI auth.
- Job results are trackable without gh auth via the runner's systemd journal: `journalctl -u actions.runner.<org>-<repo>.<name>.service` logs `Running job: X` and `Job X completed with result: Succeeded|Failed`. But step CONSOLE output is NOT in `_diag/Worker_*.log` (only step telemetry/timings/results) — reproduce failures locally or fetch logs via gh to see actual errors.
- Self-hosted runners on a dev host share the docker daemon and localhost: integration tests that `docker exec` into dev-stack containers pass/fail with the dev stack's state. Use distinct compose project names (`-p ci-project`) to isolate CI compose resources, and `touch` gitignored `env_file` targets before compose commands in CI checkouts.
- A workflow run can remain `queued` while one of its jobs is already `in_progress`. Inspect `.jobs[]` with `gh run view <id> --json jobs` instead of relying only on the run-level status.

- `svc.sh` does not exist in the runner tarball — it is generated by `config.sh` after successful registration. Registration tokens (from the UI or `gh api -X POST repos/<o>/<r>/actions/runners/registration-token`) expire after 1 hour but work standalone without gh CLI auth.
- Job results are trackable without gh auth via the runner's systemd journal: `journalctl -u actions.runner.<org>-<repo>.<name>.service` logs `Running job: X` and `Job X completed with result: Succeeded|Failed`. But step CONSOLE output is NOT in `_diag/Worker_*.log` (only step telemetry/timings/results) — reproduce failures locally or fetch logs via gh to see actual errors.
- Self-hosted runners on a dev host share the docker daemon and localhost: integration tests that `docker exec` into dev-stack containers pass/fail with the dev stack's state. Use distinct compose project names (`-p ci-project`) to isolate CI compose resources, and `touch` gitignored `env_file` targets before compose commands in CI checkouts.

## Git Hook Paths

- In a linked worktree, `git rev-parse --path-format=absolute --git-path hooks/<hook>` can resolve a hook symlink to its external target. A guard that requires the returned path to stay under `--absolute-git-dir` can therefore reject its own valid symlink; validate the configured hook directory before dereferencing the hook file.
- Git rebase and `git am` can both use `.git/rebase-apply`. Check `rebase-apply/rebasing` for a rebase and `rebase-apply/applying` for `git am`; the directory alone does not identify the operation.
- `validate-commit-references.sh` (dotfiles) supports a per-repository opt-out: `git config hooks.referenceGuard.disabled true` makes the script exit 0 in every mode (agent PreToolUse, installed git hooks, `--install`). The commit-msg hook only enforces references when branch context exists (open PR or cached issues, or `COMMIT_REFERENCE_*` env) — a plain commit on a branch with no PR passes even without the opt-out.

## Shell Exit Codes in Pipelines

- `cmd | tail -N` (or `| grep`) makes the pipeline exit with the LAST command's code — a failing test run reports exit 0 and background tasks look "completed" while tests failed. Pattern: `cmd > /tmp/out.log 2>&1; echo "exit=$?"; tail -N /tmp/out.log`. Same trap chains state-changing git commands: `git checkout ... | tail -2 && next-cmd` runs `next-cmd` even when checkout aborted.
- With `set -o pipefail`, an early-exit consumer such as `producer | awk '{ print; exit }'` can make a large producer fail with SIGPIPE (exit 141). Make the consumer read the full stream while recording only the first match when producer success is required.
- `journalctl -f` block-buffers when piped (empty output even with `grep --line-buffered` downstream). For "wait until N events" watchers, poll `journalctl --since "$TS" | grep -c pattern` in a loop instead of streaming.

- `cmd | tail -N` (or `| grep`) makes the pipeline exit with the LAST command's code — a failing test run reports exit 0 and background tasks look "completed" while tests failed. Pattern: `cmd > /tmp/out.log 2>&1; echo "exit=$?"; tail -N /tmp/out.log`. Same trap chains state-changing git commands: `git checkout ... | tail -2 && next-cmd` runs `next-cmd` even when checkout aborted.
- `journalctl -f` block-buffers when piped (empty output even with `grep --line-buffered` downstream). For "wait until N events" watchers, poll `journalctl --since "$TS" | grep -c pattern` in a loop instead of streaming.

## Windows GUI Automation over SSH

- A GUI app launched from an SSH (non-interactive/session-0) shell loads its DLLs but cannot render or drive a UI (e.g. mstsc connects to nothing). Drive it in a **logged-in interactive console session**: register a scheduled task with `New-ScheduledTaskPrincipal -LogonType Interactive -UserId <console user>` + `Start-ScheduledTask` — it runs on that user's desktop. If the console is at the lock screen (no logged-in user), this path is unavailable (needs autologon / real login).
- **UIA `TogglePattern.Toggle()`/`InvokePattern.Invoke()` often does NOT fire a WPF dialog's real handlers** (checkbox visually toggles but OK never enables/dispatches). Use UIA only to *locate* an element (`BoundingRectangle` center), then click with a real synthesized event — `user32!SetCursorPos` + `mouse_event(LEFTDOWN|LEFTUP)` — which fires the genuine handler.
- Win11 mstsc blocks headless RDP connects with two modal dialogs before any TCP: the "Opening Remote Desktop Connection" RDP-file warning (its checkbox persists per-user once accepted) and the "Unknown publisher / allow local resources" prompt (per-launch; tick **Drives** to get drive redirection). Suppress the drive prompt via `HKCU\Software\Microsoft\Terminal Server Client\LocalDevices\<server-ip>` = device-mask DWORD (writable into a live user's `HKEY_USERS\<SID>` from an admin session).
- To see another session's actual blocking dialog: run a `System.Drawing.Graphics.CopyFromScreen` capture as an Interactive-principal scheduled task in that session, pull the PNG, and read it — beats guessing which prompt is up.

## Python Dynamic Module Loading

- `importlib.util.module_from_spec()` + `spec.loader.exec_module()` does **not** register the module in `sys.modules`, but the deprecated `loader.load_module()` did. Any library that resolves a class by name lookup — e.g. impacket's `rpcrt.py` doing `__import__(request.__module__); sys.modules[request.__module__]` to find the NDRCALL `...Response` class — raises `ModuleNotFoundError` under the modern API. Per the Python docs, assign `sys.modules[name] = module` *before* `exec_module()`.
- `loader.load_module()` reuses an existing `sys.modules[name]` entry and executes new code **into that same module object**. Loading N files under one shared name (e.g. `spec_from_file_location("Plugin", path)`) leaves every earlier reference mutated to the last-loaded file's contents — a silent cross-plugin clobber that only shows when references are held across loads.
- A package directory shadows a sibling module of the same name: with both `proto/smb/` and `proto/smb.py`, `import proto.smb` resolves to the **package**. A dependency smoke-test using plain imports can therefore pass while code that loads `smb.py` *by path* fails on a missing dep. Verify by exercising the real loader, not an import.

## pydantic-settings + Docker Compose



## Linux Swap Management

- An **active** swapfile cannot be renamed or unlinked. The kernel sets `S_SWAPFILE` on the inode and `may_delete()` in `fs/namei.c` returns `-EPERM`. `mv` fails with "Operation not permitted" even under sudo, with no immutable attr and no AppArmor denial. Run `swapoff` on the file first, then rename, then `swapon`.
- To resize a swapfile with no capacity gap: create the new file, `swapon` it, then `swapoff` the old one so its pages migrate to the new swap instead of RAM. `swapoff` of a full 1.7G file took ~31s.
- `fallocate -l <size>` works for ext4 swapfiles; `dd` is only needed on btrfs/CoW filesystems.
- Diagnose swap exhaustion with `/proc/pressure/memory` (PSI) and `/proc/vmstat` `pswpout`, not just `free -h`. PSI `full avg300` above ~20 means all tasks stalled on memory for that share of the window.

## psycopg / PostgreSQL COPY

- A PostgreSQL connection is half-duplex during COPY. Streaming a server-side (named) cursor over the *same* connection you are COPYing into deadlocks: the backend sits in `ClientRead` waiting for COPY data while the client waits for cursor rows. Use a second connection for the read side.
- A second connection cannot read a table the first connection has TRUNCATEd in an open transaction (ACCESS EXCLUSIVE lock). Stage data from tables nothing is writing to, and commit before opening the reader.
- `psycopg.sql.SQL(...).format(sql.Identifier(name))` is the way to build dynamic table/column SQL — it satisfies pyright's `LiteralString` requirement on `execute()` without any `# type: ignore`.
- `LEAST()`/`GREATEST()` ignore NULLs in PostgreSQL, unlike most functions — handy for "earliest non-null date" without COALESCE gymnastics.

## Shell: pkill/pgrep self-match

- `pkill -f "<pattern>"` and `pgrep -f` match the invoking shell's own command line when the pattern appears in it, so the shell kills itself (exit 144 in zsh). Kill by PID file or free the port with `fuser -k <port>/tcp` instead.
- With `setsid ... &`, the PID captured from `$!` is often an intermediate shell rather than the process that ends up holding the port. Stop scripts must free the port, not just kill the recorded PID, or an orphan keeps listening and the replacement dies with EADDRINUSE while the stale server keeps answering.

## Next.js 16

- `middleware.ts` is renamed to `proxy.ts`, and the exported function must be named `proxy` (or be the default export).
- Segment config exports such as `export const revalidate` must be statically analysable literals. An imported constant fails the build with "Invalid segment configuration export detected".
- With `output: "standalone"`, `next start` does NOT serve metadata routes (`/robots.txt`, `/icon.svg`) — they build fine but 404 at runtime. Run `node .next/standalone/server.js` instead, after copying `.next/static` in beside it.
- Next caches 404s in `.next/cache`; a route added later can keep 404ing with `x-nextjs-cache: HIT` until the cache is cleared.
- Next 15.x carries high-severity transitive vulns in `postcss` and `sharp` that are only fixed in 16.x.

## Driver / FSCTL Security Testing

- **An `ACCESS_DENIED` from `DeviceIoControl` is only evidence about the target if you first prove the
  handle opened with the access the control code requires.** Decode the code
  (`CTL_CODE = dev<<16 | access<<14 | func<<2 | method`): a FILE_WRITE_ACCESS code probed with a
  `GENERIC_READ` handle is denied by the I/O manager before the driver runs. Print the access actually
  obtained, and distinguish an open failure from an FSCTL denial.
- **A too-small or aliased output buffer can turn a genuine SUCCESS into a misleading error.** Passing
  one buffer as both input and output, or an undersized output buffer, made an FSCTL that really does
  succeed for a non-admin report ACCESS_DENIED — and nearly caused a true finding to be retracted.
  Use separate, generously sized buffers when probing.
- **Enumerate every dispatcher, not just the first.** A driver's main IOCTL router often has a default
  arm that calls a second routing function handling many more codes. Coverage claimed from the first
  router alone is a false completion.
- **Verdicts from decompiler output can invert at the instruction level.** Ghidra rendered a length as
  a signed `char` cast (`(int64_t)*(char*)p`), implying sign-extension overflow; the actual guard was
  `cmp dl, 0x18` + `ja` — an UNSIGNED compare bounding it to [0,24], making the cast harmless. Confirm
  signedness from the jump mnemonic (`ja/jbe` unsigned vs `jg/jle` signed), never from the C rendering.

## Poetry

- `poetry lock` / `poetry install` exiting **139 (SIGSEGV) with no output** is the keyring backend
  crashing, not a corrupt project. Without the fix the real dependency-resolution error is never
  printed. Permanent fix, already applied on this machine: `poetry config keyring.enabled false`
  (persists in Poetry's own config, no shell edits). One-shot alternative:
  `PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring`.
- `^0.0.22` on a `0.0.x` package means `>=0.0.22,<0.0.23` — the caret pins the patch level, so a
  transitive `>=0.0.26` requirement is an outright conflict, not a soft one.
- "The current project could not be installed: No file/folder found for package X" on an application
  (not a library) means packaging mode is on by mistake. Set `package-mode = false` under
  `[tool.poetry]`.

## MCP Servers from FastAPI

- `FastMCP.from_fastapi(app)` names each tool from the route's OpenAPI `operationId`. FastAPI
  generates that from handler name + path + method (`create_test_run_api_runs_post`) unless you
  pass `operation_id=` to the route decorator. Always set it explicitly: it is the agent-facing
  tool name, and without it a plain handler rename silently renames the tool.
- FastMCP 3.x depends on `starlette>=1.0.1`; FastAPI only dropped its `starlette<1.0.0` cap in
  0.133.0. Adding FastMCP to an older FastAPI project forces a FastAPI upgrade.
- Mounting an MCP app inside FastAPI requires chaining `mcp_app.lifespan` into the parent
  lifespan (`async with mcp_app.lifespan(app): yield`), or MCP session handling breaks at runtime
  while the mount still appears to exist. Behind nginx, `/mcp` also needs `proxy_buffering off`
  because responses are SSE streams.

## Linux Swap

- Verify swap functionally without stressing the whole box: `sudo systemd-run --scope -p MemoryMax=120M -p MemorySwapMax=2G python3 alloc.py` where the script allocates ~400M and touches every page. cgroup v2 forces the excess into swap; check `/proc/self/status` `VmSwap` and `swapon --show` USED. A checksum read back after allocation proves the swap round-trip preserves data, not just that pages left RAM.
- `swapoff -a && swapon -a` is exactly the boot activation path, so it validates a new `/etc/fstab` swap entry without a reboot.
- `fallocate -l 16G /swapfile` is safe on **ext4** (unwritten extents, no holes) and is far faster than `dd`. On btrfs/XFS it can produce a file with holes that `swapon` rejects.
- `findmnt --verify` reports `[W] non-bind mount source /swapfile is a directory or regular file` for every swap file. This warning is expected and not a fault.
- Kali/Debian installs often leave a stale `UUID=... none swap sw` line in `/etc/fstab` after a disk change. The UUID resolves to nothing, so `blkid -U <uuid>` fails and systemd generates a `.swap` unit for a missing device. Check the fstab swap line resolves before adding new swap.
- **Never leave a backup file inside `/etc/initramfs-tools/conf.d/`.** initramfs-tools sources *every* file in that directory regardless of name or extension, so `resume.bak.20260729` still sets `RESUME=` and sorts after `resume`, silently winning. `update-initramfs -u` kept emitting the old dead UUID until the backup was moved to `/root/`. The same trap applies to any `conf.d`-style sourced directory — put backups outside the directory, not beside the original.
- `sfdisk --delete` prints `Re-reading the partition table failed.: Device or resource busy` whenever another partition on the same disk is mounted (e.g. root on sda1). The on-disk table *is* written; run `partprobe <disk>` + `udevadm settle` afterward and confirm with `lsblk`. The message is not a failure of the delete.
- Before deleting a swap partition, check `/etc/initramfs-tools/conf.d/resume` and `/proc/cmdline` for `resume=`/`RESUME=`. A hibernate-resume pointer to a removed device makes initramfs wait for a missing device at boot. `RESUME=none` disables the wait; hibernation to a swap *file* additionally needs a `resume_offset=` kernel argument.
- Back up an MBR/GPT layout with `sfdisk --dump /dev/sda > file` before editing; `sfdisk /dev/sda < file` restores it. Do this before any partition deletion — it makes the change reversible.

## Linux Disk & Partition Resize

- Growing a **mounted root** partition is routine, not risky, when the start sector is preserved: `growpart /dev/sda 1` rewrites only the end of the entry (no data moves), then `resize2fs /dev/sda1` grows ext4 online. Always run `growpart --dry-run` first — it prints the old and new `sfdisk -d` side by side, so you can confirm `start=` is unchanged before committing.
- ext4 online growth needs the `resize_inode` feature — check with `tune2fs -l <dev> | grep features`. Confirm afterward in `dmesg`: `EXT4-fs (sda1): resized filesystem to <N>`.
- `tune2fs -l` on a *mounted* ext4 always lists `needs_recovery` because the journal is active. That is not corruption — read `Filesystem state:` instead, which should say `clean`.
- `growpart` leaves ~33 sectors unallocated at the end of the disk by design (GPT secondary-header room). `sfdisk --list-free` may still report `0 B`, so do not chase the gap.
- The reclaimed space is smaller than the raw partition growth: 8 GiB added to a 1 TiB ext4 yielded ~7 GiB usable, the remainder going to group descriptors and the 5% reserved-block pool.

## Chromium Launch Failures (Linux)

- Chromium refuses to start if `~/.config/chromium/SingletonLock` (symlink `<hostname>-<pid>`) names a hostname different from the current hostname. It reports "profile appears to be in use by another Chromium process (PID) on another computer". A dead PID on the *same* host is auto-cleaned, but a hostname change (e.g. `kali` -> `kali-main`) makes the lock permanent. Fix: stop Chromium, then remove `SingletonLock`, `SingletonCookie`, and `SingletonSocket` from the profile directory.
- Chromium blocks its first window until the gnome-keyring `gcr-prompter` "Unlock Keyring" dialog is answered. Processes exist but no window appears. Test the browser separately with `chromium --temp-profile --password-store=basic <url>` to prove the binary works.
- On XFCE, `xdg-open` resolves the browser through `~/.config/xfce4/helpers.rc` (`WebBrowser=`), not through `/etc/xdg/mimeapps.list` or the `x-www-browser` alternative. These three can disagree. Check `helpers.rc` first when an application opens the wrong browser.
- `pkill -f '<pattern>'` matches the agent's own shell command line and kills the shell (non-zero exit, truncated output). Match on a PID list from `pgrep` on a narrow pattern instead.

## gnome-keyring / Secret Service

- `pam_gnome_keyring.so` unlocks ONLY the keyring named `login`. If `~/.local/share/keyrings/default` names any other keyring, every login brings a password prompt for that keyring. Fix: move the items into `login`, then repoint the alias.
- Repoint the default with D-Bus, not by editing the file: `busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service SetAlias so default /org/freedesktop/secrets/collection/login`. This updates the running daemon *and* rewrites `~/.local/share/keyrings/default`. Editing the file alone leaves the daemon on the old alias until it restarts.
- Chromium keeps `Chromium Safe Storage` (the key that encrypts saved passwords and cookies) in the *default* keyring, plus a `Chrome Safe Storage Control` marker. Migrate both items and preserve label + attributes + content type; deleting them makes every saved Chromium password undecryptable.
- Leave no duplicate of a secret in a second keyring: Chromium searches with `SECRET_SEARCH_UNLOCK`, so a copy sitting in a locked keyring pulls up the prompt you were trying to remove.
- Verify a keyring change without logging out: lock the old keyring, run Chromium's own lookup (libsecret schema `chrome_libsecret_os_crypt_password_v2`, attribute `application=chromium`), and watch `pgrep -c -x gcr-prompter` — a non-zero count means a prompt would appear at login.
- The gnome-keyring file header is unencrypted: magic `GnomeKeyring\n\r\0\n`, then major/minor/crypto/hash bytes, name string, ctime, mtime, flags, lock timeout, PBKDF2 iterations, 8-byte salt, 16 reserved bytes, then a 4-byte item count. Reading the item count needs no password and shows what the file really holds.
- A keyring file can carry an item record whose object never materialises. The daemon then lists a D-Bus path that fails with "No such secret item at path", which breaks `Secret.Service.get_sync(..., LOAD_COLLECTIONS)` and `secretstorage.Collection.get_all_items()`. Attribute searches still work. Removing the bad record needs the keyring rewritten, so it needs the keyring password.
