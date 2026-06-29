# Global Learned Insights

Accumulated knowledge from working across projects. Auto-maintained by Claude.

## SQLAlchemy Patterns

- When adding a FK to an existing model that's mocked with `SimpleNamespace` in tests, every mock instance needs the new attribute added (typically `=None`). Regex-based replacement across test files is efficient for this.

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

## Testing

- When a value has a formatter and a parser (dates, IDs, query strings), add a round-trip property test (`parse(format(x)) === x`) covering every formatter output shape. Teaching the formatter a new shape without updating the parser silently corrupts data on the next edit→save cycle.
- @testing-library/react only registers its automatic `cleanup()` when a global `afterEach` exists at import time — with Vitest that means `test.globals: true` in vitest.config; otherwise DOM leaks between tests.

## Docker Compose

- `docker compose` interpolates `$VAR`/`${VAR}` inside `command:`/`entrypoint:` blocks at parse time — embedded shell scripts silently lose their variables (unset vars become empty with only a warning). Escape every shell-runtime `$` as `$$`. `docker compose config` re-escapes surviving literals back to `$$` in its output, so asserting the `$$` form in rendered output plus zero "variable is not set" warnings makes a solid regression check.
- Compose `${VAR:?message}` hard-fails the deploy when a variable is unset/empty — use it for credentials instead of `${VAR:-default}`, which silently ships the default (e.g. Grafana admin/admin).

## Prometheus

- `absent(metric)` alert rules fire PERMANENTLY when the metric's exporter was never deployed/scraped — an alert meant to detect an outage instead manufactures one, while non-absent() rules against missing metrics silently never fire. Keep alert rules and scrape jobs in sync (and lint for it).
- Standalone cAdvisor exposes no restart-count metric; detect restart loops with `changes(container_start_time_seconds{name=~".+"}[15m]) > N`.

## Git Credential Helpers

- `GIT_ASKPASS` helpers run as child processes and read credentials from their environment — variables sourced from a file without `set -a`/`export` are invisible to them, so pushes fail auth even though the parent script sees the variable.

## zsh vs bash Scripting Gotchas

- zsh does NOT word-split unquoted `$VAR` (unlike bash). Storing a command line in a string (`CMD="sshpass -p $PASS ssh host"`) and invoking `$CMD` makes zsh treat the entire string as one command name — it fails AND the "command not found" error echoes the fully-expanded line, leaking any embedded secrets into the terminal/log. Wrap remote-command helpers in functions (or arrays), never command-strings.

## SQLite

- `sqlite3 db ".backup 'dest'"` uses the online backup API, which reads through the source connection — committed WAL frames ARE included. No prior `wal_checkpoint` is needed for backup correctness (checkpoint first only when copying the raw file directly).
