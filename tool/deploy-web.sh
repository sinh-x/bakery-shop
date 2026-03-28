#!/usr/bin/env bash
# Build Flutter web app and copy to web-build/ for Caddy to serve.
# Usage: ./tool/deploy-web.sh [--restart-caddy]
#   --restart-caddy  Restart the Caddy Docker container after copying build output
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESTART_CADDY=0

for arg in "$@"; do
  case "$arg" in
    --restart-caddy) RESTART_CADDY=1 ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--restart-caddy]"
      exit 1
      ;;
  esac
done

# --- Build Flutter web ---
echo "Building Flutter web (release)..."
nix develop "${REPO_ROOT}/.#flutter" --command bash -c "cd '${REPO_ROOT}/app' && flutter build web --release"

BUILD_OUTPUT="${REPO_ROOT}/app/build/web"
if [ ! -d "$BUILD_OUTPUT" ]; then
  echo "ERROR: Flutter web build output not found at $BUILD_OUTPUT"
  exit 1
fi

# --- Sync to web-build/ (preserve directory inode for Docker bind mount) ---
DEST="${REPO_ROOT}/web-build"
echo "Syncing build output to $DEST..."
mkdir -p "$DEST"
rsync -a --delete "$BUILD_OUTPUT/" "$DEST/"
echo "Web build ready at $DEST"

# --- Optionally restart Caddy ---
if [ "$RESTART_CADDY" -eq 1 ]; then
  echo "Restarting Caddy container..."
  cd "$REPO_ROOT"
  docker compose --profile prod restart caddy
  echo "Caddy restarted."
fi

echo "Done."
