# Phase 1: Foundation & Infrastructure -- Detailed Plan

> **Status**: Completed
> **Created**: 2026-03-29
> **Parent plan**: `2026-03-28-20-30-devable-grand-plan.md`

---

## Context & Current State

### What already exists

**Backend (`apps/devable-backend`):**

- Bun + Elysia + Prisma + PostgreSQL stack is running
- Clerk JWT auth middleware is wired up
- DI pattern via `RunContext` (singleton container -> DB -> Repositories -> Services)
- Repository pattern (`DB` facade -> `AnnouncementRepository`)
- Structured logging (tslog), OpenAPI docs, CORS
- One model: `Announcement` (id, title, content, timestamps)
- One authenticated route: `GET /v1/announcements`
- Graceful shutdown handlers for Prisma

**Frontend (`apps/devable-frontend`):**

- Next.js 16 + TypeScript + Clerk auth
- Landing page (`/`) and dashboard (`/dashboard`) with announcements list
- API proxy layer (`/api/announcements` -> backend)
- Sidebar (`Navbar`), `Header` with `UserButton`, `DashboardLayoutWrapper`
- Reusable `Button` component (CVA variants)
- Plain CSS with CSS variables (no Tailwind), Radix UI primitives
- `api-client.ts` typed fetch helper, `env.ts` validation

### What Phase 1 delivers

By the end of Phase 1, a user can:

1. See a dashboard listing their projects with status indicators
2. Create a new project (name, optional template, optional design theme)
3. Delete a project (stops containers, cleans up files)
4. Have project files scaffolded on disk in `user-projects/{userId}/{projectId}/`
5. Have project containers started/stopped via Docker Compose
6. Access a running project via `{slug}.localhost:8080` through Caddy

---

## Step-by-step Implementation

### Step 1: Prisma Schema & Migrations (backend)

**Files to modify:**

- `prisma/schema.prisma` -- add new models

**Models to add:**

```prisma
model Project {
  id        String   @id @default(uuid())
  name      String   @db.VarChar(255)
  slug      String   @unique @db.VarChar(255)
  userId    String   @db.VarChar(255)
  status    String   @default("created") @db.VarChar(50)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  containers   ProjectContainer[]
  chatSessions ChatSession[]

  @@map("projects")
}

model ProjectContainer {
  id          String   @id @default(uuid())
  projectId   String
  name        String   @db.VarChar(100)
  containerId String?  @db.VarChar(100)
  type        String   @db.VarChar(50)
  status      String   @default("stopped") @db.VarChar(50)
  port        Int?
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt

  project Project @relation(fields: [projectId], references: [id], onDelete: Cascade)

  @@map("project_containers")
}

model ChatSession {
  id           String   @id @default(uuid())
  projectId    String
  sessionName  String   @db.VarChar(255)
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt
  lastActiveAt DateTime @default(now())

  project Project @relation(fields: [projectId], references: [id], onDelete: Cascade)

  @@map("chat_sessions")
}
```

**Design decisions:**

- Field ordering follows project convention: ID -> data fields -> relations -> @@map
- All tables have `createdAt` and `updatedAt` (project rule)
- `status` is a string (not Prisma enum) for flexibility
- `onDelete: Cascade` ensures containers/sessions are cleaned up when project is deleted
- `ChatSession` included now to avoid a future migration, but not used until Phase 3 (repository deferred to Phase 3)
- `template` and `designTheme` NOT stored -- one-time inputs to scaffolding process
- `filePath` NOT stored -- derived at runtime as `{PROJECTS_ROOT}/{userId}/{projectId}/`
- `previewUrl` NOT stored -- derived at runtime as `{slug}.localhost:8080`
- Port is only on `ProjectContainer`, not on `Project` -- the port belongs to a specific container. For Caddy routing, we look up the container where `type = "app"` to get its port.
- Slug uniqueness: handled by retry logic with incremental suffix (see Step 2)

**Port mapping note:** For the POC, Caddy routes `{slug}.localhost:8080` to the single `type = "app"` container's port. In the future, a project may have multiple publicly routable containers (webapp, API, admin, etc.) -- see grand plan future section. The `ProjectContainer.port` field already supports this: each container has its own port, and multiple Caddy routes can be added per project.

**Tasks:**

- [ ] Add models to `prisma/schema.prisma`
- [ ] Create migration
- [ ] Verify migration applies cleanly

---

### Step 2: Repository & Service Layer (backend)

**New files:**

- `src/db/ProjectRepository.ts`
- `src/db/ProjectContainerRepository.ts`
- `src/services/project-service/ProjectService.ts`

**Modify:**

- `src/db/DB.ts` -- add project and container repositories
- `src/lib/RunContext.ts` -- wire up ProjectService

**ProjectRepository methods:**

