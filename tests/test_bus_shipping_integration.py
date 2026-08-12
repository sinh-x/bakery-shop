"""DG-191 Phase 7 — Integration tests + regression guard.

End-to-end coverage of the bus shipping fee accounting lifecycle and a
regression guard proving non-bus (pickup, door) orders are unaffected by the
new 2200 hold/release accounting.

Covers:

- ``test_bus_order_full_lifecycle_journal_entries`` — full lifecycle:
  create bus order → pay deposit → deliver → verify every journal entry
  (payment split, revenue exclusion, shipping release) and re-sync
  idempotency.  AC2/AC3/AC4.
- ``test_pickup_order_no_shipping_split`` — pickup order regression:
  payment entry has no 2200 line, revenue entry includes shipping_fee,
  no shipping release entry exists.  FR7 / AC8.
- ``test_door_order_no_shipping_split`` — door order regression: same
  guarantees as the pickup guard for ``delivery_type='door'``.  FR7 / AC8.

DG-366 Phase 6 — Additional scenario coverage for the fix-bus-shipping-release
work. The new section below covers the previously-untested paths produced by
Phases 1–5:

- ``test_bus_order_unpaid_completion_creates_release`` — unpaid bus order
  transitions to delivered/completed → release entry created for the full
  shipping_fee even with no held balance in 2200 (FR1/AC1, the original
  DG-366 bug scenario).
- ``test_completed_bus_order_post_completion_payment_creates_release`` —
  completed bus order with no prior release receives a payment → release
  entry created (FR2/AC2).
- ``test_completed_bus_order_payment_update_idempotent_release`` —
  completed bus order with an existing release gets a payment update that
  does not change shipping_fee → release remains unchanged (FR2/AC3).
- ``test_completed_bus_order_payment_delete_removes_release`` —
  completed bus order with a release; deleting the last payment (held → 0)
  removes the release entry (FR3/AC4).
- ``test_completed_bus_order_payment_delete_with_remaining_held_keeps_release``
  — completed bus order with two payments; deleting one leaves held > 0 →
  release entry is retained and reconciled (FR3 variant).
- ``test_bus_order_repeated_delivery_sync_no_duplicate_release`` — AC8:
  re-running delivery sync on an order that already has a correct release
  entry is a no-op (no duplicates).
- ``test_bus_order_repeated_completion_sync_no_duplicate_release`` — AC8:
  re-running completion sync on an order that already has a correct release
  entry is a no-op (no duplicates).
- ``test_completed_bus_order_repeated_payment_resync_no_duplicate_release``
  — AC8: re-triggering the payment journal sync (idempotent re-sync) on a
  completed bus order with a correct release entry produces no duplicate.
"""

