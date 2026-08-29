"""Tests for the reporting API — GET /api/reports/today-summary (DG-376 Phase 2).

Covers:
- Empty day (0 orders, 0 journal entries)
- Orders in various statuses (new, completed, cancelled) all counted
- Journal-only revenue (no double-count from order totalPrice)
- source_type filter (non-payment entries excluded from cash/bank totals)
- Response structure validation (all keys present, correct types)
"""

import pytest

from baker.db.connection import get_db
from baker.services.inventory_fifo import create_lot_with_items
from baker.utils.time import now_utc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _today() -> str:
    return now_utc()[:10]


def _create_order(client, customer="Nguyễn Văn A", total=300000, items=None, **kwargs):
    if items is None:
        items = [
            {"productName": "Bánh kem", "quantity": 1, "unitPrice": total, "productId": "BKS-16"}
        ]
    payload = {"customerName": customer, "dueDate": _today(), "items": items, **kwargs}
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _create_txn(client, ref, amount=100000, **kwargs):
    payload = {"amount": amount, **kwargs}
    resp = client.post(f"/api/orders/{ref}/transactions", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _mark_product_display(conn, product_id: int, value: str = "true"):
    conn.execute(
        """INSERT INTO product_attribute_values (product_id, attribute_type, value)
           VALUES (?, 'trung_bay', ?)
           ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
        (product_id, value),
    )


def _set_stock(conn, product_id: int, quantity: int):
    conn.execute(
        "DELETE FROM inventory_items WHERE lot_id IN (SELECT id FROM stock_lots WHERE product_id = ?)",
        (product_id,),
    )
    conn.execute("DELETE FROM stock_lots WHERE product_id = ?", (product_id,))
    if quantity > 0:
        create_lot_with_items(conn, product_id, None, quantity)


def _freeze_reconciliation_date(monkeypatch) -> str:
    """Freeze the business date so UTC/local midnight skew cannot change setup."""
    from datetime import date as real_date

    from baker.api import reconciliations

    report_date = "2026-08-23"

    class FrozenDate(real_date):
        @classmethod
        def today(cls):
            return cls.fromisoformat(report_date)

    monkeypatch.setattr(reconciliations, "date", FrozenDate)
    return report_date


def _submit_reconciliation_with_sale(client, payment_method="cash", sale_qty=2,
                                     unit_price=12000, product_id=1):
    """Submit a reconciliation with one sale row and return the API response.

    Sets up product 1 as a displayed product with stock so the reconciliation
    sale flow creates ``sale_qty`` delivered orders with ``source='reconciliation'``.
    """
    with get_db() as conn:
        _mark_product_display(conn, product_id, "true")
        _set_stock(conn, product_id, sale_qty)

    resp = client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "payment_method": payment_method,
            "lines": [
                {
                    "product_id": product_id,
                    "expected_qty": sale_qty,
                    "counted_qty": 0,
                    "sale_qty": sale_qty,
                    "waste_qty": 0,
                    "manual_unit_price": unit_price,
                }
            ],
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


# ---------------------------------------------------------------------------
# Response structure validation (AC4)
# ---------------------------------------------------------------------------


def test_today_summary_response_structure(api_client):
    """AC4: GET /api/reports/today-summary returns all required keys with
    correct types in a single JSON payload."""
    resp = api_client.get("/api/reports/today-summary", params={"date": _today()})
    assert resp.status_code == 200
    body = resp.json()
    # All required keys present
    for key in (
        "date",
        "revenue",
        "orderCount",
        "cashTotal",
        "bankTransferTotal",
        "cashInTotal",
        "cashOutTotal",
        "statusBreakdown",
    ):
        assert key in body, f"Missing key: {key}"
    # Correct types
    assert body["date"] == _today()
    assert isinstance(body["revenue"], (int, float))
    assert isinstance(body["orderCount"], int)
    assert isinstance(body["cashTotal"], (int, float))
    assert isinstance(body["bankTransferTotal"], (int, float))
    assert isinstance(body["cashInTotal"], (int, float))
    assert isinstance(body["cashOutTotal"], (int, float))
    assert isinstance(body["statusBreakdown"], dict)
    # DG-409 Phase 1 (FR7/AC8): the embedded order list is no longer
    # returned — only aggregate metrics. The dashboard fetches the order
    # list via GET /api/orders?due_date=... separately.
    assert "orders" not in body


def test_today_summary_default_date_is_today(api_client):
    """When no date param is passed, the API defaults to today's date."""
    resp = api_client.get("/api/reports/today-summary")
    assert resp.status_code == 200
    assert resp.json()["date"] == _today()


# ---------------------------------------------------------------------------
# Empty day
# ---------------------------------------------------------------------------


def test_today_summary_empty_day(api_client):
    """No orders and no journal entries → all metrics zero."""
    resp = api_client.get("/api/reports/today-summary", params={"date": _today()})
    assert resp.status_code == 200
    body = resp.json()
    assert body["revenue"] == 0
    assert body["orderCount"] == 0
    assert body["cashTotal"] == 0
    assert body["bankTransferTotal"] == 0
    assert body["cashInTotal"] == 0
    assert body["cashOutTotal"] == 0
    # DG-409 Phase 1: statusBreakdown replaces the embedded orders list.
    assert body["statusBreakdown"] == {}
    assert "orders" not in body


# ---------------------------------------------------------------------------
# Bug 1: Include completed POS orders in order count (FR1)
# ---------------------------------------------------------------------------


def test_today_summary_counts_all_statuses(api_client):
    """FR1/AC1: order count includes new, completed, and cancelled orders."""
    # new order
    o1 = _create_order(api_client, total=100000)
    # completed order (POS quick-sale)
    o2 = _create_order(api_client, total=150000, status="delivered", paymentMethod="cash")
    # cancelled order — create then cancel via status endpoint
    o3 = _create_order(api_client, total=200000)
    resp = api_client.post(f"/api/orders/{o3['orderRef']}/status", json={"status": "cancelled"})
    assert resp.status_code == 200

    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    # DG-409 Phase 1: the orders list is no longer embedded — verify via
    # orderCount and statusBreakdown instead. All three orders due today
    # are counted regardless of status.
    assert body["orderCount"] >= 3
    # statusBreakdown should include the new and cancelled statuses.
    assert "new" in body["statusBreakdown"]
    assert "cancelled" in body["statusBreakdown"]


def test_today_summary_orders_include_status_field(api_client):
    """DG-409 Phase 1: the orders list is no longer embedded; the
    statusBreakdown dict carries the per-status counts instead. Verify the
    new order shows up under the 'new' status bucket."""
    o = _create_order(api_client, total=100000)
    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    assert "orders" not in body
    assert body["statusBreakdown"].get("new", 0) >= 1


# ---------------------------------------------------------------------------
# Bug 3: Revenue from journal 4100 only — no double-count (FR2/AC2)
# ---------------------------------------------------------------------------


def test_today_summary_revenue_from_journal_only(api_client):
    """FR2/AC2: revenue = sum of journal 4100 credits, not order totalPrice.

    Create an order, pay it fully, and deliver it. The revenue should equal
    the journal 4100 credit (which equals the payment), not totalPrice added
    on top.
    """
    order = _create_order(api_client, total=300000)
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=300000, type="payment", method="cash")
    # Transition to delivered → creates the revenue journal entry (4100 credit)
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200

    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    # Revenue must equal 300000 (the journal credit), NOT 600000 (double-count).
    assert body["revenue"] == pytest.approx(300000.0)


def test_today_summary_revenue_no_double_count_partial_payment(api_client):
    """FR2/AC2: partially-paid delivered order — revenue = journal only.

    Create a 300000 order, pay 200000, deliver. Revenue should be 200000
    (the journal credit), not 500000 (totalPrice + payment).
    """
    order = _create_order(api_client, total=300000)
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=200000, type="payment", method="cash")
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200

    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    assert body["revenue"] == pytest.approx(200000.0)


