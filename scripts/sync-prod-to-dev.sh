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
LOCK_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data/sync-lock"
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
# Ensure directories exist
mkdir -p "$(dirname "$LOCK_FILE")"
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
if ! rustic -P "$RUSTIC_PROFILE" restore latest "$STAGING_DIR" 2>&1; then
    log "ERROR: rustic restore failed"
    create_failure_ticket "rustic restore failed"
    exit 1
fi

STAGING="$STAGING_DIR"

# Find baker.db in the restored snapshot (path varies by backup source machine)
BAKER_DB=$(find "$STAGING" -name "baker.db" -type f 2>/dev/null | head -1)
if [[ -z "$BAKER_DB" ]]; then
    log "ERROR: baker.db not found in restored snapshot"
    create_failure_ticket "baker.db not found in rustic snapshot"
    exit 1
fi
log "Found baker.db at: $BAKER_DB"
log "Snapshot restored successfully"

# Find photos dir if present
PHOTOS_DIR=$(find "$STAGING" -type d -name "photos" 2>/dev/null | head -1)

# === Step 3: Sync database ===
log "Copying baker.db to dev data dir..."
cp "$BAKER_DB" "$DEV_DATA_DIR/baker.db"
log "Database synced"

# === Step 4: Sync photos ===
if [[ -n "$PHOTOS_DIR" && -d "$PHOTOS_DIR" ]]; then
    log "Syncing photos (rsync --delete)..."
    mkdir -p "$DEV_DATA_DIR/photos"
    rsync -a --delete "$PHOTOS_DIR/" "$DEV_DATA_DIR/photos/"
    log "Photos synced"
else
    log "No photos directory in snapshot (skipping)"
fi

# === Step 5: Start dev container (if it exists) ===
if docker compose --profile dev ps --all 2>/dev/null | grep -q baker-dev; then
    log "Starting baker-dev container..."
    if ! docker compose --profile dev start baker-dev 2>&1; then
        log "WARNING: Could not start baker-dev (may not be built yet — skipping)"
    else
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
    fi
else
    log "baker-dev container not found (skipping start/health check)"
fi

# === Done ===
log "Sync completed successfully"
exit 0
