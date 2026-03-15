# Global Learned Insights

Accumulated knowledge from working across projects. Auto-maintained by Claude.

## SQLAlchemy Patterns

- When adding a FK to an existing model that's mocked with `SimpleNamespace` in tests, every mock instance needs the new attribute added (typically `=None`). Regex-based replacement across test files is efficient for this.
- `log_command()` returning the new record's ID after `session.refresh(log)` is a clean pattern for linking audit logs to the entities they describe — avoids needing a separate query.

## Architecture Patterns

- When N producers (analyzers) create output that flows through a single persist layer, the cleanest way to attach metadata (like a command_log_id) is at the result container level (AnalysisResult.command_log_id) with injection at the persist boundary, rather than modifying every producer.