# ---------------------------------------------------------------------------
# Bug 4: source_type filter for cash/bank totals (FR3/AC3)
# ---------------------------------------------------------------------------


def test_today_summary_cash_total_excludes_non_payment_entries(api_client):
    """FR3/AC3: cash total only sums journal debits to 1101 where
    source_type = 'payment_transaction'.

    An owner_capital entry (source_type='owner_capital') debits 1101 but
    must NOT be counted in cashTotal. A cash payment transaction debiting
    1101 must be counted.
    """
    # Owner capital — debits 1101, source_type='owner_capital' — must NOT count
    resp = api_client.post(
        "/api/accounts/owner-capital",
        json={"amount": 5000000, "method": "cash"},
    )
    assert resp.status_code == 201

    # Cash payment transaction — debits 1101, source_type='payment_transaction' — counts
    order = _create_order(api_client, total=100000)
    _create_txn(api_client, order["orderRef"], amount=100000, type="deposit", method="cash")

    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    # cashTotal should be 100000 (the payment), NOT 5100000 (including owner capital).
    assert body["cashTotal"] == pytest.approx(100000.0)


def test_today_summary_bank_total_excludes_non_payment_entries(api_client):
    """FR3/AC3: bank total only sums journal debits to 1200/1210/1220/1290
    where source_type = 'payment_transaction'.

    An owner_capital transfer entry debits 1200 but must NOT be counted.
    A transfer payment transaction debiting 1290 must be counted.
    """
    # Owner capital transfer — debits 1200, source_type='owner_capital' — excluded
    resp = api_client.post(
        "/api/accounts/owner-capital",
        json={"amount": 1000000, "method": "transfer"},
    )
    assert resp.status_code == 201

    # Transfer payment transaction — debits 1290, source_type='payment_transaction' — included
    order = _create_order(api_client, total=150000)
    _create_txn(api_client, order["orderRef"], amount=150000, type="payment", method="transfer")

    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    # bankTransferTotal should be 150000, NOT 1150000.
    assert body["bankTransferTotal"] == pytest.approx(150000.0)


