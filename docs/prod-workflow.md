# Prod DB Workflow

This document explains how database migrations work in baker and how to safely update the production database.

---

## 1. Overview: How Migrations Work

Baker uses a `schema_version` table to track which migrations have been applied. The schema lives in `src/baker/db/schema.py` in the `MIGRATIONS` dict (keyed by version number).

**In development**, migrations run automatically every time any `baker` CLI command is invoked — via `ensure_schema()` in `src/baker/db/connection.py`. This is convenient but unsafe for production because:
- No backup is taken before migrating
- No way to preview what will change
- Migrations happen silently during normal operations

**In production**, use the explicit workflow described below.

---

## 2. Checking Prod DB Status Before Deploying

Before deploying a new version, check what migrations are pending:

```bash
baker db status
```

Example output (up to date):
```
Current schema version : 7
Latest available       : 7
Status                 : up to date

Applied migrations:
  v1 (2025-01-01 10:00): Initial schema
  v2 (2025-02-15 14:30): Add event categories
  ...
  v7 (2025-11-01 09:00): Add schema_version description
```

Example output (migrations pending):
```
Current schema version : 5
Latest available       : 7
Pending migrations     : 2
  v6: Add zalo_events table
  v7: Add schema_version description
```

You can also inspect the `schema_version` table directly:

```bash
sqlite3 /var/lib/baker/baker.db \
  "SELECT version, applied_at, description FROM schema_version ORDER BY version;"
```

---

## 3. Safe Update Procedure (Step by Step)

Follow these steps when deploying a new baker version that includes migrations.

### Before you start

1. Confirm current DB state:
   ```bash
   baker db status
   ```

2. Take a manual backup (extra safety):
   ```bash
   baker db backup
   # Creates: /var/lib/baker/baker-backup-YYYYMMDD-HHMMSS.db
   ```

3. Preview what will change (dry run):
   ```bash
   baker db migrate --dry-run
   ```

### Apply the update

4. Stop the baker service to prevent concurrent writes:
   ```bash
   sudo systemctl stop baker
   ```

5. Run migrations (automatically backs up first):
   ```bash
   baker db migrate
   ```
   Example output:
   ```
   Current version: v5
   Pending (2):
     v6: Add zalo_events table
     v7: Add schema_version description

   Backup: /var/lib/baker/baker-backup-pre-migrate-20251201-143000.db

   Migrations applied. Schema is now at v7.
   ```

6. Verify the migration succeeded:
   ```bash
   baker db status
   ```
   Should show: `Status : up to date`

7. Deploy the new baker binary (via NixOS rebuild or direct install).

8. Restart the service:
   ```bash
   sudo systemctl start baker
   sudo systemctl status baker
   ```

---

## 4. Using `scripts/prod-update.sh`

For a fully automated safe update, use the provided script:

```bash
# Preview only (no changes)
./scripts/prod-update.sh --dry-run

# Apply migrations + restart service
./scripts/prod-update.sh
```

The script:
1. Detects the prod config at `/etc/baker/baker.yaml` (or falls back to the nix store path)
2. Shows current DB status
3. Exits early if no migrations are pending
4. Stops the `baker` systemd service
5. Runs `baker db migrate` (which takes a backup automatically)
6. Verifies post-migration status
7. Restarts the service and confirms it is running

**Requirements:** Run as a user with `sudo` privileges for `systemctl stop/start baker`.

---

## 5. Recovery: If Something Goes Wrong

If a migration fails or the service doesn't start after migrating, restore from backup.

### Find the latest backup

```bash
ls -lt /var/lib/baker/baker-backup-*.db | head -5
```

### Restore the backup

```bash
# Stop service first
sudo systemctl stop baker

# Restore (replace the live DB with the backup)
sudo cp /var/lib/baker/baker-backup-pre-migrate-YYYYMMDD-HHMMSS.db \
        /var/lib/baker/baker.db

# Verify the restore
baker db status

# Restart
sudo systemctl start baker
sudo systemctl status baker
```

### If the service still won't start

Check logs:
```bash
journalctl -u baker -n 100
journalctl -u baker --since "10 minutes ago"
```

---

## 6. How to Add a New Migration

When adding a new schema change:

1. Open `src/baker/db/schema.py`

2. Add an entry to the `MIGRATIONS` dict with the next version number:
   ```python
   MIGRATIONS = {
       # ... existing migrations ...
       8: {
           "description": "Add customer_notes column",
           "sql": [
               "ALTER TABLE orders ADD COLUMN customer_notes TEXT",
           ],
       },
   }
   ```

3. The `sql` field is a list of SQL statements — all run in a single transaction.

4. Test locally:
   ```bash
   baker db status   # should show v8 pending
   baker db migrate --dry-run
   baker db migrate
   baker db status   # should show up to date at v8
   ```

