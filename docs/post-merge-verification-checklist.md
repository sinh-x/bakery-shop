# Post-Merge Production Verification Checklist

> **Purpose:** Verify production database health after merging `feature/DG-175-double-entry-accounting` and deploying to production.
> **Audience:** Sinh (app owner/developer)
> **Created:** 2026-06-28
> **Updated:** 2026-07-18 (refreshed for release v0.7.14 — schema v75 and account 2500; supersedes stale v54 / account-2400-only checks)
> **Related:** [DG-175 Branch Rollout Plan](../agent-teams/requirements/artifacts/2026-06-28-dg175-branch-rollout-migration-plan.md), [UAT TS-5](../agent-teams/requirements/artifacts/2026-06-28-dg175-branch-rollout-migration-plan-uat.md), [Release v0.7.14 Rollback Plan](../agent-teams/builder/artifacts/2026-07-18-release-v0.7.14-rollback-plan.md)

---

## When to Run This Checklist

Run immediately after:
1. The `feature/DG-175-double-entry-accounting` branch has been merged into `develop`
2. The merged code has been deployed to production (`docker compose --profile prod up -d`)
3. The production container reports healthy

All checks are **Must** — this is a production health gate. If any check fails, stop and investigate before declaring the rollout successful.

---

## Prerequisites

- [ ] Production container is healthy: `docker compose --profile prod ps baker-prod` shows `(healthy)`
- [ ] Production host shell access confirmed
- [ ] Working directory: bakery-shop project root (where `docker-compose.yml` lives)

---

## §1 Schema Version Check

Verify the database is at the expected maximum schema version.

**Check:**

```bash
docker compose --profile prod exec baker-prod baker db status
```

- [ ] **1.1** Current schema version is **75**
- [ ] **1.2** Status shows **"up to date"** (no pending migrations)
- [ ] **1.3** No errors or tracebacks in the output

**Expected output example:**
```
Current schema version: 75
Status: up to date
```

> **v0.7.14 note:** Migrations v68–v75 cover auth RBAC (v68–v72), chart-of-accounts account 2500 (v73), NULL `customer_id` backfill (v74), and primary `customer_phones` backfill (v75). All are additive or idempotent. If `baker db status` reports a version less than 75, run `baker db migrate` and re-check.

---

## §2 Chart of Accounts Completeness

Verify all expected accounts exist in the chart of accounts, including the newly added account 2500 (Phải trả người bán / Accounts Payable) for release v0.7.14, alongside the previously added account 2400 (Tiền Rút Held).

**Check:**

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db \
  "SELECT code, name_vn FROM accounts ORDER BY CAST(code AS INTEGER);"
```

- [ ] **2.1** Account **2500** (Phải trả người bán / Accounts Payable) is present — exactly 1 row with `code = '2500'` (added by v73, release v0.7.14)
- [ ] **2.1a** Account **2400** (Tiền Rút Held) is present — exactly 1 row with `code = '2400'` (added by v54, prior release)
- [ ] **2.2** All standard accounts are present: 1100 (Tiền mặt), 1200 (Tiền gửi NH), 1300 (Phải thu KH), 1400 (Hàng tồn kho), 1500 (TSCĐ), 2100 (Phải trả NB), 2200 (Phải trả NV), 2300 (Vay NH), 2400 (Tiền Rút Held), 2500 (Phải trả người bán), 3000 (Vốn CSH), 4000 (Doanh thu), 4100 (Doanh thu đặt cọc), 4200 (Doanh thu SP tặng), 5000 (Giá vốn), 5100 (Giá vốn SP tặng), 6000 (Chi phí bán hàng), 6100 (Chi phí QLDN), 6200 (Chi phí vận chuyển), 6300 (Chi phí lương), 6400 (Chi phí khác), 7000 (Xác định KQKD)
- [ ] **2.3** No duplicate account codes exist

**Direct account 2500 check:**

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db \
  "SELECT code, name_vn FROM accounts WHERE code IN ('2400', '2500');"
```

