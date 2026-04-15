#!/usr/bin/env bash
# sync-prod-to-dev.sh — Automated production data sync to dev via rustic backup
#
# Scheduled daily at 23:30 via PA schedule.timer on Drgnfly.
# Restores latest rustic snapshot (baker-prod profile) and syncs to dev data dir.
# On failure, creates a DG ticket to alert Sinh.
#
# Usage: ./scripts/sync-prod-to-dev.sh
#
# Requirements:
#   - rustic profile "baker-prod" configured at ~/.config/rustic/baker-prod.toml
#   - Docker Compose v2 with "dev" profile available
#   - rclone remote accessible to rustic (Wasabi)
#   - baker-dev container running on port 2312

set -euo pipefail

# === Paths ===
STAGING_DIR="/tmp/rustic-staging"
DEV_DATA_DIR="./data"
LOCK_FILE="/var/lib/baker/sync-lock"
LOG_DIR="./data/sync-logs"
RUSTIC_PROFILE="baker-prod"

# === Helpers ===
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() { echo "[$(timestamp)] $*"; }

create_failure_ticket() {
    local reason="$1"
    unset CLAUDECODE
    pa ticket create \
        --project bakery-shop \
        --title "DG-068 Sync Failed: $reason" \
        --type fyi \
        --assignee sinh \
        --priority high \
        --estimate XS \
        --summary "Automatic prod→dev sync failed. Reason: $reason. Check sync logs at ./data/sync-logs/ for details. Manual intervention may be required." \
        2>&1 || log "WARNING: Failed to create ticket: $reason"
}

cleanup() {
    # Release lock on exit
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log "Released lock: $LOCK_FILE"
    fi
}
trap cleanup EXIT

# === Pre-flight ===
# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Check for concurrent run
if [[ -f "$LOCK_FILE" ]]; then
    log "ERROR: Lock file exists at $LOCK_FILE — another sync may be running. Exiting."
    exit 1
fi
touch "$LOCK_FILE"
log "Acquired lock: $LOCK_FILE"

# Check rustic access
if ! rustic -P "$RUSTIC_PROFILE" snapshots &>/dev/null; then
    log "ERROR: Cannot access rustic repo (baker-prod profile). Check ~/.config/rustic/baker-prod.toml"
    create_failure_ticket "rustic repo inaccessible"
    exit 1
fi

# === Step 1: Stop dev container ===
log "Stopping baker-dev container..."
if docker compose --profile dev ps --status running 2>/dev/null | grep -q baker-dev; then
    docker compose --profile dev stop baker-dev
    log "baker-dev container stopped"
else
    log "baker-dev container not running (skipping stop)"
fi

# === Step 2: Restore latest rustic snapshot ===
log "Cleaning staging directory..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

log "Restoring latest snapshot (baker-prod)..."
if ! rustic -P "$RUSTIC_PROFILE" restore latest --target "$STAGING_DIR" 2>&1; then
    log "ERROR: rustic restore failed"
    create_failure_ticket "rustic restore failed"
    exit 1
fi

STAGING="$STAGING_DIR/tmp/baker-backup-staging"

if [[ ! -f "$STAGING/baker.db" ]]; then
    log "ERROR: baker.db not found in restored snapshot at $STAGING"
    create_failure_ticket "baker.db not found in rustic snapshot"
    exit 1
fi
log "Snapshot restored successfully"

# === Step 3: Sync database ===
log "Copying baker.db to dev data dir..."
cp "$STAGING/baker.db" "$DEV_DATA_DIR/baker.db"
log "Database synced"

# === Step 4: Sync photos ===
if [[ -d "$STAGING/photos" ]]; then
    log "Syncing photos (rsync --delete)..."
    mkdir -p "$DEV_DATA_DIR/photos"
    rsync -a --delete "$STAGING/photos/" "$DEV_DATA_DIR/photos/"
    log "Photos synced"
else
    log "No photos directory in snapshot (skipping)"
fi

# === Step 5: Start dev container ===
log "Starting baker-dev container..."
docker compose --profile dev start baker-dev

# === Step 6: Health check ===
log "Waiting for baker-dev health (30s timeout)..."
HEALTHY=false
for i in $(seq 1 30); do
    if curl -sf http://localhost:2312/api/health >/dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    sleep 1
done

if [[ "$HEALTHY" != "true" ]]; then
    log "ERROR: Health check failed after 30 seconds"
    create_failure_ticket "baker-dev health check failed after restart"
    exit 1
fi
log "Health check passed"

# === Done ===
log "Sync completed successfully"
exit 0
