#!/usr/bin/env bash
# prod-update.sh — Safe prod database update workflow
# Usage: ./scripts/prod-update.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SCRIPT="$SCRIPT_DIR/db-validate.sh"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

PROD_CONFIG="/etc/baker/baker.yaml"
# Fall back to NixOS default path pattern if no config
if [[ ! -f "$PROD_CONFIG" ]]; then
  PROD_CONFIG=$(find /nix/store -name "baker.yaml" -path "*/baker*" 2>/dev/null | head -1 || true)
fi

BAKER_CMD="baker"
if [[ -n "${PROD_CONFIG:-}" && -f "$PROD_CONFIG" ]]; then
  BAKER_CMD="baker --config $PROD_CONFIG"
fi

# Resolve DB path from baker config or default
DB_PATH="./data/baker.db"
if [[ -n "${PROD_CONFIG:-}" && -f "$PROD_CONFIG" ]]; then
  DB_PATH=$(python3 -c "import yaml; c=yaml.safe_load(open('$PROD_CONFIG')); print(c.get('db_path', './data/baker.db'))" 2>/dev/null || echo "./data/baker.db")
fi

echo "=== Baker Prod DB Update ==="
echo "Config: ${PROD_CONFIG:-default}"
echo ""

# Step 1: Show current status
echo "--- Current Status ---"
$BAKER_CMD db status

# Step 2: Check for pending migrations
PENDING=$($BAKER_CMD db status 2>&1 | grep "Pending migrations" | grep -o '[0-9]*' || echo "0")
if [[ "$PENDING" == "0" ]]; then
  echo ""
  echo "No pending migrations. Nothing to do."
  exit 0
fi

echo ""
echo "$PENDING migration(s) pending."

if [[ "$DRY_RUN" == "1" ]]; then
  echo ""
  $BAKER_CMD db migrate --dry-run
  echo ""
  echo "Dry run complete. Run without --dry-run to apply."
  exit 0
fi

# Step 3: Pre-migration validation snapshot
echo ""
echo "--- Pre-migration Validation ---"
PRE_SNAP="/tmp/baker-pre-migrate-$(date +%Y%m%d-%H%M%S).json"

if [[ -x "$VALIDATE_SCRIPT" ]]; then
  if ! "$VALIDATE_SCRIPT" snapshot --db-path "$DB_PATH" --output "$PRE_SNAP" 2>/dev/null; then
    echo "ERROR: Pre-migration snapshot failed. Aborting." >&2
    exit 1
  fi
  echo "Pre-migration snapshot saved: $PRE_SNAP"

  # Check integrity of current state
  INTEGRITY=$(python3 -c "import json; print(json.load(open('$PRE_SNAP')).get('integrity_check','ok'))" 2>/dev/null || echo "ok")
  if [[ "$INTEGRITY" != "ok" ]]; then
    echo "ERROR: Pre-migration integrity check failed: $INTEGRITY" >&2
    echo "Aborting migration. Investigate database integrity before proceeding." >&2
    exit 1
  fi
  echo "Pre-migration integrity check: $INTEGRITY"
else
  echo "WARNING: db-validate.sh not found — skipping pre-migration validation"
fi

# Step 4: Stop the baker service (prevents concurrent writes during migration)
echo ""
echo "--- Stopping baker service ---"
if systemctl is-active --quiet baker 2>/dev/null; then
  sudo systemctl stop baker
  echo "Service stopped."
  RESTART_SERVICE=1
else
  echo "Service not running (ok to continue)."
  RESTART_SERVICE=0
fi

# Step 5: Backup + migrate
echo ""
echo "--- Running migrations (with backup) ---"
$BAKER_CMD db migrate

# Step 6: Post-migration validation
echo ""
echo "--- Post-migration Validation ---"
if [[ -x "$VALIDATE_SCRIPT" && -f "$PRE_SNAP" ]]; then
  POST_SNAP="/tmp/baker-post-migrate-$(date +%Y%m%d-%H%M%S).json"
  if "$VALIDATE_SCRIPT" snapshot --db-path "$DB_PATH" --output "$POST_SNAP" 2>/dev/null; then
    echo "Post-migration snapshot saved: $POST_SNAP"
    echo ""
    echo "--- Migration Diff Report ---"
    "$VALIDATE_SCRIPT" diff --pre "$PRE_SNAP" --post "$POST_SNAP" || true
  else
    echo "WARNING: Post-migration snapshot failed"
  fi
else
  echo "WARNING: db-validate.sh not found or pre-snapshot missing — skipping post-migration validation"
fi

# Step 7: Verify
echo ""
echo "--- Post-migration Status ---"
$BAKER_CMD db status

# Step 8: Restart service
if [[ "$RESTART_SERVICE" == "1" ]]; then
  echo ""
  echo "--- Restarting baker service ---"
  sudo systemctl start baker
  sleep 2
  if systemctl is-active --quiet baker; then
    echo "Service restarted successfully."
  else
    echo "WARNING: Service failed to restart. Check: journalctl -u baker -n 50"
    exit 1
  fi
fi

echo ""
echo "=== Update complete ==="
