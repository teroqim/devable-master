# Phase 2: Project Templates & Design System -- Detailed Plan

> **Status**: Completed
> **Created**: 2026-04-03
> **Parent plan**: `2026-03-28-20-30-devable-grand-plan.md`
>
> **Note**: The sections below represent the original plan as approved before implementation. The following changes were discovered or decided during implementation:
>
> - **Fullstack template needs 3 ports, not 2**: Frontend + backend + DB each need separate host ports. Added `backendPort` to scaffold options and a third `allocatePortAsync` call.
> - **Port allocation collision**: Two sequential `allocatePortAsync` calls returned the same port. Fixed by adding `excludePorts` parameter to `DockerService.allocatePortAsync`.
> - **Caddy fixes**: Server explicitly named `devable` in Caddyfile (was auto-generated `srv0`). Added `auto_https off` to prevent `.localhost` HTTPS interception.
> - **TemplateEngine location**: Moved from `src/lib/` to `src/services/project-file-service/` since it's only used by ProjectFileService.
> - **Bun-native file I/O**: Used `Bun.file().text()` / `Bun.write()` instead of `node:fs/promises` for file read/write.
> - **Repo reorganization**: Scripts, Caddy config, templates, and design themes moved into `src/` folder in devable-master root.

---

## Context

Phase 1 delivered the project data model, API routes, services (ProjectService, ProjectFileService, DockerService, CaddyService), frontend dashboard with create/delete/start/stop UI, and dev lifecycle scripts. However:

1. **The create/delete flow is incomplete** -- `ProjectService.createProjectAsync()` only creates a DB record (TODO at line 54). It does NOT scaffold files, start Docker, or register Caddy routes. Same for delete (TODO at line 154).
2. **Templates are hardcoded** -- `ProjectFileService.templates.ts` generates only Next.js content via string functions. No variation by template type.
3. **Template/theme pickers exist in the UI** but the values are logged and ignored by the backend.

Phase 2 addresses all of this: wire the full create/delete orchestration, replace hardcoded templates with disk-based templates, create three real project templates, and add design themes.

---

## Design Decisions

### 1. Templating approach: Disk-based with simple `{{VARIABLE}}` substitution

- Template files live on disk with `.tmpl` extension
- A lightweight `TemplateEngine` replaces `{{KEY}}` placeholders with values
- No new dependency needed (no Handlebars/EJS)
- Variables: `PROJECT_NAME`, `APP_PORT`, `DB_PORT`, `DB_PASSWORD`, `BACKEND_URL`

### 2. Template location: `templates/` in devable-master root

Matches the grand plan directory structure. Backend accesses via `TEMPLATES_ROOT` env var.

```text
devable-master/
├── templates/
│   ├── nextjs-ts/
│   │   ├── template.json            # manifest (metadata, file list)
│   │   ├── Dockerfile.tmpl
│   │   ├── docker-compose.yml.tmpl  # app only, NO postgres
│   │   ├── package.json.tmpl
│   │   ├── tsconfig.json
│   │   ├── eslint.config.mjs        # flat config (ESLint v9+)
│   │   ├── .prettierrc.json
│   │   ├── next.config.ts
│   │   ├── src/app/layout.tsx.tmpl
│   │   ├── src/app/page.tsx.tmpl
│   │   ├── src/app/globals.css      # default theme (overridden by design theme)
│   │   ├── CLAUDE.md.tmpl
│   │   └── .env.tmpl
│   ├── bun-elysia-api/
│   │   ├── template.json
│   │   ├── Dockerfile.tmpl
│   │   ├── docker-compose.yml.tmpl  # app + postgres (always)
│   │   ├── package.json.tmpl
│   │   ├── tsconfig.json
│   │   ├── eslint.config.mjs
│   │   ├── .prettierrc.json
│   │   ├── src/index.ts.tmpl
│   │   ├── src/routes/health.ts
│   │   ├── prisma/schema.prisma.tmpl
│   │   ├── CLAUDE.md.tmpl
│   │   └── .env.tmpl
│   └── fullstack/
│       ├── template.json
│       ├── docker-compose.yml.tmpl  # frontend + backend + postgres
│       ├── frontend/               # Next.js files (independent dir)
│       │   ├── Dockerfile.tmpl
│       │   ├── package.json.tmpl
│       │   ├── tsconfig.json
│       │   ├── eslint.config.mjs
│       │   ├── .prettierrc.json
│       │   ├── next.config.ts
│       │   ├── src/app/layout.tsx.tmpl
│       │   ├── src/app/page.tsx.tmpl
│       │   ├── src/app/globals.css
│       │   └── src/lib/api-client.ts.tmpl
│       ├── backend/                # Elysia files (independent dir)
│       │   ├── Dockerfile.tmpl
│       │   ├── package.json.tmpl
│       │   ├── tsconfig.json
│       │   ├── eslint.config.mjs
│       │   ├── .prettierrc.json
│       │   ├── src/index.ts.tmpl
│       │   └── prisma/schema.prisma.tmpl
│       ├── shared/types/index.ts
│       ├── CLAUDE.md.tmpl
│       └── .env.tmpl
├── design-themes/
│   ├── clean.css                    # neutral, subtle shadows, system fonts
│   ├── bold.css                     # vibrant, high contrast, large type
│   └── soft.css                     # pastels, rounded, gentle gradients
```

