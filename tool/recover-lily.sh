#!/usr/bin/env bash
# recover-lily.sh — Restore latest backup and redeploy baker to lily
#
# Runs from drgnfly. No git needed on lily — rsyncs only the files
# Docker needs (Dockerfile, docker-compose.yml, source, Caddyfile, etc.)
#
# Steps:
#   1. Restore latest Lily backup from Wasabi (rustic)
#   2. Update local prod/data with restored database + photos
#   3. Rsync Docker build files + prod data + web build to lily
#   4. Set up .env, certs, deploy Docker containers
#   5. Health check
#
# Usage: ./tool/recover-lily.sh [--dry-run] [--skip-restore] [--skip-web-build]
#
# Options:
#   --dry-run        Print planned steps without executing
#   --skip-restore   Skip rustic restore (use existing local prod/data)
#   --skip-web-build Skip Flutter web build (use existing web-build/)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib.sh"
load_env

REMOTE_HOST="${REMOTE_HOST:-lily}"
REMOTE_PATH="/home/sinh/bakery-shop"
RUSTIC_PROFILE="baker-prod"
RESTORE_DIR="/tmp/baker-restore"

DRY_RUN=0
SKIP_RESTORE=0
SKIP_WEB_BUILD=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-restore) SKIP_RESTORE=1 ;;
    --skip-web-build) SKIP_WEB_BUILD=1 ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--dry-run] [--skip-restore] [--skip-web-build]"
      exit 1
      ;;
  esac
done

remote_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] ssh $REMOTE_HOST '$1'"
  else
    ssh "$REMOTE_HOST" "$1"
  fi
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "=== DRY RUN — no changes will be made ==="
  echo ""
fi

# --- Step 0: Kill old containers on lily ---
echo "=== Step 0: Stop old Docker containers on lily ==="
remote_cmd "docker rm -f bakery-shop-baker-prod-1 bakery-shop-caddy-1 2>/dev/null || true"
echo ""

