#!/usr/bin/env bash
# fix-dg249-duplicate-jes.sh — Clean up 8 duplicate AR entries (DG-249).
# Run on lily after deploying the DG-249 code changes.
# All SQL operations run inside the baker-prod Docker container.
# Usage: ./scripts/repair/fix-dg249-duplicate-jes.sh [--dry-run]
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

JE_IDS=(2372 2458 2463 2464 2465 4143 4147 4153)
DB_PATH="/var/lib/baker/baker.db"

echo "=== DG-249: Clean up 8 duplicate AR entries ==="
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "=== DRY RUN — no changes ==="
  echo "Would delete JE IDs: ${JE_IDS[*]}"
  echo ""
  for id in "${JE_IDS[@]}"; do
    echo "  DELETE FROM journal_lines WHERE journal_entry_id = $id;"
    echo "  DELETE FROM journal_entries WHERE id = $id;"
  done
  echo ""
  echo "Would verify: docker compose exec baker-prod baker repair-deposit-balance --all --dry-run"
  exit 0
fi

# Step 1: Backup
BACKUP="prod/data/baker.db.backup-dg249-$(date +%Y%m%d-%H%M%S)"
echo "--- Step 1: Backup ---"
cp prod/data/baker.db "$BACKUP"
echo "  Backup: $BACKUP"

# Step 2: Delete the 8 older AR entries (inside container)
echo ""
echo "--- Step 2: Delete 8 duplicate AR entries ---"
for id in "${JE_IDS[@]}"; do
  echo "  Deleting JE #$id..."
  docker compose --profile prod exec -T baker-prod python -c "
import sqlite3
conn = sqlite3.connect('$DB_PATH')
conn.execute('DELETE FROM journal_lines WHERE journal_entry_id = $id')
conn.execute('DELETE FROM journal_entries WHERE id = $id')
conn.commit()
conn.close()
print('    deleted')
"
done
echo "  Done."

# Step 3: Verify
echo ""
echo "--- Step 3: Verify ---"
echo "  Running repair-deposit-balance --all --dry-run..."
docker compose --profile prod exec -T baker-prod baker repair-deposit-balance --all --dry-run

echo ""
echo "=== Fix complete ==="
echo "  Backup saved to: $BACKUP"
echo "  The 8 duplicate AR entries have been removed."
echo "  Run './scripts/repair-all-accounting.sh' to run all repairs with the new guards."
