"""Migration v090: _migrate_v90_force_password_change (DG-319 Phase 1)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v90_force_password_change(conn):
    """Add ``force_password_change`` column to the ``users`` table (DG-319 Phase 1).

    The column is an INTEGER NOT NULL DEFAULT 0 flag. When set to 1 (by the
    admin CLI ``baker user set-password --force-change``), the login response
    includes ``force_password_change: true`` so the client routes the user to
    the forced password-change flow. Successful self-service or forced change
    clears the flag back to 0 (FR10).

    Additive only (NFR4): a single ``ALTER TABLE ... ADD COLUMN`` with no data
    migration — existing rows default to 0 (no forced change). Idempotent via
    PRAGMA-guarded ALTER TABLE (``users`` is not in ``ALLOWED_TABLES`` so the
    shared ``_guard_add_column`` helper is not used; the inline guard mirrors
    v077's approach).
    """
    existing_cols = {
        r[1] for r in conn.execute("PRAGMA table_info(users)").fetchall()
    }
    if "force_password_change" not in existing_cols:
        conn.execute(
            "ALTER TABLE users ADD COLUMN force_password_change INTEGER NOT NULL DEFAULT 0"
        )