from baker.db.connection import get_db
from baker.db.schema import (
    BUS_SHIPPING_HELD_CODE,
    CUSTOMER_DEPOSITS_CODE,
    ORDER_REVENUE_CODE,
    ensure_schema,
)
from baker.services.journal_sync import (
    _held_shipping_for_order,
    _sync_completed_order_journal,
    _sync_delivered_order_journal,
    _sync_payment_journal,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _insert_order(
    conn,
    *,
    order_ref: str,
    customer_name: str = "Khách thử",
    total_price: float = 125000.0,
    status: str = "new",
    delivery_type: str = "bus",
    shipping_fee: float = 25000.0,
) -> int:
    cur = conn.execute(
        "INSERT INTO orders "
        "(order_ref, customer_name, total_price, status, due_date, "
        " delivery_type, shipping_fee) "
        "VALUES (?, ?, ?, ?, '2026-06-10', ?, ?)",
        (order_ref, customer_name, total_price, status, delivery_type, shipping_fee),
    )
    return int(cur.lastrowid)


def _insert_payment(
    conn,
    *,
    order_id: int,
    amount: float,
    ptype: str = "deposit",
    method: str = "cash",
) -> int:
    cur = conn.execute(
        "INSERT INTO payment_transactions (order_id, amount, type, method, note) "
        "VALUES (?, ?, ?, ?, '')",
        (order_id, amount, ptype, method),
    )
    return int(cur.lastrowid)


def _pay(conn, *, order_id: int, amount: float) -> int:
    """Insert a deposit and run the payment journal sync (bus split aware)."""
    txn_id = _insert_payment(conn, order_id=order_id, amount=amount, ptype="deposit")
    _sync_payment_journal(conn, txn_id, amount, "deposit", "cash", order_id=order_id)
    return txn_id


def _entry_lines(conn, source_type: str, source_id: int) -> dict[str, dict[str, float]]:
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = ? AND je.source_id = ?
        """,
        (source_type, source_id),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out.setdefault(r["code"], {"debit": 0.0, "credit": 0.0})
        out[r["code"]]["debit"] += float(r["debit"] or 0)
        out[r["code"]]["credit"] += float(r["credit"] or 0)
    return out


def _entry_count(conn, source_type: str, source_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries WHERE source_type = ? AND source_id = ?",
        (source_type, source_id),
    ).fetchone()
    return int(row[0])


def _assert_balanced(lines: dict[str, dict[str, float]]) -> None:
    """Double-entry integrity: total debit == total credit (0.005 VND tol)."""
    total_debit = sum(v["debit"] for v in lines.values())
    total_credit = sum(v["credit"] for v in lines.values())
    assert abs(total_debit - total_credit) < 0.005, (
        f"unbalanced: debit={total_debit} credit={total_credit}"
    )


# ---------------------------------------------------------------------------
# End-to-end bus order lifecycle
# ---------------------------------------------------------------------------


def test_bus_order_full_lifecycle_journal_entries():
    """Full lifecycle: create bus order → pay → deliver → verify all entries.

    shipping_fee=25000, total_price=125000, deposit=125000.
    Payment entry:   debit 1100 125000, credit 2100 100000, credit 2200 25000
    Revenue entry:   debit 2100 100000, credit 4100 100000  (shipping excluded)
    Release entry:   debit 2200 25000,  credit 1100 25000
    Re-sync:          no duplicate entries created.
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-E2E-001",
            total_price=125000,
            status="new",
            delivery_type="bus",
            shipping_fee=25000,
        )

        # 1. Deposit payment of 125000.
        txn_id = _pay(conn, order_id=oid, amount=125000)
        payment_lines = _entry_lines(conn, "payment_transaction", txn_id)
        assert payment_lines["1101"]["debit"] == 125000.0
        assert payment_lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 100000.0
        assert payment_lines[BUS_SHIPPING_HELD_CODE]["credit"] == 25000.0
        _assert_balanced(payment_lines)

        # 2. Transition order to delivered and run delivery journal sync.
        conn.execute("UPDATE orders SET status = 'delivered' WHERE id = ?", (oid,))
        _sync_delivered_order_journal(conn, oid, "ORD-E2E-001")

        # 3. Revenue entry: 2100 debit 100000, 4100 credit 100000 (shipping excluded).
        assert _entry_count(conn, "order", oid) == 1
        revenue_rows = conn.execute(
            """
            SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id
            WHERE je.source_type = 'order' AND je.source_id = ?
            """,
            (oid,),
        ).fetchall()
        revenue_lines = {r["code"]: {"debit": float(r["debit"]), "credit": float(r["credit"])} for r in revenue_rows}
        # Aggregate duplicates if any.
        agg: dict[str, dict[str, float]] = {}
        for r in revenue_rows:
            agg.setdefault(r["code"], {"debit": 0.0, "credit": 0.0})
            agg[r["code"]]["debit"] += float(r["debit"] or 0)
            agg[r["code"]]["credit"] += float(r["credit"] or 0)
        assert agg[CUSTOMER_DEPOSITS_CODE]["debit"] == 100000.0
        assert agg[ORDER_REVENUE_CODE]["credit"] == 100000.0
        _assert_balanced(agg)

        # 4. Shipping release entry: debit 2200 25000, credit 1100 25000.
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        release_lines = _entry_lines(conn, "order_shipping_release", oid)
        assert release_lines[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0
        assert release_lines["1101"]["credit"] == 25000.0
        _assert_balanced(release_lines)

        # 5. Re-sync must not duplicate any entries.
        payment_before = _entry_count(conn, "payment_transaction", txn_id)
        revenue_before = _entry_count(conn, "order", oid)
        release_before = _entry_count(conn, "order_shipping_release", oid)
        _sync_delivered_order_journal(conn, oid, "ORD-E2E-001")
        assert _entry_count(conn, "payment_transaction", txn_id) == payment_before
        assert _entry_count(conn, "order", oid) == revenue_before
        assert _entry_count(conn, "order_shipping_release", oid) == release_before
        conn.commit()


# ---------------------------------------------------------------------------
# Regression guard — non-bus orders unchanged (FR7 / AC8)
# ---------------------------------------------------------------------------


def _run_non_bus_regression(order_ref: str, delivery_type: str) -> None:
    """Shared body for the pickup/door regression guards."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref=order_ref,
            total_price=125000,
            status="new",
            delivery_type=delivery_type,
            shipping_fee=25000,
        )
        txn_id = _pay(conn, order_id=oid, amount=125000)
        lines = _entry_lines(conn, "payment_transaction", txn_id)
        # No 2200 involvement at all.
        assert BUS_SHIPPING_HELD_CODE not in lines, (
            f"{delivery_type} payment must not involve 2200"
        )
        assert lines["1101"]["debit"] == 125000.0
        assert lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 125000.0
        _assert_balanced(lines)

        # Transition to delivered.
        conn.execute("UPDATE orders SET status = 'delivered' WHERE id = ?", (oid,))
        _sync_delivered_order_journal(conn, oid, order_ref)

        # Revenue entry includes the full deposit (no shipping_fee exclusion).
        revenue_rows = conn.execute(
            """
            SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id
            WHERE je.source_type = 'order' AND je.source_id = ?
            """,
            (oid,),
        ).fetchall()
        agg: dict[str, dict[str, float]] = {}
        for r in revenue_rows:
            agg.setdefault(r["code"], {"debit": 0.0, "credit": 0.0})
            agg[r["code"]]["debit"] += float(r["debit"] or 0)
            agg[r["code"]]["credit"] += float(r["credit"] or 0)
        assert agg[CUSTOMER_DEPOSITS_CODE]["debit"] == 125000.0
        assert agg[ORDER_REVENUE_CODE]["credit"] == 125000.0
        _assert_balanced(agg)

        # No shipping release entry.
        assert _entry_count(conn, "order_shipping_release", oid) == 0
        conn.commit()


def test_pickup_order_no_shipping_split():
    """FR7 / AC8: pickup order is unaffected by the bus shipping accounting.

    Payment entry:   debit 1100 125000, credit 2100 125000 (no 2200 split)
    Revenue entry:   debit 2100 125000, credit 4100 125000 (shipping included)
    Release entry:   none.
    """
    _run_non_bus_regression("ORD-E2E-PICKUP", "pickup")


def test_door_order_no_shipping_split():
    """FR7 / AC8: door order is unaffected by the bus shipping accounting.

    Payment entry:   debit 1100 125000, credit 2100 125000 (no 2200 split)
    Revenue entry:   debit 2100 125000, credit 4100 125000 (shipping included)
    Release entry:   none.
    """
    _run_non_bus_regression("ORD-E2E-DOOR", "door")


# ---------------------------------------------------------------------------
# DG-366 Phase 6 — Scenario coverage for fix-bus-shipping-release
#
# These tests exercise the paths introduced by DG-366 Phases 1–5 that were
# previously only verified via ad-hoc scripts during Phase 3. Each test seeds
# the minimum state required to reach the scenario, runs the journal sync
# entry point that the real code path invokes, and asserts the observable
# journal entry outcome (entry count, debit/credit amounts, idempotency).
#
# Naming maps to the FR/AC traceability matrix in the requirements doc:
#   FR1/AC1  → test_bus_order_unpaid_completion_creates_release
#   FR2/AC2  → test_completed_bus_order_post_completion_payment_creates_release
#   FR2/AC3  → test_completed_bus_order_payment_update_idempotent_release
#   FR3/AC4  → test_completed_bus_order_payment_delete_removes_release
#   FR3 var. → test_completed_bus_order_payment_delete_with_remaining_held_keeps_release
#   AC8      → test_bus_order_repeated_delivery_sync_no_duplicate_release
#              test_bus_order_repeated_completion_sync_no_duplicate_release
#              test_completed_bus_order_repeated_payment_resync_no_duplicate_release
# ---------------------------------------------------------------------------


def _release_lines(conn, order_id: int) -> dict[str, dict[str, float]]:
    """Aggregate per-account debit/credit for the order's shipping release
    entries (sums across all release entries — used for idempotency checks
    where the absence of duplicates is the assertion)."""
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order_shipping_release' AND je.source_id = ?
        """,
        (order_id,),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out.setdefault(r["code"], {"debit": 0.0, "credit": 0.0})
        out[r["code"]]["debit"] += float(r["debit"] or 0)
        out[r["code"]]["credit"] += float(r["credit"] or 0)
    return out


def _release_entry_ids(conn, order_id: int) -> list[int]:
    rows = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'order_shipping_release' AND source_id = ? "
        "ORDER BY id ASC",
        (order_id,),
    ).fetchall()
    return [int(r[0]) for r in rows]


