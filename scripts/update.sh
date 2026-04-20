#!/usr/bin/env bash
# Full update: rebuild Flutter web + rebuild & restart Docker services.
# Usage: ./scripts/update.sh [--web-only] [--backend-only]
#   --web-only      Only rebuild Flutter web app + restart Caddy
#   --backend-only  Only rebuild & restart baker Docker service
#   (no flags)      Rebuild everything
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_env

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

echo "=== Baker Update ==="
echo "  Repo: $REPO_ROOT"
echo "  Branch: $(git -C "$REPO_ROOT" branch --show-current)"
echo "  Domain: ${DOMAIN:-<not set>}"
echo ""

# --- Flutter web build ---
if [ "$DO_WEB" -eq 1 ]; then
  build_flutter_web
  echo ""
fi

# --- Docker rebuild & restart ---
if [ "$DO_BACKEND" -eq 1 ]; then
  echo "--- Rebuilding Docker services (prod) ---"
  (cd "$REPO_ROOT" && docker compose --profile prod build --no-cache baker-prod)
  (cd "$REPO_ROOT" && docker compose --profile prod up -d)
  echo ""
fi

# If web-only, just restart Caddy to pick up new static files
if [ "$DO_WEB" -eq 1 ] && [ "$DO_BACKEND" -eq 0 ]; then
  restart_caddy
  echo ""
fi

echo "=== Update complete ==="
(cd "$REPO_ROOT" && docker compose --profile prod ps)