- `createAsync(data)` -- create project record
- `findByIdAsync(id)` -- get project by ID (include containers)
- `findByUserIdAsync(userId)` -- list user's projects
- `findBySlugAsync(slug)` -- lookup by slug (for uniqueness check)
- `updateAsync(id, data)` -- update project fields
- `deleteAsync(id)` -- delete project (cascade handles relations)

**ProjectContainerRepository methods:**

- `createAsync(data)` -- create container record
- `updateAsync(id, data)` -- update container status/containerId
- `findByProjectIdAsync(projectId)` -- list containers for a project
- `deleteByProjectIdAsync(projectId)` -- remove all containers for a project

**ProjectService methods:**

- `createProjectAsync(userId, name, template?, designTheme?)` -- orchestrates: generate slug, create DB record, scaffold files (using template/theme params), generate docker-compose, start containers, register Caddy route. Template and theme are passed through to the file service but not persisted.
- `listProjectsAsync(userId)` -- return user's projects
- `getProjectAsync(id, userId)` -- return project with containers (verify ownership)
- `updateProjectAsync(id, userId, data)` -- update project metadata
- `deleteProjectAsync(id, userId)` -- stop containers, remove Caddy route, delete files, delete DB record
- `getProjectStatusAsync(id, userId)` -- get container stats & status

**Derived paths (service-level helpers, not stored in DB):**

- `getProjectFilePath(userId, projectId)` -- returns `{PROJECTS_ROOT}/{userId}/{projectId}/`
- `getPreviewUrl(slug)` -- returns `{slug}.localhost:8080`
- `getAppContainerPort(project)` -- looks up the `type = "app"` container's port for Caddy routing

**Slug generation:**

- Derive from project name: lowercase, replace spaces/special chars with hyphens, trim
- On conflict: append `-2`, `-3`, etc. and retry until unique
- The slug is user-visible in the preview URL, so keep it readable

**Tasks:**

- [ ] Create `ProjectRepository.ts`
- [ ] Create `ProjectContainerRepository.ts`
- [ ] Update `DB.ts` to include new repositories
- [ ] Create `ProjectService.ts` with slug generation + retry logic
- [ ] Update `RunContext.ts` to wire ProjectService
- [ ] Write tests for ProjectService (mock repositories)
- [ ] Write tests for slug generation (including collision handling)

---

### Step 3: Project File Management Service (backend)

**New files:**

- `src/services/project-file-service/ProjectFileService.ts`

**Responsibilities:**

- Scaffold project directory at `{PROJECTS_ROOT}/{userId}/{projectId}/`
- Copy template files into the directory (minimal placeholder for Phase 1 -- full templates in Phase 2)
- Generate `docker-compose.yml` based on template type
- Generate `Dockerfile` for the app container
- Generate project `CLAUDE.md` (base agent instructions)
- Manage `.env` file (create with defaults, read, write)

**Environment:**

- New env var: `PROJECTS_ROOT` -- absolute path to `user-projects/` directory
- Add to `Env.ts` singleton

**docker-compose.yml generation (minimal for Phase 1):**

Base config (always present):

```yaml
services:
  app:
    build: .
    ports:
      - "{assignedAppPort}:3000"
    volumes:
      - ./src:/app/src
    environment:
      - NODE_ENV=development
    restart: unless-stopped
```

Optional postgres service (only added when the project needs a database):

```yaml
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ./.docker/pgdata:/var/lib/postgresql/data
    ports:
      - "{assignedDbPort}:5432"
```

