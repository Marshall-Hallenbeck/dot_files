---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---

# Web Development Conventions

These rules apply when working with JavaScript/TypeScript projects.

## Imports & Exports

- **Prefer named exports** over default exports
- **Never use barrel imports** (`index.ts` re-exports). Import directly from source files.
  - Bad: `import { MyComponent } from "./components"`
  - Good: `import { MyComponent } from "./components/MyComponent"`

## File & Directory Naming

- Use **kebab-case** for directories (e.g., `user-profile/`)
- Use **PascalCase** for component files (e.g., `UserProfile.tsx`)
- Use **camelCase** for utility files (e.g., `formatDate.ts`)

## React 19 / Next.js 15

- Prefer **React Server Components** — minimize client components
- Client components require explicit `'use client'` directive
- Use App Router patterns with `page.tsx` files in route directories
- Use `Suspense` for async operations and proper error boundaries
- Use `useActionState` instead of deprecated `useFormState`
- Leverage enhanced `useFormStatus` with new properties (`data`, `method`, `action`)
- For URL state management, prefer `nuqs` or similar URL search param libraries over `useState`

### Async Runtime APIs (Next.js 15)

These are no longer synchronous — always `await` them:

```typescript
const cookieStore = await cookies();
const headersList = await headers();
const { isEnabled } = await draftMode();
const params = await props.params;
const searchParams = await props.searchParams;
```

## TypeScript

- Prefer `interface` for object shapes, `type` for unions/intersections
- Use strict TypeScript — avoid `any` unless absolutely necessary
- Prefer `unknown` over `any` for truly unknown types
- Avoid enums — use `const` maps or union types instead
- Use the `satisfies` operator for type validation where appropriate
- Use early returns for readability

## CSS

- Prefer CSS Modules (`.module.css`) for component-scoped styles
- Use CSS custom properties (variables) for theming
- Avoid inline styles except for truly dynamic values
