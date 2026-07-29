"""Tests for DG-297 Phase 4 — accounting validation includes extras.

Covers FR6, FR7, AC4:

- FR6: ``_check_cogs_completeness`` removes the ``is_extra = 0`` filter so
  sold extras (is_extra=1, is_gift=0) with a missing ``cost_at_sale`` are
  flagged alongside main items. Gifted items (is_gift=1) remain excluded —
  their cost is recorded by the separate ``order_gift_cogs`` entry.
- FR7: ``_check_cogs_amount_accuracy`` includes sold extras in the expected
  COGS total comparison, matching the ``order_cogs`` journal entry scope
  from Phase 2.
- AC4: Given delivered orders with extras, when accounting validation runs,
  then ``cogs_completeness`` flags extras with missing ``cost_at_sale``,
  and ``cogs_amount_accuracy`` includes extras in the expected COGS total
  comparison.

Also pins NFR1 (backward compatibility: existing non-extra validation
tests still pass) and the read-only guarantee (no mutations).
"""

from baker.db.connection import get_db
from baker.db.schema import (
    COGS_CODE,
    INVENTORY_CODE,
    ensure_schema,
)
from baker.services.accounting_validation import run_validation
from baker.services.journal_sync import _sync_delivered_order_journal


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_PRODUCT_SEQ = {"n": 0}


def _insert_product(conn, *, name=None, category="banh_mi", base_price=100000):
    _PRODUCT_SEQ["n"] += 1
    if name is None:
        name = f"SP-DG297-P4-{_PRODUCT_SEQ['n']}"
    cur = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
        "VALUES (?, ?, ?, ?, '')",
        (name, category, base_price, base_price),
    )
    return int(cur.lastrowid)


def _insert_order(conn, *, order_ref, total_price=0, status="delivered"):
    cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date) "
        "VALUES (?, 'Khách thử', ?, ?, '2026-07-29')",
        (order_ref, total_price, status),
    )
    return int(cur.lastrowid)


def _add_item(
    conn,
    *,
    order_id,
    product_id,
    product_name="Bánh mì",
    qty=1,
    unit_price=100000,
    cost_at_sale=0,
    is_extra=0,
    is_gift=0,
):
    cur = conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, "
        " position, status, cost_at_sale, is_extra, is_gift) "
        "VALUES (?, ?, ?, ?, ?, 0, 'delivered', ?, ?, ?)",
        (order_id, product_id, product_name, qty, unit_price,
         cost_at_sale, is_extra, is_gift),
    )
    return int(cur.lastrowid)


def _cogs_completeness_check(report):
    return next(c for c in report["checks"] if c["check"] == "cogs_completeness")


def _cogs_amount_accuracy_check(report):
    return next(c for c in report["checks"] if c["check"] == "cogs_amount_accuracy")


def _account_id(conn, code: str) -> int:
    return int(conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0])


def _insert_order_cogs_entry(conn, *, order_id: int, cogs_debit: float) -> int:
    """Insert a balanced ``order_cogs`` journal entry (DR COGS 5900 /
    CR Inventory 1300) with the given COGS debit and return its id."""
    cogs_acct = _account_id(conn, COGS_CODE)
    inv_acct = _account_id(conn, INVENTORY_CODE)
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, ?, ?)",
        ("Order COGS test", "order_cogs", order_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, cogs_acct, cogs_debit, 0.0, "d"),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, inv_acct, 0.0, cogs_debit, "c"),
    )
    return entry_id


# ---------------------------------------------------------------------------
# FR6 / AC4 — cogs_completeness flags extras with missing cost_at_sale
# ---------------------------------------------------------------------------


def test_fr6_cogs_completeness_flags_sold_extra_with_missing_cost_at_sale():
    """FR6/AC4: a delivered sold extra (is_extra=1, is_gift=0) with
    ``cost_at_sale = 0`` and a resolvable cost (phụ kiện base_price > 0) is
    flagged by ``cogs_completeness``. Pre-Phase-4 the ``is_extra = 0``
    filter would have hidden it."""
    with get_db() as conn:
        ensure_schema(conn)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-FR6", total_price=5000)
        item_id = _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến FR6",
            qty=2, unit_price=5000, is_extra=1,
        )
        conn.commit()
        report = run_validation(conn)
    check = _cogs_completeness_check(report)
    finding = next(f for f in check["details"] if f["item_id"] == item_id)
    assert finding["cost_at_sale"] == 0.0
    assert finding["base_price"] == 5000.0
    assert finding["is_extra"] == 1


