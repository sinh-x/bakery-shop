"""Migration v042: _migrate_v42_backfill_payment_source (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v42_backfill_payment_source(conn):
    """Backfill payment_source: 'Shop tiền mặt' for all existing expense events."""
    import json

    rows = conn.execute(
        "SELECT id, data FROM events WHERE type = 'expense'"
    ).fetchall()

    for row in rows:
        try:
            data = json.loads(row["data"]) if row["data"] else {}
        except (json.JSONDecodeError, TypeError):
            data = {}

        if "payment_source" not in data:
            data["payment_source"] = "Shop tiền mặt"
            conn.execute(
                "UPDATE events SET data = ? WHERE id = ?",
                (json.dumps(data), row["id"]),
            )
