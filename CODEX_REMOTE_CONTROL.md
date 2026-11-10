# Fresh-host managed Codex setup

Deploy optional assets without starting, stopping, or restarting any service:

```sh
dotfiles feature-enable ai-remote-control
```

Then explicitly provision Codex on a fresh, idle Linux host:

```sh
dotfiles feature-setup ai-remote-control
```

Setup uses `~/.codex`. If `CODEX_HOME` points to a different directory, setup
refuses before it changes files or services.

For a fresh systemd installation, opt in to both steps:

```sh
DOTFILES_SETUP_REMOTE_CONTROL=1 ./install_environment.sh
```

Ordinary installer reruns and feature-enable remain deployment-only for Remote
Control. Claude project activation remains a separate operator action.

Setup invokes the standalone CLI's `app-server daemon bootstrap --remote-control`,
then **`app-server daemon update --from-cli --yes`**. The update provisions the
managed package and pins the daemon to the
installed CLI version; future CLI upgrades do not imply that this pin advances.
Setup verifies that `~/.codex/packages/app-server-daemon/current/bin/codex` is
executable and successfully answers `--version` before allowing Desktop launches.

Existing unmanaged servers, orphan proxies, and partial installations are refused
(exit 75); they are never stopped or migrated. A running managed server with a
working managed executable is left unchanged. No cleanup/migration helper is run.
Run only while other clients and installers are quiescent: process inspection is
not a lock against unrelated clients starting direct CLI processes.

On failure, setup retains `~/.codex/app-server-daemon-setup-started`, leaves partial
state in place, and returns nonzero. The wrapper blocks Desktop/proxy startup
while that marker exists, including if the update created a package but later
failed. Do not blindly retry or delete markers: inspect the daemon, package,
socket and active workloads during an authorized maintenance window. Recovery of
existing/partial installations is intentionally not automated by this command.

The installer never unlinks an existing dotfiles Codex wrapper to repair the
standalone package. Missing packages behind that guard require explicit maintenance
repair; an installer failure must not silently expose the unguarded launcher.
