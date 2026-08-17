"""Migration v048: _migrate_v48_fix_inventory_purchase_entries (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v48_fix_inventory_purchase_entries(conn):
    """One-time fix: delete and re-create expense journal entries for
    Nguyên liệu and Bao bì categories. These were originally recorded as
    debit expense (5100/5200) but should debit Inventory (1300) — the cost
    sits in inventory until goods are sold/wasted (COGS).

    Idempotent: deletes stale entries then re-runs the expense backfill
    which now routes inventory purchases to Inventory (1300).
    """
    import json

    stale_ids = []
    rows = conn.execute(
        "SELECT id, data FROM events WHERE type = 'expense' AND deleted_at IS NULL"
    ).fetchall()

    for row in rows:
        try:
            data = json.loads(row["data"]) if row["data"] else {}
        except (json.JSONDecodeError, TypeError):
            continue
        category = data.get("category")
        if category not in INVENTORY_PURCHASE_CATEGORIES:
            continue

        je = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type = 'expense' AND source_id = ?",
            (row["id"],),
        ).fetchone()
        if je is None:
            continue

        entry_id = int(je["id"])
        lines = conn.execute(
            """
            SELECT a.code FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND jl.debit > 0
            """,
            (entry_id,),
        ).fetchall()
        debit_codes = {l["code"] for l in lines}
        if INVENTORY_CODE not in debit_codes:
            stale_ids.append(entry_id)

    if stale_ids:
        placeholders = ",".join("?" * len(stale_ids))
        conn.execute(
            f"DELETE FROM journal_entries WHERE id IN ({placeholders})",  # nosec B608
            stale_ids,
        )

    _backfill_expense_journal_entries(conn)
