"""Migration v094: _migrate_v94_cash_drawer_tien_rut_columns (DG-341 Phase 4.1).

Adds the ``tien_rut_in`` and ``tien_rut_out`` INTEGER NOT NULL DEFAULT 0
columns to the ``cash_drawer`` table. These separate customer-cash-held-for-
safekeeping (tien rut) tracking from regular cash sales so the drawer's
expected balance accurately reflects the cash that should be physically
present in the drawer.

The plan document (2026-08-03-drawer-tien-rut-tracking.md) names this
migration ``v093``, but v093 was already taken by DG-337 Phase 5 (the
"quỹ" → "quầy" journal_entries.description rewrite). This phase therefore
uses the next available version number, v094. The deliverable scope
(``v093.py`` migration + updated ``CASH_DRAWER_SCHEMA``) is otherwise
unchanged — only the version number shifts to avoid a registry collision.

FR1: tien rut payments will add to ``tien_rut_in`` on the active drawer
      instead of ``cash_sales`` (the routing change itself is Phase 2; this
      phase only adds the column so the routing change has somewhere to
      write).
FR2: the ``expected_balance()`` formula becomes
      ``opening + cash_sales + tien_rut_in + owner_in
            - tien_rut_out - owner_out - cash_expenses``.
      Both new columns are needed in the schema before the formula can be
      updated (Phase 2).

NFR1: idempotent and non-destructive. The columns are added via the shared
      PRAGMA-guarded ``_guard_add_column`` helper (``cash_drawer`` is in
      ``ALLOWED_TABLES``). ``ADD COLUMN ... DEFAULT 0`` preserves all
      existing rows: every existing drawer gets ``tien_rut_in = 0`` and
      ``tien_rut_out = 0``, so historical expected balances are unchanged.
      Re-running v094 on an already-migrated DB is a no-op because
      ``_guard_add_column`` skips columns that already exist.

NFR2: backward compatible. Old Flutter clients that don't know about
      ``tienRutIn``/``tienRutOut`` ignore the unknown JSON keys, and the
      new columns default to 0 so the model's ``expected_balance()``
      formula (once updated in Phase 2) produces the same value as before
      for rows that never had a tien rut payment.
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v94_cash_drawer_tien_rut_columns(conn):
    """Add ``tien_rut_in`` and ``tien_rut_out`` to ``cash_drawer`` (DG-341 4.1).

    Both columns are ``INTEGER NOT NULL DEFAULT 0`` so existing drawer rows
    are preserved with zero tien rut totals (NFR1). The PRAGMA-guarded
    ``_guard_add_column`` helper makes the migration idempotent: re-running
    it on an already-migrated DB is a no-op.
    """
    _guard_add_column(
        conn,
        "cash_drawer",
        "tien_rut_in",
        "tien_rut_in INTEGER NOT NULL DEFAULT 0",
    )
    _guard_add_column(
        conn,
        "cash_drawer",
        "tien_rut_out",
        "tien_rut_out INTEGER NOT NULL DEFAULT 0",
    )