---
name: block-backwards-compat
enabled: true
event: file
action: block
pattern: backwards?\s*compat|kept\s+for\s+(backward|compat|legacy)|fallback\s+for\s+older|legacy\s+support|deprecated.*fallback|version\s*<|polyfill|shim\s+for
---

**BLOCKED: Backwards-compatibility code detected.**

Do not write code or comments that reference backwards compatibility, legacy support, polyfills, or version-conditional shims.

- Write for the current stack only
- Delete code paths for older versions entirely
- Do not design for hypothetical future requirements
- If unsure which version is current, check the project's package.json / go.mod / requirements.txt
