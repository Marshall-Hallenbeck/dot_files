---
name: overcautious_check
description: "Use when reviewing changes before commit to catch patterns that silence failures, fail open, add unauthorized fallbacks, or hide errors behind graceful degradation."
---

# Overcautious Check

Scan recent changes for code that silences, swallows, or hides failures. These patterns mask bugs and violate the project's hard-fail error handling policy.

## Usage

```
/overcautious_check
```

## Behavior

### 1. Gather Changes

Get all recent changes — both committed (on current branch, since divergence from main) and uncommitted:

```bash
# Uncommitted changes (staged + unstaged)
git diff HEAD

# Committed changes on this branch since main
git diff main...HEAD
```

If there are no changes at all, say so and stop.

### 2. Read Project Error Handling Rules

Read the project's error handling rules for context:
- `~/.claude/rules/error-handling.md`
- Root `CLAUDE.md` (error handling sections)

These define what IS and ISN'T allowed.

### 3. Scan for Overcautious Patterns

For each changed file, read the FULL file (not just diff hunks) and flag any of these patterns **in or near changed lines**:

#### Category A: Silent Error Swallowing

| Pattern | Example | Why It's Bad |
|---------|---------|-------------|
| Empty catch | `.catch(() => {})`, `catch (e) {}` | Error vanishes completely |
| Catch-and-return-default | `catch { return []; }`, `catch { return null; }` | Caller never knows it failed |
| Catch-and-log-only | `catch (e) { console.warn(e); }` without re-throw | Error noted but execution continues broken |
| Catch-and-continue | `try { x() } catch {} y()` | `y()` runs in potentially corrupt state |

#### Category B: Unauthorized Fallbacks

| Pattern | Example | Why It's Bad |
|---------|---------|-------------|
| Default on failure | `const data = await fetch(...).catch(() => defaultData)` | Masks network/API failures |
| Nullish coalescing masking errors | `result ?? fallbackValue` after an operation that shouldn't return null | Hides the real bug |
| Optional chaining hiding bugs | `deeply?.nested?.access` where undefined indicates a bug, not an expected state | Silences structural errors |
| Fallback import/require | `try { require('x') } catch { require('y') }` | Hides missing dependency |
| Conditional degradation | `if (service) { use(service) } else { useWorkaround() }` | Service absence is a bug, not a feature |

#### Category C: Test/Lint Silencing

| Pattern | Example | Why It's Bad |
|---------|---------|-------------|
| Skipped tests | `.skip`, `.only`, `xit(`, `xdescribe(`, `xtest(`, `pending(` | Hides failing tests |
| Lint suppression | `// eslint-disable`, `/* eslint-disable */`, `@ts-ignore`, `@ts-expect-error`, `// noinspection` | Suppresses valid warnings |
| Error filter/ignore | `filter(e => !knownErrors.includes(e))` | Normalizes errors |
| Console error suppression | `jest.spyOn(console, 'error').mockImplementation(() => {})` without restoration | Hides real errors in tests |

#### Category D: Failing Open

| Pattern | Example | Why It's Bad |
|---------|---------|-------------|
| Auth check returns true on error | `catch { return true; }` in permission check | Security bypass on failure |
| Validation defaults to valid | `catch { return { valid: true }; }` | Accepts bad input on error |
| Missing error propagation | `async function wrapper() { await inner(); }` with no error handling when caller expects throw | Error silently absorbed by async |
| Status check defaults to OK | `catch { return 200; }`, `catch { return 'success'; }` | Reports success on failure |

### 4. Evaluate Each Finding

For each pattern found, determine:

1. **Is it in changed code?** Only flag patterns in or directly adjacent to changed lines. Pre-existing patterns in untouched code are out of scope (use `/review` for full-file audits).

2. **Is it authorized?** Check for comments like `// User requested fallback`, or if the pattern is at a system boundary (user input validation, external API response handling) where graceful handling IS appropriate.

3. **What's the severity?**
   - **BLOCK**: Auth/security failing open, empty catch in error path, test skipping
   - **WARN**: Catch-and-log-only, optional chaining on expected data, lint suppression
   - **INFO**: Patterns at system boundaries that may be intentional

### 5. Output

```markdown
## Overcautious Check

Scanned N files with recent changes.

### Findings

1. **[BLOCK] Empty catch swallows API error** — `backend/src/api/foo.js:45`

   `.catch(() => {})` on the tournament fetch means callers never know the request failed.
   The error should propagate to the controller's error handler.

2. **[WARN] Catch-and-log without re-throw** — `backend/src/services/bar.js:112`

   `catch (e) { strapi.log.warn(e); }` logs the error but continues execution.
   Either re-throw after logging or let it propagate.

### Summary
- BLOCK: 1 (must fix before commit)
- WARN: 1 (should fix)
- INFO: 0

### Verdict: BLOCKED / CLEAN
```

**BLOCKED** = any BLOCK-level findings exist.
**CLEAN** = no BLOCK or WARN findings. INFO-only or no findings.

If zero findings:

```markdown
## Overcautious Check

Scanned N files with recent changes.

No overcautious patterns found. Error handling looks correct — failures propagate visibly.

### Verdict: CLEAN
```

## Legitimate Exceptions

These are NOT overcautious — do not flag them:

- **System boundary handling**: `try { JSON.parse(userInput) } catch { return 400 }` — validating external input IS appropriate
- **Cleanup/finally**: `finally { cleanup() }` — resource cleanup after error is correct
- **Intentional retry with backoff**: When explicitly requested by user
- **Expected optional data**: `user?.avatar` when avatar genuinely may not exist (not a bug)
- **Test mocks**: Mocking in test setup that's properly restored in teardown
- **Process-level handlers**: `process.on('uncaughtException', ...)` for logging before exit

## Important Rules

- **Read full files, not just diff hunks.** A catch block 5 lines below a changed line IS relevant context.
- **Don't flag system boundaries.** Validating user input, handling 404s, parsing external data — these need graceful handling.
- **Don't suggest adding error handling.** This skill finds EXCESSIVE error handling, not missing error handling.
- **One paragraph max per finding.** Describe the problem and why it masks failures.
- **No code suggestions.** Describe the problem; don't write the fix.
