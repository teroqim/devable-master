# Master Repo Setup

## Context

The `devable/` folder currently contains two app repos (`devable-backend`, `devable-frontend`) checked out side-by-side alongside the top-level `.claude/` and `CLAUDE.md`. We want to initialize this folder as a git repo (`devable-master`) that acts as a lightweight orchestration layer — not a monorepo, but a "meta-repo" that provides shared Claude Code configuration and a script to clone/update the individual app repos.

## Plan

### 1. Initialize git repo and add remote
```
git init
git remote add origin git@github.com:teroqim/devable-master.git
```

### 2. Move app folders into `apps/`
```
mkdir apps
mv devable-backend apps/
mv devable-frontend apps/
```

### 3. Create `.gitignore`
```
apps/
```
Just ignoring `apps/` is sufficient — it covers both app repos and any future ones.

### 4. Create `apps.json` — app registry
```json
{
  "apps": [
    {
      "name": "devable-backend",
      "repo": "git@github.com:teroqim/devable-backend.git",
      "defaultBranch": "main"
    },
    {
      "name": "devable-frontend",
      "repo": "git@github.com:teroqim/devable-frontend.git",
      "defaultBranch": "main"
    }
  ]
}
```

### 5. Create `setup.sh` — bash setup/update script
- Reads `apps.json` (requires `jq`)
- For each app:
  - If `apps/<name>` doesn't exist → `git clone <repo> apps/<name>`
  - If it exists → `cd` into it, `git fetch`, and `git pull` on the current branch
- Prints a summary of what was done

### 6. Create `README.md`
Explains:
- What this repo is (meta-repo for Devable)
- How to get started (`./setup.sh`)
- Folder structure
- That individual apps have their own repos/history
- That Claude Code is configured at this level to work across all apps

### 7. Update `CLAUDE.md`
Update the "Overall structure" section to reflect the new `apps/` folder layout.

### 8. Initial commit and push
- Commit: `.gitignore`, `apps.json`, `setup.sh`, `README.md`, `CLAUDE.md`, `.claude/`
- Push to `origin main`

## Files to create/modify
- **New**: `.gitignore`, `apps.json`, `setup.sh`, `README.md`
- **Modified**: `CLAUDE.md` (update folder structure references)
- **Moved**: `devable-backend` → `apps/devable-backend`, `devable-frontend` → `apps/devable-frontend`

## Verification
1. Run `./setup.sh` in a clean state (after moving apps) to confirm it works
2. `git status` shows only tracked files, no app repos leaking
3. Verify both apps are accessible at `apps/devable-backend` and `apps/devable-frontend`
