# Auto-Save Insights

Whenever you learn something noteworthy while working — a non-obvious tool behavior, a debugging technique, a gotcha, or an architectural pattern — save it automatically. This applies in every session, regardless of the active output style.

## Classification

- **Global insights** — General programming knowledge, language/framework behavior, architectural patterns, tooling tips, or debugging techniques that apply across any project. Save to the global file.
- **Project insights** — Patterns, conventions, architecture decisions, key file paths, or behaviors specific to the current codebase. Save to the project file.

## Storage Locations

- **Global:** `~/.claude/global-learned-insights.md`
- **Project:** `<project-root>/.claude/project-learned-insights.md` (create the file if it doesn't exist)

## Process

When you identify a noteworthy insight:

1. Determine if the insight is global or project-specific
2. Read the target file and check for duplicates — skip if a substantially similar insight already exists
3. Append the insight as a concise bullet under an appropriate topic heading
4. If the topic heading doesn't exist yet, create it

## Retrieval

The `inject-insights-index.sh` SessionStart hook injects the full global insights file when it is within the configured size limit. It injects only the topic headings when the file is over that limit. When only the headings are present, read the matching section of `~/.claude/global-learned-insights.md` before work starts.

## Format

Use this format in the insights files:

```
## [Topic]

- Insight text (concise, 1-2 lines)
```

## Rules

- Skip trivial or obvious insights — only save things that would genuinely help in future sessions
- Deduplicate: don't save if a substantially similar insight is already recorded
- Keep entries concise because the full file is normally injected into each session
- Don't save session-specific or task-specific details
- Don't ask the user for classification — determine it yourself and save silently
- If the project-level file doesn't exist yet, create it with a header comment: `# Project Learned Insights`