### 3. No conditional DB logic -- each template has exactly one docker-compose

- **nextjs-ts**: App container only. No database. If the AI agent later needs a DB, it modifies the project's docker-compose.yml itself.
- **bun-elysia-api**: App + postgres. An API naturally needs a DB.
- **fullstack**: Frontend + backend + postgres.

### 4. Design theme injection

Each theme CSS includes `:root` and `.dark` custom properties plus base component styles (buttons, inputs, cards, layout). During scaffolding, if a design theme is selected and the template has frontend files (`hasFrontend: true`), the theme CSS replaces the template's default `globals.css`. Default: "clean" theme when no theme is selected. Themes are ignored for API-only templates.

### 5. On partial failure: keep record with 'error' status

If create fails mid-way, keep the DB record and files but set project status to `"error"`. User can see what happened in the dashboard and retry or delete.

### 6. Fullstack layout: flat with shared compose

Independent `frontend/` and `backend/` directories sharing a root `docker-compose.yml`. No monorepo workspaces.

### 7. Config file conventions (matching existing repos)

- ESLint: `eslint.config.mjs` (flat config, ESLint v9+)
- Prettier: `.prettierrc.json`

### 8. Template manifest schema

```typescript
interface TemplateManifest {
  name: string;              // "Next.js + TypeScript"
  description: string;
  runtime: 'node' | 'bun';
  needsDatabase: boolean;
  hasFrontend: boolean;      // whether design themes apply
  internalPort: number;      // port app listens on inside container
  directories: string[];     // dirs to create
  files: Array<{
    source: string;          // path in template dir
    destination: string;     // path in output project
    template: boolean;       // whether to run through TemplateEngine
  }>;
}
```

---

## Step-by-Step Implementation

### Step 0: Wire the create/delete flow in ProjectService

**Why**: Prerequisite for all template work. Can't test templates end-to-end without this.

**Files to modify (backend):**

- `src/services/project-service/ProjectService.ts` -- Add `DockerService` and `CaddyService` as optional constructor params. Implement full create orchestration and full delete teardown.
- `src/lib/RunContext.ts` -- Pass `dockerService` and `caddyService` to ProjectService.
- `tests/services/project-service/constants.ts` -- Add mock factories for DockerService and CaddyService.
- `tests/services/project-service/ProjectService.createProjectAsync.test.ts` -- Test full orchestration.
- `tests/services/project-service/ProjectService.deleteProjectAsync.test.ts` -- Test full teardown.

**Create flow:**

1. Resolve unique slug (existing)
2. Create DB record with status='created' (existing)
3. Allocate app port via `dockerService.allocatePortAsync()`
4. Optionally allocate DB port (if template manifest says `needsDatabase`)
5. Scaffold files via `projectFileService.scaffoldProjectAsync(...)`
6. Start containers via `dockerService.startProjectAsync(projectDir)`
7. Register Caddy route via `caddyService.addRouteAsync(slug, appPort)`
8. Create `ProjectContainer` record(s) in DB
9. Update project status to `'running'`
10. Return project with containers

