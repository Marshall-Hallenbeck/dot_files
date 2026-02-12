---
name: recall-memory
description: "Recall stored preferences and project context from the memory MCP knowledge graph."
---

# Recall Memory

Retrieves stored knowledge about the user, project, and development preferences from the memory MCP.

## Usage

```
/recall-memory
```

## Behavior

1. **Read the full knowledge graph:**
   ```
   mcp__memory__read_graph()
   ```

2. **Display entities and their observations** organized by type:
   - Developer preferences
   - Project context
   - Coding conventions
   - Any other stored knowledge

3. **Acknowledge the recalled context** and apply it to the current session.

## Output Format

```markdown
## Recalled Memory

### Developer: [Name]
- [observations...]

### Project: [Name]
- [observations...]

### Preferences
- [observations...]

### Relations
- [entity] → [relation] → [entity]

---
*Memory recalled. These preferences will be applied to this session.*
```

## When to Use

- At the start of a new session
- When unsure about project conventions
- When asked "what do you remember?"
- Before making decisions that might conflict with stored preferences

## Adding to Memory

To add new information:

```
mcp__memory__create_entities([{ name: "Name", entityType: "Type", observations: ["fact"] }])
mcp__memory__add_observations([{ entityName: "Name", contents: ["new fact"] }])
mcp__memory__create_relations([{ from: "A", to: "B", relationType: "relates_to" }])
```
