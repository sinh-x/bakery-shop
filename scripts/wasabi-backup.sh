#!/usr/bin/env bash
# wasabi-backup.sh - Backup baker data to Wasabi using rustic
# Usage: DATA_DIR=/var/lib/baker ./wasabi-backup.sh
#        DATA_DIR=./data ./wasabi-backup.sh

set -euo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/baker}"
STAGING_DIR="/tmp/baker-backup-staging"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Rustic profile (baker.toml in ~/.config/rustic/)
RUSTIC_PROFILE="baker"

log() {
    echo "[$TIMESTAMP] $*"
}

cleanup() {
    if [[ -d "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
        log "Cleanup: removed staging directory"
    fi
}

trap cleanup EXIT

log "Starting backup of $DATA_DIR"

# Step 1: Create staging directory
mkdir -p "$STAGING_DIR"

# Step 2: Backup database using sqlite3 .backup for consistency
DB_SRC="$DATA_DIR/baker.db"
DB_DST="$STAGING_DIR/baker.db"

if [[ -f "$DB_SRC" ]]; then
    log "Backing up database: $DB_SRC"
    /home/sinh/Documents/bakery-shop/.venv/bin/python -c "
import sqlite3
import sys
src = '$DB_SRC'
dst = '$DB_DST'
try:
    with sqlite3.connect(src) as conn:
        conn.backup(sqlite3.connect(dst))
    print('Database backup successful')
except Exception as e:
    print(f'Database backup failed: {e}', file=sys.stderr)
    sys.exit(1)
"
    log "Database backup complete"
else
    log "WARNING: Database not found at $DB_SRC"
fi

# Step 3: Copy photos and logs to staging area
if [[ -d "$DATA_DIR/photos" ]]; then
    log "Copying photos/"
    cp -r "$DATA_DIR/photos" "$STAGING_DIR/"
fi

if [[ -d "$DATA_DIR/logs" ]]; then
    log "Copying logs/"
    cp -r "$DATA_DIR/logs" "$STAGING_DIR/"
fi

# Step 4: Run rustic backup on staging directory
log "Running rustic backup..."
rustic -P "$RUSTIC_PROFILE" \
    backup "$STAGING_DIR" \
    --tag "date=$(date '+%Y-%m-%d')" \
    --tag "host=$(hostname)" \
    --tag "type=full" 2>&1

log "Rustic backup complete"

# Step 5: Run rustic forget --prune using retention policy
log "Running rustic forget --prune..."
rustic -P "$RUSTIC_PROFILE" \
    forget --prune \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3 2>&1

log "Rustic forget --prune complete"

# Step 6: Cleanup is handled by trap

log "Backup completed successfully"
