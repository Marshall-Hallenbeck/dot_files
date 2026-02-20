---
name: require-flakiness-investigation
enabled: true
event: stop
pattern: .*
action: warn
---

**Before claiming any test failure is "flaky", "intermittent", or caused by "load/timing":**

You MUST:
1. **Investigate the actual root cause** — read the error message, understand what's failing and why
2. **Reproduce and fix** — if a test fails under load but passes alone, the test has a bug (race condition, stale state, missing waits). Fix the test.
3. **Re-run to verify** — after fixing, run the full suite again to confirm

You MUST NOT:
- Blame "backend load", "server capacity", or "infrastructure flakiness" — local environments handle thousands of requests per second
- Claim failures are "pre-existing" — always assume any test failure was caused by your changes and needs to be fixed
- Add retries as a band-aid instead of fixing the root cause
- Use `test.skip()` to hide failures
- Claim a test is "flaky" without investigating WHY it fails under concurrent execution
- Accept "passes alone, fails in suite" as an acceptable end state — that IS a bug in the test

**Every test failure has a deterministic cause. Find it.**
