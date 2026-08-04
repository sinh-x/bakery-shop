"""Migration v072: _migrate_v72_lowercase_usernames (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v72_lowercase_usernames(conn):
    """Lowercase all existing ``users.username`` values (DG-029 follow-on).

    SQLite ``lower()`` only lowercases ASCII by default, so a pure-SQL
    ``UPDATE`` would leave Vietnamese diacritics (Â, Ư, Ầ, ...) untouched.
    Instead this migration reads each row, lowercases the username in Python
    (str.lower() is Unicode-aware), and per-row UPDATEs the value.

    Defensive collision guard: if two rows would collapse to the same
    lowercased username (e.g. "An" and "an"), the conflicting pair is
    skipped + logged. There should be none for the seeded set, but existing
    DBs may have arbitrary history. We never raise — a migration must not
    crash the server.

    Idempotent: re-running on a DB where all usernames are already lowercase
    is a no-op (the UPDATE matches no rows).

    Scope: only ``users.username``. Does NOT touch ``audit_log``,
    ``sessions``, ``staff``, or any ``logged_by`` / ``completed_by``
    historical data (per DG-029 follow-on requirements).
    """
    import sys

    rows = conn.execute("SELECT id, username FROM users ORDER BY id").fetchall()
    if not rows:
        return

    # Pre-collect existing lowercase usernames (already-correct rows) so we
    # can detect collisions before any UPDATE.
    existing_lower = {row["username"] for row in rows if row["username"] == row["username"].lower()}

    skipped: list[tuple[str, str]] = []  # (original, would_be)
    for row in rows:
        original = row["username"]
        lowered = original.lower()
        if lowered == original:
            continue  # already lowercase
        if lowered in existing_lower:
            skipped.append((original, lowered))
            continue
        conn.execute(
            "UPDATE users SET username = ? WHERE id = ?",
            (lowered, row["id"]),
        )
        existing_lower.add(lowered)

    if skipped:
        print(
            "DG-029 v72 migration: skipped lowercase-colliding usernames "
            f"({len(skipped)} pairs): {skipped}",
            file=sys.stdout,
        )
