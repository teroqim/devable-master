#!/usr/bin/env bash
set -euo pipefail

# Purpose: Stop all development infrastructure and user project containers.
# When to run: At the end of a development session, or to clean up running containers.
# What it stops: User project containers, Caddy reverse proxy, backend PostgreSQL.
# Note: Data volumes are preserved — no data is lost between sessions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
USER_PROJECTS_DIR="$ROOT_DIR/user-projects"

echo "Stopping Devable development environment..."
echo ""

# Stop all user project containers
if [ -d "$USER_PROJECTS_DIR" ]; then
  echo "[user-projects] Stopping project containers..."
  find "$USER_PROJECTS_DIR" -name "docker-compose.yml" -maxdepth 3 | while read -r compose_file; do
    project_dir="$(dirname "$compose_file")"
    project_name="$(basename "$project_dir")"
    echo "  Stopping $project_name..."
    docker compose -f "$compose_file" down 2>/dev/null || true
  done
  echo ""
fi

# Stop Caddy reverse proxy
echo "[caddy] Stopping reverse proxy..."
docker compose -f "$ROOT_DIR/src/caddy/docker-compose.yml" down
echo ""

# Stop backend PostgreSQL
echo "[backend-db] Stopping PostgreSQL..."
docker compose -f "$ROOT_DIR/apps/devable-backend/docker-compose.yml" down
echo ""

echo "All containers stopped. Data volumes are preserved."
