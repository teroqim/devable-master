---
paths:
  - "prisma/**"
---

# Database & Prisma Rules

## Field Ordering

Within each model, fields must be ordered as follows:

1. **ID fields** -- `id` or compound ID fields
2. **Data fields** -- all other scalar fields (strings, ints, dates, etc.)
3. **Relation fields** -- references to other models (e.g. `project Project @relation(...)`)
4. **Block-level attributes** -- `@@map`, `@@index`, etc.

## Required Fields

All tables must have `createdAt` and `updatedAt` timestamp fields:

```prisma
createdAt DateTime @default(now())
updatedAt DateTime @updatedAt
```

## Schema Design

- **No derived data**: Don't store values that can be computed from other stored fields at runtime (e.g. file paths derivable from userId + projectId, preview URLs derivable from slug).
- **No one-time inputs**: Don't store values that are only used as inputs to a one-time process (e.g. template and design theme used only during scaffolding).
- **Before adding a DB column**, ask:
  - "Can this be computed from other stored data?" If yes, compute it in the service layer.
  - "Will this be read again after the initial process?" If no, pass it as a function parameter instead.
