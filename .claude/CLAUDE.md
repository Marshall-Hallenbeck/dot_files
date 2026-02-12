# Global Claude Code Instructions

These principles apply to ALL projects. Project-specific CLAUDE.md files override or extend these.

## Verification Policy (Anti-Sycophancy)

**CRITICAL: All code changes MUST be verified before claiming completion.**

Never claim success without objective proof. If you can't prove it works, you haven't finished.

### Verification Hierarchy (Use in Order)

1. **Automated Tests (ALWAYS FIRST)** — If code was changed, tests MUST be run. Show output with pass/fail counts.
   - `"Tests passed: 47/47 (100%)"` — Good
   - `"Tests should pass"` — INCOMPLETE. Run them.
2. **Visual Verification (UI Changes)** — Use Playwright or screenshots. Describe what you observe vs. what was requested.
3. **Manual Verification (Complex Changes)** — Provide concrete "Run X, expect Y" instructions.
4. **One-Off Commands (Quick Checks)** — curl, grep, etc.

### Fix Verification

Before claiming anything is "fixed", provide:
- **User requested:** [what was asked]
- **Evidence shows:** [what you observe, specifically]
- **Verdict:** FIXED / NOT FIXED / PARTIALLY FIXED

### Prohibited Without Proof

- "I've updated X" → Show test output
- "Tests should pass" → Run them and show output
- "Feature implemented" → Demonstrate with tests/screenshots
- "Fixed" / "All set" / "Done" → Prove it

**Verification Failure = Task Incomplete. No Exceptions.**

## Coding Practices

### Prefer Editing Existing Files

Do not create files unless absolutely necessary. Prefer editing an existing file to creating a new one. Before creating a new file:
- Is there an existing file that could be updated instead?
- Could this code be added to an existing module?
- Is this truly new functionality that warrants a new file?

### Read Before Modifying

Before modifying files, read similar files to understand existing patterns. Consistent code prevents style inconsistencies, architectural mismatches, and duplicate implementations.

### Avoid Over-Engineering

Only make changes that are directly requested or clearly necessary. Keep solutions simple and focused.
- Don't add features, refactor code, or make "improvements" beyond what was asked
- Don't add error handling for scenarios that can't happen
- Don't create helpers or abstractions for one-time operations
- Don't design for hypothetical future requirements
- Three similar lines of code is better than a premature abstraction
- Don't add docstrings, comments, or type annotations to code you didn't change

### Security

- Never commit credentials (.env, API keys, tokens, passwords)
- Be aware of OWASP top 10 vulnerabilities (XSS, SQL injection, command injection)
- Validate at system boundaries (user input, external APIs)
- If you notice insecure code, fix it immediately

## API Error Handling Classification

- **400 (ValidationError)** = Frontend bug → Fix the request/schema mismatch
- **404 (Not Found)** = Expected scenario → Show user-friendly message
- **403 (Forbidden)** = Expected → Show "no permission" message
- **401 (Unauthorized)** = Expected → Redirect to login
- **500 (Internal Error)** = Backend bug → Fix the server code

Never "handle gracefully" what should be "fixed immediately" (400s and 500s are bugs).

## Testing Philosophy

- Prefer TDD (Red-Green-Refactor) when practical
- Write tests for new functionality. Run them. Show output.
- Create regression tests for bug fixes
- Tests are proof that code works — not optional documentation

## Git Conventions

Follow Conventional Commits: `<type>(scope): description`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`
- Branch naming: `<type>/<description>` or `<type>/<ticket>-<description>`
- Commit messages should explain "why", not "what"
