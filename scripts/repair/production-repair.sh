#!/usr/bin/env bash
# production-repair.sh — Full production accounting repair sequence (DG-268 / v0.8.0 Phase 4).
#
# Runs, in dependency-safe order (FR5):
#   backup → validate-accounts (pre)
#          → repair-delivered-dates
#          → repair-unallocated-transfers
#          → repair-all-accounting.sh (9-step loop)
#          → validate-accounts (post)
#
# The script is idempotent: every repair subcommand is a no-op on a clean DB,
# so re-running after a successful repair is safe. Always run with --dry-run
# first to preview mutations.
#
# Usage: ./scripts/repair/production-repair.sh [--dry-run]
#   --dry-run  Print every command that would run; write nothing to the DB.
#              The backup step is still performed so the dry-run path mirrors
#              the real path (the backup is a read-only cp and never mutates
#              the live DB).
#
# Exit codes:
#   0  success (or dry-run completed)
#   1  unexpected error during a repair or validation step
#   2  usage error (unknown argument)
#
# Pattern: scripts/repair/fix-dg249-duplicate-jes.sh (backup + docker compose exec)
#          scripts/repair-all-accounting.sh (run_repair wrapper, --dry-run plumbing)
set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing (NFR3: --dry-run + usage error on unknown args)
# ---------------------------------------------------------------------------
DRY_RUN=0
if [[ $# -gt 0 ]]; then
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    *)
      echo "Usage: $0 [--dry-run]" >&2
      echo "Error: unrecognized argument: $1" >&2
      exit 2
      ;;
  esac
  if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [--dry-run]" >&2
    echo "Error: too many arguments: $*" >&2
    exit 2
  fi
fi

# docker compose exec wrapper used for every baker CLI call.
DC="docker compose --profile prod exec -T baker-prod"

# ---------------------------------------------------------------------------
# Helper: run a baker subcommand, or print it under --dry-run.
# ---------------------------------------------------------------------------
run_baker() {
  local label="$1"
  shift
  echo
  echo "--- $label ---"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    # Dry-run is a preview: print the command, attempt the underlying dry-run
    # for visibility, but never let a service-unreachable error fail the
    # overall dry-run (AC10: --dry-run must exit 0).
    echo "  [dry-run] $DC baker $* --dry-run"
    $DC baker "$@" --dry-run || true
  else
    $DC baker "$@"
  fi
}

# ---------------------------------------------------------------------------
# Step 1 — Backup (REQUIRED before any mutation; mirrors fix-dg249 script).
# The backup is performed even under --dry-run because it is a read-only cp
# and never mutates the live DB. If the target file already exists we abort
# to prevent clobbering a prior backup.
# ---------------------------------------------------------------------------
BACKUP="prod/data/baker.db.backup-v080-$(date +%Y%m%d-%H%M%S)"
echo "=== Production repair sequence (v0.8.0) ==="
echo
echo "--- Step 1: Backup ---"
if [[ -e "$BACKUP" ]]; then
  echo "Error: backup target already exists: $BACKUP" >&2
  echo "Move it aside or wait a second before re-running." >&2
  exit 1
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] cp prod/data/baker.db $BACKUP"
else
  cp prod/data/baker.db "$BACKUP"
  echo "  Backup written: $BACKUP"
fi

# ---------------------------------------------------------------------------
# Step 2 — Pre-repair validation
# ---------------------------------------------------------------------------
echo
echo "--- Step 2: Pre-repair validate-accounts ---"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] $DC baker validate-accounts"
  $DC baker validate-accounts || true
else
  $DC baker validate-accounts
fi

# ---------------------------------------------------------------------------
# Step 3 — repair-delivered-dates (DG-260 Phase 2)
# Rebase transaction_date on order/order_cogs/order_shipping_release JEs to
# the delivered event timestamp. Must run before repair-all-accounting.sh so
# downstream deposit-balance and AR-entry backfills see correct dates.
# ---------------------------------------------------------------------------
run_baker "Step 3: repair-delivered-dates" repair-delivered-dates

# ---------------------------------------------------------------------------
# Step 4 — repair-unallocated-transfers (DG-244 Phase 5)
# Re-route transfer-payment asset lines from legacy 1200 to 1290
# (Un-allocated Bank). Must run after repair-payment-journal's domain is
# settled conceptually; here it runs before repair-all-accounting.sh so the
# 9-step loop sees the corrected asset routing. Idempotent — re-running the
# embedded step inside repair-all-accounting.sh (step 4/9) is a no-op.
# ---------------------------------------------------------------------------
run_baker "Step 4: repair-unallocated-transfers" repair-unallocated-transfers --all

# ---------------------------------------------------------------------------
# Step 5 — repair-all-accounting.sh (9-step loop)
# Passes --dry-run through to the script, which forwards it to every baker
# subcommand via its own run_repair wrapper.
# ---------------------------------------------------------------------------
echo
echo "--- Step 5: repair-all-accounting.sh (9-step loop) ---"
if [[ "$DRY_RUN" -eq 1 ]]; then
  ./scripts/repair-all-accounting.sh --dry-run
else
  ./scripts/repair-all-accounting.sh
fi

# ---------------------------------------------------------------------------
# Step 6 — Post-repair validation
# ---------------------------------------------------------------------------
echo
echo "--- Step 6: Post-repair validate-accounts ---"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] $DC baker validate-accounts"
  $DC baker validate-accounts || true
else
  $DC baker validate-accounts
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "=== Dry run complete — no changes written ==="
  echo "Re-run without --dry-run to apply the repairs."
else
  echo "=== Production repair complete ==="
  echo "Backup: $BACKUP"
  echo "Compare pre/post validate-accounts output to confirm the baseline is clean."
  echo "Rollback: docker compose --profile prod stop baker-prod && cp $BACKUP prod/data/baker.db && docker compose --profile prod start baker-prod"
fi