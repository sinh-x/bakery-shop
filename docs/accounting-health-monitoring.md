# Accounting Health Monitoring

> Date: 2026-07-15
> Context: DG-245 (source-to-ledger reconciliation) + findings from live dev DB audit

## Quick Health Check

```bash
baker validate-accounts 2>&1 | grep -E "^(Overall|\[)"
```

## Known Gap Types and Repairs

| Gap | Check | Repair |
|-----|-------|--------|
| Missing payment_transaction JEs | `source_completeness` → `payment_transaction` rows | `baker repair-payment-journal --all` |
| Missing order revenue JEs | `source_completeness` → `order` rows | `baker repair-deposit-balance --all` |
| Cancelled orders with unreleased deposits | `deposit_balance_integrity` → `cancelled_with_deposits` | `baker repair-cancelled-orders --all` |
| Stale/missing COGS entries | `cogs_completeness`, `cogs_amount_accuracy` | `baker repair-order-revenue --cogs --all` |
| Negative inventory balance (1300) | `account_balance_sanity` | `baker repair-inventory --all` |
| Debt expense journal sync (2500) | `expense_payment_account_mismatch` | `baker repair-debt-expenses --all` |

## Architecture Risk: Silent Journal Sync Failures

`run_journal_sync` (journal_sync.py:94) wraps every journal sync in a try/except by design (NFR1: accounting failures must never block primary business operations). When a sync fails:

1. The API returns 200 OK — the business operation succeeds
2. `accountingSync: "failed"` is attached to the response — Flutter may not surface it prominently
3. The `journal_sync_failures` counter increments — surfaced via `/api/health`
4. The gap persists silently until `validate-accounts` catches it

**Evidence**: 18 payment_transactions from Mar–Jul 2026 have no journal entry. No entries in `journal_sync_failure_log` for them, suggesting the sync was either not called (direct DB import path) or the failure log did not exist at the time (DG-226 added it later).

## Recommended Monitoring Cadence

### Daily (automated)
- Monitor `/api/health` → `journal_sync_failures` counter. Alert if non-zero since last check.
- Run `baker validate-accounts` and alert on `source_completeness` or `double_entry_integrity` failures.

### Weekly (manual or cron)
```bash
# Check for any new journal gaps
baker validate-accounts

# Count recent gaps only
sqlite3 data/baker.db "
  SELECT pt.id, pt.created_at, pt.amount
  FROM payment_transactions pt
  LEFT JOIN journal_entries je ON je.source_type='payment_transaction' AND je.source_id=pt.id
  WHERE je.id IS NULL AND pt.created_at >= date('now', '-7 days')
  ORDER BY pt.created_at;
"
```

### After any deployment
- Run the full [post-merge-verification-checklist.md](post-merge-verification-checklist.md)
- Run `baker validate-accounts` and compare counts against last baseline

## Known False Positives (DG-247)

`cogs_amount_accuracy` currently reports ~631 false positives because the validator re-resolves costs at query time via `resolve_product_cost()` instead of using the `cost_at_sale` snapshot from `order_items`. After DG-247 is fixed, this check should report near-zero issues on a healthy DB.

## Live DB Baseline (2026-07-15)

```
Overall: fail (12/18 checks passed, 789 issues)

PASS: double_entry_integrity, waste_cogs_ref, cost_history_sanity,
      accounting_equation, cash_flow_integrity, lock_integrity,
      future_dated_entries, duplicate_entries, orphaned_lines,
      expense_category_mismatch, deposit_revenue_integrity,
      expense_payment_account_mismatch

FAIL: cogs_completeness (24), source_completeness (63),
      cogs_amount_accuracy (631), account_balance_sanity (1),
      deposit_balance_integrity (62), source_ledger_totals (8)
```

All failing checks have corresponding repair commands. Run them to establish a clean baseline, then monitor for regressions.
