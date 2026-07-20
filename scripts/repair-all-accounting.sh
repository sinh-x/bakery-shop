#!/usr/bin/env bash
# repair-all-accounting.sh — Run all accounting repair commands to establish a clean journal baseline.
# Usage: ./scripts/repair-all-accounting.sh [--dry-run]
# Without --dry-run: applies all repairs (idempotent, safe to re-run).
#
# v0.8.0 (DG-268 Phase 4): Two repair subcommands added at their dependency-safe
# positions:
#   - repair-unallocated-transfers after step 3 (payment journal backfill):
#     transfer-asset routing must be re-based to 1290 before deposit-balance
#     and AR-entry backfills run, since they consume the payment_journal layer.
#   - repair-delivered-dates after step 5 (cancelled order cleanup): must run
#     before repair-ar-entries so AR backfill sees the delivered-timestamp
#     transaction_date rather than the order-creation timestamp (DG-260).
# Both new steps are idempotent — re-running the script is a no-op on a clean DB.
set -euo pipefail

DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="--dry-run"
  echo "=== DRY RUN MODE (no changes will be written) ==="
  echo
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--dry-run]" >&2
  echo "Error: unrecognized argument(s): $*" >&2
  exit 2
fi

run_repair() {
  local label="$1"
  shift
  echo
  echo "--- $label ---"
  baker "$@" $DRY_RUN
}

# 1. Inventory backfill: fix negative 1300 balance by creating missing stock-in JEs
run_repair "1/9 Inventory stock-in backfill" repair-inventory --all

# 2. COGS completeness: backfill cost_at_sale + create missing order_cogs JEs
run_repair "2/9 COGS backfill" repair-order-revenue --cogs --all

# 3. Payment journal: create missing payment_transaction JEs
run_repair "3/9 Payment journal backfill" repair-payment-journal --all

# 4. Unallocated transfers (DG-244 Phase 5): re-route transfer-payment asset
#    lines from legacy 1200 to 1290 (Un-allocated Bank). Must run after
#    payment-journal backfill so the payment_transaction JEs it inspects
#    already exist; before deposit-balance / AR-entry backfills so they see
#    the corrected asset routing. Idempotent — no-op on a clean DB.
run_repair "4/9 Unallocated transfer re-route" repair-unallocated-transfers --all

# 5. Deposit balance: fix outstanding_balance + cancelled_with_deposits
#    (DG-249 Phase 2: must run before AR entries so deposit-style revenue
#    JEs are created first; repair-ar-entries then skips orders already
#    covered by a deposit-style JE — prevents duplicate revenue JEs.)
run_repair "5/9 Deposit balance repair" repair-deposit-balance --all

# 6. Cancelled orders: clean up orphan JEs from cancelled orders
run_repair "6/9 Cancelled order cleanup" repair-cancelled-orders --all

# 7. Delivered-dates rebasing (DG-260 Phase 2): rebase transaction_date on
#    order/order_cogs/order_shipping_release JEs to the delivered event
#    timestamp. Must run after cancelled-orders cleanup (so it doesn't
#    rebase dates on entries about to be removed) and before repair-ar-entries
#    (so AR backfill stamps AR entries with the delivered date). Idempotent —
#    no-op on a clean DB; skips locked JEs. NOTE: this subcommand has no
#    --all flag (it always scans the whole DB); --dry-run is passed through
#    by run_repair.
run_repair "7/9 Delivered-dates rebasing" repair-delivered-dates

# 8. AR entries: create missing accounts-receivable JEs for delivered orders without deposits
run_repair "8/9 AR entries backfill" repair-ar-entries --all

# 9. Debt expenses: fix missing/stale debt expense JEs (DG-245)
run_repair "9/9 Debt expense repair" repair-debt-expenses --all

echo
echo "=== All repairs complete ==="
echo
echo "Verify with: baker validate-accounts"