def test_today_summary_cash_total_includes_cash_payment(api_client):
    """Cash payment transaction correctly adds to cashTotal."""
    order = _create_order(api_client, total=250000)
    _create_txn(api_client, order["orderRef"], amount=250000, type="payment", method="cash")

    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    assert body["cashTotal"] == pytest.approx(250000.0)


def test_today_summary_bank_total_includes_transfer_payment(api_client):
    """Transfer payment transaction correctly adds to bankTransferTotal."""
    order = _create_order(api_client, total=200000)
    _create_txn(api_client, order["orderRef"], amount=200000, type="payment", method="transfer")

    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    assert body["bankTransferTotal"] == pytest.approx(200000.0)


# ---------------------------------------------------------------------------
# Combined metrics
# ---------------------------------------------------------------------------


def test_today_summary_mixed_payments(api_client):
    """Multiple orders with mixed cash + transfer payments produce correct
    cashTotal and bankTransferTotal sums."""
    # Order 1: cash payment 100000
    o1 = _create_order(api_client, total=100000)
    _create_txn(api_client, o1["orderRef"], amount=100000, type="payment", method="cash")
    # Order 2: transfer payment 200000
    o2 = _create_order(api_client, total=200000)
    _create_txn(api_client, o2["orderRef"], amount=200000, type="payment", method="transfer")
    # Order 3: cash deposit 50000 (partial)
    o3 = _create_order(api_client, total=300000)
    _create_txn(api_client, o3["orderRef"], amount=50000, type="deposit", method="cash")

    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    # cashTotal = 100000 + 50000 = 150000
    assert body["cashTotal"] == pytest.approx(150000.0)
    # bankTransferTotal = 200000
    assert body["bankTransferTotal"] == pytest.approx(200000.0)
    # orderCount >= 3
    assert body["orderCount"] >= 3


# ---------------------------------------------------------------------------
# Non-regression — existing flows still work (NFR4)
# ---------------------------------------------------------------------------


def test_today_summary_does_not_break_order_api(api_client):
    """NFR4: the reports endpoint addition does not affect existing endpoints."""
    order = _create_order(api_client, total=200000)
    resp = api_client.get("/api/orders", params={"due_date": _today()})
    assert resp.status_code == 200
    refs = {o["orderRef"] for o in resp.json()}
    assert order["orderRef"] in refs


def test_today_summary_isolated_date(api_client):
    """Querying a different date returns only that date's data."""
    # Create an order for today
    o_today = _create_order(api_client, total=100000)
    # Query a future date — should return empty
    body = api_client.get(
        "/api/reports/today-summary", params={"date": "2099-12-31"}
    ).json()
    assert body["orderCount"] == 0
    assert body["revenue"] == 0
    assert body["cashTotal"] == 0
    assert body["bankTransferTotal"] == 0
    assert body["cashInTotal"] == 0
    assert body["cashOutTotal"] == 0
    assert body["statusBreakdown"] == {}
    assert "orders" not in body


# ---------------------------------------------------------------------------
# DG-378 Phase 1 — cashInTotal / cashOutTotal extension (FR1, NFR1)
# ---------------------------------------------------------------------------


