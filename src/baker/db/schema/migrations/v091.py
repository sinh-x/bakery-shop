"""Migration v091: _migrate_v91_cash_drawer_schema (DG-324 Phase 1)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v91_cash_drawer_schema(conn):
    """Create the ``cash_drawer`` table and add ``cash_drawer_id`` FK columns
    to ``payment_transactions`` and ``events`` (DG-324 Phase 1).

    The ``cash_drawer`` table records one daily cash drawer session per shop.
    Balance-affecting fields are stored as INTEGER (VND) per NFR1 so drawer
    balance computation is accurate to within 1 VND. ``status`` is 'open' or
    'closed' (FR1); timestamps track open/close time. The expected balance is
    derived (opening + cash_sales + owner_in - owner_out - cash_expenses) and
    not stored to avoid drift; only the counted amount and discrepancy are
    persisted at close time.

    FR5: cash ``payment_transactions`` auto-link to the active day's drawer via
    a nullable ``cash_drawer_id`` INTEGER FK column (defaults NULL so existing
    rows remain backward-compatible).
    FR6: cash ``events`` (expenses) auto-link via the same nullable column.

    Idempotent (NFR4): the ``cash_drawer`` table uses ``CREATE TABLE IF NOT
    EXISTS``; the two FK columns are added via the shared PRAGMA-guarded
    ``_guard_add_column`` helper (both ``payment_transactions`` and ``events``
    are in ``ALLOWED_TABLES``). Re-running v091 on an already-migrated DB is
    a no-op.
    """
    conn.executescript(CASH_DRAWER_SCHEMA)
    _guard_add_column(
        conn,
        "payment_transactions",
        "cash_drawer_id",
        "cash_drawer_id INTEGER DEFAULT NULL REFERENCES cash_drawer(id)",
    )
    _guard_add_column(
        conn,
        "events",
        "cash_drawer_id",
        "cash_drawer_id INTEGER DEFAULT NULL REFERENCES cash_drawer(id)",
    )