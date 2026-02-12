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

## React / Next.js

- Prefer **React Server Components** — minimize client components
- Client components require explicit `'use client'` directive
- Use App Router patterns with `page.tsx` files in route directories
- For URL state management, prefer `nuqs` or similar URL search param libraries over `useState`

## TypeScript

- Prefer `interface` for object shapes, `type` for unions/intersections
- Use strict TypeScript — avoid `any` unless absolutely necessary
- Prefer `unknown` over `any` for truly unknown types

## CSS

- Prefer CSS Modules (`.module.css`) for component-scoped styles
- Use CSS custom properties (variables) for theming
- Avoid inline styles except for truly dynamic values
