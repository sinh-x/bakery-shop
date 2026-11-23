"""DG-444: neutral receipts and one-time destination resolution metadata."""

from .._helpers import _guard_add_column


def _migrate_v106_unknown_payment_destination(conn):
    for name, definition in (
        ("destination_resolved_at", "destination_resolved_at TEXT"),
        ("destination_resolved_by", "destination_resolved_by TEXT NOT NULL DEFAULT ''"),
    ):
        _guard_add_column(conn, "payment_transactions", name, definition)
    conn.execute(
        "INSERT OR IGNORE INTO accounts (code, name, type, parent_id) "
        "SELECT '1400', 'Tiền nhận chưa rõ nơi nhận', 'asset', id "
        "FROM accounts WHERE code = '1000'"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_payment_unknown_destination "
        "ON payment_transactions(id) WHERE method = 'unknown' AND invalidated_at IS NULL"
    )
