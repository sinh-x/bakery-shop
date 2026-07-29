"""Migration v058: _migrate_v58_customer_phones (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v58_customer_phones(conn):
    """Create customer_phones table and migrate existing customers.phone into it.

    DG-205 Phase 1. Creates the normalized ``customer_phones`` table (FR1) and
    moves each existing non-empty ``customers.phone`` value into a row with
    ``is_primary=1`` (FR2). The ``customers.phone`` denormalized column is
    retained as a backward-compatible fallback (NFR4/AC2) — it is NOT modified.

    The migration is idempotent (NFR1): before inserting, it checks whether the
    customer already has any row in ``customer_phones`` and skips those that do.
    Re-running v58 therefore never duplicates phone rows (AC1).

    The DDL (table + indexes on ``customer_id`` and ``phone``) is applied via
    the ``CUSTOMER_PHONES_SCHEMA`` ``sql`` entry in ``MIGRATIONS``; this
    callable only performs the data backfill, following the v56/v57 pattern of
    separating schema (``sql``) from data (``callable``).
    """
    import logging

    logger = logging.getLogger("baker.db")

    # Idempotency (NFR1): collect customer_ids that already have phone rows.
    # This covers re-runs of v58 and DBs where phone rows were added by the API
    # before v58 finished — either way we never insert a duplicate.
    customers_with_phones = {
        row[0]
        for row in conn.execute("SELECT DISTINCT customer_id FROM customer_phones").fetchall()
    }

    migrated = 0
    # Move each existing non-empty customers.phone into customer_phones as the
    # primary phone (FR2). Empty/NULL phones are skipped (no point inserting a
    # blank primary phone row).
    for crow in conn.execute(
        "SELECT id, phone FROM customers WHERE phone IS NOT NULL AND phone != ''"
    ).fetchall():
        cust_id = crow["id"]
        phone = crow["phone"]
        if cust_id in customers_with_phones:
            continue
        # M-1: normalize the backfilled phone so customer_phones rows are
        # consistent with rows written by _sync_customer_phones (which now
        # applies _normalize_phone). Legacy customers.phone is left as-is.
        nphone = _normalize_phone(phone)
        if not nphone:
            continue
        conn.execute(
            "INSERT INTO customer_phones (customer_id, phone, is_primary) VALUES (?, ?, 1)",
            (cust_id, nphone),
        )
        customers_with_phones.add(cust_id)
        migrated += 1

    logger.info("Đã chuyển %d số điện thoại vào customer_phones.", migrated)
