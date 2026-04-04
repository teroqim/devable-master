#!/usr/bin/env bash
set -euo pipefail

# Purpose: Start all infrastructure needed for local development.
# When to run: At the beginning of a development session, before starting the backend or frontend.
# What it starts: Caddy reverse proxy, backend PostgreSQL database.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Starting Devable development environment..."
echo ""

# Start Caddy reverse proxy
echo "[caddy] Starting reverse proxy..."
docker compose -f "$ROOT_DIR/src/caddy/docker-compose.yml" up -d
echo "[caddy] Running on port 8888 (admin API on 2019)"
echo ""

# Start backend PostgreSQL
echo "[backend-db] Starting PostgreSQL..."
docker compose -f "$ROOT_DIR/apps/devable-backend/docker-compose.yml" up -d
echo "[backend-db] Running on port 5433"
echo ""

# Verify containers are running
echo "Verifying containers..."
echo ""

docker compose -f "$ROOT_DIR/src/caddy/docker-compose.yml" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""
docker compose -f "$ROOT_DIR/apps/devable-backend/docker-compose.yml" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "Development environment is ready!"
echo ""
echo "  Caddy proxy:    http://localhost:8888"
echo "  Caddy admin:    http://localhost:2019"
echo "  Backend DB:     postgresql://localhost:5433/devable_api"
echo ""
echo "Next steps:"
echo "  cd apps/devable-backend && bun dev"
echo "  cd apps/devable-frontend && npm run dev"
