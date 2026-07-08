# Dev Verification Workflow

> **Purpose:** Step-by-step guide to deploy and test a feature branch in the dev Docker environment before merging to `develop`.
> **Audience:** Sinh (developer)
> **Created:** 2026-07-05

---

## When to Run

Run after completing implementation on a feature branch, before creating a PR or merging. This workflow validates that the feature works end-to-end in a containerized environment matching production.

---

## Prerequisites

- [ ] Feature branch is pushed to GitHub
- [ ] All tests pass locally: `python -m pytest tests -v`
- [ ] Lint is clean: `python -m ruff check src tests --select E9,F63,F7,F82`
- [ ] Docker is running (`docker info`)
- [ ] `./data/baker.db` exists (or synced from prod via `./scripts/sync-prod-to-dev.sh`)

---

## §1 Build and Deploy to Dev

### 1.1 Build the dev container

```bash
docker compose --profile dev build --no-cache baker-dev
```

- [ ] Build completes with no errors
- [ ] No warnings about missing files or broken imports

### 1.2 Start the dev container

```bash
docker compose --profile dev up -d baker-dev
```

### 1.3 Wait for healthcheck

```bash
# Check status (may take up to 40s for healthcheck)
docker compose --profile dev ps baker-dev
```

- [ ] Status shows `Up` with `(healthy)`

### 1.4 Verify API responds

```bash
curl -s http://localhost:2312/api/health | python3 -m json.tool
```

- [ ] Response includes `"status": "ok"`

---

## §2 Run Migrations in Dev

### 2.1 Check current schema version

```bash
docker compose --profile dev exec baker-dev baker db status
```

- [ ] Output shows current version and pending migrations (if any)

### 2.2 Preview migrations (dry run)

```bash
docker compose --profile dev exec baker-dev baker db migrate --dry-run
```

- [ ] Lists pending migrations without errors

### 2.3 Apply migrations

```bash
docker compose --profile dev exec baker-dev baker db migrate
```

- [ ] Migrations apply successfully
- [ ] Backup file created in `./data/`

### 2.4 Verify post-migration status

```bash
docker compose --profile dev exec baker-dev baker db status
```

- [ ] Status shows "up to date"

---

## §3 Feature-Specific Verification

Run the tests specific to the feature being deployed. Adapt this section per feature.

### 3.1 Run the test suite inside the container

```bash
docker compose --profile dev exec baker-dev python -m pytest /app/tests -v --tb=short
```

- [ ] All tests pass

### 3.2 Run lint inside the container

```bash
docker compose --profile dev exec baker-dev python -m ruff check /app/src /app/tests --select E9,F63,F7,F82
```

- [ ] No lint errors

### 3.3 Test new CLI commands

For each new or modified CLI command, run it inside the container:

```bash
# Example: test a new subcommand
docker compose --profile dev exec baker-dev baker <command> <args>
```

- [ ] Command runs without errors
- [ ] Output matches expected format

### 3.4 Test new API endpoints

For each new or modified API endpoint:

```bash
# Example: test a new endpoint
curl -s http://localhost:2312/api/<endpoint> | python3 -m json.tool
```

- [ ] Response is valid JSON
- [ ] Response data matches expected schema

---

## §4 Pre/Post-Migration Validation (if applicable)

When the feature includes schema migrations, run the validation procedure.

### 4.1 Pre-migration snapshot

```bash
# From host (DB is mounted at ./data/baker.db)
./scripts/db-validate.sh snapshot --db-path ./data/baker.db --output /tmp/dev-pre.json
```

Or from inside the container:

```bash
docker compose --profile dev exec baker-dev \
  baker db validate --db-path /var/lib/baker/baker.db --output /tmp/dev-pre.json
```

- [ ] Snapshot created successfully
- [ ] JSON contains all 8 metric categories

### 4.2 Verify snapshot integrity

```bash
python3 -c "
import json
d = json.load(open('/tmp/dev-pre.json'))
print('Schema version:', d['schema_version'])
print('Integrity:', d['integrity_check'])
print('Tables:', len(d['metrics']['row_counts']))
print('Orders:', d['metrics']['financial']['orders_total'])
"
```

- [ ] Integrity check is `ok`
- [ ] Schema version matches expected

### 4.3 Post-migration snapshot

```bash
./scripts/db-validate.sh snapshot --db-path ./data/baker.db --output /tmp/dev-post.json
```

### 4.4 Diff and check for anomalies

```bash
./scripts/db-validate.sh diff --pre /tmp/dev-pre.json --post /tmp/dev-post.json
echo "Exit: $?"
```

- [ ] Exit code is 0 (no anomalies)
- [ ] All metric changes are expected (e.g., schema version increased)

### 4.5 Test anomaly detection

```bash
# Simulate a bad migration
python3 -c "
import json; d=json.load(open('/tmp/dev-pre.json'))
for r in d['metrics']['row_counts']:
    if r['tbl']=='orders': r['cnt']=1000
json.dump(d, open('/tmp/dev-bad.json','w'), indent=2)
"
./scripts/db-validate.sh diff --pre /tmp/dev-pre.json --post /tmp/dev-bad.json
echo "Exit: $?"  # Should be 1
```

- [ ] Anomaly detected and reported to stderr
- [ ] Exit code is 1

---

## §5 Container Health Checks

### 5.1 Database integrity

```bash
docker compose --profile dev exec baker-dev \
  sqlite3 /var/lib/baker/baker.db "PRAGMA integrity_check;"
```

- [ ] Result is `ok`

### 5.2 Container logs

```bash
docker compose --profile dev logs baker-dev --tail 50
```

- [ ] No migration errors, tracebacks, or unexpected warnings
- [ ] Entrypoint shows `baker db migrate` ran successfully
- [ ] Uvicorn/FastAPI started and listening on port 2312

