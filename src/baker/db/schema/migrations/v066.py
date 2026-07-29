"""Migration v066: _migrate_v66_repair_customer_links (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v66_repair_customer_links(conn):
    """Link all NULL customer_id orders to customers on startup — DG-227 Phase 2.

    Thin wrapper around :func:`_repair_null_customer_links` retained for the
    v66 migration slot (DG-227). See the shared helper for the full
    phone → name → new customer → "Khách lẻ" resolution chain.
    """
    _repair_null_customer_links(conn)
