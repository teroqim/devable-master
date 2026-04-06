---
paths:
  - "src/**/*.ts"
  - "src/**/*.tsx"
  - "tests/**/*.ts"
---

# Error Handling

## Focused try-catch

Only wrap the specific operation that can throw. Do not wrap entire function bodies or multiple unrelated operations.

```typescript
// DO - wrap only the throwable call
async function getProjectAsync(id: string) {
  const validated = validateId(id); // pure logic, won't throw

  let project;
  try {
    project = await db.projects.findByIdAsync(id); // DB call can throw
  } catch (error) {
    return { success: false, error: 'Failed to fetch project' };
  }

  return { success: true, project };
}

// DON'T - wrapping everything hides which operation failed
async function getProjectAsync(id: string) {
  try {
    const validated = validateId(id);
    const project = await db.projects.findByIdAsync(id);
    return { success: true, project };
  } catch (error) {
    return { success: false, error: 'Something failed' };
  }
}
```

## Exception: thin wrappers

If a function's sole purpose is a single throwable call, wrapping the entire body is fine:

```typescript
// OK - the whole point of this function is the DB call
async function deleteAsync(id: string) {
  try {
    await db.projects.deleteAsync(id);
    return { success: true };
  } catch (error) {
    return { success: false, error: 'Failed to delete' };
  }
}
```

## Review generated code for throwable operations

After writing code, always review it to identify operations that can throw and ensure they have appropriate error handling. Common throwable operations:

- **Process spawning**: `Bun.spawn()`, `child_process.exec()` — executable not found, permission denied
- **File I/O**: `file.text()`, `file.exists()`, `Bun.write()`, `fs.readFile()` — permission denied, disk full
- **Network calls**: `fetch()`, database queries, API calls — connection refused, timeout
- **JSON parsing**: `JSON.parse()` — malformed input
- **Docker operations**: container not running, image not found

Do not assume these will succeed. Wrap each throwable call individually so the error message clearly identifies which operation failed.
