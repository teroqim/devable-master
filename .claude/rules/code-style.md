---
paths:
  - "src/**/*.ts"
  - "src/**/*.tsx"
  - "tests/**/*.ts"
---

# Code Style

## File Naming

When a service, class, or component is named `X`:

- **Main file**: `X.ts` (or `X.tsx` for React components)
- **Utils only used by X**: `X.utils.ts`
- **Constants only used by X**: `X.constants.ts`
- **Types only used by X**: `X.types.ts`

These companion files live in the same folder as the main file. Only use this pattern for things scoped to a single file -- shared utils/types/constants that are used across multiple files should live elsewhere.

## Type Definitions

Always put interfaces and type aliases in the dedicated types file (`types.ts` or `X.types.ts`), not inline in implementation files. This applies even for small types or type aliases. Only skip this if there's a compelling reason (e.g., a type that is truly private to a single function and never used elsewhere).

## Error Handling

Use focused try-catch blocks around the specific calls that can throw (database calls, API calls, file system operations, etc.). Keep the error handling close to where the error can occur.

- If a function's sole purpose is to call something that can throw, wrapping the entire body is fine (e.g. a thin service method that just calls a DB query).
- If a function has other logic beyond the throwable call, wrap only the throwable part -- not the entire body.

Use result objects (`{ success: true, ... } | { success: false, error }`) for service method return types.

Never use silent catch blocks (empty `catch {}` or `catch` that does nothing). Always at minimum log the error, and prefer returning an error response or re-throwing. A catch block should make it clear what went wrong and why it was handled there.

Do not create fire-and-forget helper functions that wrap DB calls or other throwable operations and silently handle errors. Keep try-catch blocks visible at the call site so error handling is explicit and reviewable. If you think a fire-and-forget pattern is genuinely needed, check with the user first.

## Async Function Naming

Functions that return a `Promise` (i.e., `async` functions or functions that use `await`) must have the `Async` postfix:

```typescript
// DO
async function fetchProjectAsync(id: string): Promise<Project> { ... }
async function createSessionAsync(data: SessionData): Promise<Session> { ... }

// DON'T
async function fetchProject(id: string): Promise<Project> { ... }
async function createSession(data: SessionData): Promise<Session> { ... }
```

This makes it immediately clear at the call site that the function is asynchronous and returns a promise.

## Loops

Do not use `for...of` loops. Use `forEach` or a regular `for` loop instead.