def _payment_entry_ids(conn, txn_id: int) -> list[int]:
    rows = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'payment_transaction' AND source_id = ? "
        "ORDER BY id ASC",
        (txn_id,),
    ).fetchall()
    return [int(r[0]) for r in rows]


def _delete_release_entry(conn, order_id: int) -> None:
    """Delete the order_shipping_release journal entry (and its lines)."""
    conn.execute(
        "DELETE FROM journal_lines WHERE journal_entry_id IN ("
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'order_shipping_release' AND source_id = ?"
        ")",
        (order_id,),
    )
    conn.execute(
        "DELETE FROM journal_entries "
        "WHERE source_type = 'order_shipping_release' AND source_id = ?",
        (order_id,),
    )


def test_bus_order_unpaid_completion_creates_release():
    """FR1/AC1: a bus order that completes with no payments at all still
    gets the full shipping_fee release entry (the original DG-366 bug — the
    `held_in_2200 > 0` gate used to suppress this path).
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DG366-UNPAID",
            total_price=125000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        # No payment — held_in_2200 == 0.
        assert _held_shipping_for_order(conn, oid) == 0.0
        assert _entry_count(conn, "order_shipping_release", oid) == 0

        _sync_delivered_order_journal(conn, oid, "ORD-DG366-UNPAID")

        # Phase 1 fix: release entry created for the full shipping_fee even
        # though no held balance exists in 2200.
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        lines = _release_lines(conn, oid)
        assert lines[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0
        # Credit side routes to 1101 (Cash in Drawer) when an open drawer
        # covers the delivery timestamp, otherwise 1102 (Owner's Cash) —
        # the drawer-aware routing used by _resolve_shipping_release_asset_account.
        credit_1101 = lines.get("1101", {"debit": 0.0, "credit": 0.0})["credit"]
        credit_1102 = lines.get("1102", {"debit": 0.0, "credit": 0.0})["credit"]
        credit_total = credit_1101 + credit_1102
        assert credit_total == 25000.0
        _assert_balanced(lines)
        conn.commit()


def test_completed_bus_order_post_completion_payment_creates_release():
    """FR2/AC2: a completed bus order with no prior release receives a
    payment → the payment sync re-trigger creates the release entry for the
    full shipping_fee.
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DG366-POSTPAY",
            total_price=125000,
            status="completed",
            delivery_type="bus",
            shipping_fee=25000,
        )
        # Complete the order first — this creates the release entry (Phase 1).
        _sync_completed_order_journal(conn, oid, "ORD-DG366-POSTPAY")
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        # Simulate the "release was never created at completion" scenario
        # (the original bug) by deleting the release entry before the
        # post-completion payment arrives.
        _delete_release_entry(conn, oid)
        assert _entry_count(conn, "order_shipping_release", oid) == 0

        # A post-completion payment arrives. The payment sync must re-trigger
        # the shipping release and create the entry for the full shipping_fee.
        txn_id = _pay(conn, order_id=oid, amount=125000)

        assert _entry_count(conn, "order_shipping_release", oid) == 1
        lines = _release_lines(conn, oid)
        assert lines[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0
        # The payment entry credits 2200 with 25000 (held) — re-triggered
        # release debits 2200 by 25000 to offset.
        assert _entry_count(conn, "payment_transaction", txn_id) == 1
        conn.commit()


def test_completed_bus_order_payment_update_idempotent_release():
    """FR2/AC3: a completed bus order with an existing release receives a
    payment update that does not change shipping_fee → the release entry is
    re-synced but remains unchanged (idempotent within tolerance).
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DG366-UPD",
            total_price=125000,
            status="completed",
            delivery_type="bus",
            shipping_fee=25000,
        )
        # Completion creates the release entry.
        _sync_completed_order_journal(conn, oid, "ORD-DG366-UPD")
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        release_ids_before = _release_entry_ids(conn, oid)

        # Payment arrives (also re-triggers release sync — idempotent).
        txn_id = _pay(conn, order_id=oid, amount=125000)
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        assert _release_entry_ids(conn, oid) == release_ids_before

        # Update the payment amount (125000 → 150000) and re-run the sync.
        # shipping_fee is unchanged, so the release entry must remain a no-op.
        conn.execute(
            "UPDATE payment_transactions SET amount = 150000 WHERE id = ?",
            (txn_id,),
        )
        _sync_payment_journal(
            conn, txn_id, 150000, "deposit", "cash", order_id=oid
        )

        assert _entry_count(conn, "order_shipping_release", oid) == 1
        assert _release_entry_ids(conn, oid) == release_ids_before
        lines = _release_lines(conn, oid)
        assert lines[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0
        conn.commit()


def test_completed_bus_order_payment_delete_removes_release():
    """FR3/AC4: a completed bus order with a release; deleting the last
    payment leaves held_in_2200 == 0 → the release entry is removed so 2200
    does not carry a stale debit.
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DG366-DEL",
            total_price=125000,
            status="completed",
            delivery_type="bus",
            shipping_fee=25000,
        )
        # Single payment — held shipping equals 25000.
        txn_id = _pay(conn, order_id=oid, amount=125000)
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        assert _held_shipping_for_order(conn, oid) == 25000.0

        # Delete the payment via the payment journal sync delete path. Held
        # drops to 0, so the release entry must be removed.
        _sync_payment_journal(
            conn, txn_id, 125000, "deposit", "cash",
            order_id=oid, deleted=True,
        )

        assert _entry_count(conn, "order_shipping_release", oid) == 0
        assert _payment_entry_ids(conn, txn_id) == []
        assert _held_shipping_for_order(conn, oid) == 0.0
        conn.commit()


