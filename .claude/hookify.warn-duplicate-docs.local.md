---
name: warn-duplicate-docs
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: docs/.*\.md$
action: warn
---

**Before creating a new document in docs/, check for existing ones first.**

Run: `ls docs/` (and subdirectories) and check if a document already covers this feature or topic.

If a doc already exists, UPDATE it instead of creating a new file.
