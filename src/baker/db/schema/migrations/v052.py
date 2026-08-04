"""Migration v052: _migrate_v52_reclassify_staff_advances_as_liabilities (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v52_reclassify_staff_advances_as_liabilities(conn):
    """Reclassify staff advance accounts (1400 asset) → staff payables (2300
    liability) for databases that already ran the v44 double-entry migration
    with the old 1400 seed (DG-194).

    On a v51-era database the chart of accounts seeded account 1400
    ("Nhân viên ứng trước", asset, parent 1000) plus per-staff sub-accounts
    14XX. The DG-194 seed now inserts 2300 ("Phải trả nhân viên", liability,
    parent 2000) via INSERT OR IGNORE, which leaves the old 1400 parent and
    its 14XX sub-accounts orphaned on existing databases.

    This migration:
      1. If 1400 exists and 2300 does not — UPDATE the 1400 row in place to
         code=2300, type='liability', parent=2000, name="Phải trả nhân viên
         (Staff Payables)".
      2. If both 1400 and 2300 exist (insert-before-migrate edge case) — move
         any 14XX sub-accounts under 2300, then delete the orphaned 1400
         parent.
      3. For each 14XX sub-account: reparent to the 2300 account, change type
         to 'liability', and renumber the code from 14XX → 23XX (zero-padded
         sequential index under 2300 to avoid colliding with seed-created
         23XX sub-accounts).
      4. If neither 1400 nor 2300 exists — no-op; seeding handles fresh DBs.

    Idempotent: re-running on an already-migrated DB finds no 1400 account and
    no 14XX sub-accounts, so every branch is a no-op.
    """
    parent_1400 = conn.execute(
        "SELECT id FROM accounts WHERE code = '1400'"
    ).fetchone()
    parent_2300 = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (STAFF_PAYABLES_CODE,)
    ).fetchone()

    if parent_1400 is None and parent_2300 is None:
        # Fresh install — seeding (INSERT OR IGNORE) handles COA. Nothing to do.
        return

    if parent_1400 is None:
        # Already migrated (no 1400, 2300 present). No-op.
        return

    old_parent_id = int(parent_1400[0])

    if parent_2300 is None:
        # Case 1: reclassify the 1400 row in place to become 2300.
        liabilities_root = conn.execute(
            "SELECT id FROM accounts WHERE code = '2000'"
        ).fetchone()
        parent_id = int(liabilities_root[0]) if liabilities_root else None
        conn.execute(
            "UPDATE accounts SET code = ?, name = ?, type = 'liability', "
            "parent_id = ? WHERE id = ?",
            (
                STAFF_PAYABLES_CODE,
                "Phải trả nhân viên (Staff Payables)",
                parent_id,
                old_parent_id,
            ),
        )
        new_parent_id = old_parent_id
    else:
        # Case 2: 2300 already present (insert-before-migrate). Keep 2300 as
        # the parent and remove the orphaned 1400 parent after reparenting.
        new_parent_id = int(parent_2300[0])

    # Reparent and renumber each 14XX sub-account. Codes are rewritten to
    # 23XX using a zero-padded sequential index starting after any existing
    # 23XX sub-accounts so we never collide with seed- or backfill-created
    # payables.
    existing_count_row = conn.execute(
        "SELECT COUNT(*) FROM accounts WHERE parent_id = ?", (new_parent_id,)
    ).fetchone()
    next_idx = int(existing_count_row[0]) if existing_count_row else 0

    subs = conn.execute(
        "SELECT id, name FROM accounts WHERE parent_id = ? ORDER BY id",
        (old_parent_id,),
    ).fetchall()
    for sub in subs:
        next_idx += 1
        new_code = f"23{next_idx:02d}"
        conn.execute(
            "UPDATE accounts SET code = ?, type = 'liability', parent_id = ? "
            "WHERE id = ?",
            (new_code, new_parent_id, int(sub["id"])),
        )

    if parent_2300 is not None:
        # Case 2 cleanup: the 1400 parent is now empty (all subs reparented).
        conn.execute("DELETE FROM accounts WHERE id = ?", (old_parent_id,))
