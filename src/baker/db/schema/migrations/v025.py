"""Migration v025: _migrate_v25_tien_rut_rename (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v25_tien_rut_rename(conn):
    """Rename rut_tien transaction type to tien_rut for consistency with Vietnamese 'Tiền rút'."""
    conn.execute(
        "UPDATE payment_transactions SET type = 'tien_rut' WHERE type = 'rut_tien'",
    )