**Dockerfile (minimal Next.js for Phase 1):**

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]
```

**Tasks:**

- [ ] Add `PROJECTS_ROOT` to `Env.ts`
- [ ] Create `ProjectFileService.ts`
- [ ] Implement `scaffoldProjectAsync(userId, projectId, template?)`
- [ ] Implement `generateDockerComposeAsync(projectId, template, appPort, dbPort)`
- [ ] Implement `generateDockerfileAsync(projectId, template)`
- [ ] Implement `generateClaudeMdAsync(projectId, projectName, template)`
- [ ] Implement `createEnvFileAsync(projectId, vars)`
- [ ] Implement `deleteProjectFilesAsync(userId, projectId)`
- [ ] Wire into `RunContext.ts`
- [ ] Write tests for file service

---

### Step 4: Docker Orchestration Service (backend)

**New files:**

- `src/services/docker-service/DockerService.ts`
- `src/services/docker-service/port-manager.ts`

**Approach:** Shell out to `docker compose` CLI via `Bun.spawn()` (simpler than Docker API for POC). Working directory for each command is the project's derived file path.

**DockerService methods:**

- `startProjectAsync(filePath)` -- `docker compose up -d --build`
- `stopProjectAsync(filePath)` -- `docker compose down`
- `restartProjectAsync(filePath)` -- `docker compose restart`
- `getContainerStatsAsync(filePath)` -- `docker compose ps --format json` + `docker stats --no-stream --format json`
- `execInContainerAsync(filePath, service, command)` -- `docker compose exec {service} {command}`
- `getLogsAsync(filePath, service?, lines?)` -- `docker compose logs --tail {lines}`
- `isRunningAsync(filePath)` -- check if containers are up

**Port Manager:**

- Allocates host ports for project containers, stored in `ProjectContainer.port`
- `allocatePortAsync()` -- find next available port starting from base (e.g. 10000), check DB for conflicts and verify port is free on host
- `releasePortAsync(port)` -- relies on DB record deletion

**Tasks:**

- [ ] Create `DockerService.ts`
- [ ] Create `port-manager.ts`
- [ ] Implement all DockerService methods
- [ ] Wire into `RunContext.ts`
- [ ] Write tests (mock `Bun.spawn`)

---

### Step 5: Caddy Reverse Proxy (repo root)

**New files (in `devable-master/caddy/`):**

- `caddy/docker-compose.yml`
- `caddy/Caddyfile`

**New service in backend:**

- `src/services/caddy-service/CaddyService.ts`

**Caddy setup:**

```yaml
# caddy/docker-compose.yml
services:
  caddy:
    image: caddy:2-alpine
    ports:
      - "8080:8080"
      - "2019:2019"   # Admin API
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped

volumes:
  caddy_data:
```

```caddyfile
# caddy/Caddyfile
{
  admin :2019
}

:8080 {
  respond "Devable: no project found at this address" 404
}
```

**CaddyService methods (uses Caddy Admin API at `http://localhost:2019`):**

- `addRouteAsync(slug, targetPort)` -- add route: `{slug}.localhost:8080` -> `host.docker.internal:{targetPort}`
- `removeRouteAsync(slug)` -- remove route from Caddy config
- `listRoutesAsync()` -- get current routes (for debugging)

**Note:** For the POC, only the `type = "app"` container gets a Caddy route. The port is looked up from `ProjectContainer` at routing time.

**Tasks:**

- [ ] Create `caddy/docker-compose.yml`
- [ ] Create `caddy/Caddyfile`
- [ ] Create `CaddyService.ts`
- [ ] Wire into `RunContext.ts`
- [ ] Test: start Caddy, add a route, verify subdomain routing works
- [ ] Add instructions to README for starting Caddy

---

### Step 6: API Routes (backend)

**New files:**

- `src/routes/project-routes.ts`

**Modify:**

- `src/routes.ts` -- register project routes

**Endpoints:**

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `POST` | `/v1/projects` | Create project | Yes |
| `GET` | `/v1/projects` | List user's projects | Yes |
| `GET` | `/v1/projects/:id` | Get project details + containers | Yes |
| `PUT` | `/v1/projects/:id` | Update project metadata | Yes |
| `DELETE` | `/v1/projects/:id` | Delete project (full cleanup) | Yes |
| `GET` | `/v1/projects/:id/status` | Container status & resource stats | Yes |
| `POST` | `/v1/projects/:id/start` | Start project containers | Yes |
| `POST` | `/v1/projects/:id/stop` | Stop project containers | Yes |
| `POST` | `/v1/projects/:id/restart` | Restart project containers | Yes |

**Request/response schemas (TypeBox, matching existing pattern):**

- `CreateProjectBody`: `{ name: string, template?: string, designTheme?: string }`
- `ProjectResponse`: project object with containers, plus derived `previewUrl`
- `ProjectListResponse`: array of projects (without containers for perf)
- `ProjectStatusResponse`: `{ status, containers: [{ name, status, cpu, memory }] }`

Note: `template` and `designTheme` are accepted in the create request body but only passed through to the file service, not stored.

**Tasks:**

- [ ] Create TypeBox schemas in `src/lib/api-schemas.ts` (extend existing)
- [ ] Create `src/routes/project-routes.ts`
- [ ] Register in `src/routes.ts`
- [ ] Write integration tests for each endpoint

---

### Step 7: Frontend -- API Layer & Types

**New/modified files in `apps/devable-frontend`:**

- `src/types/api.ts` -- add project types
- `src/app/api/projects/route.ts` -- proxy to backend
- `src/app/api/projects/[id]/route.ts` -- proxy for single project
- `src/app/api/projects/[id]/start/route.ts` -- proxy start
- `src/app/api/projects/[id]/stop/route.ts` -- proxy stop
- `src/app/api/projects/[id]/restart/route.ts` -- proxy restart
- `src/app/api/projects/[id]/status/route.ts` -- proxy status

**Types to add:**