**Delete flow:**

1. Verify ownership (existing)
2. Look up project file path and slug
3. Stop containers via `dockerService.stopProjectAsync(projectDir)`
4. Remove Caddy route via `caddyService.removeRouteAsync(slug)`
5. Delete files via `projectFileService.deleteProjectFilesAsync(userId, projectId)`
6. Delete DB record (cascade deletes containers + sessions)

**On failure**: Set status to `'error'`, log the step that failed, return error.

---

### Step 1: Create TemplateEngine utility

**Files to create (backend):**

- `src/lib/TemplateEngine.ts` -- `render(template, variables)` replaces `{{KEY}}` with values. `renderFileAsync(filePath, variables)` reads + renders.
- `src/lib/TemplateEngine.types.ts` -- `TemplateVariables`, `TemplateManifest` interfaces.
- `tests/lib/TemplateEngine.test.ts` -- Variable substitution, missing variables (left as-is), edge cases.

---

### Step 2: Create Next.js + TypeScript template (on disk)

**Files to create:** All files under `templates/nextjs-ts/`.

Key details:

- Dockerfile: Node 22 alpine, npm install, hot reload via volume mount
- docker-compose.yml: App container only, NO postgres
- package.json: Next.js 16, React 19, TypeScript
- eslint.config.mjs + .prettierrc.json
- Full `src/app` structure with layout.tsx and page.tsx
- tsconfig.json with path aliases
- CLAUDE.md with Next.js coding conventions

---

### Step 3: Create Bun + Elysia API template (on disk)

**Files to create:** All files under `templates/bun-elysia-api/`.

Key details:

- Dockerfile: `oven/bun:latest`, bun install
- docker-compose.yml: App + postgres (always)
- Prisma schema with basic setup
- Minimal Elysia server with health route
- eslint.config.mjs + .prettierrc.json
- CLAUDE.md with Elysia/Bun conventions

---

### Step 4: Create fullstack template (on disk)

**Files to create:** All files under `templates/fullstack/`.

Key details:

- docker-compose.yml: 3 services -- frontend (Next.js), backend (Elysia), postgres
- `frontend/` and `backend/` as independent directories (flat, no workspaces)
- Frontend has API client calling backend via `{{BACKEND_URL}}`
- `shared/types/index.ts` for shared TypeScript types
- Each sub-project has its own eslint.config.mjs + .prettierrc.json
- CLAUDE.md covering both frontend and backend

---

### Step 5: Create design theme CSS files

**Files to create:**

- `design-themes/clean.css` -- Neutral grays, subtle shadows, system fonts, light + dark mode
- `design-themes/bold.css` -- Vibrant colors, high contrast, large type, light + dark mode
- `design-themes/soft.css` -- Pastels, rounded, gentle gradients, light + dark mode

Each file includes:

- `:root` + `.dark` blocks with CSS custom properties (colors, spacing, borders, shadows, typography)
- Base component styles (buttons, inputs, cards, layout) using the custom properties

Also create SVG thumbnails for the frontend theme picker:

- `apps/devable-frontend/public/theme-previews/clean.svg`
- `apps/devable-frontend/public/theme-previews/bold.svg`
- `apps/devable-frontend/public/theme-previews/soft.svg`

---

### Step 6: Refactor ProjectFileService to use TemplateEngine + disk templates

**Files to modify (backend):**

- `src/services/project-file-service/ProjectFileService.ts` -- Rewrite `scaffoldProjectAsync` to read manifest, copy/render template files via TemplateEngine, apply design theme CSS.
- `src/lib/Env.ts` -- Add `TEMPLATES_ROOT` and `DESIGN_THEMES_ROOT` env vars.

**Delete:**

- `src/services/project-file-service/ProjectFileService.templates.ts` -- Replaced by disk templates.

**New signature:**

