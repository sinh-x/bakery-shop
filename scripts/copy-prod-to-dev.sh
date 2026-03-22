#!/usr/bin/env bash
# copy-prod-to-dev.sh — Copy production data to dev for testing
#
# Usage: ./scripts/copy-prod-to-dev.sh

set -euo pipefail

PROD_DIR="./prod/data"
DEV_DIR="./data"

if [ ! -f "$PROD_DIR/baker.db" ]; then
    echo "ERROR: Production database not found at $PROD_DIR/baker.db" >&2
    exit 1
fi

# Warn if dev container is running
if docker compose --profile dev ps --status running 2>/dev/null | grep -q baker-dev; then
    echo "WARNING: Dev container is running. Stop it first: docker compose --profile dev down" >&2
    exit 1
fi

# Backup current dev DB if it exists
if [ -f "$DEV_DIR/baker.db" ]; then
    BACKUP="$DEV_DIR/baker.db.bak.$(date +%Y-%m-%dT%H-%M-%S)"
    cp "$DEV_DIR/baker.db" "$BACKUP"
    echo "Backed up dev DB to: $BACKUP"
fi

# Copy database
cp "$PROD_DIR/baker.db" "$DEV_DIR/baker.db"
echo "Copied prod DB → dev DB"

# Sync photos
if [ -d "$PROD_DIR/photos" ]; then
    mkdir -p "$DEV_DIR/photos"
    rsync -a --delete "$PROD_DIR/photos/" "$DEV_DIR/photos/"
    echo "Synced prod photos → dev photos"
fi

echo "Done. Dev data is now a copy of prod."
