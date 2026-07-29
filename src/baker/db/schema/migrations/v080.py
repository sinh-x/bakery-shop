"""Migration v080: _migrate_v80_drop_amount_paid_from_orders (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v80_drop_amount_paid_from_orders(conn):
    """Drop the redundant ``amount_paid`` column from ``orders`` (DG-274).

    The column is now live-computed from ``payment_transactions`` via
    ``PaymentTransaction.total_paid_excl_outflows``; the stored value was lossy
    (included outflows) and is no longer written by ``Order.save``. The v12
    migration still reads ``amount_paid`` for pre-v12 rows, but v12 runs before
    v80 so the column exists at v12 time and is dropped here. Idempotent via
    PRAGMA-guarded ALTER TABLE (orders is in ALLOWED_TABLES).
    """
    _guard_drop_column(conn, "orders", "amount_paid")
