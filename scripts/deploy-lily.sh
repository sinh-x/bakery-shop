#!/usr/bin/env bash
# Deploy bakery-shop to lily via SSH (rsync-only, no git on lily).
# Usage: ./scripts/deploy-lily.sh [--dry-run] [--rollback] [--force] [--web-only] [--backend-only]
#
# Options:
#   --dry-run      Print planned steps without executing
#   --rollback     Rollback to previous web-build and Docker image
#   --force        Override branch warning (default branch is main)
#   --web-only     Only deploy web app (skip backend rebuild)
#   --backend-only Only deploy backend (skip web build and rsync)
#
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-lily}"
REMOTE_PATH="/home/sinh/bakery-shop"
DEPLOY_LOG="$REMOTE_PATH/deploy-history/deploy-history.log"

source "$(dirname "$0")/lib.sh"
load_env

REMOTE_PRINTER_DEVICE="${BAKER_PRINTER_DEVICE:-/dev/usb/lp0}"

DRY_RUN=0
ROLLBACK=0
FORCE=0
WEB_ONLY=0
BACKEND_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --rollback) ROLLBACK=1 ;;
    --force) FORCE=1 ;;
    --web-only) WEB_ONLY=1 ;;
    --backend-only) BACKEND_ONLY=1 ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--dry-run] [--rollback] [--force] [--web-only] [--backend-only]"
      exit 1
      ;;
  esac
done

# --- Pre-checks ---
echo "=== Pre-deploy checks ==="

CURRENT_BRANCH=$(git -C "$REPO_ROOT" branch --show-current)
GIT_STATUS=$(git -C "$REPO_ROOT" status --porcelain)

if [ -n "$GIT_STATUS" ]; then
  echo "WARNING: Working tree is dirty. Uncommitted changes:"
  git -C "$REPO_ROOT" status --short
  if [ "$DRY_RUN" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
    echo "Commit or stash changes before deploying, or use --force to override."
    exit 1
  fi
fi

if [ "$CURRENT_BRANCH" != "main" ] && [ "$FORCE" -eq 0 ]; then
  echo "WARNING: Not on main branch (currently: $CURRENT_BRANCH)."
  echo "Deploy from main unless you know what you're doing."
  echo "Use --force to override this warning."
  exit 1
fi

# Read version from pyproject.toml
APP_VERSION=$(grep '^version = ' "$REPO_ROOT/pyproject.toml" | sed 's/version = "//;s/"//')
GIT_COMMIT=$(git -C "$REPO_ROOT" rev-parse --short HEAD)
BUILD_FINGERPRINT=$(compute_build_fingerprint)
echo "  Branch: $CURRENT_BRANCH"
echo "  Commit: $GIT_COMMIT"
echo "  Fingerprint: $BUILD_FINGERPRINT"
echo "  Version: $APP_VERSION"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo "=== DRY RUN — no changes will be made ==="
fi

# Remote command template
remote_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] ssh $REMOTE_HOST '$1'"
  else
    remote_exec "$REMOTE_HOST" "$1"
  fi
}

check_remote_printer_device() {
  if [ "$WEB_ONLY" -eq 1 ]; then
    return 0
  fi

  echo "--- Printer device check ---"
  if [ "$REMOTE_PRINTER_DEVICE" = "/dev/null" ]; then
    echo "ERROR: BAKER_PRINTER_DEVICE is /dev/null. This discards print jobs while the API can still return success."
    exit 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Would verify on $REMOTE_HOST: test -c $REMOTE_PRINTER_DEVICE"
    return 0
  fi

  if ! ssh "$REMOTE_HOST" "test -c '$REMOTE_PRINTER_DEVICE'"; then
    echo "ERROR: Printer device not found on $REMOTE_HOST: $REMOTE_PRINTER_DEVICE"
    echo "Check that the thermal printer is connected and the usblp device exists."
    exit 1
  fi

  ssh "$REMOTE_HOST" "ls -l '$REMOTE_PRINTER_DEVICE'"
  echo "  Will mount $REMOTE_PRINTER_DEVICE -> /dev/usb/lp0 in baker-prod"
  echo ""
}

# --- Phase 1: Flutter web build (unless --backend-only) ---
if [ "$BACKEND_ONLY" -eq 0 ]; then
  echo "=== Building Flutter web ==="
  if [ "$DRY_RUN" -eq 0 ]; then
    build_flutter_web "$BUILD_FINGERPRINT"
  else
    echo "  Would run: build_flutter_web with BAKER_BUILD_FINGERPRINT=$BUILD_FINGERPRINT"
  fi
  echo ""