def test_completed_bus_order_payment_delete_with_remaining_held_keeps_release():
    """FR3 variant: a completed bus order with two payments; deleting one
    leaves held_in_2200 > 0 → the release entry is retained and reconciled
    (not deleted), so the 2200 debit still reflects the remaining held amount.
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DG366-DELMULTI",
            total_price=150000,
            status="completed",
            delivery_type="bus",
            shipping_fee=25000,
        )
        # Two payments — held shipping equals 25000 (the shipping portion of
        # either payment; the held calculation sums the 2200 credits).
        txn1 = _pay(conn, order_id=oid, amount=100000)
        txn2 = _pay(conn, order_id=oid, amount=50000)
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        assert _held_shipping_for_order(conn, oid) == 25000.0
        release_ids_before = _release_entry_ids(conn, oid)

        # Delete the second payment. The first payment still holds 25000 in
        # 2200, so the release entry must remain.
        _sync_payment_journal(
            conn, txn2, 50000, "deposit", "cash",
            order_id=oid, deleted=True,
        )

        assert _entry_count(conn, "order_shipping_release", oid) == 1
        assert _release_entry_ids(conn, oid) == release_ids_before
        # Held shipping still covers the full shipping_fee via the first txn.
        assert _held_shipping_for_order(conn, oid) == 25000.0
        lines = _release_lines(conn, oid)
        assert lines[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0
        conn.commit()


def test_bus_order_repeated_delivery_sync_no_duplicate_release():
    """AC8: re-running delivery sync on an order that already has a correct
    release entry produces no duplicate (idempotency).
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DG366-IDEM-DLV",
            total_price=125000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        _pay(conn, order_id=oid, amount=125000)
        _sync_delivered_order_journal(conn, oid, "ORD-DG366-IDEM-DLV")
        ids_before = _release_entry_ids(conn, oid)
        assert len(ids_before) == 1

        # Re-sync — must be a no-op.
        _sync_delivered_order_journal(conn, oid, "ORD-DG366-IDEM-DLV")
        ids_after = _release_entry_ids(conn, oid)
        assert ids_after == ids_before
        assert len(ids_after) == 1

        # A third re-sync is still a no-op.
        _sync_delivered_order_journal(conn, oid, "ORD-DG366-IDEM-DLV")
        assert _release_entry_ids(conn, oid) == ids_before
        conn.commit()


