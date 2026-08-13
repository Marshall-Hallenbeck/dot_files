# Bidirectional Ruler Configuration Sync Design

## Status

Approved on 2026-08-13.

## Goal

Use Ruler as the shared source for Claude and Codex configuration wherever the
two tools have the same meaning. A direct edit to a generated Claude or Codex
file must move back into the canonical source before Ruler regenerates both
views.

The sync changes files only. It does not create Git commits or push to a Git
remote.

## Current State

The current project source is `.ruler/AGENTS.md`. Ruler writes `CLAUDE.md` and
`.ai-config/AGENTS.shared.md`. The local `agent-sync` script then appends the
Codex overlay and writes `AGENTS.md` (`.local/bin/agent-sync:94-115` and
`.local/bin/agent-sync:143-149`).

The current state stores source and output hashes. It does not store the last
successful file content (`.local/bin/agent-sync:292-365`). It runs Ruler before
it imports output changes, so a direct edit to a generated file can be replaced
(`.local/bin/agent-sync:329-345`).

The systemd timer runs the sync every two minutes
(`.config/systemd/user/agent-sync.timer:4-9`). This is a useful fallback, but it
does not provide immediate edit handling.

The project currently disables Ruler skill and subagent propagation
(`.ruler/ruler.toml:10-19`). Ruler 0.3.44 has native canonical locations for
both features: `.ruler/skills/` and `.ruler/agents/`.

Direct output symlinks are not a valid replacement for reconciliation. Ruler
rejects a generated output when the output path is a symlink
(`dist/core/FileSystemUtils.js:336-345` in the installed Ruler package).

## Canonical Model

Configuration has one canonical tree where a common format exists:

- Project shared instructions: `<project>/.ruler/AGENTS.md`
- Project shared MCP data and Ruler settings: `<project>/.ruler/ruler.toml`
- Project shared skills: `<project>/.ruler/skills/`
- Project shared subagents: `<project>/.ruler/agents/`
- Global shared data: equivalent `.ruler/` sources in the dotfiles repository
- Tool-only values: small tracked overlays under `.ai-config/`

The dotfiles repository acts as the global Ruler root. Its Ruler output paths
point at the tracked Claude and Codex files that the installers already link or
copy into the home directory.

The sync uses a versioned mapping manifest. The manifest declares each source,
its Claude and Codex projections, its data type, its adapter, and its excluded
fields. Standard project paths do not need per-project configuration.

## Configuration Coverage

| Area | Canonical source | Projection |
|---|---|---|
| Shared instructions | `.ruler/AGENTS.md` | Claude and Codex instruction files |
| MCP servers | `.ruler/ruler.toml` | `.mcp.json` and Codex TOML |
| Skills | `.ruler/skills/` | `.claude/skills/` and `.agents/skills/` |
| Subagents | `.ruler/agents/` | Claude Markdown and Codex TOML |
| Shared hook intent | Neutral adapter data | Claude and Codex native hook data |
| Tool-only settings | `.ai-config/` native overlays | Only the applicable tool |
| Learned insights | Existing dotfiles source | Existing Claude and Codex links |

Unknown native keys stay in the applicable overlay. The sync moves a value to
shared Ruler data only when both tools use the same meaning. It must not remove
a valid native value because the other tool has no equivalent.

Ruler native skill and subagent support replaces manual copies after migration.
The pinned Ruler version remains required. An upgrade needs a dry run and the
round-trip test suite before the version pin changes.

## Managed Instruction Blocks

Generated instruction files use explicit managed blocks:

```text
<!-- agent-sync:shared:start -->
shared Ruler content
<!-- agent-sync:shared:end -->

<!-- agent-sync:codex-only:start -->
Codex overlay content
<!-- agent-sync:codex-only:end -->
```

Claude uses a matching `claude-only` block when it has native instruction text.
Edits inside a native block return to that native overlay. All unmarked
instruction edits are shared by default. Generated Ruler headers and block
markers never enter `.ruler/AGENTS.md`.

This rule lets an agent edit `CLAUDE.md` or `AGENTS.md` without prior knowledge
of Ruler. The next sync routes the edit to the correct source.

## Reconciliation Data Flow

1. Take the per-root lock.
2. Load the last successful normalized content, digest, and nanosecond
   modification time for each source and projection.
3. Read all current files before any generator runs.
4. Parse each file through its declared adapter.
5. Compare every normalized value with the stored base.
6. Import a one-sided change.
7. Merge independent changes from multiple sides.
8. Resolve the same changed line or structured key with the newest file
   modification time.
