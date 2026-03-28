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

- `useSearchParams()` causes SSR suspension. Combined with Suspense boundaries in Turbopack dev mode, client-side resolution can fail silently. Replace with `useState(() => new URLSearchParams(window.location.search))` when Suspense interaction is problematic.

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
