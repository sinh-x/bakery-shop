# Migration Rollback & Recovery

How to recover the production database after a failed migration. Covers Docker-based baker deployments (prod profile).

---

## 1. Overview

The `baker db migrate` command automatically creates a timestamped backup before applying any pending migrations. If a migration fails — or the container won't start after migrating — this procedure restores the database to its pre-migration state.

**When to use this procedure:**
- `baker db migrate` fails with an error mid-migration
- The container restarts but healthcheck fails after a migration
- Application queries error with missing columns/tables after a migration
- Schema version is inconsistent with expected version

**When NOT to use:**
- The backup file itself is missing or corrupted (see §5 Edge Cases)
- Data entered after a successful migration was later found incorrect (this is a data repair problem, not a rollback)

---

## 2. Prerequisites

### Access
- Shell access to the production host
- Docker permissions (user in `docker` group or `sudo`)
- Working directory: the bakery-shop project root (where `docker-compose.yml` lives)

### Backup file location
Backups are created by `baker db migrate` in the same directory as the database:

| Context | Path |
|---------|------|
| Host (prod profile) | `./prod/data/baker-backup-pre-migrate-<YYYYmmdd-HHMMSS>.db` |
| Inside container | `/var/lib/baker/baker-backup-pre-migrate-<YYYYmmdd-HHMMSS>.db` |

The `./prod/data` directory on the host is mounted to `/var/lib/baker` inside the container (see `docker-compose.yml`, `baker-prod` service). Backup files are visible from both sides.

### Active database
| Context | Path |
|---------|------|
| Host | `./prod/data/baker.db` |
| Container | `/var/lib/baker/baker.db` |

---

## 3. Step-by-Step Recovery

### Step 1 — Stop the container

Stop the baker container to prevent any process from writing to the database during recovery:

```bash
docker compose --profile prod stop baker-prod
```

### Step 2 — Identify the pre-migration backup

List backups in the prod data directory, sorted by modification time (newest first):

```bash
ls -lt ./prod/data/baker-backup-pre-migrate-*.db | head -5
```

Example output:
```
-rw-r--r-- 1 sinh sinh 4194304 Jun 28 10:15 ./prod/data/baker-backup-pre-migrate-20260628-101500.db
-rw-r--r-- 1 sinh sinh 4186112 Jun 15 09:22 ./prod/data/baker-backup-pre-migrate-20260615-092200.db
```

The latest backup (top of the list) corresponds to the most recent migration attempt. Verify the timestamp matches when the migration was attempted.

If no backup file exists, see §5 Edge Cases.

### Step 3 — Verify the backup integrity

Before restoring, check the backup file is a valid SQLite database:

```bash
sqlite3 "./prod/data/baker-backup-pre-migrate-20260628-101500.db" "PRAGMA integrity_check;"
```

Expected output: `ok`

If the output is anything other than `ok`, the backup is corrupted — do not restore it. See §5 Edge Cases.

### Step 4 — Note the pre-migration schema version

Record the schema version from the backup (this will be confirmed after restore):

```bash
sqlite3 "./prod/data/baker-backup-pre-migrate-20260628-101500.db" \
  "SELECT MAX(version) FROM schema_version;"
```

### Step 5 — Copy the backup over the active database

Replace the live database with the pre-migration backup:

```bash
cp "./prod/data/baker-backup-pre-migrate-20260628-101500.db" "./prod/data/baker.db"
```

**Important:** Use `cp` (not `mv`). This preserves the backup file for forensic analysis if the rollback itself has issues.

### Step 6 — Restart the container

Start the baker container. The entrypoint (`docker-entrypoint.sh`) runs `baker db migrate`, which will be a no-op since the restored database is already at its pre-migration version:

```bash
docker compose --profile prod up -d baker-prod
```

### Step 7 — Wait for healthcheck

Wait for the container to report healthy (may take up to 40 seconds — healthcheck interval + start_period):

```bash
docker compose --profile prod ps baker-prod
```

The `STATUS` column should show `Up` with `(healthy)`.

---

## 4. Verification

After the container is healthy, verify the recovery was successful.

### 4.1 Confirm schema version

Check the database is at the expected pre-migration version:

```bash
docker compose --profile prod exec baker-prod baker db status
```

Compare the `Current schema version` with the value recorded in Step 3. They must match.

