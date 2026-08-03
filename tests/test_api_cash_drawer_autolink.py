"""Tests for cash drawer auto-link — DG-324 Phase 3.

Covers:
    - AC4: cash payment_transactions auto-link to the active drawer via
      cash_drawer_id and accumulate into the drawer's cash_sales total.
    - AC5: cash expense events auto-link to the active drawer via
      cash_drawer_id and accumulate into the drawer's cash_expenses total.
    - Non-cash payments/expenses are NOT linked (NULL cash_drawer_id).
    - No active drawer → link skipped (NULL), no regression.
    - Update/delete/invalidate reconciliation reverses prior contributions.
    - NFR1: drawer expected_balance reflects linked cash_sales + cash_expenses.
    - NFR3: existing journal entries still balance after auto-link.
"""

import pytest

# DG-347 Phase 1 dropped the cash_drawer_id column from payment_transactions
# and events, and dropped the accumulator columns from cash_drawer. The
# auto-link tests assert on cash_drawer_id linking and accumulator totals,
# which are removed in Phase 3. Skip until Phase 3 updates the API/service
# code and these tests are adapted.
pytestmark = pytest.mark.skip(
    reason="DG-347 Phase 1: cash_drawer_id and accumulator columns dropped; "
           "re-enable in Phase 3 once API/service code is updated"
)

from baker.db.connection import get_db
from baker.models.cash_drawer import CashDrawer


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _open_drawer(client, opening=1_000_000):
    resp = client.post("/api/cash-drawer/open", json={"openingBalance": opening})
    assert resp.status_code == 201, resp.text
    return resp.json()


def _create_order(client, customer="Nguyễn Văn A", total=300000):
    resp = client.post("/api/orders", json={
        "customerName": customer,
        "dueDate": "2026-03-25",
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": total,
                   "productId": "BKS-16"}],
    })
    assert resp.status_code == 201
    return resp.json()


