# Global Learned Insights

Accumulated knowledge from working across projects. Auto-maintained by Claude.

## SQLAlchemy Patterns

- When adding a FK to an existing model that's mocked with `SimpleNamespace` in tests, every mock instance needs the new attribute added (typically `=None`). Regex-based replacement across test files is efficient for this.

## Claude Code Parallelism Mechanisms

- Three parallelism levels: **Subagents** (Agent tool, invisible helper returning a result), **Agent Teams** (full independent sessions in tmux panes, user can interact with each), **Workflows** (scripted JS orchestration, deterministic fan-out, no mid-flight steering). Choose by steerability needs, not task size.
- `run_in_background: true` on the Agent tool is the middle ground — the main conversation continues, but the subagent can't be steered. Use for independent lookups that don't gate the next step.
- `teammateMode: "auto"` in settings.json enables tmux split panes when running inside tmux, falling back to in-process agent panel otherwise. Default changed from `"auto"` to `"in-process"` in v2.1.179.

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
- Tool fields are nested under `.tool_input.*` — a PostToolUse file hook reads `.tool_input.file_path`, NOT top-level `.file_path`. A hook keying off the wrong path silently no-ops (empty → early exit) with no error.
- The PreToolUse payload does NOT contain the user's prompt — you cannot gate a PreToolUse hook on "did the user ask for this." To make a detected pattern a conscious choice, emit `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"..."}}` (prompts the user) instead of a hard `exit 2` block.
- The Stop payload does NOT contain the assistant's response text — it's in the transcript at `.transcript_path` (JSONL). Last assistant text: `jq -rs 'map(select(.type=="assistant"))|last|.message.content|map(select(.type=="text")|.text)|join("\n")'`.
- A hook reading a nonexistent env var (`CLAUDE_TOOL_INPUT`, `CLAUDE_USER_PROMPT`, `CLAUDE_STOP_RESPONSE`) is silently dead: the var is empty, the hook early-exits, and nothing warns you. Symptom of a dead post-edit hook: the linter/formatter you expect to auto-run after a Write/Edit simply doesn't.

## Claude Code Permissions

- Bash allow/deny patterns use colon-star syntax: `Bash(cmd:*)` matches `cmd` + any args (e.g. `Bash(git log:*)`, `Bash(ruff check:*)`). The space form `Bash(cmd *)` is NOT the matcher. Multi-word prefixes work and a short prefix blankets subcommands — `Bash(docker:*)` already covers `docker compose logs ...`.
- Many read-only commands never prompt (no allowlist entry needed): `cat`/`ls`/`grep`/`find`/`head`/`tail`/`wc`/`cut`/`sort`/`diff`, all git read subcommands (`git log/diff/status/show/branch`), gh read subcommands, `docker ps/images/logs/inspect`. Worth allowlisting only the read-only tools OUTSIDE that set: `objdump`/`nm`/`readelf`/`ping`/`dig`, etc.
- When cwd is the home directory, the "project" `.claude/settings.json` path resolves to the global `~/.claude/settings.json` — they're the same file. `settings.local.json` holds machine-specific grants and (in this setup) is symlinked into `~/.dot_files`, so it IS dotfiles-tracked despite the usual "local = gitignored" convention.

## PostgreSQL JSONB Patterns

- GIN indexes on JSONB columns enable `?|` (any key exists), `@>` (contains), `?&` (all keys exist) operators. Use `postgresql_using="gin"` in SQLAlchemy Index definition.
- SQLAlchemy 2.0 has no built-in support for `?|` -- use `column.op("?|")(pg_array([...]))` with `from sqlalchemy.dialects.postgresql import array as pg_array`.

## Background Tasks / Polling

- Never use unbounded `until <condition>; do sleep N; done` in `run_in_background` commands. These run forever invisibly if the condition is never met. Use a bounded loop: `for i in $(seq 1 N); do <check> && break; sleep 5; done`.

## CLI Tool Behavior

