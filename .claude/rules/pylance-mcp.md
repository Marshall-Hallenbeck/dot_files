---
description: "Pylance MCP tool usage. Apply when calling pylanceRunCodeSnippet or any Pylance MCP tools."
---

# Pylance MCP Tool

## pylanceRunCodeSnippet

**NEVER pass the `timeout` parameter** to `pylanceRunCodeSnippet`. Passing `timeout` triggers a bug in the Pylance MCP server's async task/polling machinery, causing the request to be immediately cancelled with "request cancelled" before the snippet runs.

Correct usage — only pass `workspaceRoot` and `codeSnippet` (and optionally `workingDirectory`):

```
pylanceRunCodeSnippet(
  workspaceRoot: "file:///path/to/workspace",
  codeSnippet: "print('hello')",
  workingDirectory: "/path/to/workspace"  # optional
)
```

**Do NOT do this:**
```
pylanceRunCodeSnippet(
  workspaceRoot: "file:///path/to/workspace",
  codeSnippet: "print('hello')",
  timeout: 120  # ← BREAKS THE TOOL, causes "request cancelled"
)
```
