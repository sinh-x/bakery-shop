#!/usr/bin/env bash
# lily-setup.sh — Deploy baker on lily
#
# Restores data from Wasabi backup (if needed) and launches Docker containers.
#
# Prerequisites:
#   - .env with DOMAIN set
#   - rustic profile at ~/.config/rustic/baker-prod.toml (repo + password + rclone)
#   - web-build/ directory (Flutter web app)
#   - certs/ directory (Tailscale HTTPS certs)
#
# Usage:
#   ./scripts/lily-setup.sh [DATA_DIR]
#
#   DATA_DIR defaults to ./prod/data

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

DATA_DIR="${1:-./prod/data}"
RUSTIC_PROFILE="baker-prod"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Load .env ---
if [[ ! -f .env ]]; then
  echo "ERROR: .env not found. cp config/docker.example .env"
  exit 1
fi
set -a
source .env
set +a
: "${DOMAIN:?DOMAIN not set in .env}"

# --- Step 1: Restore data if needed ---
mkdir -p "$DATA_DIR"

if [[ -f "$DATA_DIR/baker.db" ]]; then
  log "Data already exists at ${DATA_DIR}/baker.db — skipping restore"
else
  log "No baker.db found in ${DATA_DIR}, restoring from backup..."

  if ! rustic -P "$RUSTIC_PROFILE" snapshots &>/dev/null; then
    echo "ERROR: Cannot access rustic repo. Check ~/.config/rustic/${RUSTIC_PROFILE}.toml"
    exit 1
  fi

  RESTORE_DIR=$(mktemp -d)
  trap "rm -rf $RESTORE_DIR" EXIT

  rustic -P "$RUSTIC_PROFILE" restore latest "$RESTORE_DIR"

  STAGING="$RESTORE_DIR/tmp/baker-backup-staging"
  if [[ ! -f "$STAGING/baker.db" ]]; then
    echo "ERROR: baker.db not found in snapshot"
    exit 1
  fi

  cp "$STAGING/baker.db" "$DATA_DIR/baker.db"
  [[ -d "$STAGING/photos" ]] && cp -r "$STAGING/photos" "$DATA_DIR/"
  [[ -d "$STAGING/logs" ]] && cp -r "$STAGING/logs" "$DATA_DIR/"

  log "Data restored to ${DATA_DIR}"
fi

# --- Step 2: Launch ---
log "Building and starting containers..."
docker compose build baker-prod
DOMAIN="$DOMAIN" docker compose --profile prod up -d

log "Waiting for health check..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:2108/api/health &>/dev/null; then
    log "Server is healthy!"
    curl -s http://localhost:2108/api/health
    break
  fi
  [[ $i -eq 30 ]] && { echo "ERROR: Health check failed. Check: docker compose --profile prod logs baker-prod"; exit 1; }
  sleep 1
done

echo ""
log "=== Ready ==="
echo "  https://${DOMAIN}/"
