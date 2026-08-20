"""Migration v047: _migrate_v47_fix_stale_cogs_entries (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v47_fix_stale_cogs_entries(conn):
    """One-time fix: delete and re-create order_cogs journal entries that were
    generated with the old cost resolver (which returned 0 for products with
    cost=0 and no cost_history). The current resolver uses baseline fallback
    (30% base_price, 100% for phụ kiện) so stale entries may be understated.

    Idempotent: re-creates via _sync_delivered_order_journal which skips
    existing entries, so we delete stale ones first.
    """
    _seed_chart_of_accounts(conn)
    from baker.services.cost_resolver import resolve_product_cost
    from baker.services.journal_sync import _sync_delivered_order_journal

    stale_ids = []
    rows = conn.execute(
        """
        SELECT je.id AS entry_id, je.source_id AS order_id
        FROM journal_entries je
        WHERE je.source_type = 'order_cogs'
        ORDER BY je.id
        """
    ).fetchall()

    for r in rows:
        entry_id = int(r["entry_id"])
        order_id = int(r["order_id"])

        actual = conn.execute(
            """
            SELECT SUM(jl.debit) FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND a.code = '5900'
            """,
            (entry_id,),
        ).fetchone()[0]
        actual = float(actual or 0)

        items = conn.execute(
            """
            SELECT oi.product_id, oi.quantity
            FROM order_items oi
            WHERE oi.order_id = ? AND oi.is_extra = 0 AND oi.is_gift = 0
            """,
            (order_id,),
        ).fetchall()

        expected = 0.0
        for i in items:
            pid_str = i["product_id"]
            if pid_str is None:
                continue
            try:
                pid = int(pid_str)
            except (TypeError, ValueError):
                continue
            cost = resolve_product_cost(conn, pid)
            qty = int(i["quantity"] or 0)
            expected += cost * qty

        if abs(actual - expected) > 0.01:
            stale_ids.append(entry_id)

    if stale_ids:
        placeholders = ",".join("?" * len(stale_ids))
        conn.execute(
            f"DELETE FROM journal_entries WHERE id IN ({placeholders})",  # nosec B608
            stale_ids,
        )

    orders = conn.execute(
        """
        SELECT DISTINCT o.id, o.order_ref
        FROM orders o
        JOIN order_items oi ON oi.order_id = o.id
        WHERE o.status IN ('delivered', 'completed')
        """
    ).fetchall()

    for o in orders:
        _sync_delivered_order_journal(conn, int(o["id"]), o["order_ref"])
