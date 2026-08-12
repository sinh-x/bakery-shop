"""Migration v103: _migrate_v103_orders_delivery_type_index (DG-388 Phase 5.6-c4 Mn-2).

Adds the ``idx_orders_delivery_type`` index on ``orders(delivery_type)`` so
the door-delivery filtering clauses used by the address autocomplete and
missing-link queries (``delivery_type IN ('door','delivery')``) are backed by
an index for sub-500ms response at scale (NFR4). This migration corrects the
prior false docstring claim that ``delivery_type`` was already indexed —
there was no such index on ``orders`` before v103.

Idempotent: the index is created with ``CREATE INDEX IF NOT EXISTS`` so
re-running v103 on an already-migrated DB is a no-op.
"""


def _migrate_v103_orders_delivery_type_index(conn):
    """Create ``idx_orders_delivery_type`` on ``orders(delivery_type)``.

    Uses ``CREATE INDEX IF NOT EXISTS`` so the migration is idempotent and
    safe to re-run on an already-migrated database.
    """
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_orders_delivery_type ON orders(delivery_type)"
    )