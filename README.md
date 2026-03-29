# Devable Master

Meta-repository for the Devable project. This repo does **not** contain application code directly — instead it provides shared configuration and tooling to orchestrate the individual app repositories.

## Quick Start

```bash
# Clone this repo
git clone git@github.com:teroqim/devable-master.git
cd devable-master

# Clone all app repos (or update existing ones)
./setup.sh
```

## Structure

```text
devable-master/
├── apps/                  # App repos live here (git-ignored)
│   ├── devable-backend/   # Backend API (own git repo)
│   └── devable-frontend/  # Frontend app (own git repo)
├── .claude/               # Shared Claude Code configuration
├── CLAUDE.md              # Top-level instructions for Claude Code
├── apps.json              # Registry of app repos
├── setup.sh               # Clone/update script
└── README.md
```

## How It Works

- **`apps.json`** lists every app repo with its git URL and default branch.
- **`setup.sh`** reads `apps.json` and either clones missing repos into `apps/` or fetches + pulls the latest for existing ones.
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

Then run `./setup.sh` to clone it.

## Claude Code

This repo is configured as the top-level working directory for Claude Code, allowing agents to work across all apps simultaneously. Each app also has its own `CLAUDE.md` with project-specific instructions.

## Prerequisites

- Git
- [jq](https://jqlang.github.io/jq/) — used by `setup.sh` to parse `apps.json`