Expected: 2 rows — `2400|Tiền Rút Held` and `2500|Phải trả người bán (Accounts Payable)`

---

## §3 Journal Integrity Check

Verify no orphaned journal lines and that all journal entries are internally consistent.

### 3.1 Orphaned Lines

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db \
  "SELECT COUNT(*) FROM journal_lines WHERE journal_entry_id NOT IN (SELECT id FROM journal_entries);"
```

- [ ] **3.1** Result is **0** (no orphaned journal lines)

### 3.2 Journal Balance

Verify every journal entry balances (total debits = total credits):

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db \
  "SELECT journal_entry_id, ROUND(SUM(CASE WHEN side = 'debit' THEN amount ELSE -amount END), 2) AS balance
   FROM journal_lines
   GROUP BY journal_entry_id
   HAVING balance != 0;"
```

- [ ] **3.2** Result is **empty** (all journal entries balance)

### 3.3 Entry Count Sanity

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db \
  "SELECT COUNT(*) AS journal_entries, (SELECT COUNT(*) FROM journal_lines) AS journal_lines FROM journal_entries;"
```

- [ ] **3.3** Row counts are reasonable for the deployment window (no massive increase or decrease compared to pre-migration counts)
- [ ] **3.3** No journal entries have zero lines

---

## §4 Account Balance Sanity

Spot-check key account balances for reasonableness.

### 4.1 Account 2400 and 2500 Balance

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db \
  "SELECT account_code,
      COALESCE(SUM(CASE WHEN side = 'debit' THEN amount ELSE 0 END), 0) -
      COALESCE(SUM(CASE WHEN side = 'credit' THEN amount ELSE 0 END), 0) AS balance
    FROM journal_lines
    WHERE account_code IN ('2400', '2500')
    GROUP BY account_code
    ORDER BY CAST(account_code AS INTEGER);"
```

- [ ] **4.1** Account **2400** balance is **non-negative** (held amounts cannot go negative)
- [ ] **4.1a** Account **2500** (Phải trả người bán) balance is present and reconciles against outstanding vendor payable entries (added by v73 in release v0.7.14)

### 4.2 Key Account Balances

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db \
  "SELECT account_code,
     COALESCE(SUM(CASE WHEN side = 'debit' THEN amount ELSE 0 END), 0) -
     COALESCE(SUM(CASE WHEN side = 'credit' THEN amount ELSE 0 END), 0) AS balance
   FROM journal_lines
   WHERE account_code IN ('1100', '4000', '5000')
   GROUP BY account_code
   ORDER BY CAST(account_code AS INTEGER);"
```

- [ ] **4.2** Account 1100 (Tiền mặt) balance is non-negative
- [ ] **4.2** Account 4000 (Doanh thu) balance is non-negative
- [ ] **4.2** Account 5000 (Giá vốn) balance is non-negative

### 4.3 Material Balance Equation

Verify total debits equal total credits across the entire journal:

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db \
  "SELECT
     (SELECT COALESCE(SUM(amount), 0) FROM journal_lines WHERE side = 'debit') -
     (SELECT COALESCE(SUM(amount), 0) FROM journal_lines WHERE side = 'credit') AS total_difference;"
```

- [ ] **4.3** Total debits minus total credits equals **0** (or rounding tolerance ≤ 1)

---

## §5 Application Health

Verify the running application is healthy and API endpoints respond.

### 5.1 Database Integrity

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db "PRAGMA integrity_check;"
```

- [ ] **5.1** Result is **`ok`**

### 5.2 Database Status

```bash
docker compose --profile prod exec baker-prod baker db status
```

- [ ] **5.2** Output shows healthy status, no errors

### 5.3 Health Endpoint

```bash
docker compose --profile prod exec baker-prod \
  python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:2108/api/health').status)"
```

- [ ] **5.3** API health endpoint returns HTTP **200**

### 5.4 Chart of Accounts API

Verify the API returns the chart of accounts including account 2400 and account 2500:

```bash
docker compose --profile prod exec baker-prod \
  python -c "
