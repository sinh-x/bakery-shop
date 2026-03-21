#!/usr/bin/env bash
# docker-backup.sh — Backup baker.db with timestamp and configurable retention
#
# Usage:
#   ./scripts/docker-backup.sh [source_db] [backup_dir] [keep_count]
#
# Defaults:
#   source_db  = ./data/baker.db
#   backup_dir = ./data/backups
#   keep_count = 7
#
# Can be run:
#   - On the host via cron
#   - Inside a container via: docker exec <container> /scripts/docker-backup.sh

set -euo pipefail

SOURCE_DB="${1:-./data/baker.db}"
BACKUP_DIR="${2:-./data/backups}"
KEEP_COUNT="${3:-7}"

if [ ! -f "$SOURCE_DB" ]; then
    echo "ERROR: Source database not found: $SOURCE_DB" >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/baker.db.$TIMESTAMP"

cp "$SOURCE_DB" "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"

# Remove old backups beyond KEEP_COUNT
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/baker.db.* 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt "$KEEP_COUNT" ]; then
    REMOVE_COUNT=$(( BACKUP_COUNT - KEEP_COUNT ))
    ls -1t "$BACKUP_DIR"/baker.db.* | tail -n "$REMOVE_COUNT" | xargs rm -f
    echo "Removed $REMOVE_COUNT old backup(s), keeping last $KEEP_COUNT"
fi

echo "Done. Total backups: $(ls -1 "$BACKUP_DIR"/baker.db.* 2>/dev/null | wc -l)"
