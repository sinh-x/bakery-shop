"""Migration v071: _migrate_v71_users_role_check (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v71_users_role_check(conn):
    """Add a DB-level CHECK(role IN ('admin','staff')) to the ``users`` table.

    Mn-3 (DG-029 phase 5.6-c1): v68 created the users table without a
    DB-level CHECK on ``role``, so application bugs could persist invalid
    role values. Fresh DBs created on or after this migration get the
    constraint directly in ``USERS_SCHEMA``. Existing DBs where v68 has
    already run need a forward rebuild: SQLite has no ``ALTER TABLE ...
    ADD CONSTRAINT`` so we recreate the table with the CHECK, copy data,
    and recreate indexes. Idempotent: if the constraint is already
    present (fresh DB created post-fix, or this migration already ran),
    the rebuild is skipped.
    """
    # Detect whether the CHECK constraint is already in place. SQLite
    # exposes table-level CHECK constraints via the `sql` column of
    # sqlite_master. A fresh USERS_SCHEMA create includes the CHECK, so
    # re-running this migration on a fresh DB is a no-op.
    row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='users'"
    ).fetchone()
    if row is None:
        # users table does not exist yet — nothing to migrate. The
        # USERS_SCHEMA block in this same migration slot will create it
        # with the CHECK already in place.
        return
    create_sql = row["sql"] or ""
    if "CHECK(role IN" in create_sql.replace("\n", " "):
        return

    # DG-259 Phase 1: ensure staff_id column exists before rebuild (legacy
    # DBs where v68 ran before the DG-259 USERS_SCHEMA update won't have it).
    existing_cols = {r[1] for r in conn.execute("PRAGMA table_info(users)").fetchall()}
    if "staff_id" not in existing_cols:
        conn.execute(
            "ALTER TABLE users ADD COLUMN "
            "staff_id INTEGER REFERENCES staff(id) ON DELETE SET NULL"
        )

    # Rebuild users with the CHECK constraint (table-rebuild pattern,
    # same approach used by _migrate_v28_cascade_and_reseed).
    conn.executescript(
        """
        CREATE TABLE users_new (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            username      TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            role          TEXT NOT NULL DEFAULT 'staff' CHECK(role IN ('admin', 'staff')),
            active        INTEGER NOT NULL DEFAULT 1,
            locked_until  TEXT DEFAULT NULL,
            staff_id      INTEGER REFERENCES staff(id) ON DELETE SET NULL,
            created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
        );

        INSERT INTO users_new (id, username, password_hash, role, active, locked_until, staff_id, created_at)
        SELECT id, username, password_hash, role, active, locked_until, staff_id, created_at
        FROM users;

        DROP TABLE users;
        ALTER TABLE users_new RENAME TO users;

        CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
        CREATE INDEX IF NOT EXISTS idx_users_active ON users(active);
        """
    )
