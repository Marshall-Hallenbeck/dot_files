---
name: block-graceful-degradation
enabled: true
event: file
action: block
conditions:
  - field: new_text
    operator: regex_match
    pattern: catch\s*[\({][^}]*return\s+(null|undefined|false|None|\[\]|\{\}|""|''|0|default)|\.catch\s*\([^)]*=>[^}]*(return|null|undefined|\[\]|\{\}|""|'')|graceful(ly)?\s*(degrad|fail|recover|handle)|fail\s*safe|silent(ly)?\s*(fail|ignore|skip|swallow|continue)|except.*:\s*return\s+(None|\[\]|\{\}|False|0|"")
---

**BLOCKED: Graceful degradation / silent failure recovery detected.**

You are catching an error and returning a default value instead of letting it propagate.

- Errors should be loud and immediate
- Let them propagate, crash, and surface visibly
- No default values substituted when operations fail
- No retry logic unless explicitly requested
- The ONLY exception is when the user explicitly requests fallback behavior
