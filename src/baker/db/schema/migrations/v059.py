"""Migration v059: _migrate_v59_deduplicate_customers (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v59_deduplicate_customers(conn):
    """Merge duplicate customers that share the same case-insensitive name.

    DG-205 follow-up. v57 could create duplicate customers when phone-having
    and phone-less orders shared the same name but the name was not tracked in
    ``existing_names`` (fixed in v57 itself, but existing DBs may have dupes).
    This migration groups customers by case-insensitive trimmed name, keeps the
    one with the most orders (earliest id as tiebreak), reassigns all orders
    from duplicates to the winner, and deletes the duplicates. Idempotent:
    re-running when no duplicates exist is a no-op.
    """
    import logging

    logger = logging.getLogger("baker.db")

    # Group customers by case-insensitive trimmed name.
    rows = conn.execute(
        "SELECT id, name FROM customers ORDER BY id ASC"
    ).fetchall()
    name_groups: dict[str, list[int]] = {}
    for row in rows:
        key = (row["name"] or "").strip().lower()
        if not key:
            continue
        name_groups.setdefault(key, []).append(row["id"])

    merged = 0
    for key, ids in name_groups.items():
        if len(ids) <= 1:
            continue
        # Keep the customer with the most orders; earliest id breaks ties.
        best_id = ids[0]
        best_count = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (best_id,)
        ).fetchone()[0]
        for cid in ids[1:]:
            cnt = conn.execute(
                "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (cid,)
            ).fetchone()[0]
            if cnt > best_count:
                best_id = cid
                best_count = cnt
        # Reassign orders from duplicates to the winner.
        for cid in ids:
            if cid == best_id:
                continue
            conn.execute(
                "UPDATE orders SET customer_id = ? WHERE customer_id = ?",
                (best_id, cid),
            )
            conn.execute("DELETE FROM customer_phones WHERE customer_id = ?", (cid,))
            conn.execute("DELETE FROM customers WHERE id = ?", (cid,))
            merged += 1

    if merged:
        logger.info("Đã gộp %d khách hàng trùng tên.", merged)