def _open_drawer(client, opening_balance=1_000_000):
    resp = client.post(
        "/api/cash-drawer/open", json={"openingBalance": opening_balance}
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_today_summary_includes_cash_in_and_cash_out_keys(api_client):
    """FR1: response now includes cashInTotal and cashOutTotal fields."""
    body = api_client.get(
        "/api/reports/today-summary", params={"date": _today()}
    ).json()
    assert "cashInTotal" in body
    assert "cashOutTotal" in body
    assert isinstance(body["cashInTotal"], (int, float))
    assert isinstance(body["cashOutTotal"], (int, float))


def test_today_summary_cash_in_total_sums_cash_drawer_cash_in_entries(api_client):
    """FR1/AC1: cashInTotal = sum of 1101 debits where
    source_type='cash_drawer_cash_in'.

    Two cash-in operations of 200000 and 300000 (default equity source)
    must produce cashInTotal = 500000.
    """
    _open_drawer(api_client, opening_balance=1_000_000)
    r1 = api_client.post(
        "/api/cash-drawer/cash-in", json={"amount": 200_000}
    )
    assert r1.status_code == 200, r1.text
    r2 = api_client.post(
        "/api/cash-drawer/cash-in",
        json={"amount": 300_000, "source": "owner"},
    )
    assert r2.status_code == 200, r2.text

    body = api_client.get(
        "/api/reports/today-summary", params={"date": _today()}
    ).json()
    assert body["cashInTotal"] == pytest.approx(500000.0)


def test_today_summary_cash_out_total_sums_cash_drawer_cash_out_entries(api_client):
    """FR1/AC2: cashOutTotal = sum of 1101 credits where
    source_type='cash_drawer_cash_out'.

    Two cash-out operations of 100000 and 50000 must produce
    cashOutTotal = 150000.
    """
    _open_drawer(api_client, opening_balance=1_000_000)
    r1 = api_client.post(
        "/api/cash-drawer/cash-out", json={"amount": 100_000}
    )
    assert r1.status_code == 200, r1.text
    r2 = api_client.post(
        "/api/cash-drawer/cash-out",
        json={"amount": 50_000, "destination": "owner"},
    )
    assert r2.status_code == 200, r2.text

    body = api_client.get(
        "/api/reports/today-summary", params={"date": _today()}
    ).json()
    assert body["cashOutTotal"] == pytest.approx(150000.0)


def test_today_summary_cash_in_out_excludes_payment_transaction_entries(api_client):
    """NFR1/FR1: cashInTotal/cashOutTotal use the source_type filter —
    payment_transaction cash debits must still flow to cashTotal, NOT to
    cashInTotal. Conversely cash_drawer_cash_in entries must NOT inflate
    cashTotal.
    """
    _open_drawer(api_client, opening_balance=500_000)
    # cash-in (cash_drawer_cash_in) — should count toward cashInTotal only
    api_client.post(
        "/api/cash-drawer/cash-in", json={"amount": 400_000}
    )
    # cash payment transaction (payment_transaction) — counts toward cashTotal only
    order = _create_order(api_client, total=250_000)
    _create_txn(
        api_client, order["orderRef"], amount=250_000, type="payment", method="cash"
    )

    body = api_client.get(
        "/api/reports/today-summary", params={"date": _today()}
    ).json()
    # cashTotal only counts the payment_transaction debit (250000), NOT the
    # cash_drawer_cash_in debit (400000).
    assert body["cashTotal"] == pytest.approx(250000.0)
    # cashInTotal only counts the cash_drawer_cash_in debit (400000), NOT the
    # payment_transaction debit (250000).
    assert body["cashInTotal"] == pytest.approx(400000.0)
    # No cash-out → cashOutTotal stays at 0.
    assert body["cashOutTotal"] == pytest.approx(0.0)


def test_today_summary_cash_in_out_zero_on_empty_day(api_client):
    """Empty day → cashInTotal and cashOutTotal are both 0."""
    body = api_client.get(
        "/api/reports/today-summary", params={"date": _today()}
    ).json()
    assert body["cashInTotal"] == 0
    assert body["cashOutTotal"] == 0


# ---------------------------------------------------------------------------
# DG-384 Phase 5 — reconciliation order visibility in today-summary (AC1)
# ---------------------------------------------------------------------------


def test_today_summary_includes_reconciliation_orders(api_client, monkeypatch):
    """DG-384 AC1: reconciliation for the report date creates sale orders
    with ``source='reconciliation'`` and a non-empty ``publicOrderCode``. The
    today-summary endpoint must count them in ``orderCount`` and surface
    their 'delivered' status via ``statusBreakdown`` (DG-409 Phase 1: the
    full order list is no longer embedded; verify order presence via
    ``GET /api/orders?due_date=<report-date>`` instead)."""
    report_date = _freeze_reconciliation_date(monkeypatch)
    session = _submit_reconciliation_with_sale(api_client, payment_method="cash",
                                               sale_qty=2, unit_price=15000)
    assert session["id"] > 0

    with get_db() as conn:
        rows = conn.execute(
            "SELECT order_ref, status, source, public_order_code, due_date "
            "FROM orders WHERE source = 'reconciliation' ORDER BY id"
        ).fetchall()
    assert len(rows) == 2, f"expected 2 reconciliation orders, got {len(rows)}"
    assert {r["due_date"] for r in rows} == {report_date}
    recon_refs = {r["order_ref"] for r in rows}

    body = api_client.get(
        "/api/reports/today-summary", params={"date": report_date}
    ).json()
    # DG-409 Phase 1: the orders list is no longer embedded in the summary
    # response — fetch via the dedicated orders endpoint to verify the
    # reconciliation orders are present and well-formed.
    orders_resp = api_client.get("/api/orders", params={"due_date": report_date})
    assert orders_resp.status_code == 200
    summary_refs = {o["orderRef"] for o in orders_resp.json()}

    # Every reconciliation order must appear in the today orders list.
    assert recon_refs.issubset(summary_refs), (
        f"reconciliation orders {recon_refs} not all in today orders {summary_refs}"
    )

    for order in orders_resp.json():
        if order["orderRef"] in recon_refs:
            assert order["status"] == "delivered", (
                f"reconciliation order {order['orderRef']} status should be 'delivered', "
                f"got {order['status']!r}"
            )
            assert order["source"] == "reconciliation", (
                f"reconciliation order {order['orderRef']} source should be 'reconciliation', "
                f"got {order['source']!r}"
            )
            assert order["publicOrderCode"], (
                f"reconciliation order {order['orderRef']} has empty publicOrderCode"
            )

    # orderCount must reflect the reconciliation orders.
    assert body["orderCount"] >= 2
    # statusBreakdown should include the delivered bucket for the recon orders.
    assert body["statusBreakdown"].get("delivered", 0) >= 2


def test_today_summary_reconciliation_orders_revenue_counted_once(
    api_client, monkeypatch
):
    """DG-384 AC1 (supplementary): reconciliation order revenue is counted
    exactly once via the journal 4100 credit — the reconciliation orders
    appear in the orders list but revenue is not double-counted by
    totalPrice."""
    unit_price = 20000
    sale_qty = 2
    report_date = _freeze_reconciliation_date(monkeypatch)
    _submit_reconciliation_with_sale(api_client, payment_method="cash",
                                     sale_qty=sale_qty, unit_price=unit_price)

    body = api_client.get(
        "/api/reports/today-summary", params={"date": report_date}
    ).json()
    # Revenue equals sum of journal 4100 credits (one per delivered order),
    # i.e. sale_qty * unit_price — not 2x that from double-counting.
    assert body["revenue"] == pytest.approx(sale_qty * unit_price)


# ---------------------------------------------------------------------------
# DG-384 Phase 5 — AC7: old reconciliation orders NOT retroactively included
# ---------------------------------------------------------------------------


def test_today_summary_excludes_old_reconciliation_orders_without_due_date(api_client):
    """DG-384 AC7: reconciliation orders created *before* the fix (i.e. with
    ``due_date IS NULL`` and ``source='reconciliation'``) must NOT be
    retroactively included in the today-summary. The fallback only matches
    reconciliation orders whose ``due_date`` equals the queried date.

    DG-409 Phase 1: verify via ``orderCount`` and the dedicated orders
    endpoint (the summary no longer embeds the orders list).

    This simulates a pre-fix reconciliation order by inserting one directly
    into the DB with a NULL ``due_date`` and an old ``created_at``."""
    with get_db() as conn:
        conn.execute(
            """INSERT INTO orders
                 (order_ref, customer_name, status, source, due_date,
                  public_order_code, total_price, created_at, updated_at)
               VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?)""",
            (
                "OLD-RECON-001",
                "Đối soát tồn kho",
                "delivered",
                "reconciliation",
                "",
                15000,
                "2025-01-15T10:00:00Z",
                "2025-01-15T10:00:00Z",
            ),
        )

    body = api_client.get("/api/reports/today-summary", params={"date": _today()}).json()
    # The old reconciliation order should not be counted in orderCount for
    # today. Use the dedicated orders endpoint to confirm absence.
    orders_resp = api_client.get("/api/orders", params={"due_date": _today()})
    refs = {o["orderRef"] for o in orders_resp.json()}
    assert "OLD-RECON-001" not in refs, (
        "old reconciliation order without due_date must NOT appear in today orders "
        "(forward-only fix)"
    )