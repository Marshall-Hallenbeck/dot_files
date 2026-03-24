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
4. **No blame-shifting** — if it's in the diff, you own it. Fix it.
5. **No `test.skip()`** — tests must fail loudly, never skip silently
6. **No untested new code** — new public functions, components, routes, or handlers must have corresponding test coverage. If you added functionality without tests, write them before completing.
7. **No bug fixes without regression tests** — if you fixed a bug, there must be a test that would have caught it. If missing, create it.

If ANY of these exist in your uncommitted changes, fix them before stopping.
