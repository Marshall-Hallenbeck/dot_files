---
name: claude-remote-control-service
description: Set up or repair a persistent Claude Remote Control environment for a project using a systemd user service, including blocker checks, project symlink, linger, verification, and URL capture.
---

# Claude Remote Control Service

Use this when the user asks to create, repair, migrate, or verify a persistent Claude Remote Control environment for a project. Prefer this service pattern over tmux for long-lived project environments.

## What this does

Creates a systemd user service instance:

```text
claude-rc@<environment-name>.service
```

The service runs:

```bash
claude remote-control --name <environment-name> --permission-mode bypassPermissions --spawn same-dir
```

from a symlinked project directory:

```text
~/.config/claude-rc/projects/<environment-name> -> <absolute-project-dir>
```

This keeps service instance names simple and avoids escaping full paths in systemd unit names.

## Inputs

Determine these before acting:

- `ENV_NAME`: display/service name, e.g. `example-project`, `development`, or another short environment label.
- `PROJECT_DIR`: absolute project directory discovered on the target host, e.g. `$HOME/projects/example-project`.
- `REMOTE_HOST`: optional SSH target if configuring another host, e.g. `user@host.example`.

If the user provides an obvious project name but not a path, inspect common project roots before asking:

```bash
for d in ~/code ~/projects ~/pentest/tools /mnt/code/repos/personal; do
  [ -d "$d" ] && find "$d" -maxdepth 2 -type d -iname '*PROJECT_NAME*' 2>/dev/null
 done
```

## Procedure

### 1. Check prerequisites

Run on the target host:

```bash
export PATH="$HOME/.local/bin:$PATH"
command -v claude
systemctl --user is-system-running || true
loginctl show-user "$USER" -p Linger 2>/dev/null || true
[ -d "$PROJECT_DIR" ] && printf 'project exists: %s\n' "$PROJECT_DIR"
```

Completion criteria: `claude` is found, `PROJECT_DIR` exists, and the user systemd manager is available.

### 2. Remove Remote Control blocker settings

Claude Remote Control fails if these keys exist in `~/.claude/settings.json` under `env`:

- `DO_NOT_TRACK`
- `CLAUDE_CODE_ENABLE_TELEMETRY`
- `DISABLE_EXTRA_USAGE_COMMAND`
- `DISABLE_INSTALL_GITHUB_APP_COMMAND`

Back up and remove only those keys:

```bash
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
  python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home()/'.claude/settings.json'
s = json.loads(p.read_text())
env = s.setdefault('env', {})
removed = {}
for k in ['DO_NOT_TRACK','CLAUDE_CODE_ENABLE_TELEMETRY','DISABLE_EXTRA_USAGE_COMMAND','DISABLE_INSTALL_GITHUB_APP_COMMAND']:
    if k in env:
        removed[k] = env.pop(k)
p.write_text(json.dumps(s, indent=2) + '\n')
print('removed', removed)
PY
fi
```

Completion criteria: a verification read prints `{}` for remaining blockers:

```bash
python3 - <<'PY'
import json, pathlib
p=pathlib.Path.home()/'.claude/settings.json'
env=json.loads(p.read_text()).get('env', {}) if p.exists() else {}
keys=['DO_NOT_TRACK','CLAUDE_CODE_ENABLE_TELEMETRY','DISABLE_EXTRA_USAGE_COMMAND','DISABLE_INSTALL_GITHUB_APP_COMMAND']
print({k:env.get(k) for k in keys if k in env})
PY
```

### 3. Probe Remote Control once

This verifies auth, feature flags, and workspace trust before installing a persistent service:

```bash
cd "$PROJECT_DIR"
rc=0
timeout 8s claude remote-control --name "$ENV_NAME" --permission-mode bypassPermissions --spawn same-dir || rc=$?
if [ "$rc" = 124 ]; then
  echo probe-ok-timeout
else
  exit "$rc"
fi
```

Completion criteria: output reaches `Connected` or `Ready` and includes a `https://claude.ai/code?environment=...` URL. A timeout exit code `124` is expected because the server keeps running until killed by `timeout`.

If the probe exits immediately with a trust prompt or settings error, fix that before creating the service. Do not claim the service is fixed without a successful probe.

### 4. Install the systemd user service

```bash
mkdir -p "$HOME/.config/systemd/user" "$HOME/.config/claude-rc/projects"
cat > "$HOME/.config/systemd/user/claude-rc@.service" <<'UNIT'
[Unit]
Description=Claude Remote Control environment: %i
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/.config/claude-rc/projects/%i
Environment=PATH=%h/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=%h/.local/bin/claude remote-control --name %i --permission-mode bypassPermissions --spawn same-dir
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
UNIT

ln -sfn "$PROJECT_DIR" "$HOME/.config/claude-rc/projects/$ENV_NAME"
systemctl --user daemon-reload
systemctl --user enable --now "claude-rc@$ENV_NAME.service"
```

Completion criteria: `systemctl --user status claude-rc@$ENV_NAME.service` shows `active (running)`.

### 5. Enable linger for reboot persistence

Best effort, requires sudo rights:

```bash
if loginctl show-user "$USER" -p Linger 2>/dev/null | grep -qx 'Linger=yes'; then
  echo linger-already-enabled
elif sudo -n loginctl enable-linger "$USER"; then
  echo linger-enabled
else
  echo "linger not enabled; run: sudo loginctl enable-linger $USER"
fi
```

Completion criteria: `loginctl show-user "$USER" -p Linger` prints `Linger=yes`, or you explicitly report that sudo was unavailable and the service is only persistent for the current user manager/session.

### 6. Verify and capture URL

```bash
systemctl --user --no-pager --full status "claude-rc@$ENV_NAME.service" || true
journalctl --user -u "claude-rc@$ENV_NAME.service" -n 80 --no-pager \
  | grep -Eo 'https://claude.ai/code\?environment=[^ ]+' \
  | tail -1
readlink -f "$HOME/.config/claude-rc/projects/$ENV_NAME"
```

Also confirm there is only one Remote Control process for the environment:

```bash
for p in $(pgrep -f 'claude remote-control' || true); do
  cwd=$(readlink -f /proc/$p/cwd 2>/dev/null || true)
  cmd=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null || true)
  case "$cmd" in *"--name $ENV_NAME "*) echo "$p | $cwd | $cmd";; esac
done
```

Completion criteria: status is active, URL is present, symlink resolves to `PROJECT_DIR`, and exactly one intended process is running for the environment.

### 7. Clean up duplicate tmux servers only after service is healthy

If the environment was previously tmux-backed, stop duplicate `claude remote-control` processes/windows after service verification. Do not kill unrelated interactive Claude sessions.

Safe pattern:

```bash
# Inspect first
ps -eo pid,ppid,cmd | grep -E '[c]laude remote-control' || true
tmux list-windows -a 2>/dev/null || true

# Then kill only the known duplicate PID/window for the same ENV_NAME.
# Example:
# kill <old-pid>
# tmux kill-window -t hermes-claude:<old-window-name>
```

Completion criteria: only the systemd-managed `claude-rc@<name>` process remains for that environment.

## Remote host wrapper

For a remote host, run the same commands through SSH with BatchMode:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 <user@host> 'export PATH=$HOME/.local/bin:$PATH; ...'
```

Prefer one carefully quoted script over many ad-hoc commands. Always verify with `systemctl --user status` and `journalctl --user` on the target host.

## Reporting

Report:

- host;
- environment name;
- project path;
- service name;
- linger status;
- Remote Control URL;
- any settings keys removed;
- any duplicate tmux/process cleanup performed.
