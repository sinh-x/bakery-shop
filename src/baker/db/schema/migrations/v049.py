"""Migration v049: _migrate_v49_bus_shipping_backfill (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v49_bus_shipping_backfill(conn):
    """One-time backfill: correct delivered bus orders for the shipping hold & release accounting.

    Prior to the bus shipping separation (FR5), delivered bus orders had:

    1. Stale revenue entries that *included* the shipping fee in the 2100→4100
       conversion (because ``shipping_fee`` was part of ``total_price`` and the
       old reconciler did not exclude it).
    2. No shipping hold entry — the shipping portion sat in 2100 instead of
       being moved to the dedicated 2200 holding account at payment time.
    3. No shipping release entry — nothing debited 2200 / credited 1100 at
       delivery to reflect paying the bus driver.

    This migration iterates every delivered/completed bus order with
    ``shipping_fee > 0`` and corrects all three:

    a. **Revenue fix** — delegates to
       :func:`_reconcile_order_revenue_entry`, which already excludes
       ``shipping_fee`` from the recognized revenue for bus orders (Phase 3).
       Stale entries are reconciled (locked → reversed, unlocked → deleted and
       recreated) so the 2100 debit matches ``net_deposits − shipping_fee``.
    b. **Hold entry** — when no ``order_shipping_hold`` journal entry exists for
       the order, creates one moving the shipping portion from Customer
       Deposits (2100) to Bus Shipping Held (2200): debit 2100, credit 2200.
       This mirrors what the payment-time split (Phase 2) would have produced.
    c. **Release entry** — delegates to
       :func:`_sync_bus_shipping_release_entry`, which creates the
       2200→1100 release entry (Phase 3, FR4) and is idempotent.

    Idempotency (NFR2):

    - Revenue reconciliation is idempotent (no-op when the 2100 debit already
      matches ``net_deposits − shipping_fee``).
    - The hold entry is skipped when an ``order_shipping_hold`` entry already
      exists for the order.
    - The release entry is idempotent by construction.

    Non-bus orders and bus orders with ``shipping_fee == 0`` are untouched
    (FR7 regression guard).
    """
    _seed_chart_of_accounts(conn)

    from baker.services.journal_sync import (
        _reconcile_order_revenue_entry,
        _sync_bus_shipping_release_entry,
    )

    orders = conn.execute(
        "SELECT id, order_ref, total_price, shipping_fee "
        "FROM orders "
        "WHERE status IN ('delivered', 'completed') "
        "  AND delivery_type = 'bus' "
        "  AND shipping_fee > 0"
    ).fetchall()

    deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
    bus_shipping_account_id = _account_id_by_code(conn, BUS_SHIPPING_HELD_CODE)

    for orow in orders:
        order_id = int(orow["id"])
        order_ref = orow["order_ref"]
        shipping_fee = float(orow["shipping_fee"] or 0)
        if shipping_fee <= 0:
            continue

        # (a) Fix the revenue entry: reconcile against net deposits minus the
        # bus shipping fee (Phase 3 logic lives inside the reconciler).
        _reconcile_order_revenue_entry(
            conn,
            order_id,
            order_ref,
            total_price=float(orow["total_price"] or 0),
        )

        # (b) Create the hold entry (2100 → 2200) if not already present.
        # Skip when shipping is already held in 2200 — either via an earlier
        # run of this backfill (order_shipping_hold entry exists) or via the
        # Phase 2 payment-time split (payment_transaction entries crediting
        # 2200). This keeps the backfill idempotent and avoids double-holding.
        existing_hold = conn.execute(
            "SELECT 1 FROM journal_entries "
            "WHERE source_type = 'order_shipping_hold' AND source_id = ?",
            (order_id,),
        ).fetchone()
        if not existing_hold:
            from baker.services.journal_sync import _held_shipping_for_order

            already_held = _held_shipping_for_order(conn, order_id)
            if already_held < shipping_fee - 0.005:
                _insert_journal_entry(
                    conn,
                    description=f"Bus shipping hold: {order_ref}",
                    source_type="order_shipping_hold",
                    source_id=order_id,
                    lines=[
                        (
                            deposits_account_id,
                            shipping_fee,
                            0.0,
                            "Rút ship bus khỏi cọc",
                        ),
                        (
                            bus_shipping_account_id,
                            0.0,
                            shipping_fee,
                            "Tiền ship bus giữ hộ",
                        ),
                    ],
                )

        # (c) Create the release entry (2200 → 1100). Idempotent by construction.
        _sync_bus_shipping_release_entry(conn, order_id, order_ref)
