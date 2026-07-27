# Pre-flight Check for Remote Deployment

Run pre-flight checks before deploying to a remote host. Catches the most common homelab deploy failure modes (quota, permissions, credential mismatch) before anything breaks.

## Arguments
`$ARGUMENTS` — target host, e.g. `ansible@host.example` or `user@server.example`. If blank, check the current local machine only.

## Checks

### Local checks (always run)
- [ ] `.env` file present and non-empty (if the project uses one)
- [ ] Required env vars are set (check `.env` and current shell)
- [ ] SSH key exists for the target host: check `~/.ssh/` for relevant keys
- [ ] No uncommitted secrets in git staging: `git diff --cached | grep -Ei 'password|secret|token|api_key'`

### Remote checks (if $ARGUMENTS is a host)
1. **Reachability** — `ssh -o ConnectTimeout=5 $ARGUMENTS 'echo ok'`
2. **Disk space** — `ssh $ARGUMENTS 'df -h / /var /opt 2>/dev/null | tail -n +2'` — warn if any partition >85% full
3. **Permissions** — verify the deploy user can write to the target paths for this project
4. **Service state** — `ssh $ARGUMENTS 'systemctl --user status 2>/dev/null || docker ps 2>/dev/null | head -10'` to confirm the current state before touching it
5. **Credentials** — if the deploy involves a password (e.g. DB, sudo), confirm it is present in `.env` or an env var; do not proceed if it is missing

### Report
Output a checklist with PASS/FAIL/WARN per item. If any item is FAIL, stop and explain what is missing before proceeding with the deployment.
