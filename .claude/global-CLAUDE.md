# Global Claude Code Instructions

These principles apply to ALL projects. Project-specific CLAUDE.md files override or extend these.

## Environment & Preferences

- Primary OS: Kali Linux (Debian-based)
- Shell: zsh with oh-my-zsh
- Primary use cases: security tooling, full-stack web development, infrastructure automation
- Shell scripts: bash (`#!/bin/bash` with `set -euo pipefail`)

## Debugging

When investigating issues, verify the actual infrastructure routing (e.g., nginx, reverse proxies) BEFORE assuming the problem is in application code. Check how URLs are routed at the infrastructure level first.

## Planning & Refactoring

When creating plans or reviewing code, do NOT assume codebase state — always read the actual files to verify existing abstractions, function signatures, and current behavior before proposing changes. Never guess at what exists.

## Simplicity

Always prefer simple, minimal solutions first. Avoid over-engineering with unnecessary features like color output, complex abstractions, or multi-layered architectures unless explicitly requested. If you believe a more complex approach is genuinely needed, explain why BEFORE implementing it and let me decide.
