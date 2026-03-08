# Auto-Save Insights

When operating in explanatory output style (generating ★ Insight blocks), automatically save noteworthy insights after generating them.

## Classification

- **Global insights** — General programming knowledge, language/framework behavior, architectural patterns, tooling tips, or debugging techniques that apply across any project. Save to the global file.
- **Project insights** — Patterns, conventions, architecture decisions, key file paths, or behaviors specific to the current codebase. Save to the project file.

## Storage Locations

- **Global:** `~/.claude/global-learned-insights.md`
- **Project:** `<project-root>/.claude/project-learned-insights.md` (create the file if it doesn't exist)

## Process

After generating a ★ Insight block:

1. Determine if the insight is global or project-specific
2. Read the target file and check for duplicates — skip if a substantially similar insight already exists
3. Append the insight as a concise bullet under an appropriate topic heading
4. If the topic heading doesn't exist yet, create it

## Format

Use this format in the insights files:

```
## [Topic]

- Insight text (concise, 1-2 lines)
```

## Rules

- Skip trivial or obvious insights — only save things that would genuinely help in future sessions
- Deduplicate: don't save if a substantially similar insight is already recorded
- Keep entries concise — these files are loaded into every conversation's context
- Don't save session-specific or task-specific details
- Don't ask the user for classification — determine it yourself and save silently
- If the project-level file doesn't exist yet, create it with a header comment: `# Project Learned Insights`
