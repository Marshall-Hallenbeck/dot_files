# Defense-in-Depth Validation

## Overview

When you fix a bug caused by invalid data, adding validation at one place feels sufficient. But that single check can be bypassed by different code paths, refactoring, or mocks.

**Core principle:** Validate at EVERY layer data passes through. Make the bug structurally impossible.

## The Four Layers

### Layer 1: Entry Point Validation
Reject obviously invalid input at API boundary.

### Layer 2: Business Logic Validation
Ensure data makes sense for this operation.

### Layer 3: Environment Guards
Prevent dangerous operations in specific contexts (e.g., refuse destructive ops outside temp dirs in tests).

### Layer 4: Debug Instrumentation
Capture context for forensics (stack traces, state snapshots before dangerous operations).

## Applying the Pattern

When you find a bug:

1. **Trace the data flow** - Where does bad value originate? Where is it used?
2. **Map all checkpoints** - List every point data passes through
3. **Add validation at each layer** - Entry, business, environment, debug
4. **Test each layer** - Try to bypass layer 1, verify layer 2 catches it

**Don't stop at one validation point.** Add checks at every layer.
