---
description: "Docker Compose log retrieval, container debugging, and Docker MCP tool limitations. Use when running docker commands, debugging services, viewing logs, or troubleshooting containers."
---

# Docker Conventions

## Log Retrieval

Always use precise log retrieval instead of unbounded `docker compose logs` or guessing with `--tail`.

**Key flags:**
- `-t` — show timestamps (always include for debugging)
- `--since` — time window: relative (`5m`, `1h`, `30s`) or absolute (`2026-01-15T10:00:00Z`)
- `--until` — upper time bound (same format as `--since`)
- `-n` / `--tail` — last N lines
- `--no-color` — clean output for grep or saving to files
- `-f` — follow (live tail)

### Recommended Patterns

```bash
# Recent logs with timestamps (most common debugging command)
docker compose logs -t --since 5m frontend backend

# Search for errors in last 10 minutes
docker compose logs -t --since 10m --no-color backend 2>&1 | grep -i "error\|failed\|exception"

# Last N lines with timestamps
docker compose logs -t -n 100 backend

# Follow with timestamps
docker compose logs -f -t backend

# Logs in a time window
docker compose logs -t --since 2026-02-25T10:00:00Z --until 2026-02-25T10:30:00Z backend

# Save to file for analysis
docker compose logs -t --since 1h --no-color frontend backend > /tmp/logs.txt
```

### Avoid These

```bash
# No time context — could dump thousands of lines
docker compose logs backend

# No timestamps — can't correlate with events
docker compose logs --tail 50 backend

# Following without timestamps — hard to read
docker compose logs -f backend
```

## Docker MCP Tool Limitations

The `mcp__mcp-server-docker__fetch_container_logs` MCP tool only supports:
- `container_id` — container name or ID
- `tail` — number of lines from the end

It does **NOT** support `--since`, `--until`, `--timestamps`, `--no-color`, or multi-container queries.

**Use MCP for:** quick "last N lines" checks
**Use CLI for:** time-based debugging, error searching, multi-service queries, saving logs to files
