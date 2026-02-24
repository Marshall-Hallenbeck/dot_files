---
name: block-error-swallowing
enabled: true
event: all
action: block
pattern: \.catch\s*\(\s*\(\s*\)\s*=>\s*\{[\s]*\}\s*\)|catch\s*\{\s*\}|catch\s*\([^)]*\)\s*\{[\s]*\}|except\s*:\s*(pass|\.\.\.)|except\s+\w+(\s+as\s+\w+)?\s*:\s*(pass|\.\.\.)|_\s*=\s*recover\(\)|defer\s+func\(\)\s*\{\s*recover\(\)|if\s+err\s*!=\s*nil\s*\{\s*(return\s+nil|_\s*=\s*err)\s*\}|2>\s*/dev/null|2>&1\s*\|\s*true|\|\|\s*true|\|\|\s*:|trap\s+['"]?\s*['"]?\s+ERR
---

**BLOCKED: Silent error swallowing detected.**

You are writing code that catches an error and does nothing with it.

**Detected patterns (any language):**

JavaScript/TypeScript:
- `.catch(() => {})` — empty catch callback
- `catch {}` — empty catch block
- `catch (e) { }` — catch with unused variable

Python:
- `except: pass` — bare except with pass
- `except Exception as e: pass` — catch-all with pass
- `except ValueError: ...` — catch with ellipsis

Go:
- `_ = recover()` — discarded recover
- `if err != nil { return nil }` — swallowed error
- `if err != nil { _ = err }` — explicitly discarded error

Bash:
- `2> /dev/null` — stderr redirected to nowhere
- `2>&1 | true` — piped to true to force exit 0
- `|| true` — error exit code silently ignored
- `|| :` — error exit code silently ignored (`:` is a no-op)
- `trap '' ERR` — empty ERR trap disables error handling

**What to do instead:**
- Let the error propagate and crash visibly
- Re-throw the error after logging if you need observability
- If this is truly an expected condition, handle it explicitly with a meaningful code path