def test_fr6_cogs_completeness_passes_when_extra_cost_at_sale_set():
    """FR6: a sold extra whose ``cost_at_sale`` was snapshotted at delivery is
    not flagged (the snapshot is authoritative)."""
    with get_db() as conn:
        ensure_schema(conn)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-FR6-OK", total_price=5000)
        _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến FR6 OK",
            qty=1, unit_price=5000, cost_at_sale=5000, is_extra=1,
        )
        conn.commit()
        report = run_validation(conn)
    check = _cogs_completeness_check(report)
    # No finding referencing this order's extra item.
    extra_findings = [
        f for f in check["details"]
        if f["order_ref"] == "ORD-DG297-P4-FR6-OK"
    ]
    assert extra_findings == []


def test_fr6_cogs_completeness_still_excludes_gift_items():
    """FR6: gifted items (is_gift=1) are NOT flagged by ``cogs_completeness``
    — their cost is recorded by the separate ``order_gift_cogs`` entry, not
    the ``order_cogs`` scope this check mirrors."""
    with get_db() as conn:
        ensure_schema(conn)
        gift_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-FR6-GIFT", total_price=5000)
        gift_item_id = _add_item(
            conn, order_id=oid, product_id=gift_pid, product_name="Nến tặng FR6",
            qty=1, unit_price=5000, is_extra=1, is_gift=1,
        )
        conn.commit()
        report = run_validation(conn)
    check = _cogs_completeness_check(report)
    gift_findings = [f for f in check["details"] if f["item_id"] == gift_item_id]
    assert gift_findings == [], (
        f"gift item should be excluded from cogs_completeness, got: {gift_findings}"
    )


def test_fr6_cogs_completeness_flags_main_and_extra_in_same_order():
    """FR6/AC4: in a single delivered order with both a main item and a sold
    extra missing cost_at_sale, both rows are flagged — the validator scope
    now matches the ``order_cogs`` journal entry scope."""
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-FR6-BOTH", total_price=105000)
        main_item_id = _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì FR6 BOTH",
            qty=1, unit_price=100000,
        )
        extra_item_id = _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến FR6 BOTH",
            qty=1, unit_price=5000, is_extra=1,
        )
        conn.commit()
        report = run_validation(conn)
    check = _cogs_completeness_check(report)
    flagged_ids = {f["item_id"] for f in check["details"]}
    assert main_item_id in flagged_ids
    assert extra_item_id in flagged_ids


# ---------------------------------------------------------------------------
# FR7 / AC4 — cogs_amount_accuracy includes extras in expected total
# ---------------------------------------------------------------------------


def test_fr7_cogs_amount_accuracy_includes_sold_extra_in_expected_total():
    """FR7/AC4: for a delivered order with a main item + a sold extra, the
    expected COGS total includes both items' costs. A journal debit that
    matches the combined total reports no mismatch.

    Setup: main (Bánh mì, base_price=100000, unit_price=50000, qty=2) →
    cost = 30%×50000×2 = 30000; sold extra (phụ kiện, base_price=5000,
    unit_price=5000, qty=3, cost_at_sale=5000) → 5000×3 = 15000. Combined
    expected = 45000. A journal debit of 45000 → no mismatch.
    """
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-FR7", total_price=110000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì FR7",
            qty=2, unit_price=50000,
        )
        _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến FR7",
            qty=3, unit_price=5000, cost_at_sale=5000, is_extra=1,
        )
        _insert_order_cogs_entry(conn, order_id=oid, cogs_debit=45000)
        conn.commit()
        report = run_validation(conn)
    check = _cogs_amount_accuracy_check(report)
    finding = next((f for f in check["details"] if f["order_id"] == oid), None)
    assert finding is None, (
        f"expected no mismatch when extras are included, got: {finding}"
    )


def test_fr7_cogs_amount_accuracy_flags_mismatch_when_extra_omitted_from_debit():
    """FR7/AC4: when the journal debit omits the extra's cost, the validator
    flags the mismatch — proving the extra is part of the expected total.

    Setup: same as above (expected 45000) but journal debit = 30000 (only
    the main item). The validator must flag actual=30000, expected=45000,
    difference=15000.
    """
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-FR7-MM", total_price=110000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì FR7 MM",
            qty=2, unit_price=50000,
        )
        _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến FR7 MM",
            qty=3, unit_price=5000, cost_at_sale=5000, is_extra=1,
        )
        _insert_order_cogs_entry(conn, order_id=oid, cogs_debit=30000)
        conn.commit()
        report = run_validation(conn)
    check = _cogs_amount_accuracy_check(report)
    finding = next(f for f in check["details"] if f["order_id"] == oid)
    assert finding["actual_cogs"] == 30000.0
    assert finding["expected_cogs"] == 45000.0
    assert abs(finding["difference"]) == 15000.0