# --- Step 1: Restore latest Lily backup from Wasabi ---
if [ "$SKIP_RESTORE" -eq 0 ]; then
  echo "=== Step 1: Restore latest Lily backup from Wasabi ==="

  # Find the latest Lily snapshot
  LATEST_SNAPSHOT=$(rustic -P "$RUSTIC_PROFILE" snapshots --filter-host Lily --json 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
# Flatten groups
snaps = []
for group in data:
    snaps.extend(group.get('snapshots', []))
if not snaps:
    print(''); sys.exit(0)
latest = max(snaps, key=lambda s: s['time'])
print(latest['id'][:8])
" 2>/dev/null || echo "")

  if [ -z "$LATEST_SNAPSHOT" ]; then
    echo "ERROR: No Lily snapshots found in rustic repo"
    exit 1
  fi

  echo "  Latest Lily snapshot: $LATEST_SNAPSHOT"

  if [ "$DRY_RUN" -eq 0 ]; then
    rm -rf "$RESTORE_DIR"
    mkdir -p "$RESTORE_DIR"
    echo "  Restoring..."
    rustic -P "$RUSTIC_PROFILE" restore "$LATEST_SNAPSHOT" "$RESTORE_DIR"
  else
    echo "  Would restore snapshot $LATEST_SNAPSHOT to $RESTORE_DIR"
  fi

  # Find the staging dir (path varies between backup versions)
  STAGING=""
  for candidate in "$RESTORE_DIR/tmp/rustic-backup-staging" "$RESTORE_DIR/tmp/baker-backup-staging"; do
    if [ -d "$candidate" ]; then
      STAGING="$candidate"
      break
    fi
  done

  if [ "$DRY_RUN" -eq 0 ] && [ -z "$STAGING" ]; then
    echo "ERROR: Could not find staging directory in restored snapshot"
    ls -la "$RESTORE_DIR/tmp/" 2>/dev/null || true
    exit 1
  fi

  echo ""

  # --- Step 2: Update local prod/data ---
  echo "=== Step 2: Update local prod/data with restored backup ==="
  LOCAL_DATA="$REPO_ROOT/prod/data"
  mkdir -p "$LOCAL_DATA"

  if [ "$DRY_RUN" -eq 0 ]; then
    # Backup current local db if it exists
    if [ -f "$LOCAL_DATA/baker.db" ]; then
      cp "$LOCAL_DATA/baker.db" "$LOCAL_DATA/baker.db.local-backup"
      echo "  Backed up existing local db to baker.db.local-backup"
    fi

    cp "$STAGING/baker.db" "$LOCAL_DATA/baker.db"
    echo "  Restored baker.db ($(du -h "$LOCAL_DATA/baker.db" | cut -f1))"

    if [ -d "$STAGING/photos" ]; then
      rsync -a "$STAGING/photos/" "$LOCAL_DATA/photos/"
      echo "  Restored photos/ ($(ls "$LOCAL_DATA/photos/" | wc -l) files)"
    fi

    if [ -d "$STAGING/logs" ]; then
      rsync -a "$STAGING/logs/" "$LOCAL_DATA/logs/"
      echo "  Restored logs/"
    fi
  else
    echo "  Would copy baker.db, photos/, logs/ from $STAGING to $LOCAL_DATA"
  fi
  echo ""
else
  echo "=== Steps 1-2: Skipped (--skip-restore) ==="
  echo ""
fi

# --- Step 3: Rsync everything to lily ---
echo "=== Step 3: Rsync Docker files + data + web build to lily ==="

# Build Flutter web first (if not skipped) so it's included in the rsync
if [ "$SKIP_WEB_BUILD" -eq 0 ]; then
  echo "  Building Flutter web..."
  if [ "$DRY_RUN" -eq 0 ]; then
    build_flutter_web
  else
    echo "  [dry-run] Would build Flutter web"
  fi
fi

if [ "$DRY_RUN" -eq 0 ]; then
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_PATH/prod/data $REMOTE_PATH/certs"

  # Rsync Docker build files (everything Docker needs to build + run)
  echo "  Syncing Docker build files..."
  rsync -av \
    "$REPO_ROOT/docker-compose.yml" \
    "$REPO_ROOT/Dockerfile" \
    "$REPO_ROOT/docker-entrypoint.sh" \
    "$REPO_ROOT/Caddyfile" \
    "$REPO_ROOT/pyproject.toml" \
    "$REMOTE_HOST:$REMOTE_PATH/"

  # Rsync source code (needed for Docker image build)
  rsync -av --delete "$REPO_ROOT/src/" "$REMOTE_HOST:$REMOTE_PATH/src/"

  # Rsync config templates
  rsync -av "$REPO_ROOT/config/" "$REMOTE_HOST:$REMOTE_PATH/config/"

  # Rsync scripts (backup, etc.)
  rsync -av "$REPO_ROOT/scripts/" "$REMOTE_HOST:$REMOTE_PATH/scripts/"

  # Rsync prod data (database + photos + logs)
  LOCAL_DATA="$REPO_ROOT/prod/data"
  echo "  Syncing prod data..."
  rsync -av "$LOCAL_DATA/baker.db" "$REMOTE_HOST:$REMOTE_PATH/prod/data/baker.db"
  if [ -d "$LOCAL_DATA/photos" ]; then
    rsync -av "$LOCAL_DATA/photos/" "$REMOTE_HOST:$REMOTE_PATH/prod/data/photos/"
  fi
  if [ -d "$LOCAL_DATA/logs" ]; then
    rsync -av "$LOCAL_DATA/logs/" "$REMOTE_HOST:$REMOTE_PATH/prod/data/logs/"
  fi

  # Rsync web build
  if [ -d "$REPO_ROOT/web-build" ] && [ "$(ls -A "$REPO_ROOT/web-build" 2>/dev/null)" ]; then
    echo "  Syncing web-build/..."
    rsync -av --delete "$REPO_ROOT/web-build/" "$REMOTE_HOST:$REMOTE_PATH/web-build/"
  else
    echo "  WARNING: No local web-build/ exists. Web app will not be available."
  fi

  echo "  All files synced to lily"
else
  echo "  Would rsync: docker-compose.yml, Dockerfile, docker-entrypoint.sh,"
  echo "    Caddyfile, pyproject.toml, src/, config/, prod/data/, web-build/"
fi
echo ""

# --- Step 4: Set up .env and deploy Docker ---
echo "=== Step 4: Deploy Docker on lily ==="

# Ensure .env exists on lily
remote_cmd "cd $REMOTE_PATH && test -f .env || cp config/docker.example .env"
# Set correct DOMAIN for lily
remote_cmd "cd $REMOTE_PATH && sed -i 's|DOMAIN=.*|DOMAIN=lily.tail10c2c6.ts.net|' .env"

# Ensure certs exist
echo "  Checking TLS certs..."
HAS_CERTS=$(ssh "$REMOTE_HOST" "test -f $REMOTE_PATH/certs/lily.tail10c2c6.ts.net.crt && echo yes || echo no" 2>/dev/null)
if [ "$HAS_CERTS" = "no" ]; then
  echo "  Generating Tailscale certs..."
  remote_cmd "mkdir -p $REMOTE_PATH/certs && tailscale cert --cert-file=$REMOTE_PATH/certs/lily.tail10c2c6.ts.net.crt --key-file=$REMOTE_PATH/certs/lily.tail10c2c6.ts.net.key lily.tail10c2c6.ts.net"
fi

# Detect remote UID for sinh (container user must match file owner)
REMOTE_UID=$(ssh "$REMOTE_HOST" "id -u" 2>/dev/null)
echo "  Remote sinh UID: $REMOTE_UID"

# Stop old containers if running
echo "  Stopping old containers..."
remote_cmd "cd $REMOTE_PATH && docker compose --profile prod down 2>/dev/null || true"

# Build and start (pass BAKER_UID so container user matches file owner)
echo "  Building Docker image..."
remote_cmd "cd $REMOTE_PATH && BAKER_UID=$REMOTE_UID docker compose --profile prod build baker-prod"

echo "  Starting containers..."
remote_cmd "cd $REMOTE_PATH && BAKER_UID=$REMOTE_UID docker compose --profile prod up -d"
echo ""

# --- Step 5: Health check ---
echo "=== Step 5: Health check ==="
if [ "$DRY_RUN" -eq 0 ]; then
  sleep 5
  if check_health "$REMOTE_HOST" 2108 10 3; then
    echo ""
    echo "=== Recovery complete! ==="
    echo "  Web app: https://lily.tail10c2c6.ts.net/"
    echo "  API:     https://lily.tail10c2c6.ts.net/api/health"
  else
    echo ""
    echo "ERROR: Health check failed. Check logs:"
    echo "  ssh lily 'cd $REMOTE_PATH && docker compose --profile prod logs baker-prod'"
    exit 1
  fi
else
  echo "  Would run health check against $REMOTE_HOST:2108"
  echo ""
  echo "=== DRY RUN complete — no changes made ==="
fi