### 4.2 Confirm no pending migrations applied

The `baker db status` output should show `Status: up to date` (no pending migrations) — the restored database should be at whatever version it was before the migration attempt.

### 4.3 Journal integrity check

Verify the database journal is consistent:

```bash
docker compose --profile prod exec baker-prod \
  sqlite3 /var/lib/baker/baker.db "PRAGMA integrity_check;"
```

Expected output: `ok`

### 4.4 Health endpoint check

Confirm the API is responding:

```bash
docker compose --profile prod exec baker-prod \
  python -c "import urllib.request; urllib.request.urlopen('http://localhost:2108/api/health')"
```

No output means success (HTTP 200). An error trace means the application is unhealthy.

### 4.5 Check container logs for errors

```bash
docker compose --profile prod logs baker-prod --tail 50
```

Look for any migration errors, import errors, or tracebacks. A clean restart shows the entrypoint running `baker db migrate` (no-op) and `baker serve` starting successfully.

---

## 5. Edge Cases

### Missing backup file (`baker-backup-pre-migrate-*.db` not found)

**Causes:**
- `baker db migrate` was invoked with `--no-backup`
- Backup was manually deleted or never created
- Container's `/var/lib/baker` volume was not persistent (misconfigured mount)
- Migration failed before the backup step completed (the backup runs *before* any migration SQL)

**Recovery options (in order of preference):**
1. Check for manual backups: `ls -lt ./prod/data/baker-backup-*.db` (created by `baker db backup`)
2. Check for Docker volume snapshots or host filesystem snapshots
3. If no backup exists, the database cannot be restored to pre-migration state. Assess the damage:
   ```bash
   docker compose --profile prod exec baker-prod baker db status
   ```
   If the schema version is higher than expected but the database is functional, it may be safer to proceed forward (fix any remaining issues) rather than attempt a rollback without a backup.

### Container won't restart

**Causes:**
- Corrupted database file after bad `cp` (use Step 3 integrity check to prevent)
- File permissions changed (container runs as UID from `BAKER_UID`, default 1000)
- Disk full — `cp` succeeded but container writes fail on startup

**Checks:**
```bash
# Check DB file ownership (should be the same as before restore)
ls -la ./prod/data/baker.db

# Check available disk space
df -h ./prod/data/

# View container startup logs
docker compose --profile prod logs baker-prod --tail 100
```

### Data corruption indicators

If the restored database fails `PRAGMA integrity_check`, try:
1. Try a different backup file (older `baker-backup-pre-migrate-*.db` or `baker-backup-*.db`)
2. If the backup itself is corrupted but the active DB is still accessible, export journal data with `sqlite3 .dump` before replacing it
3. As a last resort, check if host filesystem snapshots (ZFS, btrfs, LVM) are available

### Multiple consecutive failed migrations

If the same migration fails repeatedly after rollback:
1. Leave the database at its working version (do not re-attempt migration)
2. Review the failing migration's SQL in `src/baker/db/schema.py` for data-dependent issues (e.g., `ALTER TABLE` on a column that already exists, `INSERT` violating a new constraint)
3. Run the migration in a cloned database to diagnose:
   ```bash
   cp ./prod/data/baker.db ./prod/data/baker-debug.db
   BAKER_DATA_DIR=./prod/data sqlite3 ./prod/data/baker-debug.db < migration-sql.sql
   ```
4. Fix the migration in code, redeploy, then run `baker db migrate` again on the (still-at-previous-version) database

---

## 6. Quick Reference

| Command | Purpose |
|---------|---------|
| `docker compose --profile prod stop baker-prod` | Stop the baker container |
| `ls -lt ./prod/data/baker-backup-pre-migrate-*.db` | List pre-migration backups (newest first) |
| `sqlite3 <backup> "PRAGMA integrity_check;"` | Verify backup integrity |
| `cp <backup> ./prod/data/baker.db` | Restore the backup |
| `docker compose --profile prod up -d baker-prod` | Start the container |
| `docker compose --profile prod ps baker-prod` | Check container health status |
| `docker compose --profile prod exec baker-prod baker db status` | Check schema version |
| `docker compose --profile prod exec baker-prod sqlite3 /var/lib/baker/baker.db "PRAGMA integrity_check;"` | Verify database integrity |
