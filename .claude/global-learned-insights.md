# Global Learned Insights

Accumulated knowledge from working across projects. Auto-maintained by Claude.

## SQLAlchemy Patterns

- When adding a FK to an existing model that's mocked with `SimpleNamespace` in tests, every mock instance needs the new attribute added (typically `=None`). Regex-based replacement across test files is efficient for this.
- `log_command()` returning the new record's ID after `session.refresh(log)` is a clean pattern for linking audit logs to the entities they describe — avoids needing a separate query.

## Architecture Patterns

- When N producers (analyzers) create output that flows through a single persist layer, the cleanest way to attach metadata (like a command_log_id) is at the result container level (AnalysisResult.command_log_id) with injection at the persist boundary, rather than modifying every producer.

## Bug Bounty / Recon

- Prometheus `/metrics` endpoints on Grafana instances expose far more than version info: full API route map (from `grafana_http_request_duration_seconds` handler labels), OAuth config (client IDs, redirect URIs from login redirect headers), feature toggle state, datasource counts, and traffic patterns. This goes beyond "version disclosure" OOS exclusions.
- Azure deployment endpoints returning `InvalidQueryParameterValue` with `comp` query param are Azure Blob Storage REST API — not actual deployment APIs. The `PublicAccessNotPermitted` error (409) means the storage account properly blocks public access.
- Static CSP nonces (same value across all requests) defeat the purpose of nonces entirely. Check by requesting the page 3 times and comparing nonce values.
- Okta custom domains can sometimes leak the underlying Okta org name via `/oauth2/default/.well-known/openid-configuration` — the issuer field shows the real `.okta.com` domain.

## CSS / Tailwind

- In Tailwind v4 with CSS Modules, `@apply` can only resolve Tailwind utility classes — not custom classes defined in `globals.css`. If `.card` is `@apply bg-gray-900 border ...` in globals, you can't `@apply card` inside a `.module.css` file. Inline the utilities directly or apply the class in JSX.