5. Write a test in `tests/test_db_commands.py` that exercises the new version.

6. On prod deploy, use the procedure in §3 or `./scripts/prod-update.sh`.

---

## 7. Pre/Post-Migration Validation

The `scripts/db-validate.sh` script (and `baker db validate` CLI) captures database state before and after migrations, diffs the two snapshots, and reports anomalies. This replaces ad-hoc manual checks with a repeatable, auditable process.

### What it captures (8 metric categories)

1. **Row counts** — per user table (excluding `server_logs`)
2. **Financial lump sums** — orders total/by year/by month, delivered orders, deposits, expenses
3. **Stock position** — total remaining qty + available inventory items
4. **Journal trial balance** — per-account debit/credit totals
5. **Order status distribution** — count per status
6. **Event type distribution** — count per event type
7. **Journal totals** — total debit = total credit check
8. **Counts** — customer count + active product count

Plus: schema version and `PRAGMA integrity_check`.

### Step-by-step test workflow

```bash
# === 1. Pre-migration snapshot ===
./scripts/db-validate.sh snapshot --db-path ./data/baker.db --output /tmp/pre.json

# Verify snapshot is valid JSON with all 8 categories
python3 -c "import json; d=json.load(open('/tmp/pre.json')); \
  print('Schema:', d['schema_version']); \
  print('Tables:', len(d['metrics']['row_counts'])); \
  print('Integrity:', d['integrity_check'])"

# === 2. Run migration (or simulate) ===
baker db migrate --dry-run
# or: baker db migrate

# === 3. Post-migration snapshot ===
./scripts/db-validate.sh snapshot --db-path ./data/baker.db --output /tmp/post.json

# === 4. Diff and report ===
./scripts/db-validate.sh diff --pre /tmp/pre.json --post /tmp/post.json
# Exit 0 = clean, no anomalies
# Exit 1 = anomalies detected (printed to stderr)

# === 5. Test anomaly detection ===
# Simulate a bad migration by editing the post snapshot:
python3 -c "
import json; d=json.load(open('/tmp/pre.json'))
for r in d['metrics']['row_counts']:
    if r['tbl']=='orders': r['cnt']=1000
json.dump(d, open('/tmp/bad.json','w'), indent=2)
"
./scripts/db-validate.sh diff --pre /tmp/pre.json --post /tmp/bad.json
echo "Exit code: $?"  # Should be 1

# === 6. Python CLI (same output) ===
baker db validate --db-path ./data/baker.db --output /tmp/cli.json
baker db validate --pre /tmp/pre.json --post /tmp/pre.json

# === 7. Full prod workflow dry-run ===
./scripts/prod-update.sh --dry-run
# Shows validation steps in correct order:
#   pre-snapshot → integrity check → stop service → migrate → post-snapshot → diff → restart
```

### Anomaly types detected

| Anomaly | Trigger |
|---------|---------|
| Row count decrease | Any table has fewer rows after migration |
| Financial value decrease | Order count/value, deposits, or expenses drop |
| Stock position decrease | Remaining qty or available items drop |
| Balance drift | Any account debit/credit changes by > 0.01 VND |
| Distribution decrease | Order status or event type counts drop |
| Journal imbalance | Total debit ≠ total credit by > 0.01 VND |
| Count decrease | Customer or active product count drops |
| Schema version decrease | Version went backward |
| Integrity failure | `PRAGMA integrity_check` returns non-ok |

### Docker path

```bash
# Inside container or with mounted volume:
./scripts/db-validate.sh snapshot --db-path /var/lib/baker/baker.db --output /tmp/docker-snap.json
```

### Integration in prod-update.sh

The `prod-update.sh` script now runs validation automatically:

1. **Pre-migration:** Takes snapshot, checks integrity. If integrity fails → **aborts** (migration blocked).
2. **Post-migration:** Takes snapshot, runs diff. Anomalies reported but migration is **not rolled back** — Sinh decides.

## Quick Reference

| Command | What it does |
|---------|-------------|
| `baker db status` | Show current version and pending migrations |
| `baker db backup` | Create a timestamped backup of the DB |
| `baker db migrate --dry-run` | Preview pending migrations (no changes) |
| `baker db migrate` | Apply pending migrations (auto-backup first) |
| `baker db migrate --no-backup` | Apply without backup (not recommended for prod) |
| `./scripts/prod-update.sh --dry-run` | Full prod workflow preview |
| `./scripts/prod-update.sh` | Full prod update: validate → stop → backup → migrate → verify → restart |
| `./scripts/db-validate.sh snapshot` | Capture DB metrics snapshot to JSON |
| `./scripts/db-validate.sh diff` | Compare two snapshots, report anomalies |
| `baker db validate` | Same validation from Python CLI |
