#!/usr/bin/env bash
# Validate a staged or restored bakery backup before operator-gated promotion.

set -euo pipefail

TARGET_DIR="${1:?Usage: verify-backup-restore.sh TARGET_DIR}"
DATA_DIR="${BAKER_DATA_DIR:-/var/lib/baker}"
ALLOW_PRODUCTION_RESTORE="${BAKER_ALLOW_PRODUCTION_RESTORE:-false}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -d "$TARGET_DIR" ]] || fail "restore target does not exist"
TARGET_REAL="$(realpath "$TARGET_DIR")"
DATA_REAL="$(realpath -m "$DATA_DIR")"
if [[ "$TARGET_REAL" == "$DATA_REAL" && "$ALLOW_PRODUCTION_RESTORE" != "true" ]]; then
  fail "refusing to validate the production data directory without explicit approval"
fi

MANIFEST="$TARGET_REAL/SHA256SUMS"
DB_PATH="$TARGET_REAL/baker.db"
[[ -f "$MANIFEST" ]] || fail "SHA256SUMS manifest is missing"
[[ -f "$DB_PATH" ]] || fail "baker.db is missing"
if find "$TARGET_REAL" -type l -print -quit | grep -q .; then
  fail "restore target must not contain symbolic links"
fi

# Restrict manifest entries to paths below the isolated target before asking
# sha256sum to read them.
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" != \\* ]] || fail "escaped manifest paths are not supported"
  manifest_path="${line#*  }"
  [[ "$manifest_path" == ./* ]] || fail "manifest contains a non-local path"
  [[ "/$manifest_path/" != *"/../"* ]] || fail "manifest contains path traversal"
done < "$MANIFEST"

(
  cd "$TARGET_REAL"
  sha256sum --check --strict SHA256SUMS >/dev/null
)

integrity="$(sqlite3 "$DB_PATH" "PRAGMA integrity_check;")"
[[ "$integrity" == "ok" ]] || fail "SQLite integrity_check failed"

manifest_contains() {
  local relative_path="$1"
  local expected
  expected="$(cd "$TARGET_REAL" && sha256sum "./$relative_path")"
  grep -Fqx "$expected" "$MANIFEST"
}

manifest_contains "baker.db" || fail "database is not covered by the manifest"
while IFS= read -r photo_hash; do
  [[ "$photo_hash" =~ ^[0-9a-f]{64}$ ]] || fail "database contains an invalid photo hash"
  photo_path="photos/${photo_hash}.jpg"
  [[ -f "$TARGET_REAL/$photo_path" ]] || fail "database-referenced photo is missing"
  manifest_contains "$photo_path" || fail "database-referenced photo is not covered by the manifest"
done < <(sqlite3 -noheader "$DB_PATH" "SELECT hash FROM photos ORDER BY hash;")

echo "Backup validation passed: manifest and SQLite integrity are valid"
