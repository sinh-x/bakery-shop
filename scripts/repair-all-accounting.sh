#!/usr/bin/env bash
# repair-all-accounting.sh — Run all accounting repair commands to establish a clean journal baseline.
# Usage: ./scripts/repair-all-accounting.sh [--dry-run]
# Without --dry-run: applies all repairs (idempotent, safe to re-run).
set -euo pipefail

DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="--dry-run"
  echo "=== DRY RUN MODE (no changes will be written) ==="
  echo
fi

run_repair() {
  local label="$1"
  shift
  echo
  echo "--- $label ---"
  baker "$@" $DRY_RUN
}

# 1. Inventory backfill: fix negative 1300 balance by creating missing stock-in JEs
run_repair "1/6 Inventory stock-in backfill" repair-inventory --all

# 2. COGS completeness: backfill cost_at_sale + create missing order_cogs JEs
run_repair "2/6 COGS backfill" repair-order-revenue --cogs --all

# 3. Payment journal: create missing payment_transaction JEs
run_repair "3/6 Payment journal backfill" repair-payment-journal --all

# 4. Deposit balance: fix outstanding_balance + cancelled_with_deposits
#    (DG-249 Phase 2: must run before AR entries so deposit-style revenue
#    JEs are created first; repair-ar-entries then skips orders already
#    covered by a deposit-style JE — prevents duplicate revenue JEs.)
run_repair "4/7 Deposit balance repair" repair-deposit-balance --all

# 5. Cancelled orders: clean up orphan JEs from cancelled orders
run_repair "5/7 Cancelled order cleanup" repair-cancelled-orders --all

# 6. AR entries: create missing accounts-receivable JEs for delivered orders without deposits
run_repair "6/7 AR entries backfill" repair-ar-entries --all

# 7. Debt expenses: fix missing/stale debt expense JEs (DG-245)
run_repair "7/7 Debt expense repair" repair-debt-expenses --all

echo
echo "=== All repairs complete ==="
echo
echo "Verify with: baker validate-accounts"
