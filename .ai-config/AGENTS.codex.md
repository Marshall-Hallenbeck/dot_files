## External Limitations

If a task is blocked by external limitations (third-party APIs, minified code, CAPTCHAs), stop after 2 failed attempts, explain why it's blocked, and propose alternative approaches.

## Codex Configuration

When creating skills or plugins, check whether the context is global (`~/.Codex/`) vs project-level (`.Codex/`) and place files accordingly. Ask if unsure.

## Learned Insights

Cross-project insights are accumulated in `~/.codex/global-learned-insights.md`. Read this file at the start of each session to benefit from prior observations. Per-project insights are stored in `<project-root>/.codex/project-learned-insights.md` when present.