fi

# --- Rollback flow ---
if [ "$ROLLBACK" -eq 1 ]; then
  echo "=== Remote operations on $REMOTE_HOST ==="
  check_remote_printer_device
  echo "--- Rolling back ---"
  remote_cmd "cd $REMOTE_PATH && docker compose --profile prod stop"
  echo "  Restoring previous web-build..."
  remote_cmd "cd $REMOTE_PATH && if [ -d web-build.prev ]; then mv web-build web-build.new && mv web-build.prev web-build && rm -rf web-build.new; fi"
  echo "  Rebuilding Docker image..."
  remote_cmd "cd $REMOTE_PATH && BAKER_BUILD_FINGERPRINT=$BUILD_FINGERPRINT BAKER_PRINTER_DEVICE=$REMOTE_PRINTER_DEVICE docker compose --profile prod build baker-prod"
  echo "  Restarting containers..."
  remote_cmd "cd $REMOTE_PATH && BAKER_BUILD_FINGERPRINT=$BUILD_FINGERPRINT BAKER_PRINTER_DEVICE=$REMOTE_PRINTER_DEVICE docker compose --profile prod up -d"
  echo "  Running health check..."
  remote_cmd "curl -sf --max-time 10 http://localhost:2108/api/health || echo 'Health check failed'"
  echo "  Logging rollback..."
  remote_cmd "mkdir -p $REMOTE_PATH/deploy-history"
  remote_exec "$REMOTE_HOST" "echo '{\"timestamp\":\"$(date -Iseconds)\",\"version\":\"rollback\",\"commit\":\"$GIT_COMMIT\",\"status\":\"rollback\",\"user\":\"$(whoami)\"}' >> $DEPLOY_LOG" 2>/dev/null || true
  echo ""
  echo "=== Rollback complete ==="
  exit 0
fi

# --- Normal deploy flow (rsync-only, no git on lily) ---
echo "=== Remote operations on $REMOTE_HOST ==="
check_remote_printer_device

# 1. Snapshot previous web-build/ BEFORE rsync (for rollback)
if [ "$BACKEND_ONLY" -eq 0 ]; then
  echo "--- Snapshot web-build/ ---"
  remote_cmd "cd $REMOTE_PATH && rm -rf web-build.prev && cp -r web-build web-build.prev 2>/dev/null || true"
  echo ""
fi

# 2. Rsync Docker build files + source to lily
if [ "$WEB_ONLY" -eq 0 ]; then
  echo "--- Rsync Docker build files to lily ---"
  if [ "$DRY_RUN" -eq 0 ]; then
    ssh "$REMOTE_HOST" "mkdir -p $REMOTE_PATH"

    # Rsync top-level Docker build files
    echo "  Syncing Docker build files..."
    rsync -av \
      "$REPO_ROOT/docker-compose.yml" \
      "$REPO_ROOT/Dockerfile" \
      "$REPO_ROOT/docker-entrypoint.sh" \
      "$REPO_ROOT/Caddyfile" \
      "$REPO_ROOT/pyproject.toml" \
      "$REMOTE_HOST:$REMOTE_PATH/"

    # Rsync source code (needed for Docker image build)
    echo "  Syncing src/..."
    rsync -av --delete "$REPO_ROOT/src/" "$REMOTE_HOST:$REMOTE_PATH/src/"

    # Rsync config templates
    echo "  Syncing config/..."
    rsync -av "$REPO_ROOT/config/" "$REMOTE_HOST:$REMOTE_PATH/config/"

    # Rsync scripts (backup, etc.)
    echo "  Syncing scripts/..."
    rsync -av "$REPO_ROOT/scripts/" "$REMOTE_HOST:$REMOTE_PATH/scripts/"
  else
    echo "  Would rsync: docker-compose.yml, Dockerfile, docker-entrypoint.sh,"
    echo "    Caddyfile, pyproject.toml, src/, config/, scripts/"
  fi
  echo ""
fi

# 3. Rsync web-build/ (unless --backend-only)
if [ "$BACKEND_ONLY" -eq 0 ]; then
  echo "--- Rsync web-build/ to lily ---"
  if [ "$DRY_RUN" -eq 0 ]; then
    echo "  Syncing to $REMOTE_HOST:$REMOTE_PATH/web-build/"
    rsync -av --delete "$REPO_ROOT/web-build/" "$REMOTE_HOST:$REMOTE_PATH/web-build/"
  else
    echo "  Would run: rsync -av --delete $REPO_ROOT/web-build/ $REMOTE_HOST:$REMOTE_PATH/web-build/"
  fi
  echo ""
