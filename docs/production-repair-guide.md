# Production Repair Guide

> Date: 2026-07-20
> Context: DG-268 / Release v0.8.0 Phase 4 — production accounting repair documentation
> Audience: Sinh (operator on lily production)
> Related: [accounting-health-monitoring.md](accounting-health-monitoring.md), [scripts/repair/production-repair.sh](../scripts/repair/production-repair.sh), [scripts/repair-all-accounting.sh](../scripts/repair-all-accounting.sh)

## Purpose

Establish a clean journal baseline on the lily production database by running, in dependency-safe order, every accounting repair subcommand shipped through v0.8.0. The sequence:

1. Backs up the live SQLite DB
2. Pre-validates the current state (`validate-accounts`)
3. Runs each repair subcommand once with `--dry-run` first, then for real
4. Re-validates post-repair
5. Documents rollback in case the baseline looks wrong

## Prerequisites

- `docker compose --profile prod` running on lily with `baker-prod` healthy
- All v0.8.0 code deployed to lily (the repair subcommands `repair-delivered-dates` and `repair-unallocated-transfers` shipped in this release)
- Free disk for the backup copy of `prod/data/baker.db` (~size of the live DB)
- Operator is Sinh — this guide performs mutations on production data

## Dependency-Safe Order (FR5)

The order is **load-bearing** — running steps out of order can create duplicate journal entries or leave deposit-balance entries in place before the AR-entry backfill tries to cover the same orders. Specifically, deposit-style revenue JEs must exist *before* `repair-ar-entries` runs, so that `repair-ar-entries` skips orders already covered by a deposit JE (DG-249 Phase 2 guard).

```
backup → validate-accounts (pre)
       → repair-delivered-dates
       → repair-unallocated-transfers
       → repair-all-accounting.sh
            1/9  repair-inventory
            2/9  repair-order-revenue --cogs
            3/9  repair-payment-journal
            4/9  repair-unallocated-transfers   ← re-run here is idempotent no-op
            5/9  repair-deposit-balance
            6/9  repair-cancelled-orders
            7/9  repair-delivered-dates          ← re-run here is idempotent no-op
            8/9  repair-ar-entries
            9/9  repair-debt-expenses
       → validate-accounts (post)
```

`repair-delivered-dates` and `repair-unallocated-transfers` are run *before* the `repair-all-accounting.sh` loop because they fix historical transaction dates and asset-account routing that the downstream deposit-balance and AR-entry backfills depend on. The same two subcommands are also embedded in `repair-all-accounting.sh` at their correct positions (steps 4/9 and 7/9) — re-running them there is idempotent and a no-op on the second pass. Note: `repair-delivered-dates` has no `--all` flag — it always scans the whole DB; `repair-unallocated-transfers` requires `--all` (or `--order-id`) to run.

## Step-by-Step

All `docker compose exec` commands assume you are in the repo root on lily. Replace timestamps in backup filenames as needed.

### Step 1 — Backup (REQUIRED before any mutation)

```bash
BACKUP="prod/data/baker.db.backup-v080-$(date +%Y%m%d-%H%M%S)"
cp prod/data/baker.db "$BACKUP"
echo "Backup: $BACKUP"
```

The `production-repair.sh` script aborts if this backup target already exists, to prevent overwriting a prior backup. If you re-run the script, move the old backup aside first or pick a fresh timestamp.

### Step 2 — Pre-repair validation

```bash
docker compose --profile prod exec -T baker-prod baker validate-accounts 2>&1 | tee /tmp/validate-pre.txt
```

Save the pre-repair count. After repair, the same command should report `Overall: pass` (or a substantially smaller issue count modulo the known DG-247 `cogs_amount_accuracy` false positives).

### Step 3 — Dry-run every repair first (REQUIRED)

Always preview the mutations before applying. The bundled script does this for you:

```bash
./scripts/repair/production-repair.sh --dry-run
```

Expected behavior: prints each repair command that *would* run, exits 0, writes nothing to the DB. Review the output — if any step reports an unexpected number of mutations, stop and investigate before continuing.

### Step 4 — Apply the repairs

Run the bundled script without `--dry-run`:

```bash
./scripts/repair/production-repair.sh
```

The script is idempotent — re-running it after a successful run is safe; every repair subcommand is a no-op on a clean DB. The script performs, in order: backup (Step 1), pre-validation (Step 2), `repair-delivered-dates`, `repair-unallocated-transfers`, `repair-all-accounting.sh` (the full 9-step loop), and post-validation.

If you prefer to drive the commands manually instead of the script, the equivalent sequence is:

```bash
# backup (Step 1) and pre-validation (Step 2) as above
docker compose --profile prod exec -T baker-prod baker repair-delivered-dates
docker compose --profile prod exec -T baker-prod baker repair-unallocated-transfers --all
./scripts/repair-all-accounting.sh
# post-validation (Step 5) as below
```

### Step 5 — Post-repair validation

```bash
docker compose --profile prod exec -T baker-prod baker validate-accounts 2>&1 | tee /tmp/validate-post.txt
diff /tmp/validate-pre.txt /tmp/validate-post.txt
```

Expected: issue counts drop across `source_completeness`, `deposit_balance_integrity`, `cogs_completeness`, `account_balance_sanity`, `expense_payment_account_mismatch`. `cogs_amount_accuracy` may still show ~631 false positives (DG-247, deferred).

## Rollback

If the post-repair validation regresses an unexpected check, roll back to the backup:

```bash
# Stop the API first so no new journal writes happen during restore
docker compose --profile prod stop baker-prod

cp "$BACKUP" prod/data/baker.db

docker compose --profile prod start baker-prod
docker compose --profile prod exec -T baker-prod baker validate-accounts
```

The repair subcommands are one-directional migrations (asset re-route to 1290, transaction_date rebasing to delivered timestamp). Rolling back the *data* via the DB backup is supported; rolling back by re-running the inverse of each repair subcommand is not — there is no `unrepair` command.

## Notes

- All repairs are idempotent. A clean DB produces zero mutations on every subcommand.
- The `repair-unallocated-transfers` subcommand only touches `method = 'transfer'` payment transactions with empty `payment_source` — cash/card transactions and transactions with an explicit payment_source are untouched.
- The `repair-delivered-dates` subcommand skips locked journal entries; locked entries keep their original `transaction_date`.
- See [accounting-health-monitoring.md](accounting-health-monitoring.md) for the gap-to-repair mapping table and the recommended monitoring cadence after the baseline is clean.