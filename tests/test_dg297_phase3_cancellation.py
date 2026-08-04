"""Tests for DG-297 Phase 3 — cancellation reverses ``order_gift_cogs`` entries.

Covers FR5 and AC5:

- AC5: Given a delivered order with extras COGS and gift journal entries, when
  the order is cancelled, then both the ``order_cogs`` entry and the
  ``order_gift_cogs`` entry are reversed (locked) or deleted (unlocked).

Mirrors the existing ``order_cogs`` cancellation pattern (locked → reversing
entry, unlocked → cascade delete) and pins both branches for the gift entry.
"""

from baker.db.connection import get_db
from baker.db.schema import (
    COGS_CODE,
    INVENTORY_CODE,
    PROMO_EXPENSE_CODE,
    ensure_schema,
)
from baker.services.journal_sync import (
    _sync_cancelled_order_journal,
    _sync_delivered_order_journal,
)
from tests.helpers_dg297 import _insert_order, _insert_product, _add_item


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _entry_ids(conn, source_type, order_id):
    return [
        int(r[0]) for r in conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type = ? AND source_id = ? ORDER BY id",
            (source_type, order_id),
        ).fetchall()
    ]


def _entry_count(conn, source_type, order_id):
    return len(_entry_ids(conn, source_type, order_id))


def _lock_entries(conn, entry_ids):
    if not entry_ids:
        return
    placeholders = ",".join("?" for _ in entry_ids)
    conn.execute(
        f"UPDATE journal_entries SET locked_at = CURRENT_TIMESTAMP "
        f"WHERE id IN ({placeholders})",
        entry_ids,
    )


def _reversal_count(conn, original_description):
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries WHERE description = ?",
        (f"Reversal: {original_description}",),
    ).fetchone()
    return int(row[0])


# ---------------------------------------------------------------------------
# AC5 — unlocked gift entry is deleted on cancellation
# ---------------------------------------------------------------------------


def test_ac5_cancel_deletes_unlocked_order_gift_cogs_entry():
    """AC5 (unlocked branch): cancelling a delivered order with an
    ``order_gift_cogs`` entry cascade-deletes the unlocked gift entry, and the
    matching ``order_cogs`` entry is deleted too."""
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        gift_pid = _insert_product(conn, category="phu_kien", base_price=5000)
        oid = _insert_order(conn, order_ref="ORD-DG297-P3-DEL", total_price=100000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì P3-DEL",
            qty=1, unit_price=100000,
        )
        _add_item(
            conn, order_id=oid, product_id=gift_pid, product_name="Nến tặng P3-DEL",
            qty=2, unit_price=5000, is_extra=1, is_gift=1,
        )
        conn.commit()

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-P3-DEL")
        assert _entry_count(conn, "order_cogs", oid) == 1
        assert _entry_count(conn, "order_gift_cogs", oid) == 1

        _sync_cancelled_order_journal(conn, oid)

        # Both extras-related entries are deleted (unlocked → cascade delete).
        assert _entry_count(conn, "order_cogs", oid) == 0
        assert _entry_count(conn, "order_gift_cogs", oid) == 0
        # No reversal entries created for the unlocked originals.
        assert _reversal_count(conn, f"Order COGS: ORD-DG297-P3-DEL") == 0
        assert _reversal_count(conn, f"Order gift COGS: ORD-DG297-P3-DEL") == 0
        conn.commit()


# ---------------------------------------------------------------------------
# AC5 — locked gift entry is reversed (not deleted) on cancellation
# ---------------------------------------------------------------------------


def test_ac5_cancel_reverses_locked_order_gift_cogs_entry():
    """AC5 (locked branch): cancelling a delivered order whose ``order_gift_cogs``
    entry is locked produces a reversing entry (the original is preserved),
    mirroring the ``order_cogs`` locked-reversal behaviour."""
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        gift_pid = _insert_product(conn, category="phu_kien", base_price=5000)
        oid = _insert_order(conn, order_ref="ORD-DG297-P3-LCK", total_price=100000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì P3-LCK",
            qty=1, unit_price=100000,
        )
        _add_item(
            conn, order_id=oid, product_id=gift_pid, product_name="Nến tặng P3-LCK",
            qty=2, unit_price=5000, is_extra=1, is_gift=1,
        )
        conn.commit()

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-P3-LCK")
        cogs_ids = _entry_ids(conn, "order_cogs", oid)
        gift_ids = _entry_ids(conn, "order_gift_cogs", oid)
        assert len(cogs_ids) == 1
        assert len(gift_ids) == 1

        # Lock both entries — cancellation must reverse (not delete) them.
        _lock_entries(conn, cogs_ids + gift_ids)

        _sync_cancelled_order_journal(conn, oid)

        # Locked originals are preserved; a reversal entry offsets each.
        assert _entry_count(conn, "order_cogs", oid) == 2  # original + reversal
        assert _entry_count(conn, "order_gift_cogs", oid) == 2
        assert _reversal_count(conn, f"Order COGS: ORD-DG297-P3-LCK") == 1
        assert _reversal_count(conn, f"Order gift COGS: ORD-DG297-P3-LCK") == 1
        conn.commit()


# ---------------------------------------------------------------------------
# FR5 — gift entry absence is a no-op (no error, no spurious reversal)
# ---------------------------------------------------------------------------


def test_fr5_cancel_when_no_gift_entry_is_noop():
    """FR5: when the order has no ``order_gift_cogs`` entry (no gifts, or all
    zero-cost), cancellation leaves nothing to reverse and does not error."""
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        oid = _insert_order(conn, order_ref="ORD-DG297-P3-NOGIFT", total_price=100000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì P3-NG",
            qty=1, unit_price=100000,
        )
        conn.commit()

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-P3-NOGIFT")
        assert _entry_count(conn, "order_cogs", oid) == 1
        assert _entry_count(conn, "order_gift_cogs", oid) == 0

        # No error even though there is no gift entry to reverse.
        _sync_cancelled_order_journal(conn, oid)

        assert _entry_count(conn, "order_cogs", oid) == 0
        assert _entry_count(conn, "order_gift_cogs", oid) == 0
        conn.commit()