fi

# 4. Database backup on lily
echo "--- Database backup ---"
if [ "$DRY_RUN" -eq 0 ]; then
  remote_exec "$REMOTE_HOST" "cd $REMOTE_PATH && docker compose --profile prod exec -T baker-prod python -m baker db backup /tmp/baker.db.backup 2>/dev/null || echo 'Backup via entrypoint approach'"
  remote_exec "$REMOTE_HOST" "cd $REMOTE_PATH && docker compose --profile prod cp baker-prod:/tmp/baker.db.backup ./data/backups/baker.db.rollback 2>/dev/null && echo 'DB backup taken for rollback' || echo 'Backup step completed (migration backup on restart)'"
else
  echo "  Would run: database backup via docker exec"
fi
echo ""

# 5. Detect remote UID + Docker rebuild on lily (unless --web-only)
if [ "$WEB_ONLY" -eq 0 ]; then
  echo "--- Docker rebuild ---"
  REMOTE_UID=$(ssh "$REMOTE_HOST" "id -u" 2>/dev/null)
  echo "  Remote sinh UID: $REMOTE_UID"
  remote_cmd "cd $REMOTE_PATH && BAKER_UID=$REMOTE_UID BAKER_BUILD_FINGERPRINT=$BUILD_FINGERPRINT BAKER_PRINTER_DEVICE=$REMOTE_PRINTER_DEVICE docker compose --profile prod build baker-prod"
  echo ""
fi

# 6. Docker restart
echo "--- Restarting containers ---"
if [ "$WEB_ONLY" -eq 0 ]; then
  REMOTE_UID="${REMOTE_UID:-$(ssh "$REMOTE_HOST" "id -u" 2>/dev/null)}"
  remote_cmd "cd $REMOTE_PATH && BAKER_UID=$REMOTE_UID BAKER_BUILD_FINGERPRINT=$BUILD_FINGERPRINT BAKER_PRINTER_DEVICE=$REMOTE_PRINTER_DEVICE docker compose --profile prod up -d"
else
  remote_cmd "cd $REMOTE_PATH && docker compose --profile prod restart caddy"
fi
echo ""

# 7. Health check with retry
echo "--- Health check ---"
if [ "$DRY_RUN" -eq 0 ]; then
  if ! check_health "$REMOTE_HOST" 2108 10 3; then
    echo "ERROR: Health check failed after retries"
    exit 1
  fi
else
  echo "  Would run: check_health with 10 attempts, 3s delay"
fi
echo ""

# 8. Version verification
echo "--- Version verification ---"
if [ "$DRY_RUN" -eq 0 ]; then
  DEPLOYED_VERSION=$(curl -sf --max-time 5 "http://${REMOTE_HOST}:2108/api/health" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','unknown'))" 2>/dev/null || echo "unknown")
  echo "  Deployed version: $DEPLOYED_VERSION"
  if [ "$DEPLOYED_VERSION" != "$APP_VERSION" ]; then
    echo "  Note: Deployed version ($DEPLOYED_VERSION) != pyproject.toml ($APP_VERSION)"
    echo "  This may be due to in-flight migration. Verify manually."
  fi
else
  echo "  Would verify: pyproject.toml version ($APP_VERSION) matches /api/health response"
fi
echo ""

# 9. Printer mount verification
if [ "$WEB_ONLY" -eq 0 ]; then
  echo "--- Printer mount verification ---"
  if [ "$DRY_RUN" -eq 0 ]; then
    remote_exec "$REMOTE_HOST" "cd $REMOTE_PATH && docker compose --profile prod exec -T baker-prod ls -l /dev/usb/lp0 && curl -sf --max-time 5 http://localhost:2108/api/orders/print/status"
  else
    echo "  Would verify baker-prod /dev/usb/lp0 and /api/orders/print/status"
  fi
  echo ""
fi

# 10. Deploy log
echo "--- Logging deployment ---"
if [ "$DRY_RUN" -eq 0 ]; then
  log_deploy "$REMOTE_HOST" "$APP_VERSION" "$GIT_COMMIT" "success"
  echo "  Logged to $DEPLOY_LOG"
else
  echo "  Would log: timestamp, version=$APP_VERSION, commit=$GIT_COMMIT, status=success"
fi
echo ""

echo "=== Deploy complete ==="
if [ "$DRY_RUN" -eq 0 ]; then
  echo "  Web app: https://${REMOTE_HOST}"
  echo "  API: http://${REMOTE_HOST}:2108/api/health"
fi
