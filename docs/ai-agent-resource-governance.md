# AI agent host resource governance

## Purpose

This design keeps a development host responsive when many AI sessions use Git worktrees, test runners, MCP servers, and project hooks.

The key rule is simple: Git worktrees are not the resource unit. A session, its test process group, its MCP servers, and its worktree runtime are the resource unit.

## Incident evidence from `ubuntu22`

The host has 10 logical CPUs and approximately 47 GiB of RAM.

The incident had more than one cause:

- One Claude session ran two Jest commands at the same time. Four Jest workers used approximately four CPUs.
- The global post-edit hook ran a whole-program TypeScript check after each TypeScript edit.
- Three resident TypeScript compiler watchers had no session lease or expiry. They used approximately 1.7 GiB and used global keys that were not unique to a worktree.
- Old worktrees still had a SessionStart hook that ran the former full preflight. Current `main` uses a Git-only preflight, but a worktree does not receive this change until it integrates the new commit.
- Eight Codex threads shared one app-server service. The service had 567 tasks and approximately 11.3 GiB of cgroup memory. Each thread started its own MCP process set.
- `agent-sync.timer` ran every two minutes. Each run recursively hashed large skill trees and used 5 to 45 CPU-seconds. A run could take longer than its timer interval.
- Several test workers, shell loops, a Next server, and TypeScript watchers survived their parent session or a deleted worktree.
- The repository had 45 registered Git worktrees. The count did not use CPU by itself, but it made stale configuration and stale runtime ownership difficult to see.

## Control layers

### 1. Host cgroup boundary

All managed Codex and Claude services use `ai-agents.slice`.

Portable limits in the shared dotfiles are:

| Control | Value |
|---|---:|
| CPU weight | 25 |
| I/O weight | 25 |
| Memory high threshold | 25% of host RAM |
| Memory hard limit | 35% of host RAM |
| Aggregate task limit | 1536 |

The low CPU and I/O weights keep normal interactive and system work responsive during contention. The memory limit reserves at least 65% of host RAM for the OS, the desktop, SSH, Docker, and other services.

A host-specific drop-in adds a hard CPU quota. On `ubuntu22`, `/etc/systemd/system/user-1000.slice.d/20-development-host.conf` limits all processes for UID 1000 to 600% CPU, a 24 GiB memory high threshold, a 32 GiB hard memory limit, and 2048 tasks. This includes interactive Claude sessions that do not use a managed service and leaves four logical CPUs for Docker and system services.

The nested `~/.config/systemd/user/ai-agents.slice.d/20-ubuntu22.conf` also sets `CPUQuota=600%`. The host keeps persistent service drop-ins. Codex uses a 300% CPU quota, a 12 GiB memory high threshold, and a 16 GiB hard limit. Claude Remote Control uses a 200% CPU quota, an 8 GiB memory high threshold, and a 10 GiB hard limit. These files are host-local and do not change portable defaults.

Ubuntu 22.04 delegates only the memory and `pids` controllers to `user@1000.service` by default. Without CPU and I/O delegation, `systemctl --user show` still reports `CPUQuota`, `CPUWeight`, and `IOWeight`, but the nested cgroup has no `cpu.max`, `cpu.weight`, or `io.weight` file. These settings are then inactive. The host uses `/etc/systemd/system/user@1000.service.d/20-resource-delegation.conf` with `Delegate=cpu io memory pids`. The system-level `user-1000.slice` drop-in sets `IOWeight=100` so systemd enables the I/O controller down the hierarchy. After changing these files, run `sudo systemctl daemon-reload` and restart `user@1000.service` in a maintenance window; a host reboot also applies both settings. Verify the result from cgroupfs: `user@1000.service/ai.slice/ai-agents.slice/cpu.max` must contain `600000 100000`, `cpu.weight` must contain `25`, and `io.weight` must contain `default 25`. A live eight-worker probe averaged 5.794 cores and recorded 14 throttle events. The system-level `user-1000.slice` quota remains the final hard limit for all user processes.

Individual service limits are:

| Service | Task limit | Other limits |
|---|---:|---|
| Codex app server | 1024 | Full process-group cleanup on stop |
| Claude Remote Control instance | 768 | Full process-group cleanup on stop |
| Agent configuration sync | 64 | 50% of one CPU, 512 MiB high, 1 GiB hard |

A service stop or restart must use `KillMode=control-group`. A child process must not survive its service.

### 2. Agent admission

The global Claude tool-use concurrency is 4, not 20.

This is a concurrency ceiling, not a target. An agent must not start a second test command while the first test command is active.

