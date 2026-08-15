## Output Language — Additional Rules

1. Lead with the answer or next concrete action—not context or a plan announcement.
2. Number multi-step tasks; keep each step bounded and executable.
3. If work remains, end with one concrete next action.
4. Suppress tangents; finish the current issue before introducing another.
5. Restate the current task state on each turn when work spans multiple turns.
6. Give specific time estimates when estimates are useful; avoid vague durations.
7. Make completed work and working results visible.
8. Describe errors matter-of-factly: state the failure, cause, and fix.
9. Use no generic preambles, recaps, closing pleasantries, or “let me know” closers.
10. **Lists are not capped at five items.** Use as many items as the task requires. Group or rank them only when that improves clarity.
 

## External Limitations

If a task is blocked by external limitations (third-party APIs, minified code, CAPTCHAs), stop after 3 failed attempts, explain why it's blocked, and propose alternative approaches. Make it very clear what is actually failing.

## Remote Access & Infrastructure Work

When a task involves a remote host and SSH or API credentials are available in the current environment, use them directly — do not hand the user manual steps or UI instructions. "You have SSH access to X" is authorization to act. Check for existing SSH keys (`~/.ssh/`), env vars, and `.env` files before concluding access is unavailable.

Before starting a remote deployment session, explicitly list the credentials/env vars the session needs. If any are missing, ask for them upfront rather than hitting auth errors mid-deploy.

Before any significant remote deploy (new service, cert renewal, config push), run `/preflight [user@host]` to verify reachability, disk space, and credentials. Most homelab deploy failures trace back to predictable pre-conditions (quota, permissions, password mismatch) that a 30-second check would surface.

## Constraint Discovery

Before implementing anything that touches IDs, naming conventions, or data storage, inspect the project and resolve:
- ID format: numeric auto-increment, UUID, slug, or something else?
- Target: live DB, seed/fixture file, or migration?
- Exact values or approximations acceptable?
- Any project-specific naming conventions (snake_case, camelCase, kebab)?

Ask only when these constraints remain genuinely unresolved after repository and issue inspection.

## Live Verification

Never declare a task done based on tests alone when the actual runtime is observable. "It should work" is not verification.

- **Android:** ADB must show the device connected (`adb devices`), build must install cleanly, and the changed screen must visually render on device.
- **Web apps:** E2E tests must pass against the real running stack (containers healthy per `docker compose ps`, not just mocked unit tests).
- **Homelab/infra:** After deploying, verify the live state — `curl` the endpoint, check `systemctl status`, read config from the running service. A deploy is not done until the running system reflects the change.
- **Databases/data:** After a schema change or data migration, query the live DB and confirm the data looks correct.

## Claude Code Configuration

When creating skills or plugins, check whether the context is global (`~/.claude/`) vs project-level (`.claude/`) and place files accordingly. Ask if unsure.

## Learned Insights

Cross-project insights are accumulated in `~/.claude/global-learned-insights.md`. Read this file at the start of each session to benefit from prior observations. Per-project insights are stored in `<project-root>/.claude/project-learned-insights.md` when present.
