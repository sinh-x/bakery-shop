#!/usr/bin/env bash
# Rebuild Flutter web app and bring up the dev Docker stack in one shot.
# Usage: ./scripts/rebuild-dev.sh
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_env

# Step 1 — rebuild Flutter web bundle
echo "=== Step 1: Rebuild Flutter web ==="
build_flutter_web "$(compute_build_fingerprint)"

# Step 2 — bring up dev Docker stack (baker-dev + caddy-dev)
echo "=== Step 2: Bring up dev Docker stack ==="
docker compose --profile dev up -d --build

# Step 3 — health check with retry
echo "=== Step 3: Health check ==="
healthy=false
for i in 1 2 3; do
  if curl -sf http://localhost:2312/api/health >/dev/null 2>&1; then
    echo "baker-dev health OK"
    healthy=true
    break
  fi
  if [ "$i" -lt 3 ]; then
    sleep 2
  fi
done
if [ "$healthy" = false ]; then
  echo "WARNING: baker-dev /api/health not reachable after 3 attempts (may still be starting)"
fi

echo
echo "Done. Open https://drgnfly.tail10c2c6.ts.net/ on a tailnet device."
