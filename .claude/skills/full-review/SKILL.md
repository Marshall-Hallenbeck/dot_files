---
name: full-review
description: "Run correctness + security/fail-open + best-practice review with full validation."
---

# Full Review

Performs a complete review pass for correctness, security posture, and verification policy.

## Usage

```text
/full-review
```

## Examples

```text
/full-review
```

Use before merge/PR when you want one workflow that checks code quality, security posture, and verification completeness.

## Review Pipeline

1. **Correctness review**
   - Run `/review`.
2. **Security/fail-open review**
   - Run `/overcautious_check`.
3. **Best-practices cross-check**
   - Run `/codex_review` and `/opencode_review` when available.
4. **Quality gate execution**
   - Run `/run-quality-gate`.

## Enforcement

- Any stage failure = overall failure.
- No "pre-existing issue" deferral without explicit evidence:
  1. reproduced before this change,
  2. unchanged after this change,
  3. user explicitly approved deferral.
- No silent fallback masking, fail-open auth behavior, or skipped tests.

## Output Requirements

```markdown
## Full Review Report

- Correctness review: ✅/❌
- Security/fail-open review: ✅/❌
- Best-practices review: ✅/❌
- Quality gate: ✅/❌
- Final verdict: PASS/FAIL
```
