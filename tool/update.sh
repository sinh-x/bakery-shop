#!/usr/bin/env bash
# Full update: rebuild Flutter web + rebuild & restart Docker services.
# Usage: ./tool/update.sh [--web-only] [--backend-only]
#   --web-only      Only rebuild Flutter web app + restart Caddy
#   --backend-only  Only rebuild & restart baker Docker service
#   (no flags)      Rebuild everything
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DO_WEB=1
DO_BACKEND=1

for arg in "$@"; do
  case "$arg" in
    --web-only) DO_BACKEND=0 ;;
    --backend-only) DO_WEB=0 ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--web-only] [--backend-only]"
      exit 1
      ;;
  esac
done

DOMAIN="${DOMAIN:-drgnfly.tail10c2c6.ts.net}"
export DOMAIN

echo "=== Baker Update ==="
echo "  Repo: $REPO_ROOT"
echo "  Branch: $(git branch --show-current)"
echo "  Domain: $DOMAIN"
echo ""

# --- Flutter web build ---
if [ "$DO_WEB" -eq 1 ]; then
  echo "--- Building Flutter web (release) ---"
  nix develop "${REPO_ROOT}/.#flutter" --command bash -c "cd '${REPO_ROOT}/app' && flutter build web --release"

  BUILD_OUTPUT="${REPO_ROOT}/app/build/web"
  if [ ! -d "$BUILD_OUTPUT" ]; then
    echo "ERROR: Flutter web build output not found at $BUILD_OUTPUT"
    exit 1
  fi

  DEST="${REPO_ROOT}/web-build"
  echo "Syncing build to $DEST..."
  mkdir -p "$DEST"
  rsync -a --delete "$BUILD_OUTPUT/" "$DEST/"
  echo "Web build ready."
  echo ""
fi

# --- Docker rebuild & restart ---
if [ "$DO_BACKEND" -eq 1 ]; then
  echo "--- Rebuilding Docker services (prod) ---"
  docker compose --profile prod build --no-cache baker-prod
  docker compose --profile prod up -d
  echo ""
fi

# If web-only, just restart Caddy to pick up new static files
if [ "$DO_WEB" -eq 1 ] && [ "$DO_BACKEND" -eq 0 ]; then
  echo "--- Restarting Caddy ---"
  docker compose --profile prod restart caddy
  echo ""
fi

echo "=== Update complete ==="
docker compose --profile prod ps
