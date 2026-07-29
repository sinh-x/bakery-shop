"""Migration v075: _migrate_v75_backfill_primary_customer_phones (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v75_backfill_primary_customer_phones(conn):
    """Backfill a primary ``customer_phones`` row from legacy
    ``customers.phone`` for every customer with zero phone rows (DG-252 r4).

    R4-M1 (Major) data-loss defense-in-depth: a target customer created
    before v58/v66 (or whose phone rows were otherwise lost) carries its
    phone only in the denormalized ``customers.phone`` column. The runtime
    merge in :func:`baker.api.customers._merge_customer_into_target` now
    materializes such a legacy phone on the fly before copying source
    phones, but historic customers that are never merged would still be
    invisible to the duplicates finder (which joins on
    ``customer_phones``) and inconsistent with the "every customer with a
    phone has a primary row" invariant. This migration backfills a
    primary ``customer_phones`` row from any non-empty ``customers.phone``
    for customers that currently have zero phone rows.

    Idempotent: a second run finds zero candidates (every backfilled row
    is now present) and inserts nothing. The INSERT is also guarded by
    ``WHERE NOT EXISTS`` so concurrent writers cannot double-insert.
    """
    conn.execute(
        """
        INSERT INTO customer_phones (customer_id, phone, is_primary, created_at)
        SELECT
            c.id,
            c.phone,
            1,
            strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'
        FROM customers c
        WHERE
            c.phone IS NOT NULL
            AND c.phone <> ''
            AND NOT EXISTS (
                SELECT 1 FROM customer_phones cp
                WHERE cp.customer_id = c.id
            )
        """
    )