9. Keep the Ruler value on an exact time tie. Save all competing values in a
   conflict report.
10. Run Ruler from the reconciled canonical source.
11. Add managed blocks and native overlays.
12. Write all files atomically.
13. Update state only after all writes and validation checks succeed.

Text uses a base-aware three-way line merge. JSON and TOML use a recursive
three-way key merge. Directory mappings compare each relative file. A generated
file that still matches the last output hash is not treated as a new edit even
when its modification time is newer.

## Automation

A Claude or Codex post-edit hook calls `agent-sync` when a mapped file changes
and that tool exposes a suitable hook event. The hook passes the changed path so
the sync can skip unrelated roots.

The existing two-minute systemd timer remains enabled as the reliable fallback.
Windows uses the same reconciliation rules through the PowerShell entry point.
POSIX can use links for installed global files. Windows continues to use copies
and relies on content hashes for reverse import.

Manual `agent-sync` runs use the same import-first flow. Project documentation
must direct agents to `agent-sync`, not direct `ruler apply`, for normal updates.

## Error Handling and Recovery

- Invalid JSON, TOML, frontmatter, or managed block structure stops only the
  affected mapping.
- A failed mapping is not overwritten.
- State is not advanced for a failed mapping.
- A report and recovery copies go under `~/.cache/agent-sync/conflicts/`.
- Other independent roots can continue to synchronize.
- The command returns a failure status when any mapping fails.
- The next timer run retries the failed mapping after the file is corrected.
- The lock prevents concurrent writes and feedback loops.

The initial migration creates timestamped backups and a dry-run report before
it replaces any canonical or generated path.

## Security and Exclusions

The following data never enters Ruler, dotfiles Git history, a generated view,
or reverse-sync state content:

- Credentials and authentication files
- API keys, bearer tokens, and secret environment values
- Session data and conversation history
- Caches, logs, telemetry, and application databases
- Machine-local overrides such as `settings.local` files
- Worktree runtime state and temporary files

The manifest uses an allowlist. A new configuration path is not synchronized
until it has an explicit mapping and tests. Secret-like fields cause a failure
unless the mapping declares a safe reference to an external environment value.

## Migration

1. Record a dry-run inventory of current shared and native files.
2. Back up every path that will change.
3. Merge the current global Claude and Codex instructions into one dotfiles
   `.ruler/AGENTS.md` plus minimal native overlays.
4. Move shared project and global skills to `.ruler/skills/` and remove exact
   duplicates.
5. Convert shared agents to `.ruler/agents/` and keep only unsupported native
   fields in overlays.
6. Enable Ruler skills and subagents.
7. Seed reconciliation state from the validated canonical sources and outputs.
8. Enable post-edit hooks and retain the timer.
9. Run the sync twice and require no change on the second run.

Existing unrelated working-tree changes remain untouched. Migration commits are
split by responsibility so instruction, skill, agent, and sync-engine changes
can be reviewed separately.

## Test Plan

Automated tests must cover:

- A Ruler-only edit
- A Claude-only edit
- A Codex-only edit
- Independent edits on two or three sides
- An overlapping text edit where the newest file wins
- An overlapping structured key where the newest file wins
- An exact modification-time tie
- Generated marker removal
- Shared and native instruction block routing
- Invalid JSON, TOML, frontmatter, and block markers
- Preservation of unknown native keys
- Secret and local-file exclusions
- Skill and subagent directory add, update, rename, and removal
- A failed partial run with unchanged state
- Two concurrent sync requests
- Idempotent second sync
- POSIX link installation
- Windows copy installation and reverse import

The validation gate includes Python tests, shell tests, PowerShell syntax checks
when PowerShell is available, ShellCheck, Ruler dry runs, and a live round trip
against a temporary Ruler project.

## Acceptance Criteria

- An edit to `CLAUDE.md` reaches `.ruler/AGENTS.md` and `AGENTS.md` within one
  timer cycle.
- An edit to the shared block in `AGENTS.md` reaches `.ruler/AGENTS.md` and
  `CLAUDE.md` within one timer cycle.
- Independent changes from Ruler, Claude, and Codex are all preserved.
- The newest edit wins only for the same line or key.
- Tool-only settings remain tool-only.
- A second sync produces no file changes.
- No secret or runtime state is added to the dotfiles repository.
- The sync does not commit or push Git changes.

## Non-Goals

- Synchronize application-owned databases or conversation state.
- Store credentials in Ruler.
- Make direct output symlinks that Ruler cannot write.
- Automatically commit or push configuration changes.
