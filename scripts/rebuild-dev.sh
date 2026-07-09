#!/usr/bin/env bash
# Rebuild Flutter web app and bring up the dev Docker stack in one shot.
# Usage: ./scripts/rebuild-dev.sh [--build-backend]
#   --build-backend  Also rebuild the baker-dev Docker image (when server code changed)
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_env

BACKEND_REBUILD=0

for arg in "$@"; do
  case "$arg" in
    --build-backend) BACKEND_REBUILD=1 ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--build-backend]"
      exit 1
      ;;
  esac
done

# Step 1 — rebuild Flutter web bundle
echo "=== Step 1: Rebuild Flutter web ==="
build_flutter_web "$(compute_build_fingerprint)"

# Step 2 — bring up dev Docker stack (baker-dev + caddy-dev)
echo "=== Step 2: Bring up dev Docker stack ==="
if [ "$BACKEND_REBUILD" -eq 1 ]; then
  echo "(rebuilding baker-dev image)"
  docker compose --profile dev up -d --build baker-dev caddy-dev
else
  docker compose --profile dev up -d
fi

# Step 3 — quick health check
echo "=== Step 3: Health check ==="
if curl -sf http://localhost:2312/api/health >/dev/null 2>&1; then
  echo "baker-dev health OK"
else
  echo "WARNING: baker-dev /api/health not reachable (may still be starting)"
fi

echo
echo "Done. Open https://drgnfly.tail10c2c6.ts.net/ on a tailnet device."
