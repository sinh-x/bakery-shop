"""Migration v087: _migrate_v87_order_delivery_schedule_gps (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v87_order_delivery_schedule_gps(conn):
    """Add delivery schedule + GPS columns to ``orders`` (DG-303 Phase 4.1).

    Adds four nullable columns for door-delivery orders:
      * ``latitude`` REAL DEFAULT NULL — GPS latitude (FR1)
      * ``longitude`` REAL DEFAULT NULL — GPS longitude (FR1)
      * ``google_maps_url`` TEXT DEFAULT NULL — full Google Maps URL (FR2)
      * ``delivery_time_slot`` TEXT DEFAULT NULL — 1-hour slot label
        ("7:00" ... "20:00") (FR3)

    All columns default to NULL so existing orders remain functional with
    empty/null new fields (NFR1, AC7) — no data migration is needed. Bus
    and pickup orders leave these NULL forever. Idempotent via
    PRAGMA-guarded ``_guard_add_column`` (``orders`` is in ALLOWED_TABLES).

    Version note: the requirements plan (2026-07-27-delivery-schedule-gps.md)
    named this migration "v86", but v86 was already consumed by DG-302
    (expense subcategories, merged to main). This phase uses the next
    available version, v87.
    """
    _guard_add_column(conn, "orders", "latitude", "latitude REAL DEFAULT NULL")
    _guard_add_column(conn, "orders", "longitude", "longitude REAL DEFAULT NULL")
    _guard_add_column(
        conn, "orders", "google_maps_url", "google_maps_url TEXT DEFAULT NULL"
    )
    _guard_add_column(
        conn, "orders", "delivery_time_slot", "delivery_time_slot TEXT DEFAULT NULL"
    )
