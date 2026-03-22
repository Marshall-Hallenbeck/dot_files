# Global Learned Insights

Accumulated knowledge from working across projects. Auto-maintained by Claude.

## SQLAlchemy Patterns

- When adding a FK to an existing model that's mocked with `SimpleNamespace` in tests, every mock instance needs the new attribute added (typically `=None`). Regex-based replacement across test files is efficient for this.
- `log_command()` returning the new record's ID after `session.refresh(log)` is a clean pattern for linking audit logs to the entities they describe — avoids needing a separate query.

## Architecture Patterns

- When N producers (analyzers) create output that flows through a single persist layer, the cleanest way to attach metadata (like a command_log_id) is at the result container level (AnalysisResult.command_log_id) with injection at the persist boundary, rather than modifying every producer.

## Bug Bounty / Recon

- HackerOne public GraphQL API (`hackerone.com/graphql`) has removed `bounty_table{rows{...}}` -- `rows` no longer exists on the `BountyTable` type. Bounty details are now only in the `policy` text field. When querying H1 GraphQL, write the JSON payload to a temp file and use `curl -d @file` to avoid shell escaping issues with nested braces/quotes.
- Prometheus `/metrics` endpoints on Grafana instances expose far more than version info: full API route map (from `grafana_http_request_duration_seconds` handler labels), OAuth config (client IDs, redirect URIs from login redirect headers), feature toggle state, datasource counts, and traffic patterns. This goes beyond "version disclosure" OOS exclusions.
- Azure deployment endpoints returning `InvalidQueryParameterValue` with `comp` query param are Azure Blob Storage REST API — not actual deployment APIs. The `PublicAccessNotPermitted` error (409) means the storage account properly blocks public access.
- Static CSP nonces (same value across all requests) defeat the purpose of nonces entirely. Check by requesting the page 3 times and comparing nonce values.
- Okta custom domains can sometimes leak the underlying Okta org name via `/oauth2/default/.well-known/openid-configuration` — the issuer field shows the real `.okta.com` domain.

## CSS / Tailwind

- In Tailwind v4 with CSS Modules, `@apply` can only resolve Tailwind utility classes — not custom classes defined in `globals.css`. If `.card` is `@apply bg-gray-900 border ...` in globals, you can't `@apply card` inside a `.module.css` file. Inline the utilities directly or apply the class in JSX.

## WAF Bypass Analysis

- AWS WAF event handler detection triggers on `on[event-name]=` (attribute assignment form) but can miss `on<TAB>error=` / `on<LF>error=`. However, HTML5 prohibits whitespace in attribute names, so browsers parse the split differently -- the bypass passes the WAF but the browser never registers the event handler.
- To map a WAF's XSS rule trigger precisely: test `<img onerror>` (boolean attr, no =) separately from `<img onerror=x>`. The = sign is often what activates the WAF rule.

## Claude Code Skills vs Agents

- Skills are prompt templates (directory with SKILL.md) injected into the main conversation -- they run as the main Claude instance, can interact with the user mid-execution, and inherit all available tools. Best for orchestration and interactive workflows.
- Agents are isolated subprocesses (single .md file with YAML frontmatter including explicit `tools` list) that run autonomously and return a single result. Best for parallel execution and autonomous work. Cannot interact with the user mid-task.
- Colon-based namespace in skill directory names (e.g., `bb:full-sweep`) groups related skills in the `/` completion menu and makes them visually distinct from other skills.

## XSS in Script Blocks

- HTML entities inside `<script>` (raw text element) are NOT decoded by the browser's JS parser. `&quot;` remains the literal string `&quot;` in JS, not a double-quote. You cannot break out of a JS string using only HTML entity-encoded characters inside a `<script>` block.

## SQL Injection / WAF

- Azure Application Gateway WAF v2 blocks WAITFOR DELAY, SLEEP, OR keyword, double-dash comments (--), and SQL comment blocks (/**/) in both form-encoded and JSON POST bodies. Single quote alone passes through, making parameterized-vs-raw-SQL determination difficult without a timing oracle.
- MSSQL/Azure SQL signature: CHAR(n) columns in JSON responses show trailing spaces e.g. `"Code":"AL        "`. MySQL and PostgreSQL trim CHAR columns when serializing. Use this to identify the DBMS from read-only endpoints.
- When the backend always errors for a reason unrelated to SQL (e.g., downstream API rejection), time-based blind SQLi is untestable -- the injected delay is indistinguishable from the inherent backend error delay.
