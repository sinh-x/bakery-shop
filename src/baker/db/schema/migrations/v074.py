"""Migration v074: _migrate_v74_backfill_null_customer_links (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v74_backfill_null_customer_links(conn):
    """Backfill migration linking remaining ``customer_id IS NULL`` orders.

    DG-252 Phase 4 (FR9 / NFR2 / AC5). Re-runs the shared
    :func:`_repair_null_customer_links` body so that any historic orders
    still lacking a ``customer_id`` after the v66 repair (e.g. orders
    created between v66 and the Phase 1 guaranteed-link landing, or rows
    that slipped past the guarantee due to a bug) are linked using the
    same phone → name → new customer → shared "Khách lẻ" chain.

    Idempotent (NFR2): a second run reports ``null_before = 0`` and changes
    zero rows. Pre/post NULL counts are written to logs by
    :func:`_repair_null_customer_links`; this wrapper does not return the
    summary dict (Mn-10, DG-252 review). Tests that need the summary call
    :func:`_repair_null_customer_links` directly; ``baker db`` surfaces
    counts via log lines only.
    """
    _repair_null_customer_links(conn)
