---
name: security-review
description: "Security audit of uncommitted changes. Scans for OWASP top 10, injection, exposed secrets, auth bypasses, and unsafe patterns."
argument-hint: "[path]"
context: fork
---

# Security Review

Dedicated security audit of code changes. Focuses exclusively on security vulnerabilities — not code quality, style, or correctness (those are `/review`'s job).

## Usage

```text
/security-review
/security-review backend/src/
```

## Behavior

### 1. Gather the Diff

```bash
git diff HEAD
```

If arguments provided, scope the diff:
```bash
git diff HEAD -- <path>
```

If no uncommitted changes, say so and stop.

### 2. Read Full Files for Context

For each changed file, read the full file (not just diff hunks). Security issues often span multiple functions.

### 3. Scan for Vulnerability Categories

#### A. Injection

- **SQL injection**: Raw string interpolation in queries, missing parameterized queries
- **NoSQL injection**: Unsanitized user input in MongoDB/Strapi filters
- **Command injection**: User input passed to shell execution without sanitization
- **XSS**: Unsanitized user content rendered as HTML, missing output encoding
- **Path traversal**: User input in file paths without sanitization

#### B. Authentication & Authorization

- **Auth bypass**: Missing auth checks on new routes/endpoints
- **Privilege escalation**: User can access/modify resources they shouldn't own
- **JWT/token issues**: Hardcoded secrets, missing expiration, weak algorithms
- **IDOR**: Direct object references without ownership validation

#### C. Data Exposure

- **Secret leaks**: API keys, passwords, tokens hardcoded in source (not env vars)
- **Sensitive data in logs**: PII, credentials, tokens logged to console/files
- **Verbose errors**: Stack traces or internal paths exposed to clients
- **Over-fetching**: API returns more fields than the client needs

#### D. Configuration

- **CORS misconfiguration**: Overly permissive origins, credentials with wildcards
- **Missing rate limiting**: New endpoints without rate limiting on auth/sensitive routes
- **Insecure defaults**: Debug mode in production, permissive CSP, missing security headers
- **Dependency issues**: Known vulnerable package versions in changed package.json

#### E. Unsafe Code Patterns

- **Dynamic code execution**: Functions that interpret strings as code with user-controlled input
- **Unsafe HTML rendering**: Setting inner HTML content without sanitization
- **Prototype pollution**: Object merging/spreading with unsanitized user objects
- **Race conditions**: TOCTOU bugs in auth checks, file operations
- **Unvalidated redirects**: User-controlled redirect URLs without allowlist

### 4. Assign Severity

- **[CRITICAL]** — Exploitable now. Auth bypass, injection, secret leak. Must fix immediately.
- **[HIGH]** — Likely exploitable with effort. IDOR, XSS, privilege escalation.
- **[MEDIUM]** — Needs specific conditions. Race condition, verbose errors, missing rate limit.
- **[LOW]** — Defense in depth. Missing security header, overly broad CORS in dev.

### 5. Self-Check

Before reporting:
- Is this actually exploitable, or am I speculating about a theoretical attack?
- Is user input actually reaching this code path?
- Does the framework already protect against this (e.g., React auto-escapes, Strapi has built-in auth)?
- Is this a dev-only configuration that won't reach production?

Drop findings below 70% confidence.

### 6. Fix Every Finding

Fix every finding you reported — CRITICAL, HIGH, MEDIUM, AND LOW. A clean security review leaves zero open findings, not just zero CRITICAL/HIGH.

For each finding:
1. Read the full file for context.
2. Apply the fix (parameterize the query, add the missing auth/ownership check, move the secret to an env var, narrow the over-fetch, restrict CORS, add the rate limit, etc.).
3. Add a regression test where one is meaningful — e.g. a test asserting the endpoint returns 403 for a non-owner, or that a query rejects an injection payload. Follow the project's existing test conventions.
4. Briefly note what changed and what test was added.

Only leave a finding unfixed if (a) it's a verified false positive — say so and why — or (b) the fix needs a threat-model decision (e.g. "should this role be allowed here at all?") that only the user can make — surface it explicitly and ask. Never defer a real finding silently.

Run the test suite after fixes to confirm nothing broke.

### 7. Output

```markdown
## Security Review

Scanned N files with uncommitted changes.

### Findings

1. **[CRITICAL] Brief title** — `file:line`

   Description of the vulnerability and how it could be exploited.

2. **[HIGH] Brief title** — `file:line`

   Description.

### Verdict: SECURE / NEEDS INPUT
```

Each finding line should end with **Fixed:** a one-line description of the fix (and the regression test, if added).

Verdicts:
- **SECURE**: Zero open findings at any severity (CRITICAL through LOW) — everything found was fixed.
- **NEEDS INPUT**: A finding remains only because it needs a user threat-model decision or was flagged as a false positive. List exactly which, and why.

If zero findings, report "No security issues found" with verdict SECURE.

## Rules

- **Security only.** Don't flag code quality, style, or correctness issues — that's `/review`'s domain.
- **No false positives.** A wrong security finding causes alert fatigue. When in doubt, don't flag.
- **Find AND fix.** Every real finding (CRITICAL→LOW) gets fixed, not just reported. A clean review leaves zero open findings.
- **Brief.** One paragraph max per finding: describe the attack vector, then state the fix in one line.
- **Respect frameworks.** Don't flag things the framework already handles (React escaping, Strapi auth middleware).
- **Read context.** A SQL query in a migration script is not injection. A hardcoded string in a test is not a secret leak.
