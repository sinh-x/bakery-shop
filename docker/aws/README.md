# AWS application image assets

Phase 2 packages three images for the later ECS task definitions:

```bash
docker build -t baker-backend:dg426 .
docker build -f docker/aws/Dockerfile.web -t baker-web:dg426 .
docker build -f docker/aws/Dockerfile.backup -t baker-backup:dg426 .
```

- The backend remains non-root and keeps `BAKER_DATA_DIR=/var/lib/baker`.
- The web container runs as `caddy` on port 8080. `/healthz` checks Caddy
  itself; the ALB service health path should be `/api/health`, which is proxied
  to backend port 2108 over the shared ECS task network namespace.
- The backup container runs as UID 1000, mounts EFS at `/var/lib/baker`, and
  stages only a consistent SQLite backup plus database-referenced photos.
- Flutter, Caddy, Alpine, Rustic 0.11.4, and SQLite 3.50.4 sources are pinned.
  Rustic and SQLite downloads are SHA-256 verified during the image build.

The backup entrypoint requires an existing Rustic repository configuration. It
uses an atomic directory lock on EFS, verifies SQLite and `SHA256SUMS`, uploads
one snapshot under stable host `baker-aws-prod`, then applies 48 hourly, 7 daily,
4 weekly, and 3 monthly retention only to that host's `/baker` hourly snapshots.
Set `BACKUP_HOST` only when intentionally isolating another backup lineage.
Staging and the lock are removed on success and failure.

`verify-backup-restore.sh TARGET_DIR` is safe for isolated restores by default.
It rejects the active data directory unless an operator explicitly sets
`BAKER_ALLOW_PRODUCTION_RESTORE=true`; setting that value validates only and
does not copy or promote any data.
