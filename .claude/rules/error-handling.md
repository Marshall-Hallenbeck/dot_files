# Error Handling

## No Fallbacks or Degraded Recovery

NEVER add fallback checks, degraded recovery paths, graceful degradation, or silent error swallowing unless the user explicitly asks for it.

- No try/catch that silently continues with default values
- No fallback to alternative behavior on failure
- No "safe" wrappers that absorb errors
- No degraded modes that hide failures
- No default values substituted when operations fail
- No retry logic unless explicitly requested

## Hard Fail on Errors

Errors should be loud and immediate. Let them propagate, crash, and surface visibly.

- Throw/raise on unexpected conditions — don't recover silently
- Let the process crash rather than limp along in a broken state
- Surface errors to the caller, don't absorb them
- If something fails, it should be obvious and immediate
- Alert the user/developer of the error — never hide it

**The only exception:** When the user explicitly requests fallback behavior, graceful degradation, or retry logic.
