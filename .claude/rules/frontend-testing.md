# Frontend Testing Requirements

## Component Tests

Every new React (or other framework) component must have:

1. **Render test** — component renders without crashing with required props
2. **Interaction tests** — for components with user interactions:
   - Button clicks and their effects
   - Form submissions and validation
   - Keyboard navigation (Enter, Escape, Tab)
   - Toggle/expand/collapse behavior
3. **Conditional rendering** — test each branch of conditional UI (loading states, empty states, error states, permission-gated content)
4. **Props/state variations** — test with different prop combinations that produce different output

## Custom Hooks

Every new custom hook must have:

1. **State change tests** — verify state transitions with `renderHook`
2. **Effect tests** — verify side effects fire correctly
3. **Cleanup tests** — verify cleanup runs on unmount
4. **Error states** — verify error handling behavior

## User-Centric Testing

- Prefer semantic queries: `getByRole`, `getByLabelText`, `getByText` over `getByTestId`
- Test what users see and do, not internal implementation
- Use `userEvent` over `fireEvent` for realistic interactions

## E2E Tests

Create E2E tests (Playwright/Cypress) when:

- A feature involves multi-step user workflows (form wizard, checkout flow)
- Navigation between pages is part of the feature
- The feature integrates with external APIs visible to the user
- Authentication/authorization flows are involved

## What Doesn't Need Frontend Tests

- Pure CSS/styling changes (unless conditional rendering is involved)
- Type definitions and interfaces
- Static content with no logic
- Third-party component library wrappers with no custom logic