```typescript
async scaffoldProjectAsync(
  userId: string,
  projectId: string,
  projectName: string,
  appPort: number,
  options?: {
    template?: string;      // defaults to 'nextjs-ts'
    designTheme?: string;   // defaults to 'clean'
    dbPort?: number;
    dbPassword?: string;
  },
): Promise<{ success: true } | { success: false; error: string }>
```

**Update tests:** `tests/services/project-file-service/ProjectFileService.test.ts` -- Test each template type, theme application, default fallbacks.

---

### Step 7: Wire template params through ProjectService

**Files to modify (backend):**

- `src/services/project-service/ProjectService.ts` -- Read template manifest to determine if DB is needed, pass template/designTheme to scaffoldProjectAsync, allocate correct ports based on manifest.

This step integrates Step 0 (wiring) with Step 6 (template-aware scaffolding).

---

### Step 8: Move root scripts into `scripts/` folder, add descriptions, update README

**Why**: Housekeeping -- the root is getting cluttered. Group scripts, document their purpose, and keep the README current.

**Scripts to move (devable-master root -> `scripts/`):**

- `setup.sh` -> `scripts/setup.sh`
- `dev-start.sh` -> `scripts/dev-start.sh`
- `dev-stop.sh` -> `scripts/dev-stop.sh`

**Changes per script:**

- Add a header comment block describing: purpose, when to run it, what it starts/stops/requires

**Update references:**

- `README.md` -- Add a "Scripts" section documenting each script's purpose and usage
- `CLAUDE.md` -- Update any references to script paths (e.g. `./dev-start.sh` -> `./scripts/dev-start.sh`)
- Any other files referencing the old paths

**New rule:** Add a rule to `.claude/rules/` (root, applies to all repos) that READMEs must be kept up to date when changes affect setup, commands, architecture, or developer workflows.

No dependencies on other steps -- can be done at any point.

---

### Step 9: Enhance frontend CreateProjectDialog with theme previews

**Files to modify (frontend):**

- `src/components/CreateProjectDialog/CreateProjectDialog.tsx` -- Replace select dropdowns with visual cards showing template descriptions and theme color preview thumbnails.
- `src/components/CreateProjectDialog/CreateProjectDialog.css` -- Card grid layout for pickers.
- `src/components/CreateProjectDialog/CreateProjectDialog.test.tsx` -- Update tests for new card-based UI.

---

## Implementation Order

```text
Step 0 (Wire create/delete)  ─────────────────────────────┐
                                                           │
Step 1 (TemplateEngine)                                    │
  │                                                        │
  ├── Step 2 (nextjs-ts template)      ┐                   │
  ├── Step 3 (bun-elysia-api template) ├── parallel        │
  ├── Step 4 (fullstack template)      │                   │
  └── Step 5 (design themes)           ┘                   │
       │                                                   │
Step 6 (Refactor ProjectFileService) ──── depends on 1-5   │
       │                                                   │
Step 7 (Wire template params) ──────── depends on 0 + 6  ─┘
       │
Step 8 (Move scripts + README) ──── independent, any time
       │
Step 9 (Frontend UI) ──────── can parallel with 6-7
```

---

## Testing Strategy

- **Unit tests**: TemplateEngine, ProjectService orchestration (mocked deps)
- **Integration tests**: ProjectFileService with real template files + temp dirs
- **Manual E2E**: Create project with each template -> verify files on disk -> verify containers start -> verify Caddy routing -> verify preview works -> delete project -> verify cleanup
- **Theme tests**: Scaffold with each theme -> verify CSS variables in output

---

## Verification

1. Run backend tests: `cd apps/devable-backend && bun test`
2. Run frontend tests: `cd apps/devable-frontend && npm test`
3. Start infrastructure: `./dev-start.sh`
4. Start backend: `cd apps/devable-backend && bun dev`
5. Start frontend: `cd apps/devable-frontend && npm run dev`
6. Create project with each template type and verify:
   - Files scaffolded correctly on disk
   - Docker containers start
   - Caddy routes registered
   - Preview accessible at `{slug}.localhost:8888`
7. Delete project and verify cleanup
8. Lint + typecheck both repos
