# Global Learned Insights

Accumulated knowledge from working across projects. Auto-maintained by Claude.

## SQLAlchemy Patterns

- When adding a FK to an existing model that's mocked with `SimpleNamespace` in tests, every mock instance needs the new attribute added (typically `=None`). Regex-based replacement across test files is efficient for this.

## Claude Code Parallelism Mechanisms

- Three parallelism levels: **Subagents** (Agent tool, invisible helper returning a result), **Agent Teams** (full independent sessions in tmux panes, user can interact with each), **Workflows** (scripted JS orchestration, deterministic fan-out, no mid-flight steering). Choose by steerability needs, not task size.
- `run_in_background: true` on the Agent tool is the middle ground — the main conversation continues, but the subagent can't be steered. Use for independent lookups that don't gate the next step.
- `teammateMode: "auto"` in settings.json enables tmux split panes when running inside tmux, falling back to in-process agent panel otherwise. Default changed from `"auto"` to `"in-process"` in v2.1.179.

## Claude Code Skills vs Agents

- Skills are prompt templates (directory with SKILL.md) injected into the main conversation -- they run as the main Claude instance, can interact with the user mid-execution, and inherit all available tools. Best for orchestration and interactive workflows.
- Agents are isolated subprocesses (single .md file with YAML frontmatter including explicit `tools` list) that run autonomously and return a single result. Best for parallel execution and autonomous work. Cannot interact with the user mid-task.
- Colon-based namespace in skill directory names (e.g., `bb:full-sweep`) groups related skills in the `/` completion menu and makes them visually distinct from other skills.

## Next.js App Router / React SSR

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

## Claude Code Permissions

- Bash allow/deny patterns use colon-star syntax: `Bash(cmd:*)` matches `cmd` + any args (e.g. `Bash(git log:*)`, `Bash(ruff check:*)`). The space form `Bash(cmd *)` is NOT the matcher. Multi-word prefixes work and a short prefix blankets subcommands — `Bash(docker:*)` already covers `docker compose logs ...`.
- Many read-only commands never prompt (no allowlist entry needed): `cat`/`ls`/`grep`/`find`/`head`/`tail`/`wc`/`cut`/`sort`/`diff`, all git read subcommands (`git log/diff/status/show/branch`), gh read subcommands, `docker ps/images/logs/inspect`. Worth allowlisting only the read-only tools OUTSIDE that set: `objdump`/`nm`/`readelf`/`ping`/`dig`, etc.
- When cwd is the home directory, the "project" `.claude/settings.json` path resolves to the global `~/.claude/settings.json` — they're the same file. `settings.local.json` holds machine-specific grants and (in this setup) is symlinked into `~/.dot_files`, so it IS dotfiles-tracked despite the usual "local = gitignored" convention.

## PostgreSQL JSONB Patterns

- GIN indexes on JSONB columns enable `?|` (any key exists), `@>` (contains), `?&` (all keys exist) operators. Use `postgresql_using="gin"` in SQLAlchemy Index definition.
- SQLAlchemy 2.0 has no built-in support for `?|` -- use `column.op("?|")(pg_array([...]))` with `from sqlalchemy.dialects.postgresql import array as pg_array`.

## Background Tasks / Polling

- Never use unbounded `until <condition>; do sleep N; done` in `run_in_background` commands. These run forever invisibly if the condition is never met. Use a bounded loop: `for i in $(seq 1 N); do <check> && break; sleep 5; done`.

## VMware ESXi

- ESXi FIPS mode rejects Ed25519 SSH keys (`ssh-ed25519 not in PubkeyAcceptedAlgorithms`) and EC TLS certs (rhttpproxy crashes with `asn1 encoding routines::nested asn1 error`). Use RSA-4096 for SSH keys and RSA-2048 for TLS certs.
- ESXi uses BusyBox — `bash` is not available. Use `sh` for remote command execution via SSH.
- ESXi SSH authorized keys live at `/etc/ssh/keys-<user>/authorized_keys` (not `~/.ssh/`). The `AuthorizedKeysFile` directive in sshd_config confirms this path.
- When replacing ESXi TLS certs, restart `rhttpproxy` and `hostd` but NOT `vpxa` (the vCenter agent). Restarting vpxa triggers vCenter to re-provision a VMCA-signed cert, overwriting the custom cert.
- vCenter's `ReconnectHost_Task` always re-provisions VMCA certs on the ESXi host, even with `force=false`. To update the expected thumbprint without triggering cert re-provisioning, directly update `vpx_host.expected_ssl_thumbprint` in the VCDB PostgreSQL database.
- vCenter 8 LE cert replacement requires publishing ISRG Root X1 to VECS TRUSTED_ROOTS via `dir-cli trustedcert publish`, and restarting vsphere-ui after MACHINE_SSL_CERT changes. Without the trusted root, vsphere-ui can't validate the cert chain when connecting to STS/SSO (HTTP 500 on /ui/login).
