#!/usr/bin/env bash
# Create one consistent SQLite/photo snapshot and upload it with Rustic.

set -euo pipefail

DATA_DIR="${DATA_DIR:-${BAKER_DATA_DIR:-/var/lib/baker}}"
STAGING_ROOT="${STAGING_ROOT:-/tmp}"
RUSTIC_PROFILE="${RUSTIC_PROFILE:-}"
BACKUP_HOST="${BACKUP_HOST:-baker-aws-prod}"
LOCK_DIR="$DATA_DIR/.backup.lock"
STAGING_DIR=""
LOCK_ACQUIRED=false

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    if rm -rf -- "$STAGING_DIR"; then
      log "Cleanup: removed staging directory"
    else
      log "ERROR: could not remove staging directory" >&2
      status=1
    fi
  fi
  if [[ "$LOCK_ACQUIRED" == true ]]; then
    if rmdir -- "$LOCK_DIR"; then
      log "Cleanup: released backup lock"
    else
      log "ERROR: could not release backup lock" >&2
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

run_rustic() {
  if [[ -n "$RUSTIC_PROFILE" ]]; then
    rustic -P "$RUSTIC_PROFILE" "$@"
  else
    rustic "$@"
  fi
}

[[ -d "$DATA_DIR" ]] || fail "data directory does not exist"
[[ -f "$DATA_DIR/baker.db" ]] || fail "database is missing"
mkdir -p "$STAGING_ROOT"
if ! mkdir -- "$LOCK_DIR" 2>/dev/null; then
  fail "another backup holds the EFS lock"
fi
LOCK_ACQUIRED=true
STAGING_DIR="$(mktemp -d "$STAGING_ROOT/baker-backup.XXXXXX")"

log "Checking Rustic repository access"
run_rustic snapshots >/dev/null

DB_DST="$STAGING_DIR/baker.db"
log "Creating a consistent SQLite backup"
sqlite3 "$DATA_DIR/baker.db" ".timeout 30000" ".backup '$DB_DST'"
integrity="$(sqlite3 "$DB_DST" "PRAGMA integrity_check;")"
[[ "$integrity" == "ok" ]] || fail "SQLite integrity_check failed"

mkdir -p "$STAGING_DIR/photos"
PHOTO_LIST="$STAGING_DIR/photo-hashes.txt"
sqlite3 -noheader "$DB_DST" "SELECT hash FROM photos ORDER BY hash;" > "$PHOTO_LIST"
while IFS= read -r photo_hash; do
  [[ "$photo_hash" =~ ^[0-9a-f]{64}$ ]] || fail "database contains an invalid photo hash"
  source_photo="$DATA_DIR/photos/${photo_hash}.jpg"
  [[ -f "$source_photo" ]] || fail "database-referenced photo is missing"
  cp -- "$source_photo" "$STAGING_DIR/photos/${photo_hash}.jpg"
done < "$PHOTO_LIST"

cat > "$STAGING_DIR/backup-metadata.txt" <<EOF
created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
backup_host=$BACKUP_HOST
source_task=$(hostname)
sqlite_version=$(sqlite3 --version | awk '{print $1}')
EOF

log "Writing and checking SHA-256 manifest"
(
  cd "$STAGING_DIR"
  find . -type f ! -name SHA256SUMS -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum > SHA256SUMS
)
BAKER_DATA_DIR="$DATA_DIR" "$(dirname "$0")/verify-backup-restore.sh" "$STAGING_DIR"

log "Uploading verified staging set"
run_rustic backup "$STAGING_DIR" \
  --as-path /baker \
  --host "$BACKUP_HOST" \
  --tag "date=$(date -u '+%Y-%m-%d')" \
  --tag "type=hourly"

log "Applying bounded retention"
run_rustic forget --prune \
  --filter-host "$BACKUP_HOST" \
  --filter-paths-exact /baker \
  --filter-tags type=hourly \
  --keep-hourly 48 \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 3

log "Backup completed successfully"
