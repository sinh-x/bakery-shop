"""Migration v102: _migrate_v102_backfill_address_library (DG-387 Phase 2)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

_DOOR_DELIVERY_TYPES = ("door", "delivery")


def _migrate_v102_backfill_address_library(conn):
    """Backfill ``address_library`` and ``customer_addresses`` from historical orders.

    DG-387 Phase 2. Scans all door-to-door delivery orders
    (``delivery_type IN ('door','delivery')``) that have a non-empty
    ``delivery_address`` AND a non-empty ``google_maps_url``, derives the
    unique ``(normalize_address(delivery_address), google_maps_url)`` pairs,
    and ``INSERT OR IGNORE``'s each pair into ``address_library`` (FR2). For
    each customer whose orders contributed to a backfilled entry, a
    ``customer_addresses`` row is ``INSERT OR IGNORE``'d linking that
    customer to the library entry (FR3).

    Idempotency (NFR1): both inserts use ``INSERT OR IGNORE`` so re-running
    on an already-backfilled DB is a no-op and reports 0 new entries. The
    ``address_library`` unique index
    ``idx_address_library_normalized_url_unique`` enforces one row per
    ``(normalized_address, google_maps_url)`` pair; the ``customer_addresses``
    composite PK enforces one link per (customer, library entry).

    The whole callable runs within the ``ensure_schema`` migration
    transaction (NFR2), following the v057 customer backfill pattern
    (direct SQL, no API round-trip). ``normalize_address`` is registered as
    a SQLite custom function via ``conn.create_function()`` so the pair
    dedup can run server-side instead of post-filtering in Python (same
    pattern as ``_ensure_normalize_function`` in
    ``address_library.py:318-326``).

    A summary line is logged at INFO severity (AC7):
    ``"Đã backfill X địa chỉ, liên kết Y khách hàng."``
    """
    import logging

    from baker.models.address import normalize_address
    from baker.services.address_library import (
        create_library_entry,
        link_customer_address,
    )

    logger = logging.getLogger("baker.db")

    # Register normalize_address as a SQLite UDF so the DISTINCT pair
    # dedup runs server-side (idempotent — re-registering replaces the
    # previous binding, same pattern as _ensure_normalize_function).
    conn.create_function("normalize_address", 1, normalize_address)

    placeholders = ",".join("?" for _ in _DOOR_DELIVERY_TYPES)

    # FR2: collect all unique (normalize_address(delivery_address),
    # google_maps_url, display_address) pairs from door-delivery orders
    # with a non-empty link. Skip rows with empty delivery_address.
    # The display_address carried forward is selected via
    # MIN(delivery_address), which returns the lexicographically smallest
    # raw display text for that pair. This is cosmetic only — any
    # variant maps to the same normalized key value, so the choice of
    # display text does not affect dedup or linkage.
    pair_rows = conn.execute(
        f"""
        SELECT
            normalize_address(delivery_address) AS normalized_address,
            google_maps_url,
            MIN(delivery_address) AS display_address
        FROM orders
        WHERE delivery_type IN ({placeholders})
          AND delivery_address IS NOT NULL
          AND delivery_address != ''
          AND google_maps_url IS NOT NULL
          AND google_maps_url != ''
        GROUP BY normalized_address, google_maps_url
        """,  # nosec B608
        _DOOR_DELIVERY_TYPES,
    ).fetchall()

    library_entries_created = 0
    customers_linked = 0

    for prow in pair_rows:
        normalized = prow["normalized_address"]
        url = prow["google_maps_url"]
        display = prow["display_address"]

        # Count current library rows for this pair so we can report how
        # many were newly created by this run (AC7). The INSERT OR IGNORE
        # below makes the upsert idempotent (NFR1).
        before = conn.execute(
            "SELECT COUNT(*) AS cnt FROM address_library "
            "WHERE normalized_address = ? AND google_maps_url = ?",
            (normalized, url),
        ).fetchone()["cnt"]

        # Reuse the service-layer idempotent upsert (create_library_entry
        # is INSERT OR IGNORE + SELECT). It normalizes the display text
        # again internally; passing the already-normalized value would
        # double-normalize, so we pass the raw display text.
        entry = create_library_entry(
            conn, display_address=display, google_maps_url=url
        )

        after = conn.execute(
            "SELECT COUNT(*) AS cnt FROM address_library "
            "WHERE normalized_address = ? AND google_maps_url = ?",
            (normalized, url),
        ).fetchone()["cnt"]

        if after > before:
            library_entries_created += 1

        # FR3: link every customer whose orders contributed to this pair.
        # SELECT DISTINCT customer_id so each customer is linked once per
        # library entry; the composite PK on customer_addresses makes
        # re-linking a no-op (NFR1).
        customer_rows = conn.execute(
            f"""
            SELECT DISTINCT customer_id
            FROM orders
            WHERE delivery_type IN ({placeholders})
              AND delivery_address IS NOT NULL
              AND delivery_address != ''
              AND google_maps_url = ?
              AND customer_id IS NOT NULL
              AND normalize_address(delivery_address) = ?
            """,  # nosec B608
            (*_DOOR_DELIVERY_TYPES, url, normalized),
        ).fetchall()

        for crow in customer_rows:
            customer_id = crow["customer_id"]
            # Count current links so we can report newly-linked customers
            # (AC7). link_customer_address is INSERT OR IGNORE.
            link_before = conn.execute(
                "SELECT COUNT(*) AS cnt FROM customer_addresses "
                "WHERE customer_id = ? AND address_library_id = ?",
                (customer_id, entry.id),
            ).fetchone()["cnt"]
            link_customer_address(conn, customer_id, entry.id)
            link_after = conn.execute(
                "SELECT COUNT(*) AS cnt FROM customer_addresses "
                "WHERE customer_id = ? AND address_library_id = ?",
                (customer_id, entry.id),
            ).fetchone()["cnt"]
            if link_after > link_before:
                customers_linked += 1

    # AC7: summary log.
    logger.info(
        "Đã backfill %d địa chỉ, liên kết %d khách hàng.",
        library_entries_created,
        customers_linked,
    )