import urllib.request, json
resp = urllib.request.urlopen('http://localhost:2108/api/accounts')
data = json.loads(resp.read())
codes = [a['code'] for a in data]
print('Account 2400 present:', '2400' in codes)
print('Account 2500 present:', '2500' in codes)
print('Total accounts:', len(codes))
"
```

- [ ] **5.4** Response includes account **2400**
- [ ] **5.4** Response includes account **2500** (release v0.7.14)
- [ ] **5.4** Total account count is reasonable (20+ accounts)

### 5.5 Container Logs

```bash
docker compose --profile prod logs baker-prod --tail 50
```

- [ ] **5.5** No migration errors, tracebacks, or unexpected warnings in recent logs
- [ ] **5.5** Entrypoint shows `baker db migrate` ran successfully (or reported up-to-date)
- [ ] **5.5** Uvicorn/FastAPI started and is listening

---

## §6 Regression Check

Run a quick end-to-end smoke test to verify core functionality.

- [ ] **6.1** Create a test order via API (or mobile app) — order creates without error
- [ ] **6.2** Journal entries are auto-generated for the test order
- [ ] **6.3** Order list API returns the test order with correct data
- [ ] **6.4** Delete the test order after verification

---

## Sign-Off

| Check | Result | Notes |
|-------|--------|-------|
| §1 Schema version = 75 | pass / fail | |
| §2 Chart of accounts (2500 present) | pass / fail | |
| §2 Chart of accounts (2400 present) | pass / fail | |
| §2 All 22+ accounts present | pass / fail | |
| §3 Journal orphaned lines = 0 | pass / fail | |
| §3 Journal entries balance | pass / fail | |
| §4 Account 2400 balance ≥ 0 | pass / fail | |
| §4 Account 2500 balance present | pass / fail | |
| §4 Total debits = total credits | pass / fail | |
| §5 PRAGMA integrity_check ok | pass / fail | |
| §5 API health endpoint 200 | pass / fail | |
| §5 Accounts API includes 2400 + 2500 | pass / fail | |
| §6 End-to-end smoke test | pass / fail | |

### Reviewer

- **Name:** Sinh
- **Date:** _________
- **Deployment version:** _________
- **Schema version confirmed:** _________

---

## Troubleshooting

### Schema version is not 75
- Run `baker db migrate` from inside the container: `docker compose --profile prod exec baker-prod baker db migrate`
- Check container logs for migration errors: `docker compose --profile prod logs baker-prod --tail 100`
- If a migration crashed and you need to revert the deploy, follow the [Release v0.7.14 Rollback Plan](../agent-teams/builder/artifacts/2026-07-18-release-v0.7.14-rollback-plan.md).

### Account 2400 or 2500 is missing
- The v54 (2400) or v73 (2500) migration may not have run. Execute it manually: ensure `baker db migrate` ran and re-check.
- If migration ran but the account is still missing, review `src/baker/db/schema.py` for `_migrate_v54_add_account_2400()` / `_migrate_v73_add_account_2500()` (both call `_seed_chart_of_accounts` with `INSERT OR IGNORE`).

### Orphaned journal lines found
- This indicates a data integrity issue from a prior bug. Document the count and affected entry IDs.
- The repair commands (`baker repair ...`) may address this — check `src/baker/commands/repair.py`.
- Do NOT proceed with rollout success declaration until orphaned lines are resolved.

### Account balances show inconsistencies
- Total debits ≠ total credits: this indicates a journal integrity violation. Review journal entries for the affected accounts.
- Negative balance on asset accounts (1100, 1200, etc.): this is a data error. Investigate the journal lines for that account.

### Health endpoint returns non-200
- Check container logs: `docker compose --profile prod logs baker-prod --tail 100`
- Verify the container is running: `docker compose --profile prod ps baker-prod`
- Check for port conflicts or binding issues
