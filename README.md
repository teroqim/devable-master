# Devable Master

Meta-repository for the Devable project. This repo does **not** contain application code directly — instead it provides shared configuration and tooling to orchestrate the individual app repositories.

## Quick Start

```bash
# Clone this repo
git clone git@github.com:teroqim/devable-master.git
cd devable-master

# Clone all app repos (or update existing ones)
./src/scripts/setup.sh

# Start infrastructure (Caddy + PostgreSQL)
./src/scripts/dev-start.sh

# Then start the backend and frontend
cd apps/devable-backend && bun dev
cd apps/devable-frontend && npm run dev
```

## Structure

```text
devable-master/
├── apps/                       # App repos live here (git-ignored)
│   ├── devable-backend/        # Backend API (own git repo)
│   └── devable-frontend/       # Frontend app (own git repo)
├── src/
│   ├── scripts/                # Dev lifecycle scripts
│   │   ├── setup.sh            # Clone/update app repos
│   │   ├── dev-start.sh        # Start dev infrastructure
│   │   └── dev-stop.sh         # Stop all containers
│   ├── caddy/                  # Caddy reverse proxy config
│   ├── templates/              # Project scaffold templates
│   │   ├── nextjs-ts/          # Next.js + TypeScript
│   │   ├── bun-elysia-api/     # Bun + Elysia API
│   │   └── fullstack/          # Frontend + Backend + DB
│   └── design-themes/          # CSS theme files
│       ├── clean.css
│       ├── bold.css
│       └── soft.css
├── user-projects/              # Scaffolded user projects (git-ignored)
├── .claude/                    # Shared Claude Code configuration
├── CLAUDE.md                   # Top-level instructions for Claude Code
├── apps.json                   # Registry of app repos
└── README.md
```

## Scripts

All scripts live in `src/scripts/`. They resolve the repo root automatically, so you can run them from anywhere.

### `setup.sh` — Clone or update app repos

Reads `apps.json` and clones missing repos into `apps/`, or fetches + pulls the latest for existing ones. Run after first clone or to sync all repos.

```bash
./src/scripts/setup.sh
```

### `dev-start.sh` — Start dev infrastructure

Starts the Caddy reverse proxy and backend PostgreSQL database. Run at the beginning of a development session.

```bash
./src/scripts/dev-start.sh
```

### `dev-stop.sh` — Stop all containers

Stops all user project containers, Caddy, and the backend database. Data volumes are preserved — no data is lost between sessions.

```bash
./src/scripts/dev-stop.sh
```

## Debugging Caddy Routes

Caddy runs on port 8888 (proxy) and 2019 (admin API). Useful commands for debugging:

```bash
# View full Caddy config (shows all registered routes)
curl -s http://localhost:2019/config/ | python3 -m json.tool

# View only the routes
curl -s http://localhost:2019/config/apps/http/servers/devable/routes | python3 -m json.tool

# Delete a specific route by ID (e.g. devable-my-app)
curl -X DELETE http://localhost:2019/id/devable-my-app

# Test a project preview URL directly (bypassing Caddy)
curl http://localhost:<port>    # where <port> is the allocated container port (e.g. 10000)

# Restart Caddy (recreate container to pick up Caddyfile changes)
docker compose -f src/caddy/docker-compose.yml down && docker compose -f src/caddy/docker-compose.yml up -d

# Check Caddy container logs
docker compose -f src/caddy/docker-compose.yml logs
```

## How It Works

- **`apps.json`** lists every app repo with its git URL and default branch.
- **`src/scripts/setup.sh`** reads `apps.json` and either clones missing repos into `apps/` or fetches + pulls the latest for existing ones.
- The `apps/` directory is git-ignored so each app maintains its own independent git history.

## Adding a New App

Add an entry to `apps.json`:

```json
{
  "name": "devable-new-service",
  "repo": "git@github.com:teroqim/devable-new-service.git",
  "defaultBranch": "main"
}
```

Then run `./src/scripts/setup.sh` to clone it.

## Claude Code

This repo is configured as the top-level working directory for Claude Code, allowing agents to work across all apps simultaneously. Each app also has its own `CLAUDE.md` with project-specific instructions.

## Prerequisites

- Git
- Docker + Docker Compose
- [jq](https://jqlang.github.io/jq/) — used by `setup.sh` to parse `apps.json`
- [Bun](https://bun.sh/) — for the backend
- [Node.js](https://nodejs.org/) 22+ — for the frontend
