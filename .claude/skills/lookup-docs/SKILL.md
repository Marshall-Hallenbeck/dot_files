---
name: lookup-docs
description: "Look up documentation for any library using Context7. Resolves library IDs and queries versioned docs."
---

# Lookup Documentation

Find relevant documentation for any technology using Context7 MCP.

## Usage

```
/lookup-docs <library> <query>
```

## Examples

- `/lookup-docs strapi document service populate relations`
- `/lookup-docs mantine Modal controlled state`
- `/lookup-docs playwright wait for network idle`
- `/lookup-docs react server components data fetching`
- `/lookup-docs django queryset filtering`

## Steps

### 1. Parse Input

Extract:
- **Library name**: The technology (strapi, nextjs, mantine, django, etc.)
- **Query**: What they want to know

### 2. Resolve Library ID

```
mcp__context7__resolve-library-id or mcp__plugin_context7_context7__resolve-library-id
```

Call with the library name and query for context. This returns the Context7 library ID.

### 3. Query Documentation

```
mcp__context7__query-docs or mcp__plugin_context7_context7__query-docs
```

Call with the resolved library ID and the specific question.

### 4. Synthesize Response

From the documentation results:
- Extract the most relevant code examples
- Identify best practices
- Note any gotchas or common mistakes
- Provide a clear, actionable answer

## Output Format

```markdown
## Documentation: [library] - [topic]

### Quick Answer
[1-2 sentence direct answer]

### Code Example
[Most relevant, complete code example]

### Key Points
- [Important detail 1]
- [Important detail 2]

### Best Practices
- [Recommended approach]
- [What to avoid]

### Source
Library: [library ID]
```
