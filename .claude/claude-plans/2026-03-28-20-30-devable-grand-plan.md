# Devable Grand Plan

> A developer-friendly Lovable alternative: chat-driven development with full transparency and control.
>
> **Status**: Planning phase
> **Created**: 2026-03-28
> **Last updated**: 2026-03-29

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Phase 1: Foundation & Infrastructure](#2-phase-1-foundation--infrastructure)
3. [Phase 2: Project Templates & Design System](#3-phase-2-project-templates--design-system)
4. [Phase 3: AI Agent Integration](#4-phase-3-ai-agent-integration)
5. [Phase 4: IDE Experience](#5-phase-4-ide-experience)
6. [Phase 5: Developer Tools & Settings](#6-phase-5-developer-tools--settings)
7. [Phase 6: Polish & Integration](#7-phase-6-polish--integration)
8. [Future / Production Notes](#8-future--production-notes)
9. [Key Decisions Log](#9-key-decisions-log)

---

## 1. Architecture Overview

```
                         Browser
                           |
                    Next.js Frontend
                    (devable-frontend)
                     /           \
                    /             \
           Devable API         Caddy (Docker)
        (devable-backend)      reverse proxy
          Bun + Elysia        *.localhost:8080
               |                    |
          PostgreSQL           User Project
        (platform DB)         Docker containers
               |               (app + db)
          Prisma ORM               |
                            Claude Code CLI
                          (host, per session)
```

### Component Responsibilities

| Component | Role |
|-----------|------|
| **devable-frontend** | Next.js app: landing, dashboard, IDE (Monaco editor, chat, preview, settings) |
| **devable-backend** | Elysia API: project CRUD, session management, container orchestration, secrets, streaming |
| **Caddy** | Single Docker container, reverse proxy routing `{slug}.localhost:8080` to project containers |
| **Claude Code CLI** | Runs on host, one session per user+project, streams JSON output to backend |
| **Docker Compose (per project)** | App container + optional PostgreSQL/MongoDB containers |
| **user-projects/** | On-disk storage for all user project files, DB data, .env secrets |

### Directory Structure

This is a **meta-repo** (`devable-master`). App repositories live under `apps/` and are git-ignored — each has its own repo and git history. Run `./setup.sh` to clone or update them. The `apps.json` file is the registry of app repos.

```
devable-master/
├── .claude/
│   ├── claude-plans/
│   │   └── 2026-03-28-20-30-devable-grand-plan.md   # this file
│   └── settings.json
├── CLAUDE.md
├── README.md
├── apps.json                 # Registry of app repos (used by setup.sh)
├── setup.sh                  # Clone/update script for app repos
├── apps/                     # App repos (git-ignored, each has own repo)
│   ├── devable-backend/      # Platform API (Bun + Elysia + Prisma)
│   └── devable-frontend/     # Platform UI (Next.js)
├── user-projects/            # All user project files (to be created)
│   └── {userId}/
│       └── {projectId}/
│           ├── docker-compose.yml
│           ├── Dockerfile
│           ├── .env                # Project secrets (gitignored)
│           ├── CLAUDE.md           # Agent instructions (auto-generated + user custom)
│           ├── src/
│           └── .docker/            # DB data volumes
├── templates/                # Starter templates (to be created)
│   ├── nextjs-ts/
│   ├── bun-elysia-api/
│   └── fullstack/
├── design-themes/            # Design token sets (to be created)
│   ├── clean/
│   ├── bold/
│   └── soft/
└── caddy/                    # Caddy reverse proxy config (to be created)
    ├── docker-compose.yml
    └── Caddyfile
```

---

## 2. Phase 1: Foundation & Infrastructure ✅ COMPLETED

Core platform infrastructure that everything else depends on.

### 1.1 Project data model & API
- [ ] Design Prisma schema: Project model (id, name, slug, userId, template, designTheme, status, createdAt, updatedAt)
- [ ] Design Prisma schema: ProjectContainer model (id, projectId, name, containerId, type, status, port)
- [ ] Design Prisma schema: ChatSession model (id, projectId, sessionName, createdAt, lastActiveAt)
- [ ] Create and apply migrations
- [ ] API: POST /v1/projects - create project
- [ ] API: GET /v1/projects - list user's projects
- [ ] API: GET /v1/projects/:id - get project details
- [ ] API: PUT /v1/projects/:id - update project
- [ ] API: DELETE /v1/projects/:id - delete project (stop containers, clean up files)
- [ ] API: GET /v1/projects/:id/status - get container status & resource stats

### 1.2 Project file management
- [ ] Create `user-projects/` directory structure
- [ ] Service: scaffold project from template into `user-projects/{userId}/{projectId}/`
- [ ] Service: generate docker-compose.yml based on template type
- [ ] Service: generate CLAUDE.md for project (system prompt + user custom agent file)
- [ ] Service: manage .env file (read/write secrets)

### 1.3 Docker orchestration service
- [ ] Service: start project containers (docker-compose up)
- [ ] Service: stop project containers (docker-compose down)
- [ ] Service: restart containers
- [ ] Service: get container stats (CPU, memory, status) via Docker API
- [ ] Service: execute commands in app container (docker exec)
- [ ] Service: get container logs (docker logs, with streaming)
- [ ] Service: detect available port for each new project

### 1.4 Caddy reverse proxy
- [ ] Create Caddy docker-compose.yml (single instance)
- [ ] Caddyfile base config
- [ ] Service: add/remove project routes dynamically (via Caddy admin API)
- [ ] Route pattern: `{project-slug}.localhost:8080` -> project app container
- [ ] Test: verify subdomain routing works

### 1.5 Dashboard UI (extend existing)
- [ ] Project list page: show all user projects with status
- [ ] Create project dialog: name, optional template picker, optional design theme picker
- [ ] Project card: name, status indicator, preview thumbnail, quick actions (open, stop, delete)
- [ ] Delete project confirmation

---

## 3. Phase 2: Project Templates & Design System ✅ COMPLETED

> **Deviations from plan:**
>
> - The Next.js template has no database at all (not optional) -- if the AI agent later needs a DB, it modifies the project's docker-compose.yml itself.
> - The fullstack template uses a flat layout (`frontend/` + `backend/` dirs sharing a root docker-compose.yml) instead of a monorepo with workspaces.
> - The full create/delete orchestration (Docker start/stop, Caddy routing, port allocation, file scaffolding) was left as TODOs in Phase 1 and was wired in this phase.
> - Scripts, Caddy config, templates, and design themes were reorganized into a `src/` folder in devable-master.
> - Caddy was fixed: server explicitly named `devable`, `auto_https off` added for `.localhost` domains.
> - Port allocation was enhanced with `excludePorts` parameter to prevent collisions when allocating multiple ports in the same flow.

### 2.1 Next.js + TypeScript template
- [ ] Dockerfile (Node.js, hot reload in dev)
- [ ] docker-compose.yml (app + optional postgres)
- [ ] Next.js project scaffold with TypeScript
- [ ] Base project structure (src/app, src/components, src/lib)
- [ ] ESLint + Prettier config
- [ ] CLAUDE.md with coding conventions
- [ ] package.json with dev/build/start scripts

### 2.2 Bun + Elysia API template
- [ ] Dockerfile (Bun runtime)
- [ ] docker-compose.yml (app + postgres)
- [ ] Elysia project scaffold with TypeScript
- [ ] Prisma setup with PostgreSQL
- [ ] Base project structure (src/routes, src/services, src/db, src/lib)
- [ ] ESLint + Prettier config
- [ ] CLAUDE.md with coding conventions

### 2.3 Full-stack template
- [ ] docker-compose.yml (frontend + backend + postgres)
- [ ] Combined Next.js frontend + Elysia backend
- [ ] Shared types package
- [ ] API client in frontend calling backend
- [ ] CLAUDE.md covering both

### 2.4 Design themes
- [ ] **Clean theme**: minimal, neutral grays, subtle shadows, system fonts
  - [ ] CSS variables file (colors, spacing, typography, borders, shadows)
  - [ ] Base component styles (buttons, inputs, cards, layout)
  - [ ] Light + dark mode tokens
- [ ] **Bold theme**: vibrant colors, large typography, high contrast
  - [ ] CSS variables file
  - [ ] Base component styles
  - [ ] Light + dark mode tokens
- [ ] **Soft theme**: rounded, pastels, gentle gradients
  - [ ] CSS variables file
  - [ ] Base component styles
  - [ ] Light + dark mode tokens
- [ ] Theme preview thumbnails for the selection UI

---

## 4. Phase 3: AI Agent Integration

The chat-driven development experience.

### 3.1 Claude Code CLI integration
- [ ] Create `ChatSessionRepository` and wire into DB facade (table created in Phase 1 but repository deferred to here)
- [ ] Service: spawn Claude Code CLI process per session
  - Working directory: project's `user-projects/{userId}/{projectId}/`
  - Flags: `-p`, `--output-format stream-json`, `--verbose`, `--allowedTools`
  - Session naming: `--name "{userId}-{projectId}"`
  - Append user's custom agent instructions via `--append-system-prompt`
- [ ] Service: resume existing session (`--resume "{userId}-{projectId}"`)
- [ ] Service: parse streaming JSON output into structured events
- [ ] Service: kill/cancel running session
- [ ] Store session references in ChatSession table

### 3.2 Streaming to frontend
- [ ] API: POST /v1/projects/:id/chat - send message to agent
- [ ] WebSocket or SSE endpoint: stream agent responses to frontend
- [ ] Handle event types: text output, tool use, tool results, errors, completion
- [ ] Frontend: display streaming text responses
- [ ] Frontend: show tool use indicators (reading file, editing file, running command, etc.)

### 3.3 Agent system prompt
- [ ] Create base system prompt template for Devable agent
  - Awareness of project structure and docker-compose setup
  - Instructions to use the project's design system/tokens
  - Instructions to install deps inside the app container
  - Instructions for running dev servers
  - Guidelines for TypeScript-first development
  - DB access patterns (Prisma for PostgreSQL, Mongoose/native for MongoDB)
  - Awareness that user can see preview at `{slug}.localhost:8080`
- [ ] Merge user's custom agent file into CLAUDE.md
- [ ] Test: verify agent can create files, run commands, and see preview

### 3.4 Agent screenshot capability
- [ ] Install Playwright on host for screenshot support
- [ ] Service: take screenshot of `{slug}.localhost:8080` and save to project directory
- [ ] Make screenshot available to agent as a tool (via CLAUDE.md instructions or MCP)
- [ ] Test: agent requests screenshot and receives it

### 3.5 User-provided Anthropic API key
- [ ] API: PUT /v1/user/settings - save user's Anthropic API key
- [ ] Store in platform DB (or user-level .env)
- [ ] When spawning Claude Code: set ANTHROPIC_API_KEY env var if user provided one
- [ ] Frontend: settings page for API key input

---

## 5. Phase 4: IDE Experience

The main editor view at `/project/[id]/editor`.

### 4.1 Layout shell
- [ ] Split-pane layout: chat (left), file tree + editor (center), preview (right)
- [ ] Resizable panes
- [ ] Top bar: project name, container status, start/stop buttons, settings link
- [ ] Bottom bar: connection status, resource stats summary

### 4.2 Chat panel
- [ ] Message list with user and agent messages
- [ ] Streaming text display with markdown rendering
- [ ] Tool use indicators (file read, edit, bash command, etc.)
- [ ] Input field with send button
- [ ] Chat history (load previous messages from session)
- [ ] "New conversation" button (starts fresh session, keeps project context)

### 4.3 File tree
- [ ] Read project directory structure from backend
- [ ] API: GET /v1/projects/:id/files - list files/directories recursively
- [ ] Tree view with expand/collapse
- [ ] Click file to open in editor
- [ ] File icons by extension
- [ ] Auto-refresh when agent modifies files (via WebSocket notification)

### 4.4 Code editor (Monaco)
- [ ] Monaco editor integration
- [ ] API: GET /v1/projects/:id/files/:path - read file content
- [ ] API: PUT /v1/projects/:id/files/:path - save file content
- [ ] Multi-tab support (open multiple files)
- [ ] Syntax highlighting (TypeScript, JavaScript, CSS, HTML, JSON, YAML, Markdown, Dockerfile)
- [ ] Auto-save or explicit save
- [ ] Indicate when agent has modified the currently open file

### 4.5 Live preview
- [ ] Iframe pointing to `{slug}.localhost:8080`
- [ ] Refresh button
- [ ] Auto-refresh option (on file changes)
- [ ] Open in new tab button
- [ ] Loading/error states

### 4.6 Logs panel
- [ ] Toggleable bottom panel for container logs
- [ ] API: GET /v1/projects/:id/logs - stream container logs
- [ ] Filter by container (app, postgres, mongo)
- [ ] Clear logs button
- [ ] Auto-scroll with pause on scroll-up

---

## 6. Phase 5: Developer Tools & Settings

### 5.1 Secrets / environment variables manager
- [ ] UI: list, add, edit, delete env vars for a project
- [ ] API: CRUD /v1/projects/:id/env
- [ ] Write to project's .env file
- [ ] Restart containers after env change (prompt user)

### 5.2 Database viewer
- [ ] UI: list tables in project's PostgreSQL
- [ ] UI: show table schema (columns, types, constraints)
- [ ] UI: browse table data with pagination
- [ ] API: proxy SQL queries to project's PostgreSQL container
- [ ] For MongoDB: list collections, browse documents

### 5.3 SQL editor
- [ ] Monaco editor configured for SQL
- [ ] Execute query button
- [ ] Results table display
- [ ] Query history
- [ ] For MongoDB: query editor with JSON syntax

### 5.4 Container management
- [ ] UI: list all containers for a project
- [ ] Start/stop/restart per container
- [ ] Live resource stats (CPU %, memory usage, status)
- [ ] Container logs per service

### 5.5 Project settings
- [ ] Rename project
- [ ] Change design theme
- [ ] Custom agent instructions (textarea, saved to CLAUDE.md)
- [ ] User's Anthropic API key (global setting)
- [ ] Delete project

---

## 7. Phase 6: Polish & Integration

### 6.1 Agent-accessible tools
- [ ] Ensure agent can read/write project files
- [ ] Ensure agent can run commands in app container
- [ ] Ensure agent can query project's database
- [ ] Ensure agent can take screenshots of preview
- [ ] Ensure agent can read container logs
- [ ] Ensure agent can see env vars (non-secret values)
- [ ] Ensure agent can modify docker-compose.yml (add services)
- [ ] Test: full end-to-end flow (user describes app -> agent builds it -> preview works)

### 6.2 Error handling & resilience
- [ ] Handle container crash/restart gracefully
- [ ] Handle Claude Code CLI process crash
- [ ] Handle disk space warnings
- [ ] Graceful shutdown of all containers on platform stop
- [ ] Cleanup orphaned containers

### 6.3 UX polish
- [ ] Loading states throughout
- [ ] Error messages and recovery suggestions
- [ ] Keyboard shortcuts (save file, send message, toggle panels)
- [ ] Responsive layout (reasonable minimum width)
- [ ] Empty states (no projects, no files, no messages)

---

## 8. Future / Production Notes

> These are NOT in scope for the POC but should be considered for production deployment.

### Infrastructure
- **Multiple public URLs per project**: A project may contain several services that each need a public URL (e.g. webapp, API, admin panel). The reverse proxy and data model should support mapping multiple containers to distinct subdomains (e.g. `my-app.localhost:8080`, `my-app-api.localhost:8080`, `my-app-admin.localhost:8080`). For the POC we only route the main app container; this should be generalized later.
- **Reverse proxy**: Replace Caddy with **Traefik** for auto-discovery of Docker containers via labels, better scaling, built-in dashboard, Let's Encrypt integration
- **Container orchestration**: Move from Docker Compose to **Kubernetes** or **Docker Swarm** for multi-node scaling
- **Project isolation**: Run each project in its own **Docker-in-Docker** or **sandboxed VM** (e.g., Firecracker) for proper security isolation between users
- **Code storage**: Move from local disk to **cloud storage** (S3/GCS) with a git-backed system, or provide each project its own git repo (GitHub/GitLab integration)

### AI Agent
- **Migrate from Claude Code CLI to Claude Agent SDK** (TypeScript) for:
  - No dependency on CLI installation
  - Proper programmatic control
  - Custom tool definitions
  - Better error handling and retry logic
  - Easier API key management per user
- **Sandboxed execution**: Agent runs commands in container, not on host
- **Rate limiting**: Per-user token/message limits
- **Cost tracking**: Track API usage per user/project

### Security
- **Secrets**: Move from .env files to a proper secrets manager (HashiCorp Vault, AWS Secrets Manager)
- **Network isolation**: Each project's Docker network fully isolated, no cross-project access
- **Container limits**: CPU/memory limits enforced per project
- **File system**: Read-only mounts where possible, prevent container escape

### Features
- **Publishing**: Deploy projects to a hosting provider (Vercel, Fly.io, Railway)
- **Code download**: Git clone or zip download
- **Collaboration**: Multiple users on a project, real-time cursors
- **Version history**: Git-based rollback, conversation-linked snapshots
- **Custom domains**: User brings their own domain for published projects
- **Supabase/Neon integration**: Managed database option
- **Edge functions**: Serverless function support

---

## 9. Key Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-28 | Claude Code CLI for POC, Agent SDK for prod | Max subscription available, CLI has all tools built in |
| 2026-03-28 | Docker-compose per project | Clean isolation, each project gets its own DB containers |
| 2026-03-28 | Caddy in Docker as reverse proxy | Simple, no host install needed, admin API for dynamic routes |
| 2026-03-28 | Monaco Editor | Industry standard, VS Code-like experience for developers |
| 2026-03-28 | Same Next.js app for IDE | Reuse existing auth, build tooling, avoid maintaining two frontends |
| 2026-03-28 | 3 templates + 3 design themes | Cover common use cases without overwhelming choice |
| 2026-03-28 | User picks template optionally | Flexibility: guided or AI-decided |
| 2026-03-28 | Clerk for auth, no collaboration features | Already set up, sufficient for POC |
| 2026-03-28 | .env files for secrets | Simple for POC, upgrade to vault for production |
| 2026-03-28 | Project files in devable-master/user-projects/ (git-ignored) | Keep everything together for POC development |
| 2026-03-28 | *.localhost:8080 for preview URLs | Works natively on macOS, no DNS setup |
| 2026-03-28 | Claude Code runs on host | Simpler than containerizing, uses Max subscription auth |
| 2026-03-28 | PostgreSQL preferred, MongoDB for NoSQL | Proven stack, Prisma for PostgreSQL, native driver for Mongo |
| 2026-03-28 | Traefik recommended for production | Auto-discovery, better scaling, but overkill for POC |

---

## Implementation Order

Phases are numbered in implementation order. Each phase builds on the previous:

1. **Phase 1** - Foundation & Infrastructure: without this, nothing else works
2. **Phase 2** - Project Templates & Design System: needed before the agent can create projects
3. **Phase 3** - AI Agent Integration: the core chat-driven experience
4. **Phase 4** - IDE Experience: the main UI wrapping the agent
5. **Phase 5** - Developer Tools & Settings: enhances the experience
6. **Phase 6** - Polish & Integration: final integration and cleanup

After Phases 1-3 you'll have a functional (if rough) chat-driven development experience. Phase 4 wraps it in a proper IDE UI.