A human can still run an interactive Claude process outside the managed service. Use the same test and worktree wrappers so that the process enters the shared admission locks.

### 3. Test admission

Tests have two classes.

- A focused unit or component test can use at most two Jest workers.
- A heavy test has one host-wide slot. Heavy tests include Playwright, integration, migration, full-suite, production-suite, and full preflight commands.

A linked worktree must run host-side tests through:

```bash
./scripts/worktree-env.sh run -- <command> [args...]
```

The wrapper keeps the heavy-test lock for the full child process. It waits for at most 300 seconds. It fails instead of starting another heavy job after that limit.

A TypeScript Stop hook uses a separate host-wide typecheck lock. The check:

- waits at most 30 seconds for the slot;
- runs for at most 120 seconds;
- uses a nice value of 10;
- uses a 2 GiB Node heap ceiling;
- leaves no resident compiler process.

`tsc --watch` is not permitted in agent hooks. A resident compiler needs a worktree-specific identity, an owner, a lease, and an expiry. The retired implementation had none of these controls.

### 4. Worktree runtime admission

A Git worktree alone has no runtime cost. A worktree becomes a resource owner only when it has a registered runtime or an active agent lease.

The worktree manager keeps a 20 GiB aggregate memory admission check. This allows at most three full frontend-and-backend runtimes on the 47 GiB host and leaves memory for AI services and the OS. Each worktree container also has a local limit:

| Container | CPU limit | PID limit | Memory limit |
|---|---:|---:|---:|
| Frontend | 2 CPUs | 512 | 5120 MiB |
| Backend | 2 CPUs | 512 | 1536 MiB |

The container CPU limits prevent one rebuild loop from taking all host CPUs. The host-wide heavy-test slot prevents several runtimes from becoming busy at the same time.

Use this lifecycle:

1. Create the worktree.
2. Register only the runtime mode that the task needs.
3. Record an active session lock.
4. Stop the runtime when the task no longer needs a live service.
5. Remove the session lock when the agent exits.
6. Run `./scripts/worktree-env.sh gc` from the primary checkout.
7. Use `gc --apply` only for clean, merged worktrees with no live session lock.

Do not use worktree age alone as a deletion rule. Dirty state and live session ownership are safety gates.

### 5. Configuration synchronization

Configuration synchronization is a background maintenance task. It is not part of a session hot path.

The timer runs 30 minutes after the prior run completes. It has a five-minute random delay. It cannot overlap itself. The service has low CPU and I/O priority and a hard memory limit.

Run a manual synchronization after an intentional configuration change. Use the timer only as a repair path.

A host-local model choice must not be an uncommitted edit to a tracked dotfile. That condition blocks `dotfiles-update` forever. Store a host override in a supported local overlay or in a systemd drop-in, then keep the tracked source clean.

### 6. MCP process profiles

Use three MCP profiles:

1. **Base profile:** only tools needed by almost every thread.
2. **Project profile:** database, Docker, framework, and application MCP servers for that repository.
3. **Task profile:** Playwright, security analysis, or other high-cost tools only for the thread that needs them.

Do not load the same Docker, PostgreSQL, Next.js, Playwright, memory, or sequential-thinking server from both the global and project configuration. Each duplicate becomes one more process per thread.

Where an MCP implementation supports multiplexing, use one host service and connect threads to it. If it only supports stdio, keep it out of the base profile and start it on demand.

## Operational checks

Use these thresholds on `ubuntu22`:

- Investigate when the AI slice uses more than 600% CPU for five minutes.
- Investigate when the slice crosses the 25% memory high threshold.
- Reject new work when the slice reaches 1300 tasks. The hard limit is 1536.
- Investigate any Jest worker, TypeScript watcher, or dev server whose parent is PID 1.
- Investigate any process whose current working directory contains `(deleted)`.
- Investigate any synchronization run that lasts longer than ten minutes.

Do not use broad `pkill` or `killall` commands. Select the exact session or process group, send `TERM`, wait, and use `KILL` only for survivors.

## Migration for old worktrees

An existing worktree keeps the AI configuration from its commit. It does not inherit the current `main` hooks.

For each active worktree:

1. Save or commit task changes.
2. Integrate current `origin/main`.
3. Run the configuration parity tests.
4. Restart the agent session so it loads the new hooks.
5. Stop legacy compiler watchers with `.claude/hooks/ts-daemon.sh stop-all` before deleting the old worktree.

Do not copy a current settings file into every worktree. That makes unrelated worktrees dirty and hides the actual commit dependency.
