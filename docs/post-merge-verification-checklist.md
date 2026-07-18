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

> **Note:** The `baker-prod` image (`python:3.12-slim`) does not ship `sqlite3` or `curl`. The DB is bind-mounted to the host at `./prod/data/baker.db` (`docker-compose.yml:12-13`), so run all SQL host-side from the bakery-shop project root. Stop the stack first for any WRITE operation.

```bash
sqlite3 ./prod/data/baker.db \
  "SELECT code, name FROM accounts ORDER BY CAST(code AS INTEGER);"
```

- [ ] **2.1** Account **2500** (Phải trả người bán / Accounts Payable) is present — exactly 1 row with `code = '2500'` (added by v73, release v0.7.14)
- [ ] **2.1a** Account **2400** (Tiền Rút Held) is present — exactly 1 row with `code = '2400'` (added by v54, prior release)
- [ ] **2.2** All seeded accounts are present (25 rows from `SEED_CHART_OF_ACCOUNTS`, `src/baker/db/schema.py:1524-1556`):
  - Assets (1000): 1000 (Tài sản), 1100 (Tiền mặt / Cash on Hand), 1200 (Tài khoản ngân hàng / Bank Account), 1300 (Hàng tồn kho / Inventory), 1500 (Phải thu khách hàng / Accounts Receivable)
  - Liabilities (2000): 2000 (Nợ phải trả), 2100 (Tiền khách đặt cọc / Customer Deposits), 2200 (Tiền ship bus giữ hộ / Bus Shipping Held), 2300 (Phải trả nhân viên / Staff Payables), 2400 (Tiền rút tạm giữ / Tien Rut Held), 2500 (Phải trả người bán / Accounts Payable)
  - Equity: 3000 (Vốn chủ sở hữu), 3100 (Vốn chủ sở hữu / Owner's Equity)
  - Income: 4000 (Doanh thu), 4100 (Doanh thu bán hàng / Order Revenue)
  - Expenses (5000): 5000 (Chi phí), 5100 (Nguyên liệu / Ingredients), 5200 (Bao bì / Packaging), 5300 (Vận chuyển / Delivery-Shipping), 5400 (Điện-nước / Utilities), 5500 (Dụng cụ / Tools), 5600 (Sửa chữa / Equipment Maintenance), 5700 (Lương-phụ cấp / Staff Salary), 5800 (Khác / Other Expenses), 5900 (Giá vốn hàng bán / COGS)
  - Note: runtime-created sub-accounts (23xx staff, 25xxx vendor per `_ensure_vendor_payable_sub_account`, `schema.py:1693-1747`) may add additional rows beyond the 24 seeded.
- [ ] **2.3** No duplicate account codes exist

**Direct account 2500 check:**

```bash
sqlite3 ./prod/data/baker.db \
  "SELECT code, name FROM accounts WHERE code IN ('2400', '2500');"
```

Expected: 2 rows — `2400|Tiền rút tạm giữ (Tien Rut Held)` and `2500|Phải trả người bán (Accounts Payable)`

---

## §3 Journal Integrity Check

Verify no orphaned journal lines and that all journal entries are internally consistent.

### 3.1 Orphaned Lines

```bash
sqlite3 ./prod/data/baker.db \
  "SELECT COUNT(*) FROM journal_lines WHERE journal_entry_id NOT IN (SELECT id FROM journal_entries);"
```

- [ ] **3.1** Result is **0** (no orphaned journal lines)

### 3.2 Journal Balance

Verify every journal entry balances (total debits = total credits):

```bash
sqlite3 ./prod/data/baker.db \
  "SELECT journal_entry_id, ROUND(SUM(debit) - SUM(credit), 2) AS balance
   FROM journal_lines
   GROUP BY journal_entry_id
   HAVING balance != 0;"
```

- [ ] **3.2** Result is **empty** (all journal entries balance)

### 3.3 Entry Count Sanity

```bash
sqlite3 ./prod/data/baker.db \
  "SELECT COUNT(*) AS journal_entries, (SELECT COUNT(*) FROM journal_lines) AS journal_lines FROM journal_entries;"
```

- [ ] **3.3** Row counts are reasonable for the deployment window (no massive increase or decrease compared to pre-migration counts)
- [ ] **3.3** No journal entries have zero lines

---

## §4 Account Balance Sanity

Spot-check key account balances for reasonableness.

### 4.1 Account 2400 and 2500 Balance

```bash
sqlite3 ./prod/data/baker.db \
  "SELECT a.code, ROUND(SUM(l.debit) - SUM(l.credit), 2) AS balance
   FROM journal_lines l JOIN accounts a ON a.id = l.account_id
   WHERE a.code IN ('2400', '2500')
   GROUP BY a.code
   ORDER BY CAST(a.code AS INTEGER);"
```

- [ ] **4.1** Account **2400** balance is **non-negative** (held amounts cannot go negative)
- [ ] **4.1a** Account **2500** (Phải trả người bán) balance is present and reconciles against outstanding vendor payable entries (added by v73 in release v0.7.14)

### 4.2 Key Account Balances

```bash
sqlite3 ./prod/data/baker.db \
  "SELECT a.code, ROUND(SUM(l.debit) - SUM(l.credit), 2) AS balance
   FROM journal_lines l JOIN accounts a ON a.id = l.account_id
   WHERE a.code IN ('1100', '4000', '5000')
   GROUP BY a.code
   ORDER BY CAST(a.code AS INTEGER);"
```

- [ ] **4.2** Account 1100 (Tiền mặt) balance is non-negative
- [ ] **4.2** Account 4000 (Doanh thu) balance is non-negative
- [ ] **4.2** Account 5000 (Chi phí) balance is non-negative

### 4.3 Material Balance Equation

Verify total debits equal total credits across the entire journal:

```bash
sqlite3 ./prod/data/baker.db \
  "SELECT
     (SELECT COALESCE(SUM(debit), 0) FROM journal_lines) -
     (SELECT COALESCE(SUM(credit), 0) FROM journal_lines) AS total_difference;"
```

- [ ] **4.3** Total debits minus total credits equals **0** (or rounding tolerance ≤ 1)

---

## §5 Application Health

Verify the running application is healthy and API endpoints respond.

### 5.1 Database Integrity

```bash
sqlite3 ./prod/data/baker.db "PRAGMA integrity_check;"
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
| §2 All 25 seeded accounts present | pass / fail | |
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
