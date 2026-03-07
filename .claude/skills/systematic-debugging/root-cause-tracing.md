# Root Cause Tracing

## Overview

Bugs often manifest deep in the call stack. Your instinct is to fix where the error appears, but that's treating a symptom.

**Core principle:** Trace backward through the call chain until you find the original trigger, then fix at the source.

## The Tracing Process

### 1. Observe the Symptom
Note the error message, stack trace, and context.

### 2. Find Immediate Cause
What code directly causes this error?

### 3. Ask: What Called This?
Trace backward through the call chain. At each level ask: what value was passed, and where did it come from?

### 4. Keep Tracing Up
Continue until you find the original source of the bad value or state.

### 5. Find Original Trigger
The root cause is often several layers above where the error appears.

## Adding Stack Traces

When you can't trace manually, add instrumentation:

```typescript
// Before the problematic operation
async function riskyOperation(input: string) {
  const stack = new Error().stack;
  console.error('DEBUG riskyOperation:', {
    input,
    cwd: process.cwd(),
    stack,
  });
  // ... proceed
}
```

**Critical:** Use `console.error()` in tests (not logger - may not show)

## Key Principle

**NEVER fix just where the error appears.** Trace back to find the original trigger. Fix at the source, then add validation at each layer the data passes through.
