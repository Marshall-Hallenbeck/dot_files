---
name: completion-check
enabled: true
event: stop
action: block
pattern: .*
---

**Before completing, verify these are NOT in your changes:**

1. **No empty catch blocks** — no `.catch(() => {})`, no `catch { }`, no `except: pass`, no catch-and-return-default
2. **No backwards-compat shims** — no "kept for backwards compat", no version-conditional code, no polyfills
3. **No graceful degradation** — no catch-and-return-null, no fallback default values on error
4. **No "pre-existing" dismissals** — if it's in the diff, you own it. Fix it.
5. **No `test.skip()`** — tests must fail loudly, never skip silently

If ANY of these exist in your uncommitted changes, fix them before stopping.
