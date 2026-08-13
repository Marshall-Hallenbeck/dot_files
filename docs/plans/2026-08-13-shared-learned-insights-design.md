# Shared Learned Insights Design

## Goal

Use one tracked global learned-insights file for Claude Code and Codex.

## Design

The canonical file is `.claude/global-learned-insights.md` in the dotfiles
repository. The installer links both runtime paths directly to this file:

- `~/.claude/global-learned-insights.md`
- `~/.codex/global-learned-insights.md`

Before the current regular Claude file is replaced, its newer entries are
merged into the canonical file. The existing `link_file` helper provides a
backup for a regular destination file before it creates the link.

The installer verification must require both paths to be links and must
require both links to resolve to the canonical file. The Codex instructions
must use the lowercase `.codex` path used by the application.

## Scope

This change applies to the Linux installer and the current Linux home
directory. The Windows installer keeps its current copy behavior.

