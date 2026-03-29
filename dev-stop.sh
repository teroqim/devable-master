#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_PROJECTS_DIR="$SCRIPT_DIR/user-projects"

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
docker compose -f "$SCRIPT_DIR/caddy/docker-compose.yml" down
echo ""

# Stop backend PostgreSQL
echo "[backend-db] Stopping PostgreSQL..."
docker compose -f "$SCRIPT_DIR/apps/devable-backend/docker-compose.yml" down
echo ""

echo "All containers stopped. Data volumes are preserved."
