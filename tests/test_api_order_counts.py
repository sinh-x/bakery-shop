"""Tests for GET /api/orders/counts (DG-409 Phase 1 / FR2 / NFR4).

Covers:
- Response structure (urgency + incomplete keys, integer values)
- Active-order filtering (completed/cancelled excluded)
- Delivered+fully-paid orders excluded (same rule as active_only)
- Urgency counts include critical + urgent tiers
- Incomplete counts require missing required fields
- Zero-on-error contract (FR2 — degraded UX returns 0 instead of stale)
- No embedded order list in today-summary / period-summary (FR7/FR8/AC8)
"""

import pytest

from baker.db.connection import get_db
from baker.utils.time import now_utc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _today() -> str:
    return now_utc()[:10]


def _create_order(
    client,
    customer="Nguyễn Văn A",
    total=300000,
    items=None,
    **kwargs,
):
    if items is None:
        items = [
            {
                "productName": "Bánh kem",
                "quantity": 1,
                "unitPrice": total,
                "productId": "BKS-16",
            }
        ]
    payload = {
        "customerName": customer,
        "dueDate": _today(),
        "items": items,
        **kwargs,
    }
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _create_txn(client, ref, amount=100000, **kwargs):
    payload = {"amount": amount, **kwargs}
    resp = client.post(f"/api/orders/{ref}/transactions", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


# ---------------------------------------------------------------------------
# Response structure (FR2 / AC1)
# ---------------------------------------------------------------------------


def test_order_counts_response_structure(api_client):
    """FR2/AC1: GET /api/orders/counts returns {urgency, incomplete} with
    integer values."""
    resp = api_client.get("/api/orders/counts")
    assert resp.status_code == 200
    body = resp.json()
    assert "urgency" in body
    assert "incomplete" in body
    assert isinstance(body["urgency"], int)
    assert isinstance(body["incomplete"], int)


def test_order_counts_empty_db_returns_zeros(api_client):
    """No orders → both counts are 0."""
    body = api_client.get("/api/orders/counts").json()
    assert body == {"urgency": 0, "incomplete": 0}


# ---------------------------------------------------------------------------
# Active-order filtering (FR2)
# ---------------------------------------------------------------------------


def test_order_counts_excludes_completed_orders(api_client):
    """Completed orders are terminal and must not be counted in either
    badge."""
    order = _create_order(api_client, total=100000)
    # Pay in full so the delivered→completed transition is allowed.
    _create_txn(
        api_client,
        order["orderRef"],
        amount=100000,
        type="payment",
        method="cash",
    )
    # Transition new → confirmed → in_progress → ready → delivered → completed.
    for status in ("confirmed", "in_progress", "ready", "delivered", "completed"):
        resp = api_client.post(
            f"/api/orders/{order['orderRef']}/status",
            json={"status": status},
        )
        assert resp.status_code == 200, resp.text

    body = api_client.get("/api/orders/counts").json()
    # The completed order should not bump either count beyond baseline.
    # Use a baseline-by-comparison approach: create a fresh new order and
    # verify only it contributes.
    fresh = _create_order(api_client, customer="Khách mới", total=150000)
    body_after = api_client.get("/api/orders/counts").json()
    # The fresh order contributes to urgency (due today → urgent) and
    # possibly incomplete (missing source/due_time depending on payload).
    # The completed order should not appear, so urgency should be at most
    # the count contributed by the fresh order alone.
    assert body_after["urgency"] >= 1  # fresh order is urgent (due today)
    # Before adding the fresh order, urgency from the completed order alone
    # must have been 0.
    assert body["urgency"] == 0, (
        f"completed order should not contribute to urgency, got {body}"
    )


def test_order_counts_excludes_cancelled_orders(api_client):
    """Cancelled orders are terminal and must not be counted."""
    order = _create_order(api_client, total=100000)
    resp = api_client.post(
        f"/api/orders/{order['orderRef']}/status",
        json={"status": "cancelled"},
    )
    assert resp.status_code == 200

    body = api_client.get("/api/orders/counts").json()
    # The cancelled order should not contribute to urgency (it is terminal).
    assert body["urgency"] == 0


def test_order_counts_excludes_delivered_fully_paid_orders(api_client):
    """Delivered + fully-paid orders are filtered out of the active view
    (same rule as GET /api/orders?active_only=true). They must not
    contribute to either badge."""
    order = _create_order(api_client, total=200000)
    _create_txn(
        api_client, order["orderRef"], amount=200000, type="payment", method="cash"
    )
    resp = api_client.post(
        f"/api/orders/{order['orderRef']}/status", json={"status": "delivered"}
    )
    assert resp.status_code == 200

    body = api_client.get("/api/orders/counts").json()
    # Delivered + fully paid → excluded from active view → urgency 0.
    assert body["urgency"] == 0, (
        f"delivered+paid order should not contribute to urgency, got {body}"
    )


# ---------------------------------------------------------------------------
# Urgency counts (FR2 — critical + urgent)
# ---------------------------------------------------------------------------


def test_order_counts_urgency_counts_critical_and_urgent(api_client):
    """Orders due today (non-terminal) are urgent → counted in urgency."""
    # An order due today with status 'new' is urgent per compute_urgency.
    _create_order(api_client, total=100000)

    body = api_client.get("/api/orders/counts").json()
    assert body["urgency"] >= 1


def test_order_counts_urgency_excludes_normal_orders(api_client):
    """Orders due in the far future (normal tier) are NOT counted in
    urgency."""
    _create_order(api_client, total=100000, dueDate="2099-12-31")

    body = api_client.get("/api/orders/counts").json()
    # Due in 2099 → normal tier, not urgent/critical.
    assert body["urgency"] == 0


# ---------------------------------------------------------------------------
# Incomplete counts (FR2)
# ---------------------------------------------------------------------------


def test_order_counts_incomplete_counts_missing_fields(api_client):
    """An order missing required fields (no source, no due_time) is
    incomplete → counted in incomplete."""
    # Create an order without 'source' and 'dueTime' — both required fields.
    # _create_order default payload omits them.
    _create_order(api_client, total=100000)

    body = api_client.get("/api/orders/counts").json()
    # The default payload omits source and dueTime → incomplete.
    assert body["incomplete"] >= 1


def test_order_counts_incomplete_excludes_complete_orders(api_client):
    """A fully-populated order is complete → not counted in incomplete."""
    payload = {
        "customerName": "Nguyễn Văn B",
        "customerPhone": "0901234567",
        "deliveryPhone": "0901234567",
        "dueDate": _today(),
        "dueTime": "14:00",
        "deliveryType": "pickup",
        "source": "manual",
        "items": [
            {
                "productName": "Bánh kem",
                "quantity": 1,
                "unitPrice": 200000,
                "productId": "BKS-16",
            }
        ],
    }
    resp = api_client.post("/api/orders", json=payload)
    assert resp.status_code == 201, resp.text

    # Get baseline incomplete count from orders created by other tests in
    # this session — verify our complete order is NOT in the incomplete
    # count by checking via the dedicated orders endpoint.
    orders_resp = api_client.get("/api/orders", params={"active_only": True})
    assert orders_resp.status_code == 200
    our_order = next(
        (o for o in orders_resp.json() if o["customerName"] == "Nguyễn Văn B"),
        None,
    )
    assert our_order is not None
    assert our_order["completeness"] == "complete", (
        f"expected complete order, got {our_order['completeness']} "
        f"(missing: {our_order.get('missingFields')})"
    )


# ---------------------------------------------------------------------------
# Zero-on-error contract (FR2)
# ---------------------------------------------------------------------------


def test_order_counts_returns_zero_on_db_error(monkeypatch, api_client):
    """FR2: when the count query raises, the endpoint returns
    {urgency: 0, incomplete: 0} instead of 500 — degraded UX avoids
    showing stale badges."""
    import baker.api.orders as orders_mod

    def _boom(*args, **kwargs):
        raise RuntimeError("simulated DB failure")

    monkeypatch.setattr(orders_mod, "get_db", _boom)

    body = api_client.get("/api/orders/counts").json()
    assert body == {"urgency": 0, "incomplete": 0}


# ---------------------------------------------------------------------------
# CQ-2 — batched amount_paid (no N+1 per-order SUM query)
# ---------------------------------------------------------------------------


def test_order_counts_uses_batched_amount_paid_not_per_row_queries(
    monkeypatch, api_client
):
    """CQ-2: the counts endpoint computes amount_paid for all delivered orders
    in a single grouped SUM query (sum_paid_excl_outflows_batch), NOT one
    total_paid_excl_outflows call per delivered row (N+1). Verified by
    monkeypatching the per-row helper to fail if invoked and the batch
    helper to record a single call."""
    import baker.api.orders as orders_mod
    from baker.models.payment_transaction import PaymentTransaction

    # Create several delivered orders so the N+1 path would issue multiple
    # per-row SUM queries.
    delivered_paid_count = 3
    for i in range(delivered_paid_count):
        order = _create_order(api_client, customer=f"Khách {i}", total=200000)
        _create_txn(
            api_client,
            order["orderRef"],
            amount=200000,
            type="payment",
            method="cash",
        )
        resp = api_client.post(
            f"/api/orders/{order['orderRef']}/status",
            json={"status": "delivered"},
        )
        assert resp.status_code == 200, resp.text

    batch_calls = {"count": 0, "ids": []}

    def _fake_batch(conn, order_ids):
        batch_calls["count"] += 1
        batch_calls["ids"].append(list(order_ids))
        # Delegate to the real implementation so the counts are correct.
        return PaymentTransaction.sum_paid_excl_outflows_batch(conn, order_ids)

    def _fail_per_row(*args, **kwargs):
        raise AssertionError(
            "CQ-2: counts endpoint must not call per-row "
            "total_paid_excl_outflows — use the batched helper instead."
        )

    monkeypatch.setattr(orders_mod, "_sum_paid_excl_outflows_batch", _fake_batch)
    # The per-row helper is still imported by list_orders; only fail it
    # within the counts endpoint path by patching the model method that
    # _is_delivered_and_fully_paid delegates to.
    monkeypatch.setattr(PaymentTransaction, "total_paid_excl_outflows", _fail_per_row)

    body = api_client.get("/api/orders/counts").json()

    # The batched helper was called exactly once with all delivered order ids.
    assert batch_calls["count"] == 1, (
        f"expected 1 batched amount_paid query, got {batch_calls['count']}"
    )
    assert len(batch_calls["ids"][0]) == delivered_paid_count, (
        f"expected {delivered_paid_count} delivered ids in one batch, "
        f"got {len(batch_calls['ids'][0])}"
    )
    # All delivered+paid orders are excluded from urgency.
    assert body["urgency"] == 0


def test_sum_paid_excl_outflows_batch_returns_grouped_totals(api_client):
    """CQ-2: PaymentTransaction.sum_paid_excl_outflows_batch returns a
    {order_id: amount_paid} map from a single grouped query, and matches
    the per-order total_paid_excl_outflows values."""
    from baker.db.connection import get_db
    from baker.models.payment_transaction import PaymentTransaction

    order_a = _create_order(api_client, customer="A", total=100000)
    order_b = _create_order(api_client, customer="B", total=300000)
    _create_txn(api_client, order_a["orderRef"], amount=60000, type="payment")
    _create_txn(api_client, order_b["orderRef"], amount=300000, type="payment")

    with get_db() as conn:
        ids = [int(order_a["id"]), int(order_b["id"])]
        batch = PaymentTransaction.sum_paid_excl_outflows_batch(conn, ids)
        # Matches per-order totals.
        assert batch[int(order_a["id"])] == pytest.approx(60000)
        assert batch[int(order_b["id"])] == pytest.approx(300000)
        # Empty input issues no query.
        assert PaymentTransaction.sum_paid_excl_outflows_batch(conn, []) == {}


# ---------------------------------------------------------------------------
# Consistency with active_only list (FR2)
# ---------------------------------------------------------------------------


def test_order_counts_matches_active_only_filtering(api_client):
    """The urgency count from /api/orders/counts must equal the count of
    urgent/critical orders in GET /api/orders?active_only=true. This
    verifies the count endpoint uses the same active-filter rule as the
    list endpoint (delivered+paid excluded, terminal excluded)."""
    # Create a mix: one new order due today (urgent), one delivered+paid
    # (excluded), one far-future order (normal, not urgent).
    _create_order(api_client, customer="Khách gấp", total=100000)
    paid = _create_order(api_client, customer="Khách đã trả", total=200000)
    _create_txn(
        api_client, paid["orderRef"], amount=200000, type="payment", method="cash"
    )
    api_client.post(
        f"/api/orders/{paid['orderRef']}/status", json={"status": "delivered"}
    )
    _create_order(api_client, customer="Khách xa", total=150000, dueDate="2099-12-31")

    counts = api_client.get("/api/orders/counts").json()
    active = api_client.get("/api/orders", params={"active_only": True}).json()
    expected_urgency = sum(1 for o in active if o["urgency"] in ("critical", "urgent"))
    expected_incomplete = sum(1 for o in active if o["completeness"] == "incomplete")
    assert counts["urgency"] == expected_urgency, (
        f"urgency {counts['urgency']} != active-only urgent count {expected_urgency}"
    )
    assert counts["incomplete"] == expected_incomplete, (
        f"incomplete {counts['incomplete']} != active-only incomplete count "
        f"{expected_incomplete}"
    )


# ---------------------------------------------------------------------------
# Report endpoints no longer embed the order list (FR7/FR8/AC8)
# ---------------------------------------------------------------------------


def test_today_summary_does_not_embed_orders(api_client):
    """FR7/AC8: GET /api/reports/today-summary returns aggregate metrics
    only — the 'orders' key is absent and 'statusBreakdown' is present."""
    _create_order(api_client, total=100000)
    body = api_client.get(
        "/api/reports/today-summary", params={"date": _today()}
    ).json()
    assert "orders" not in body
    assert "statusBreakdown" in body
    assert isinstance(body["statusBreakdown"], dict)


def test_period_summary_does_not_embed_orders(api_client):
    """FR8/AC8: GET /api/reports/period-summary returns aggregate metrics
    only — the 'orders' key is absent and 'statusBreakdown' is present."""
    _create_order(api_client, total=100000)
    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    assert "orders" not in body
    assert "statusBreakdown" in body
    assert isinstance(body["statusBreakdown"], dict)


def test_today_summary_status_breakdown_sums_to_order_count(api_client):
    """AC8: statusBreakdown values sum to orderCount."""
    _create_order(api_client, customer="A", total=100000)
    _create_order(api_client, customer="B", total=150000)
    body = api_client.get(
        "/api/reports/today-summary", params={"date": _today()}
    ).json()
    assert sum(body["statusBreakdown"].values()) == body["orderCount"]


def test_period_summary_status_breakdown_sums_to_order_count(api_client):
    """AC8: statusBreakdown values sum to orderCount for period-summary."""
    _create_order(api_client, customer="A", total=100000)
    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    assert sum(body["statusBreakdown"].values()) == body["orderCount"]
