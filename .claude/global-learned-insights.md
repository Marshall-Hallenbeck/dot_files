# Global Learned Insights

Accumulated knowledge from working across projects. Auto-maintained by Claude.

## SQLAlchemy Patterns

- When adding a FK to an existing model that's mocked with `SimpleNamespace` in tests, every mock instance needs the new attribute added (typically `=None`). Regex-based replacement across test files is efficient for this.

## Claude Code Skills vs Agents

- Skills are prompt templates (directory with SKILL.md) injected into the main conversation -- they run as the main Claude instance, can interact with the user mid-execution, and inherit all available tools. Best for orchestration and interactive workflows.
- Agents are isolated subprocesses (single .md file with YAML frontmatter including explicit `tools` list) that run autonomously and return a single result. Best for parallel execution and autonomous work. Cannot interact with the user mid-task.
- Colon-based namespace in skill directory names (e.g., `bb:full-sweep`) groups related skills in the `/` completion menu and makes them visually distinct from other skills.

## Claude Code Model/Effort Inheritance

- Subagents inherit the parent session's model and effort level by default. Creating "-max" or "-team" variants of skills that just add "use Opus Max Effort" text is redundant and causes drift — the duplicate falls behind as the canonical version evolves.
- The `model` field in agent frontmatter overrides inheritance. Setting `model: haiku` on an agent means it ALWAYS uses Haiku regardless of session. Omit the field (or use `inherit`) to respect the session model.
- Prompt-level instructions like "Create a team of Opus 4.6 Max Effort agents" are suggestions Claude tries to honor, not enforced configuration. For deterministic model selection, use agent frontmatter `model` field or the Agent tool's `model` parameter.