### 5.3 Journal integrity (if accounting feature)

```bash
docker compose --profile dev exec baker-dev \
  sqlite3 /var/lib/baker/baker.db \
  "SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS imbalance FROM journal_lines;"
```

- [ ] Imbalance is 0 (or within rounding tolerance)

---

## §6 HTTPS Access via Tailscale MagicDNS (Dev Caddy)

The dev stack can be exposed over HTTPS on the Tailscale tailnet via the `caddy-dev` service, mirroring the prod `caddy` setup. This lets you verify the Flutter web app and API from a browser on any tailnet device using the drgnfly MagicDNS hostname.

### 6.1 Prerequisites

- [ ] Tailscale is connected on this host (`tailscale status` shows the node)
- [ ] TLS cert exists for the dev domain: `./certs/drgnfly.tail10c2c6.ts.net.crt` and `.key`
  - Renew/generate with: `./scripts/renew-certs.sh drgnfly.tail10c2c6.ts.net`
- [ ] Fresh web bundle is built (so `web-build/` is up to date):
  ```bash
  cd app && flutter build web --release
  # or: ./scripts/deploy-web.sh
  ```

### 6.2 Validate the dev Caddyfile

`caddy validate` additionally loads the TLS certificates referenced by the `tls` directive, which fails in a syntax-only check without the cert files mounted. Use `caddy adapt` instead for a syntax-only check that works without certs (it renders the Caddyfile to its JSON config and exits 0 if the syntax is valid):

```bash
docker run --rm -v "$(pwd)/Caddyfile.dev:/etc/caddy/Caddyfile:ro" \
  -e DOMAIN=drgnfly.tail10c2c6.ts.net caddy:2-alpine \
  caddy adapt --config /etc/caddy/Caddyfile
```

- [ ] Exits 0 and emits valid JSON (syntax valid). Note: full `caddy validate` additionally loads certs, so `caddy adapt` is used here for syntax-only checks.

### 6.3 Start the dev stack with caddy

```bash
docker compose --profile dev up -d
```

This starts both `baker-dev` and `caddy-dev`. The caddy-dev container publishes host port `443` and serves the Flutter web app + reverse-proxies `/api/*` to `baker-dev:2312` over the tailnet TLS cert.

### 6.4 Verify HTTPS access

Open in a browser on any tailnet device:

```
https://drgnfly.tail10c2c6.ts.net
```

- [ ] App loads with valid TLS (no cert warning)
- [ ] `/api/health` responds 200:
  ```bash
  curl -sf https://drgnfly.tail10c2c6.ts.net/api/health
  ```
- [ ] SPA deep-link fallback works (e.g. navigate to a client-side route and reload)

### 6.5 Stop the dev stack

```bash
docker compose --profile dev stop
```

---

## §7 Cleanup

### 7.1 Stop the dev container

```bash
docker compose --profile dev stop baker-dev
```

### 7.2 Remove temp files

```bash
rm -f /tmp/dev-pre.json /tmp/dev-post.json /tmp/dev-bad.json
```

### 7.3 Restore dev DB if needed

If the dev DB was modified during testing and you want to restore it:

```bash
# Restore from the pre-migration backup created by baker db migrate
ls -lt ./data/baker-backup-pre-migrate-*.db | head -1
# cp ./data/baker-backup-pre-migrate-<timestamp>.db ./data/baker.db
```

---

## Sign-Off

| Check | Result | Notes |
|-------|--------|-------|
| §1 Dev container healthy | pass / fail | |
| §2 Migrations applied | pass / fail | |
| §3 Tests pass in container | pass / fail | |
| §3 Lint clean in container | pass / fail | |
| §3 New CLI commands work | pass / fail | |
| §3 New API endpoints work | pass / fail | |
| §4 Pre-migration snapshot | pass / fail | |
| §4 Post-migration diff clean | pass / fail | |
| §4 Anomaly detection works | pass / fail | |
| §5 DB integrity ok | pass / fail | |
| §5 Container logs clean | pass / fail | |
| §6 Dev caddy HTTPS valid | pass / fail | |
| §7 Cleanup done | pass / fail | |

### Reviewer

- **Name:** Sinh
- **Date:** _________
- **Feature branch:** _________
- **Ticket:** _________

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `docker compose --profile dev build --no-cache baker-dev` | Rebuild dev container |
| `docker compose --profile dev up -d baker-dev` | Start dev container |
| `docker compose --profile dev ps baker-dev` | Check container health |
| `docker compose --profile dev exec baker-dev baker db status` | Check schema version |
| `docker compose --profile dev exec baker-dev baker db migrate` | Apply migrations |
| `docker compose --profile dev exec baker-dev python -m pytest /app/tests -v` | Run tests in container |
| `docker compose --profile dev logs baker-dev --tail 50` | View container logs |
| `docker compose --profile dev stop baker-dev` | Stop dev container |
| `docker compose --profile dev up -d` | Start full dev stack (baker-dev + caddy-dev) |
| `docker run --rm -v "$(pwd)/Caddyfile.dev:/etc/caddy/Caddyfile:ro" -e DOMAIN=drgnfly.tail10c2c6.ts.net caddy:2-alpine caddy adapt --config /etc/caddy/Caddyfile` | Validate dev Caddyfile (syntax-only via adapt; full `caddy validate` additionally loads certs) |
| `./scripts/renew-certs.sh drgnfly.tail10c2c6.ts.net` | Renew/generate dev TLS cert |
| `./scripts/db-validate.sh snapshot --db-path ./data/baker.db` | Capture DB snapshot |
| `./scripts/db-validate.sh diff --pre pre.json --post post.json` | Diff two snapshots |
