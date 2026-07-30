"""Migration v046: _migrate_v46_fix_old_expense_journal (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v46_fix_old_expense_journal(conn):
    """One-time fix: backfill journal entry for old-format expense event #25.

    Event #25 uses pre-standardization data keys (``amount``, ``currency``
    instead of ``amount_vnd``, ``category``). Map the known fields manually:
    equipment repair → Sửa chữa (5600), Shop tiền mặt → 1100.
    """
    import json

    row = conn.execute(
        "SELECT id, summary, data, timestamp FROM events WHERE id = 25"
    ).fetchone()
    if row is None:
        return

    existing = conn.execute(
        "SELECT 1 FROM journal_entries "
        "WHERE source_type = 'expense' AND source_id = 25"
    ).fetchone()
    if existing:
        return

    try:
        data = json.loads(row["data"]) if row["data"] else {}
    except (json.JSONDecodeError, TypeError):
        return

    amount = data.get("amount")
    payment_source = data.get("payment_source")
    if not isinstance(amount, (int, float)) or amount <= 0:
        return
    if payment_source != "Shop tiền mặt":
        return

    expense_account_id = _account_id_by_code(conn, "5600")
    asset_account_id = _account_id_by_code(conn, "1100")
    _insert_journal_entry(
        conn,
        description=f"Expense: {row['summary']}",
        source_type="expense",
        source_id=25,
        transaction_date=row["timestamp"] or "",
        lines=[
            (expense_account_id, float(amount), 0.0, "Chi phí sửa chữa"),
            (asset_account_id, 0.0, float(amount), "Thanh toán tiền mặt"),
        ],
    )
