# Verification Requirements

## Before Claiming Completion

You MUST verify changes actually work before claiming task completion. This is non-negotiable.

### Required Verification

1. **Run tests** if code was changed — show pass/fail counts
2. **Take screenshots** if UI was changed — describe what you observe
3. **Run the code** if behavior was changed — show output matches expectations

### Fix Verification Format

When claiming a fix, always provide:

```
**User requested:** [exact issue/request]
**Evidence shows:** [specific observations from tests/screenshots/output]
**Comparison:**
- [ ] Does X match the request? [Yes/No + evidence]
- [ ] Any remaining issues? [List them]
**Verdict:** FIXED / NOT FIXED / PARTIALLY FIXED
```

### Prohibited Statements Without Proof

These are NEVER acceptable without accompanying evidence:
- "I've updated X" → Show test output
- "Tests should pass" → Run them and show results
- "Feature implemented" → Demonstrate it working
- "Fixed" / "All set" / "Done" / "Complete" → Prove it
- "Should work now" → Verify it does

### The Key Question

After every change, ask yourself:
**"If I were the user looking at this, would I agree it's done?"**

If you can't answer "yes" with specific evidence, it's NOT done.
