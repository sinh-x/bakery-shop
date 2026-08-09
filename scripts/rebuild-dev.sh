#!/usr/bin/env bash
# Rebuild Flutter web app and bring up the dev Docker stack in one shot.
# Usage: ./scripts/rebuild-dev.sh [--check] [--clean-failures]
#   (default)          Build + deploy + health check.
#   --check            Run CI-equivalent checks (ruff, fast-gate tests,
#                      compose config, Docker build) before building.
#   --clean-failures   Clear journal_sync_failure_log after deploy (dev only).
set -euo pipefail

RUN_CHECKS=false
CLEAN_FAILURES=false
for arg in "${@}"; do
  case "$arg" in
    --check)           RUN_CHECKS=true ;;
    --clean-failures)  CLEAN_FAILURES=true ;;
    *)                 echo "Usage: $0 [--check] [--clean-failures]" >&2; exit 1 ;;
  esac
done

source "$(dirname "$0")/lib.sh"
load_env

# ---------------------------------------------------------------------------
# Pre-flight: verification checks matching CI pipeline (--check only)
# ---------------------------------------------------------------------------

if $RUN_CHECKS; then
  echo "======================================================================"
  echo "  Pre-flight: CI-equivalent verification"
  echo "======================================================================"

  # ruff lint (CI fast-gate / python-tests lint step)
  echo
  echo "--- [1/4] Ruff lint (E9,F63,F7,F82) ---"
  python -m ruff check src tests --select E9,F63,F7,F82
  echo "  ruff: ok"

  # fast gate tests (CI fast-gate job — skips xdist, no -n auto)
  echo
  echo "--- [2/4] Fast gate tests (markers: fast or critical) ---"
  BAKER_BCRYPT_ROUNDS="${BAKER_BCRYPT_ROUNDS:-4}" \
    python -m pytest tests -v -m "fast or critical"
  echo "  fast gate tests: ok"

  # compose prod config validation (CI docker-build guard)
  echo
  echo "--- [3/4] Compose prod config validation ---"
  docker compose --profile prod config >/dev/null
  echo "  compose config: ok"

  # Docker image build (CI docker-build job)
  echo
  echo "--- [4/4] Docker image build ---"
  docker build --quiet -t bakery-shop:dev-check . >/dev/null
  echo "  docker build: ok"

  echo
  echo "======================================================================"
  echo "  Pre-flight: all checks passed"
  echo "======================================================================"
fi

# ---------------------------------------------------------------------------
# Build and deploy
# ---------------------------------------------------------------------------

# Step 1 — rebuild Flutter web bundle
echo
echo "=== Step 1: Rebuild Flutter web ==="
build_flutter_web "$(compute_build_fingerprint)"

# Step 2 — bring up dev Docker stack (baker-dev + caddy-dev)
echo
echo "=== Step 2: Bring up dev Docker stack ==="
docker compose --profile dev up -d --build

# Step 3 — health check with retry (production-style output)
echo
echo "=== Step 3: Health check (production-style) ==="
HEALTH_JSON=$(curl -sf --max-time 5 http://localhost:2312/api/health 2>/dev/null || true)
if [ -z "$HEALTH_JSON" ]; then
  for i in $(seq 1 9); do
    sleep 3
    HEALTH_JSON=$(curl -sf --max-time 5 http://localhost:2312/api/health 2>/dev/null || true)
    [ -n "$HEALTH_JSON" ] && break
  done
fi
if [ -z "$HEALTH_JSON" ]; then
  echo "WARNING: baker-dev /api/health not reachable (may still be starting)"
else
  echo "$HEALTH_JSON" | python3 -c "
import sys, json
h = json.load(sys.stdin)
print(f'  status:               {h.get(\"status\",\"?\")}')
print(f'  version:              {h.get(\"version\",\"?\")}')
print(f'  fingerprint:          {h.get(\"fingerprint\",\"?\")}')
print(f'  journalSyncFailures:  {h.get(\"journalSyncFailures\",\"?\")}')
rows = h.get('journalSyncFailureLogRows', [])
if rows:
    print(f'  journalSyncFailureLogRows: {len(rows)} historical entries')
    # group by error pattern
    from collections import Counter
    patterns = Counter(r['error_message'] for r in rows)
    for msg, count in patterns.most_common():
        print(f'    - {count}x: {msg}')
else:
    print('  journalSyncFailureLogRows: 0 (clean)')
"
fi

# ---------------------------------------------------------------------------
# Optional: clear historical journal sync failure log (--clean-failures)
# ---------------------------------------------------------------------------

if $CLEAN_FAILURES; then
  echo
  echo "=== Step 4: Clear journal_sync_failure_log (dev only) ==="
  docker compose --profile dev exec -T baker-dev python -c "
from baker.db.connection import get_db
with get_db() as conn:
    conn.execute('DELETE FROM journal_sync_failure_log')
    conn.commit()
    print('  Cleared journal_sync_failure_log')
" 2>&1 || echo "  WARNING: cleanup failed (baker-dev may not be ready)"
  echo
  echo "=== Re-check health ==="
  curl -s http://localhost:2312/api/health | python3 -c "
import sys, json
h = json.load(sys.stdin)
rows = h.get('journalSyncFailureLogRows', [])
print(f'  journalSyncFailureLogRows: {len(rows)} (clean)' if not rows else f'  journalSyncFailureLogRows: {len(rows)} remaining')
"
fi

echo
echo "Done. Open https://drgnfly.tail10c2c6.ts.net/ on a tailnet device."