def test_bus_order_repeated_completion_sync_no_duplicate_release():
    """AC8: re-running completion sync on an order that already has a correct
    release entry produces no duplicate (idempotency).
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DG366-IDEM-CMP",
            total_price=125000,
            status="completed",
            delivery_type="bus",
            shipping_fee=25000,
        )
        _pay(conn, order_id=oid, amount=125000)
        _sync_completed_order_journal(conn, oid, "ORD-DG366-IDEM-CMP")
        ids_before = _release_entry_ids(conn, oid)
        assert len(ids_before) == 1

        _sync_completed_order_journal(conn, oid, "ORD-DG366-IDEM-CMP")
        _sync_completed_order_journal(conn, oid, "ORD-DG366-IDEM-CMP")
        ids_after = _release_entry_ids(conn, oid)
        assert ids_after == ids_before
        assert len(ids_after) == 1
        conn.commit()


def test_completed_bus_order_repeated_payment_resync_no_duplicate_release():
    """AC8: re-running the payment journal sync on a completed bus order
    that already has a correct release entry produces no duplicate (the
    re-trigger path introduced in DG-366 Phase 3 is idempotent).
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DG366-IDEM-PAY",
            total_price=125000,
            status="completed",
            delivery_type="bus",
            shipping_fee=25000,
        )
        txn_id = _pay(conn, order_id=oid, amount=125000)
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        ids_before = _release_entry_ids(conn, oid)

        # Re-run the payment journal sync with the same amount — the
        # underlying _sync_bus_shipping_release_entry must be idempotent.
        _sync_payment_journal(
            conn, txn_id, 125000, "deposit", "cash", order_id=oid
        )
        _sync_payment_journal(
            conn, txn_id, 125000, "deposit", "cash", order_id=oid
        )

        assert _release_entry_ids(conn, oid) == ids_before
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        lines = _release_lines(conn, oid)
        assert lines[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0
        # The payment entry itself must also remain singular.
        assert len(_payment_entry_ids(conn, txn_id)) == 1
        conn.commit()