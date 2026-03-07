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

### 6. Output

```markdown
## Security Review

Scanned N files with uncommitted changes.

### Findings

1. **[CRITICAL] Brief title** — `file:line`

   Description of the vulnerability and how it could be exploited.

2. **[HIGH] Brief title** — `file:line`

   Description.

### Verdict: SECURE / NEEDS FIXES
```

Verdicts:
- **SECURE**: No CRITICAL or HIGH findings.
- **NEEDS FIXES**: Has CRITICAL or HIGH findings that must be addressed.

If zero findings, report "No security issues found" with verdict SECURE.

## Rules

- **Security only.** Don't flag code quality, style, or correctness issues — that's `/review`'s domain.
- **No false positives.** A wrong security finding causes alert fatigue. When in doubt, don't flag.
- **Brief.** One paragraph max per finding. Describe the attack vector, not the fix.
- **Respect frameworks.** Don't flag things the framework already handles (React escaping, Strapi auth middleware).
- **Read context.** A SQL query in a migration script is not injection. A hardcoded string in a test is not a secret leak.