```typescript
interface Project {
  id: string;
  name: string;
  slug: string;
  userId: string;
  status: "created" | "starting" | "running" | "stopped" | "error";
  previewUrl: string;
  createdAt: string;
  updatedAt: string;
  containers?: ProjectContainer[];
}

interface ProjectContainer {
  id: string;
  name: string;
  type: string;
  status: string;
  port: number | null;
}
```

**Tasks:**

- [ ] Add types to `src/types/api.ts`
- [ ] Create API proxy routes
- [ ] Verify proxy routes forward auth correctly

---

### Step 8: Frontend -- Dashboard UI

**New/modified components:**

- `src/components/pages/DashboardPage/` -- replace announcements with project list
- `src/components/ProjectCard/` -- project card with status, actions
- `src/components/CreateProjectDialog/` -- modal dialog for creating a project

**Dashboard page changes:**

- Fetch `GET /api/projects` on load
- Display grid of `ProjectCard` components
- "New Project" button opens `CreateProjectDialog`
- Empty state when no projects exist

**ProjectCard:**

- Project name and slug
- Status indicator (colored dot: green=running, yellow=starting, gray=stopped, red=error)
- Quick actions: Open (placeholder for Phase 4), Stop/Start, Delete
- Created date

**CreateProjectDialog:**

- Project name input (required)
- Template picker (optional -- dropdown: "None / Next.js / Elysia API / Full-stack")
- Design theme picker (optional -- dropdown: "None / Clean / Bold / Soft")
- Create button -> `POST /api/projects` -> refresh list
- Loading state while creating

**Delete confirmation:**

- Simple confirmation dialog before deleting
- Shows project name
- Warns that all files and containers will be removed

**Tasks:**

- [ ] Create `ProjectCard` component
- [ ] Create `CreateProjectDialog` component
- [ ] Create delete confirmation dialog
- [ ] Update `DashboardPage` to show projects instead of announcements
- [ ] Add empty state for no projects
- [ ] Add loading and error states
- [ ] Style with CSS variables (matching existing design)
- [ ] Write component tests

---

### Step 9: Dev Lifecycle Scripts (repo root)

**New files (in `devable-master/`):**

- `dev-start.sh` -- starts all infrastructure needed for development
- `dev-stop.sh` -- tears everything down cleanly

**`dev-start.sh` responsibilities:**

1. Start Caddy reverse proxy (`docker compose -f caddy/docker-compose.yml up -d`)
2. Start backend PostgreSQL (`docker compose -f apps/devable-backend/docker-compose.yml up -d`)
3. Verify all containers are healthy
4. Print status summary (what's running, on which ports)

**`dev-stop.sh` responsibilities:**

1. Stop all running user project containers (iterate `user-projects/` and run `docker compose down` for each)
2. Stop Caddy (`docker compose -f caddy/docker-compose.yml down`)
3. Stop backend PostgreSQL (`docker compose -f apps/devable-backend/docker-compose.yml down`)
4. Print confirmation

**Important:** Neither script uses `docker compose down -v`. Volumes are preserved so no data is lost between sessions. User project files on disk are untouched.

**Tasks:**

- [ ] Create `dev-start.sh`
- [ ] Create `dev-stop.sh`
- [ ] Make both executable (`chmod +x`)
- [ ] Update README with usage instructions
- [ ] Test full start/stop cycle

---

## Implementation Order

```text
Step 1 (Schema)
  |
  v
Step 2 (Repos + Service)  ->  Step 3 (File Service)  ->  Step 4 (Docker Service)
  |                                                          |
  v                                                          v
Step 5 (Caddy)                                               |
  |                                                          |
  v                                                          v
Step 6 (API Routes) <-- depends on Steps 2-5
  |
  v
Step 7 (Frontend API) -> Step 8 (Frontend UI)
  |
  v
Step 9 (Dev Lifecycle Scripts) <-- depends on Steps 5 + 4
```

Steps 2, 3, 4, 5 can be partially parallelized. Step 6 ties them together. Steps 7-8 depend on Step 6. Step 9 can be done any time after Steps 4-5 but makes most sense at the end when everything is testable.

---

## Testing Strategy

- **Unit tests**: Service methods with mocked dependencies (repositories, Docker, Caddy)
- **Integration tests**: API routes hitting real DB (use test database)
- **Manual E2E**: Create project -> verify files on disk -> verify containers running -> verify Caddy routing -> delete project -> verify cleanup

---

## Resolved Questions

1. **Port range**: Start allocating from 10000+. Each container gets its own port (app: 10000, next app: 10001, etc.). DB containers also get their own port if present.
2. **Templates in Phase 1**: Scaffold a minimal working app (basic "Hello World" that runs in Docker) so the full flow is testable end-to-end. Full templates come in Phase 2.
3. **Project limits**: No limits for the POC. Database containers are only created when the project actually needs a database — not every project gets one by default.
