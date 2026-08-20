"""Migration v098: _migrate_v98_reconciliation_sale_rows_linked_order_refs (DG-368 Phase 1).

Adds the ``linked_order_refs`` TEXT column to the ``reconciliation_sale_rows``
table. The column stores a JSON array of every ``order_ref`` created for a
given sale row during reconciliation submit, so that the 1-order-per-cake
split (DG-368) can record multiple orders against a single sale row instead
of the single ``linked_order_ref`` value used previously.

FR3: ``reconciliation_sale_rows`` lưu danh sách tất cả order_ref dưới dạng
JSON array trong cột ``linked_order_refs``.

The column is nullable and defaults to NULL:
- Existing rows (and existing client code that still writes the single
  ``linked_order_ref``) are untouched — backward compatible (NFR1).
- Phase 2 will populate ``linked_order_refs`` for new reconciliation submits;
  the single ``linked_order_ref`` column is retained and continues to point
  at the first order (FR4 / AC4).

Idempotent (NFR2): the migration uses an inline PRAGMA-guarded
``ALTER TABLE ... ADD COLUMN`` — ``reconciliation_sale_rows`` is not in
``ALLOWED_TABLES`` so the shared ``_guard_add_column`` helper is not used;
this mirrors the v077/v090 approach. Re-running v098 on an already-migrated
DB is a no-op.

Requires SQLite >= 3.35.0 for ``ALTER TABLE ... ADD COLUMN`` with a
non-constant DEFAULT (the runtime already mandates >= 3.35.0 for the v80
``DROP COLUMN`` migration).
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v98_reconciliation_sale_rows_linked_order_refs(conn):
    """Add ``linked_order_refs`` TEXT column to ``reconciliation_sale_rows``.

    The column is nullable with DEFAULT NULL so existing rows are preserved
    untouched (NFR1). The inline PRAGMA guard makes the migration idempotent:
    re-running it on an already-migrated DB is a no-op because the column is
    skipped when it already exists (NFR2).
    """
    existing_cols = {
        r[1] for r in conn.execute("PRAGMA table_info(reconciliation_sale_rows)").fetchall()
    }
    if "linked_order_refs" not in existing_cols:
        conn.execute(
            "ALTER TABLE reconciliation_sale_rows ADD COLUMN linked_order_refs TEXT DEFAULT NULL"
        )
