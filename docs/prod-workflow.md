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

## Quick Reference

| Command | What it does |
|---------|-------------|
| `baker db status` | Show current version and pending migrations |
| `baker db backup` | Create a timestamped backup of the DB |
| `baker db migrate --dry-run` | Preview pending migrations (no changes) |
| `baker db migrate` | Apply pending migrations (auto-backup first) |
| `baker db migrate --no-backup` | Apply without backup (not recommended for prod) |
| `./scripts/prod-update.sh --dry-run` | Full prod workflow preview |
| `./scripts/prod-update.sh` | Full prod update: stop → backup → migrate → verify → restart |
