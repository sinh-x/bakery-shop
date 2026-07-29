"""Migration v061: _migrate_v61_customer_search_name (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v61_customer_search_name(conn):
    """Add ``search_name`` column and backfill for all existing customers.

    DG-206 follow-up: adds diacritic-insensitive search. For fresh DBs the
    column already exists via CUSTOMERS_SCHEMA; for existing DBs we add it
    with ALTER TABLE. Then backfills ``_strip_diacritics(name)`` for every
    customer row. Idempotent: re-running overwrites existing values with
    the same result.
    """
    cols = [r["name"] for r in conn.execute("PRAGMA table_info(customers)").fetchall()]
    if "search_name" not in cols:
        conn.execute("ALTER TABLE customers ADD COLUMN search_name TEXT DEFAULT ''")
    rows = conn.execute("SELECT id, name FROM customers").fetchall()
    for row in rows:
        conn.execute(
            "UPDATE customers SET search_name = ? WHERE id = ?",
            (_strip_diacritics(row["name"]), row["id"]),
        )
