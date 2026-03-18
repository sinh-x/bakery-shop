#!/usr/bin/env bash
# prod-update.sh — Safe prod database update workflow
# Usage: ./scripts/prod-update.sh [--dry-run]
set -euo pipefail

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

# Step 3: Stop the baker service (prevents concurrent writes during migration)
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

# Step 4: Backup + migrate
echo ""
echo "--- Running migrations (with backup) ---"
$BAKER_CMD db migrate

# Step 5: Verify
echo ""
echo "--- Post-migration Status ---"
$BAKER_CMD db status

# Step 6: Restart service
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
