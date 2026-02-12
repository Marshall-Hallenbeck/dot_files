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

## Clean Deletion

Avoid backwards-compatibility hacks:
- No renaming unused `_vars`
- No re-exporting types for compatibility
- No `// removed` comments for deleted code
- If something is unused, delete it completely
