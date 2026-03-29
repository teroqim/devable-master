#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$SCRIPT_DIR/apps"
CONFIG="$SCRIPT_DIR/apps.json"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install it with: brew install jq"
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  echo "Error: apps.json not found at $CONFIG"
  exit 1
fi

mkdir -p "$APPS_DIR"

app_count=$(jq '.apps | length' "$CONFIG")

for ((i = 0; i < app_count; i++)); do
  name=$(jq -r ".apps[$i].name" "$CONFIG")
  repo=$(jq -r ".apps[$i].repo" "$CONFIG")
  default_branch=$(jq -r ".apps[$i].defaultBranch" "$CONFIG")
  app_path="$APPS_DIR/$name"

  if [ -d "$app_path/.git" ]; then
    echo "[$name] Already cloned — fetching latest..."
    current_branch=$(git -C "$app_path" branch --show-current)
    git -C "$app_path" fetch
    git -C "$app_path" pull --ff-only || echo "  Warning: fast-forward pull failed on branch '$current_branch'. Resolve manually."
    echo "  Branch: $current_branch (up to date)"
  else
    echo "[$name] Cloning from $repo..."
    git clone "$repo" "$app_path"
    echo "  Cloned on branch: $default_branch"
  fi

  echo ""
done

echo "Done! All apps are in $APPS_DIR"