def test_fr7_cogs_amount_accuracy_still_excludes_gift_items():
    """FR7: gifted items (is_gift=1) are excluded from the expected COGS
    total — they belong to the separate ``order_gift_cogs`` entry. A
    journal debit that matches only the main+sold-extra cost (excluding
    the gift) reports no mismatch."""
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        gift_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-FR7-GIFT", total_price=100000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì FR7 GIFT",
            qty=1, unit_price=100000, cost_at_sale=30000,
        )
        _add_item(
            conn, order_id=oid, product_id=gift_pid, product_name="Nến tặng FR7",
            qty=2, unit_price=5000, cost_at_sale=5000, is_extra=1, is_gift=1,
        )
        # Journal debit covers only the main item (gift is in order_gift_cogs).
        _insert_order_cogs_entry(conn, order_id=oid, cogs_debit=30000)
        conn.commit()
        report = run_validation(conn)
    check = _cogs_amount_accuracy_check(report)
    finding = next((f for f in check["details"] if f["order_id"] == oid), None)
    assert finding is None, (
        f"gift cost should be excluded from order_cogs expected total, got: {finding}"
    )


def test_fr7_cogs_amount_accuracy_includes_extra_with_zero_cost_at_sale_fallback():
    """FR7: a sold extra with ``cost_at_sale = 0`` has its cost recomputed
    via the baseline rule (phụ kiện = 100% base_price) — proving the
    fallback path in the validator also includes extras.

    Setup: sold extra (phụ kiện, base_price=5000, unit_price=5000, qty=2,
    cost_at_sale=0) → resolved cost = 5000 (phụ kiện baseline) × 2 = 10000.
    A journal debit of 10000 → no mismatch.
    """
    with get_db() as conn:
        ensure_schema(conn)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-FR7-FB", total_price=10000)
        _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến FR7 FB",
            qty=2, unit_price=5000, cost_at_sale=0, is_extra=1,
        )
        _insert_order_cogs_entry(conn, order_id=oid, cogs_debit=10000)
        conn.commit()
        report = run_validation(conn)
    check = _cogs_amount_accuracy_check(report)
    finding = next((f for f in check["details"] if f["order_id"] == oid), None)
    assert finding is None, (
        f"zero-cost-at-sale extra fallback not honored: {finding}"
    )


# ---------------------------------------------------------------------------
# NFR1 — backward compatibility (existing non-extra validation still works)
# ---------------------------------------------------------------------------


def test_nfr1_validation_after_real_delivery_sync_including_extras_passes():
    """NFR1/AC4: when an order with a main item + sold extra goes through
    the real delivery sync (which now creates per-item lines including the
    extra), the ``cogs_amount_accuracy`` validator reports no mismatch —
    the validator scope matches the journal entry scope."""
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-NFR1", total_price=110000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì NFR1",
            qty=2, unit_price=50000,
        )
        _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến NFR1",
            qty=3, unit_price=5000, is_extra=1,
        )
        conn.commit()
        _sync_delivered_order_journal(conn, oid, "ORD-DG297-P4-NFR1")
        conn.commit()
        report = run_validation(conn)
    check = _cogs_amount_accuracy_check(report)
    finding = next((f for f in check["details"] if f["order_id"] == oid), None)
    assert finding is None, (
        f"validator should match the real journal entry including extras: {finding}"
    )


# ---------------------------------------------------------------------------
# Read-only guarantee (no mutations during validation)
# ---------------------------------------------------------------------------


def test_phase4_validation_is_read_only_with_extras_present():
    """The validator performs no writes — row counts and the seeded
    ``cost_at_sale = 0`` value are unchanged after a validation run that
    includes a sold extra with a missing cost (the FR6 flagging path).
    """
    with get_db() as conn:
        ensure_schema(conn)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-P4-RO", total_price=5000)
        item_id = _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến RO",
            qty=1, unit_price=5000, is_extra=1,
        )
        conn.commit()

        table_names = [
            r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
        ]
        pre_counts = {
            t: conn.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
            for t in table_names
        }
        pre_cost = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()[0]

        run_validation(conn)

        post_counts = {
            t: conn.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
            for t in table_names
        }
        post_cost = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()[0]

    assert pre_counts == post_counts, (
        f"row counts changed during validation: "
        f"{ {k: v for k, v in post_counts.items() if v != pre_counts[k]} }"
    )
    assert pre_cost == post_cost
    assert post_cost == 0, "cost_at_sale should remain 0 (read-only)"