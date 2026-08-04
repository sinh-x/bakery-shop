"""Migration v077: _migrate_v77_staff_id_columns (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v77_staff_id_columns(conn):
    """Add ``staff_id`` columns to ``users`` and ``sessions`` tables, create
    UNIQUE index on ``users.staff_id``, and back-link existing users to staff
    using case+diacritic-insensitive name matching (DG-259 Phase 1, FR4/FR5/FR7).

    ``users.staff_id`` is an FK to ``staff(id) ON DELETE SET NULL`` with a
    UNIQUE partial index so each staff member can be linked to at most one
    user account. ``sessions.staff_id`` is a plain nullable integer (login-time
    population lands in Phase 2, FR5).

    The backfill matches existing usernames to staff names by stripping
    Vietnamese diacritics and lowercasing both sides. First match wins —
    administrators can override via Settings (Phase 4).

    Idempotent: re-running on an already-migrated DB is a no-op because each
    column and index is PRAGMA-guarded.
    """
    # Add users.staff_id (PRAGMA guard)
    existing_users_cols = {
        r[1] for r in conn.execute("PRAGMA table_info(users)").fetchall()
    }
    if "staff_id" not in existing_users_cols:
        conn.execute(
            "ALTER TABLE users ADD COLUMN "
            "staff_id INTEGER REFERENCES staff(id) ON DELETE SET NULL"
        )

    conn.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_staff_id "
        "ON users(staff_id) WHERE staff_id IS NOT NULL"
    )

    # Add sessions.staff_id (PRAGMA guard)
    existing_sessions_cols = {
        r[1] for r in conn.execute("PRAGMA table_info(sessions)").fetchall()
    }
    if "staff_id" not in existing_sessions_cols:
        conn.execute(
            "ALTER TABLE sessions ADD COLUMN staff_id INTEGER DEFAULT NULL"
        )

    # Back-link existing users to staff by case+diacritic-insensitive name matching
    users = conn.execute(
        "SELECT id, username FROM users WHERE staff_id IS NULL ORDER BY id"
    ).fetchall()
    if users:
        staff_rows = conn.execute("SELECT id, name FROM staff ORDER BY id").fetchall()
        if staff_rows:
            staff_by_normalized: dict[str, int] = {}
            for srow in staff_rows:
                key = _strip_diacritics(srow["name"])
                if key and key not in staff_by_normalized:
                    staff_by_normalized[key] = int(srow["id"])

            # Track already-assigned staff ids (from v68 or manual binding)
            # to avoid UNIQUE index collisions during backfill (m7).
            assigned_staff_ids: set[int] = {
                int(r["staff_id"])
                for r in conn.execute(
                    "SELECT staff_id FROM users WHERE staff_id IS NOT NULL"
                ).fetchall()
            }
            for urow in users:
                key = _strip_diacritics(urow["username"])
                staff_id = staff_by_normalized.get(key)
                if staff_id is not None:
                    if staff_id in assigned_staff_ids:
                        continue
                    assigned_staff_ids.add(staff_id)
                    conn.execute(
                        "UPDATE users SET staff_id = ? WHERE id = ?",
                        (staff_id, int(urow["id"])),
                    )
