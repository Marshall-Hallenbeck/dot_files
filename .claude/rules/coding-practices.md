# Coding Practices

## Prefer Editing Existing Files

Before creating a new file, verify:
- Is there an existing file that could be updated instead?
- Could this code be added to an existing component or module?
- Is this truly a new feature that warrants a new file?

**When new files ARE appropriate:**
- New components with distinct functionality
- New API routes or controllers
- New test files for new functionality
- New utility modules with standalone purpose

**When to use existing files instead:**
- Adding helper functions → Check if a utils file already exists
- Adding types → Check if types are defined elsewhere
- Small tweaks or additions → Update the existing file
- Fixing bugs → Modify the existing code

## Verify Schemas Before Writing Code

Before editing code that references database columns, API fields, or type properties, read the actual schema or type definitions first. Do not assume field names — verify them. This applies to ORM models, API response shapes, GraphQL schemas, and any typed interface.

## Read Before Modifying

Before modifying files, read similar files to understand existing patterns. This prevents:
- Style inconsistencies (import order, formatting, naming)
- Architectural mismatches (server vs client, service patterns)
- Duplicate implementations (existing utilities not reused)
- Breaking conventions (route structure, type definitions, test patterns)

**Skip this when:**
- You've already read similar files in this session
- Making trivial changes (typo fixes, comment updates)
- Following explicit instructions with exact code provided

## Avoid Over-Engineering

Only make changes that are directly requested or clearly necessary.

- Don't add features, refactor code, or make "improvements" beyond what was asked
- A bug fix doesn't need surrounding code cleaned up
- A simple feature doesn't need extra configurability
- Don't add error handling for scenarios that can't happen
- Trust internal code and framework guarantees
- Only validate at system boundaries (user input, external APIs)
- Don't create helpers or abstractions for one-time operations
- Don't design for hypothetical future requirements
- Three similar lines of code is better than a premature abstraction
- Don't add docstrings, comments, or type annotations to code you didn't change
- Only add comments where the logic isn't self-evident

## Comments

- Comment only what needs one. Do not narrate code that already reads clearly.
- Maximum 2 lines per comment; a third only when genuinely necessary. Line length is not capped — prefer one long line over a third line.
- If a comment runs long, **shorten the comment** — never restructure the code to accommodate it.
- Do not write rationale, historical context, or the story of a bug into a comment. That belongs in the PR or issue. Reference it instead.

```python
# Wrong — rationale, history, and a quoted error belong in the PR
# Setting ad.baseDN narrowed every search alike, including ones whose objects
# do not live under the given subtree. The domain object and its trusts are
# children of the naming context, so those searches returned nothing and
# collection aborted with "Could not find the requested domain ...".
# The search_base fallback is therefore chosen per query instead.

# Right
# These objects live at the naming context root, not under a scoped OU. PR #1374
```

## Direct Attribute Access

Use dot notation for attribute access in Python. Do not use `getattr(obj, "attr")` or `setattr(obj, "attr", val)` when the attribute name is a constant — use `obj.attr` and `obj.attr = val` directly. Similarly, do not add `# pyright: ignore` or `# type: ignore` comments unless absolutely unavoidable for third-party library compatibility.

## No Underscore-Prefixed Names

Never use leading underscores for "private" functions, methods, classes, or module-level constants. All names are public. Use plain, descriptive names.

```python
# Wrong
def _parse_response(data): ...
_MAX_RETRIES = 3
class _InternalHelper: ...

# Right
def parse_response(data): ...
MAX_RETRIES = 3
class InternalHelper: ...
```

The only acceptable leading underscore is `_` as a throwaway variable in unpacking (e.g., `for _, value in items`).

## Clean Deletion

Avoid backwards-compatibility hacks:
- No renaming unused `_vars`
- No re-exporting types for compatibility
- No `// removed` comments for deleted code
- If something is unused, delete it completely