def _create_txn(client, ref, amount=100000, **kwargs):
    payload = {"amount": amount, **kwargs}
    resp = client.post(f"/api/orders/{ref}/transactions", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _create_expense(client, amount=50000, category="Vận chuyển",
                    payment_source="Tiền mặt tại quầy", paid_by_name="Phượng",
                    vendor="Chợ", note="ghi chu", summary="Chi phí test",
                    payment_method="Tiền mặt"):
    resp = client.post("/api/events", json={
        "summary": summary,
        "type": "expense",
        "data": {
            "amount_vnd": amount,
            "category": category,
            "payment_method": payment_method,
            "payment_source": payment_source,
            "vendor": vendor,
            "note": note,
            "paid_by_name": paid_by_name,
        },
    })
    assert resp.status_code == 201, resp.text
    return resp.json()


def _txn_cash_drawer_id(conn, txn_id: int):
    row = conn.execute(
        "SELECT cash_drawer_id FROM payment_transactions WHERE id = ?", (txn_id,)
    ).fetchone()
    return row["cash_drawer_id"] if row else None


def _event_cash_drawer_id(conn, event_id: int):
    row = conn.execute(
        "SELECT cash_drawer_id FROM events WHERE id = ?", (event_id,)
    ).fetchone()
    return row["cash_drawer_id"] if row else None


def _drawer(conn, drawer_id: int) -> CashDrawer | None:
    return CashDrawer.get_by_id(conn, drawer_id)


# ---------------------------------------------------------------------------
# AC4: cash payment_transactions auto-link
# ---------------------------------------------------------------------------


def test_cash_payment_links_to_active_drawer_ac4(api_client):
    """AC4: active drawer exists → cash payment → payment linked via
    cash_drawer_id and drawer.cash_sales increased."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"], amount=150_000,
                     method="cash", type="deposit")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert _txn_cash_drawer_id(conn, txn_id) == drawer_id
        d = _drawer(conn, drawer_id)
        assert d is not None
        assert d.cash_sales == 150_000
        # NFR1: expected balance now includes the cash sale
        assert d.expected_balance() == 1_000_000 + 150_000


def test_transfer_payment_not_linked(api_client):
    """Bank transfers do not touch the physical drawer — no link."""
    _open_drawer(api_client)
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"], amount=100_000,
                     method="transfer", type="deposit")
    with get_db() as conn:
        assert _txn_cash_drawer_id(conn, int(txn["id"])) is None
        drawer = CashDrawer.get_active(conn)
        assert drawer.cash_sales == 0


def test_card_payment_not_linked(api_client):
    """Card payments do not touch the physical drawer — no link."""
    _open_drawer(api_client)
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"], amount=100_000,
                     method="card", type="deposit")
    with get_db() as conn:
        assert _txn_cash_drawer_id(conn, int(txn["id"])) is None


def test_cash_payment_without_active_drawer_not_linked(api_client):
    """No active drawer → cash payment keeps NULL cash_drawer_id (no error)."""
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"], amount=50_000, method="cash")
    with get_db() as conn:
        assert _txn_cash_drawer_id(conn, int(txn["id"])) is None
        assert CashDrawer.get_active(conn) is None


def test_refund_cash_payment_reduces_cash_sales(api_client):
    """An outflow (refund) cash transaction reduces the drawer's cash_sales."""
    _open_drawer(api_client, opening=1_000_000)
    order = _create_order(api_client)
    # Inflow deposit
    _create_txn(api_client, order["orderRef"], amount=200_000, method="cash",
                type="deposit")
    # Outflow refund
    _create_txn(api_client, order["orderRef"], amount=50_000, method="cash",
                type="refund")
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        assert drawer.cash_sales == 200_000 - 50_000
        assert drawer.expected_balance() == 1_000_000 + 150_000


def test_update_cash_payment_amount_adjusts_cash_sales(api_client):
    """Updating a linked cash transaction's amount recomputes the drawer total."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100_000, method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_sales == 100_000

    # Update amount to 250,000
    resp = api_client.patch(f"/api/orders/{ref}/transactions/{txn_id}",
                            json={"amount": 250_000})
    assert resp.status_code == 200, resp.text
    with get_db() as conn:
        d = _drawer(conn, drawer_id)
        assert d.cash_sales == 250_000
        assert _txn_cash_drawer_id(conn, txn_id) == drawer_id


def test_update_payment_method_to_transfer_unlinks(api_client):
    """Changing a cash payment to transfer clears the link + reverses cash_sales."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100_000, method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_sales == 100_000

    resp = api_client.patch(f"/api/orders/{ref}/transactions/{txn_id}",
                            json={"method": "transfer"})
    assert resp.status_code == 200, resp.text
    with get_db() as conn:
        assert _txn_cash_drawer_id(conn, txn_id) is None
        assert _drawer(conn, drawer_id).cash_sales == 0


def test_delete_cash_payment_reverses_cash_sales(api_client):
    """Deleting a linked cash transaction reverses its cash_sales contribution."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=120_000, method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_sales == 120_000

    resp = api_client.delete(f"/api/orders/{ref}/transactions/{txn_id}")
    assert resp.status_code == 204, resp.text
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_sales == 0


def test_invalidate_cash_payment_reverses_cash_sales(api_client):
    """Invalidating a linked cash transaction reverses its cash_sales contribution."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=80_000, method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_sales == 80_000

    resp = api_client.post(
        f"/api/orders/{ref}/transactions/{txn_id}/invalidate",
        json={"invalidatedBy": "test", "reason": "sai"},
    )
    assert resp.status_code == 200, resp.text
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_sales == 0


# ---------------------------------------------------------------------------
# AC5: cash expense events auto-link
# ---------------------------------------------------------------------------


def test_cash_expense_links_to_active_drawer_ac5(api_client):
    """AC5: active drawer exists → cash expense → expense linked via
    cash_drawer_id and drawer.cash_expenses increased."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    ev = _create_expense(api_client, amount=50_000,
                         payment_source="Tiền mặt tại quầy")
    event_id = int(ev["id"])
    with get_db() as conn:
        assert _event_cash_drawer_id(conn, event_id) == drawer_id
        d = _drawer(conn, drawer_id)
        assert d is not None
        assert d.cash_expenses == 50_000
        # NFR1: expected balance = opening - cash_expenses
        assert d.expected_balance() == 1_000_000 - 50_000


def test_bank_expense_not_linked(api_client):
    """Expenses paid from a bank source (TK Phượng VCB → 1210) do not link."""
    _open_drawer(api_client)
    ev = _create_expense(api_client, amount=50_000,
                         payment_source="TK Phượng VCB")
    with get_db() as conn:
        assert _event_cash_drawer_id(conn, int(ev["id"])) is None
        drawer = CashDrawer.get_active(conn)
        assert drawer.cash_expenses == 0


def test_debt_expense_not_linked(api_client):
    """Debt expenses credit Accounts Payable, not cash — no link."""
    _open_drawer(api_client)
    resp = api_client.post("/api/events", json={
        "summary": "Mua nợ nguyên liệu",
        "type": "expense",
        "data": {
            "amount_vnd": 100_000,
            "category": "Nguyên liệu",
            "payment_method": "Nợ",
            "payment_source": "",
            "vendor": "NCC A",
            "note": "ghi nợ",
            "paid_by_name": "",
        },
    })
    assert resp.status_code == 201, resp.text
    with get_db() as conn:
        assert _event_cash_drawer_id(conn, int(resp.json()["id"])) is None
        drawer = CashDrawer.get_active(conn)
        assert drawer.cash_expenses == 0


def test_cash_expense_without_active_drawer_not_linked(api_client):
    """No active drawer → cash expense keeps NULL cash_drawer_id (no error)."""
    ev = _create_expense(api_client, amount=50_000,
                         payment_source="Tiền mặt tại quầy")
    with get_db() as conn:
        assert _event_cash_drawer_id(conn, int(ev["id"])) is None
        assert CashDrawer.get_active(conn) is None


def test_update_cash_expense_amount_adjusts_cash_expenses(api_client):
    """Updating a linked cash expense's amount recomputes the drawer total."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    ev = _create_expense(api_client, amount=50_000,
                         payment_source="Tiền mặt tại quầy")
    event_id = int(ev["id"])
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_expenses == 50_000

    resp = api_client.patch(f"/api/events/{event_id}", json={
        "data": {
            "amount_vnd": 120_000,
            "category": "Vận chuyển",
            "payment_method": "Tiền mặt",
            "payment_source": "Tiền mặt tại quầy",
            "vendor": "Chợ",
            "note": "ghi chu",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 200, resp.text
    with get_db() as conn:
        d = _drawer(conn, drawer_id)
        assert d.cash_expenses == 120_000
        assert _event_cash_drawer_id(conn, event_id) == drawer_id


def test_update_expense_to_bank_unlinks(api_client):
    """Changing a cash expense to a bank source clears the link + reverses total."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    ev = _create_expense(api_client, amount=60_000,
                         payment_source="Tiền mặt tại quầy")
    event_id = int(ev["id"])
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_expenses == 60_000

    resp = api_client.patch(f"/api/events/{event_id}", json={
        "data": {
            "amount_vnd": 60_000,
            "category": "Vận chuyển",
            "payment_method": "Tiền mặt",
            "payment_source": "TK Phượng VCB",
            "vendor": "Chợ",
            "note": "ghi chu",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 200, resp.text
    with get_db() as conn:
        assert _event_cash_drawer_id(conn, event_id) is None
        assert _drawer(conn, drawer_id).cash_expenses == 0


def test_delete_cash_expense_reverses_cash_expenses(api_client):
    """Soft-deleting a linked cash expense reverses its cash_expenses contribution."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    ev = _create_expense(api_client, amount=70_000,
                         payment_source="Tiền mặt tại quầy")
    event_id = int(ev["id"])
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_expenses == 70_000

    resp = api_client.delete(f"/api/events/{event_id}")
    assert resp.status_code == 204, resp.text
    with get_db() as conn:
        assert _drawer(conn, drawer_id).cash_expenses == 0


# ---------------------------------------------------------------------------
# NFR1 + NFR3: combined balance + journal entries still balance
# ---------------------------------------------------------------------------


def test_expected_balance_includes_cash_sales_and_cash_expenses(api_client):
    """NFR1: expected_balance = opening + cash_sales - cash_expenses after
    both a cash payment and a cash expense auto-link."""
    _open_drawer(api_client, opening=1_000_000)
    order = _create_order(api_client)
    _create_txn(api_client, order["orderRef"], amount=500_000, method="cash")
    _create_expense(api_client, amount=50_000, payment_source="Tiền mặt tại quầy")
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    body = resp.json()
    # 1,000,000 + 500,000 - 50,000 = 1,450,000
    assert body["cashSales"] == 500_000
    assert body["cashExpenses"] == 50_000
    assert body["expectedBalance"] == 1_450_000


def test_autolink_journal_entries_still_balance(api_client):
    """NFR3: existing payment and expense journal entries still balance after
    the auto-link logic runs (auto-link must not break double-entry)."""
    _open_drawer(api_client, opening=1_000_000)
    order = _create_order(api_client)
    _create_txn(api_client, order["orderRef"], amount=200_000, method="cash")
    _create_expense(api_client, amount=30_000, payment_source="Tiền mặt tại quầy")

    with get_db() as conn:
        for source_type in ("payment_transaction", "expense"):
            rows = conn.execute(
                "SELECT jl.debit, jl.credit FROM journal_lines jl "
                "JOIN journal_entries je ON je.id = jl.journal_entry_id "
                "WHERE je.source_type = ?",
                (source_type,),
            ).fetchall()
            debit = sum(float(r["debit"]) for r in rows)
            credit = sum(float(r["credit"]) for r in rows)
            assert abs(debit - credit) < 0.005, (
                f"unbalanced {source_type}: debit={debit} credit={credit}"
            )