- `searchsploit --strict` disables fuzzy version range expansion (e.g., "1.1" won't match "1.0 < 1.3"). The `-s` flag is the short form. Without it, a search for "Apache 2.4" returns every Apache exploit that mentions any version in the 2.x range.

## Android

- `RenderEffect.createBlurEffect()` is API 31+ only. For premium content gating on minSdk 26, use alpha dimming + click-blocking overlay instead — same pattern Google's own apps use.
- `BottomSheetDialogFragment` subclasses must have a no-arg constructor. Use an interface on the host Activity (`requireActivity() as Listener`) for callbacks, not lambda constructors — they break on configuration changes.
- Android Emulator on ESXi requires nested virtualization (`nested_hv_enabled = true` in vSphere VM config, exposes `/dev/kvm` to guest). Without KVM, the emulator falls back to QEMU software emulation (~10x slower). Boot time with KVM: ~75s; without: minutes+.
- For headless emulator testing: `-no-window -no-audio -gpu swiftshader_indirect -no-snapshot-save -no-boot-anim`. Use `adb -a -P 5037 server nodaemon` as a systemd service to expose ADB on all interfaces for remote access from build hosts.

## Testing

- When a value has a formatter and a parser (dates, IDs, query strings), add a round-trip property test (`parse(format(x)) === x`) covering every formatter output shape. Teaching the formatter a new shape without updating the parser silently corrupts data on the next edit→save cycle.
- @testing-library/react only registers its automatic `cleanup()` when a global `afterEach` exists at import time — with Vitest that means `test.globals: true` in vitest.config; otherwise DOM leaks between tests.

## Docker Compose

- `docker compose` interpolates `$VAR`/`${VAR}` inside `command:`/`entrypoint:` blocks at parse time — embedded shell scripts silently lose their variables (unset vars become empty with only a warning). Escape every shell-runtime `$` as `$$`. `docker compose config` re-escapes surviving literals back to `$$` in its output, so asserting the `$$` form in rendered output plus zero "variable is not set" warnings makes a solid regression check.
- Compose `${VAR:?message}` hard-fails the deploy when a variable is unset/empty — use it for credentials instead of `${VAR:-default}`, which silently ships the default (e.g. Grafana admin/admin).
- Push a file into a running container without host SSH via the Docker/Portainer archive API: `PUT /containers/<id>/archive?path=<dir>` with a tar body AND `Content-Type: application/x-tar` (omitting the header → HTTP 400). `path` must be an existing dir; if it's a **read-write** bind mount the write lands on the host. A `:ro` mount blocks it (no host-side write path) — check the mount mode before assuming you can deploy config this way.

## Prometheus

- `absent(metric)` alert rules fire PERMANENTLY when the metric's exporter was never deployed/scraped — an alert meant to detect an outage instead manufactures one, while non-absent() rules against missing metrics silently never fire. Keep alert rules and scrape jobs in sync (and lint for it).
- Standalone cAdvisor exposes no restart-count metric; detect restart loops with `changes(container_start_time_seconds{name=~".+"}[15m]) > N`.
- Hot-reload config/rules with SIGHUP (`docker kill -s HUP <ctr>`) — but only if Prometheus runs with `--web.enable-lifecycle`; otherwise `POST /-/reload` 403s and SIGHUP is the only in-place reload. A `docker restart` works too but drops the metrics series (gap). Run `promtool check config|rules` inside the container before reloading.
- A textfile-collector metric is absent until first written, so `absent(metric) for: 26h` (long `for:`) is bootstrap-safe — the first scheduled write clears it before the window — yet still fires if the series later vanishes. Pairs with value-based rules (`metric == 0`, staleness), which go blind when the series is absent entirely.
- GitLab Omnibus bundles its OWN node_exporter on `localhost:9100`; expose it on the LAN via `gitlab.rb` `node_exporter['listen_address']='0.0.0.0:9100'` instead of installing a second exporter (port clash). Do NOT set `node_exporter['flags']` to add one flag — it REPLACES Omnibus's whole default set (mountstats, runit, runit.servicedir), so leave the textfile dir at Omnibus's default `/var/opt/gitlab/node-exporter/textfile_collector`.

## VMware VCSA

- VCSA partitions storage into many small LVM volumes (`/storage/log` ~10G, `/storage/archive` ~49G). A single runaway log file can fill a partition and cascade into service failures. Always check `df -h` on the VCSA when SSO behaves inexplicably.
- The most dangerous VCSA logs aren't the ones covered by VMware's built-in rotation (rsyslog + imfile) — they're the Java stderr/stdout redirects (`*-runtime.log.stderr`) that bypass syslog entirely, have no size cap, and no rotation.
- When content-library loses STS cert trust (e.g. after MACHINE_SSL_CERT renewal that restarts some services but not content-library), it writes `UntrustedSslCertificateException` stack traces at ~3 GB/hour. Fix: `vmon-cli -r content-library`. Proactively restart it after any cert change.
- A full `/storage/log` breaks vCenter WebSSO login — vsphere-ui can't write SAML session state, producing "No matching request found for WebSSO response." The error is misleading (looks like SSO/cert misconfiguration, actually disk space).
- VMware services on VCSA 8.0 are managed by `vmon-cli`, not systemd directly. All vmware-*.service units show as "masked" in systemctl — this is normal. Use `/usr/lib/vmware-vmon/vmon-cli -s <svc>` for status.

## Git Credential Helpers

- `GIT_ASKPASS` helpers run as child processes and read credentials from their environment — variables sourced from a file without `set -a`/`export` are invisible to them, so pushes fail auth even though the parent script sees the variable.

## Bash TSV Parsing

- Tab is an "IFS whitespace" character, so `IFS=$'\t' read` collapses consecutive tabs into one delimiter — an empty field in `jq @tsv` output silently shifts all later variables left. When extracting optional JSON fields into TSV, emit a non-empty sentinel (`// "none"`) and filter it out in bash.

## Claude Code Output Styles

- Native output styles were deprecated in Claude Code v2 — style plugins (e.g. `explanatory-output-style@claude-plugins-official`) now inject their instructions via a SessionStart hook (`hooks.json` → script → stdout becomes session context). No `outputStyle` settings key is involved; disabling the plugin in `enabledPlugins` removes the style. Local directory-source plugins can use the same mechanism for always-on custom styles.

## Claude Code Statusline

- Statusline stdin JSON exposes reasoning effort at `.effort.level` (`low`/`medium`/`high`/`xhigh`/`max`); the key is omitted entirely when the model has no effort parameter. Also available: `.fast_mode`, `.thinking.enabled`, `.rate_limits`, `.agent.name`, `.exceeds_200k_tokens`.

## Shell Script Extraction & set -e

- Line-number-based `sed -n 'A,Bp'` extraction (e.g. a test harness slicing a section out of another script) couples silently to the source's exact line layout. Inserting any line upstream shifts the range and can split a block — e.g. capture an `if` but not its `fi` — producing an unparseable fragment. Use marker-based extraction instead: `sed -n '/^### START MARKER/,/^# END MARKER/p' file | head -n -1`.
- `git clone git+https://...` is invalid: `git+https` is a pip/pipx URL scheme, not a git transport, so the clone fails. Without `set -euo pipefail` the failure is swallowed and later steps run against the missing dir (e.g. `uv tool install <dir>` on a dir that was never created) — also silently. A script that installs tools should have `set -euo pipefail`; then guard each install for idempotency (`command -v x || install x`, `[ -d dir ] || git clone ...`) so re-runs don't abort.
- zsh 5.9 handles `set -euo pipefail` correctly: empty-array expansion under `set -u` is safe, `cmd || fallback` survives under `set -e`, and a bare failing command aborts. Safe to add to a zsh script (unlike some older zsh set -e lore).
- `systemctl enable/start` aborts with "System has not been booted with systemd as init system" on any host where systemd isn't PID 1 (Docker containers, WSL-without-systemd). Under `set -e` this kills the whole install script. Guard service-enable with `if [ -d /run/systemd/system ]; then systemctl ...; fi` — a presence check, not error-masking. This is a portability bug static review misses (it only fails off-systemd) — running the install in a container surfaces it.
- Verifying symlinks: a whole-directory symlink (`~/.claude/skills -> repo/skills`) makes files INSIDE it real files, not symlinks — so a per-file `[ -L dir/file ]` check FAILS ("exists but not a symlink"). Verify the directory symlink itself (`[ -L dir ]`) plus that each file resolves (`[ -f dir/file ]`), not each file's link-ness.

## zsh vs bash Scripting Gotchas

- zsh does NOT word-split unquoted `$VAR` (unlike bash). Storing a command line in a string (`CMD="sshpass -p $PASS ssh host"`) and invoking `$CMD` makes zsh treat the entire string as one command name — it fails AND the "command not found" error echoes the fully-expanded line, leaking any embedded secrets into the terminal/log. Wrap remote-command helpers in functions (or arrays), never command-strings.

## SQLite

- `sqlite3 db ".backup 'dest'"` uses the online backup API, which reads through the source connection — committed WAL frames ARE included. No prior `wal_checkpoint` is needed for backup correctness (checkpoint first only when copying the raw file directly).

## GitLab API

- Root admin PAT returns 401 on the merge endpoint if `root` isn't an explicit project member. Use `Sudo: <username>` header (requires `sudo` scope on the token) to impersonate a project owner for the merge call.
- The `/repository/commits` endpoint accepts an `actions` array with create/update/delete operations, applying all as a single atomic commit — useful for infrastructure changes that must land together.
- Portainer API (`/api/endpoints/{id}/docker/...`) proxies the full Docker Engine API. Create ephemeral containers with host bind mounts + tar archive upload (`PUT /containers/{id}/archive`) to write config files to the host filesystem when SSH is unavailable.

## Hermes Agent MCP Configuration

- `hermes mcp add --env` passes environment variables to the stdio subprocess, but if the connection test fails the env vars can end up as `args` entries instead of an `env:` block. Always verify the generated YAML after a failed connection test.
- When the current shell lacks the `docker` group (needs re-login), wrap the MCP command with `sg docker -c "..."` to acquire the group for that subprocess — avoids requiring a full session re-login.
- Hermes MCP servers configured via `hermes mcp add` that fail the connection test are saved as `enabled: false` — edit `~/.hermes/config.yaml` to set `enabled: true` after fixing the issue, or use `hermes mcp test <name>` to verify.
- Pre-warm the npx cache (`npx -y <pkg> --help`) before `hermes mcp add` for npx-based servers — first-run package download otherwise exceeds the 40s MCP connection-test timeout and the server saves as disabled.

## Hermes Mixture of Agents (MoA)

- MoA presets live under `moa:` in config.yaml (`default_preset`, `active_preset`, `presets.<name>` with `reference_models[]`, `aggregator`, temps, `max_tokens`). `active_preset: ''` = on-demand via `/moa <prompt>`; setting it to a preset name makes MoA the active mode for EVERY turn (expensive). `/moa` uses `default_preset`.
- MoA slots store only `{provider, model}` — `base_url` is dropped by `_clean_slot`. A local custom provider (e.g. Ollama at a LAN IP) therefore CANNOT be a MoA slot: `provider: custom` resolves via `resolve_runtime_provider` to OpenRouter with no key. Use natively-resolved providers (openai-codex, anthropic, ollama-cloud) instead. Verify any slot with `resolve_runtime_provider(requested=prov, target_model=model)` — check the returned `api_key` is non-empty before saving the preset.
- Hermes plugin pip deps install into its venv via `uv pip install --python ~/.hermes/hermes-agent/venv/bin/python <pkg>` (the venv has no `pip`). Hindsight local_embedded needs `hindsight-all` (not just `hindsight-client`/`hindsight-embed`) — the meta-package provides the `hindsight` module that `is_available()` imports.

## VMware ESXi Persistence & Recovery

- ESXi `/etc` is an in-RAM visorfs rebuilt each boot from the active bootbank's `state.tgz` (encrypted `local.tgz.ve` on 8.x — decrypt on-host with `crypto-util envelope extract --aad ESXConfiguration`). `/sbin/auto-backup.sh` (hourly) archives ONLY files with a filesystem-managed `.#<name>` branch-marker beside them, plus the ConfigStore DB. Files created via scp/shell get no marker, cannot be given one (`touch /etc/.../.#x` → Operation not permitted), and silently vanish on reboot. Persist through sanctioned interfaces instead: `esxcli system ssh key add` (SSH keys), `esxcli system account set` (passwords) — both land in the ConfigStore.
- ESXi upgrades stage the new image into the INACTIVE bootbank with a state snapshot from staging time, while hourly backups keep updating only the active bank. The upgrade reboot swaps banks and can resurrect months-old config (certs, passwords, authorized_keys). After any ESXi upgrade reboot, verify the served cert and re-push config before trusting automation against the host.
- Locked out of ESXi root (password reverted/unknown) while the host is still CONNECTED in vCenter: `docker run vmware/powerclicore` → `Connect-VIServer <vcenter>` → `Get-EsxCli -VMHost <host> -V2` → `$esxcli.system.account.set.Invoke(@{id="root";password=...;passwordconfirmation=...})` — esxcli passthrough runs over the vCenter→vpxa channel, no host creds needed. `sshpass` exit code 5 = wrong password (vs 255 = other SSH failure).
- Cert-revert forensics: a "self-signed" cert with an issuer of `CN=CA, DC=vsphere, DC=local` is VMCA-signed, and an OLD notBefore date proves a restored file (state/backup rollback) rather than fresh re-provisioning — a new VMCA push or hostd regen would be dated at event time.
