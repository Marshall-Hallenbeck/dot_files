---
name: commit
description: Create a git commit
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*)
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

Based on the above changes, create a single git commit.

**CRITICAL: Only stage files that you modified during this conversation.** Do NOT stage unrelated changes that happen to be in the working tree. Review the diff carefully and only `git add` files that are relevant to the work you performed in the current session.

You have the capability to call multiple tools in a single response. Stage and create the commit using a single message. Do not use any other tools or do anything else. Do not send any other text or messages besides these tool calls.
