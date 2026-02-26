---
name: multi-model-review
description: "Run code review with 4 free OpenCode models in parallel, then have them peer-review each other to reach consensus findings."
---

# Multi-Model Code Review

Run code review using 4 free OpenCode models in parallel, then have them peer-review each other to reach consensus findings.

## Usage

```
/multi-model-review
/multi-model-review backend/src/
```

## Behavior

### 1. Gather the Diff

Run git diff to get the changes:
```bash
git diff HEAD
```

If arguments were provided, scope the diff:
```bash
git diff HEAD -- <path>
```

If there are no uncommitted changes, say so and stop.

### 2. Run 4 Models in Parallel (CRITICAL: Use bash, not Task agents)

Launch 4 concurrent bash commands IN PARALLEL using separate tool calls:

```bash
# Model 1: big-pickle (fast, concise)
~/.opencode/bin/opencode run -m opencode/big-pickle "You are a code reviewer. Run git diff HEAD first to see uncommitted changes. Focus on bugs, security issues. Output format: ## Code Review\n### Findings\n1. [P1] Title — file:line\n### Verdict: PASS | NEEDS FIXES" 2>/dev/null

# Model 2: gpt-5-nano (thorough)
~/.opencode/bin/opencode run -m opencode/gpt-5-nano "You are a code reviewer. Run git diff HEAD first to see uncommitted changes. Focus on bugs, security issues. Output format: ## Code Review\n### Findings\n1. [P1] Title — file:line\n### Verdict: PASS | NEEDS FIXES" 2>/dev/null

# Model 3: minimax-m2.5-free (balanced)
~/.opencode/bin/opencode run -m opencode/minimax-m2.5-free "You are a code reviewer. Run git diff HEAD first to see uncommitted changes. Focus on bugs, security issues. Output format: ## Code Review\n### Findings\n1. [P1] Title — file:line\n### Verdict: PASS | NEEDS FIXES" 2>/dev/null

# Model 4: trinity-large-preview-free (critical)
~/.opencode/bin/opencode run -m opencode/trinity-large-preview-free "You are a code reviewer. Run git diff HEAD first to see uncommitted changes. Focus on bugs, security issues. Output format: ## Code Review\n### Findings\n1. [P1] Title — file:line\n### Verdict: PASS | NEEDS FIXES" 2>/dev/null
```

**IMPORTANT**: Use bash tool with the exact prompt above - do NOT use Task agents, they don't invoke skills properly.

### 3. Save Individual Reviews

Save each output to:
```
reviews/
├── review_big-pickle.md
├── review_gpt-5-nano.md
├── review_minimax-m2.5-free.md
└── review_trinity-large-preview-free.md
```

### 4. Peer Review Round

Once all 4 complete, create a new prompt with all 4 reviews and ask for peer review:

```
You have 4 code reviews of the same changes. Review each finding and identify:
1. Which findings are valid (confirmed by code evidence)
2. Which are false positives
3. Any issues missed

Reviews:
[paste all 4 reviews]

Output format:
## Peer Review

### Validated Issues (2+ models agree)
- [issue]

### Disputed/False Positive Issues
- [issue]

### Missing Issues
- [issue]

## Consensus Verdict: PASS | NEEDS FIXES
```

### 5. Synthesize Consensus

Create `reviews/SUMMARY.md` with:
- Table comparing models
- Issues grouped by consensus level
- Final verdict

## Important Rules

- **Use bash commands directly** - Not Task agents, not skill invocation
- **Run all 4 in parallel** - Use separate bash tool calls simultaneously  
- **Always pipe to /dev/null** - Avoids noise
- **Quote prompts properly** - Use single quotes around prompts to prevent shell interpretation of special chars

---

## Bonus: Auto-Fix with Opus

After consensus, you can have Opus 4.6 implement fixes:

```
~/.opencode/bin/opencode run -m anthropic/opus-4-6 "You are a code reviewer. Read the SUMMARY.md in reviews/ directory for consensus issues. Fix each P1 issue found there. Run tests after fixes."
```

Or use bash with proper quoting:
```bash
~/.opencode/bin/opencode run -m anthropic/opus-4-6 'You are a code reviewer. Read reviews/SUMMARY.md for consensus issues. Fix each P1 issue. Run tests after.' 2>/dev/null
```
