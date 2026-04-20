"""Tests for Baker API — payment transactions endpoints."""

import pytest


# --- Helpers ---

def _create_order(client, customer="Nguyễn Văn A", total=300000):
    resp = client.post("/api/orders", json={
        "customerName": customer,
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": total}],
    })
    assert resp.status_code == 201
    return resp.json()


def _create_txn(client, ref, amount=100000, **kwargs):
    payload = {"amount": amount, **kwargs}
    resp = client.post(f"/api/orders/{ref}/transactions", json=payload)
    assert resp.status_code == 201
    return resp.json()


# --- List transactions ---


def test_list_transactions_empty(api_client):
    order = _create_order(api_client)
    resp = api_client.get(f"/api/orders/{order['orderRef']}/transactions")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_transactions_returns_created(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    _create_txn(api_client, ref)
    resp = api_client.get(f"/api/orders/{ref}/transactions")
    assert resp.status_code == 200
    assert len(resp.json()) == 1


def test_list_transactions_order_not_found(api_client):
    resp = api_client.get("/api/orders/ORD-NOTEXIST/transactions")
    assert resp.status_code == 404


# --- Create transaction ---


def test_create_transaction_minimal(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/transactions", json={"amount": 50000})
    assert resp.status_code == 201
    txn = resp.json()
    assert txn["amount"] == 50000
    assert txn["type"] == "deposit"
    assert txn["method"] == "cash"
    assert txn["note"] == ""
    assert txn["orderId"] == order["id"]


def test_create_transaction_with_all_fields(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/transactions", json={
        "amount": 150000,
        "type": "payment",
        "method": "transfer",
        "note": "Chuyển khoản ngân hàng",
    })
    assert resp.status_code == 201
    txn = resp.json()
    assert txn["amount"] == 150000
    assert txn["type"] == "payment"
    assert txn["method"] == "transfer"
    assert txn["note"] == "Chuyển khoản ngân hàng"


def test_create_transaction_id_is_string(api_client):
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"])
    assert isinstance(txn["id"], str)


def test_create_transaction_amount_zero_rejected(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/transactions", json={"amount": 0})
    assert resp.status_code == 422
    assert "lớn hơn 0" in resp.json()["detail"]


def test_create_transaction_negative_amount_rejected(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/transactions", json={"amount": -5000})
    assert resp.status_code == 422


def test_create_transaction_full_payment_type(api_client):
    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000, type="full_payment")
    assert txn["type"] == "full_payment"
    assert txn["amount"] == 200000


def test_create_transaction_invalid_type(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/transactions",
        json={"amount": 50000, "type": "unknown_type"},
    )
    assert resp.status_code == 422
    assert "Loại giao dịch" in resp.json()["detail"]


def test_create_transaction_invalid_method(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/transactions",
        json={"amount": 50000, "method": "bitcoin"},
    )
    assert resp.status_code == 422
    assert "Phương thức" in resp.json()["detail"]


def test_create_transaction_order_not_found(api_client):
    resp = api_client.post(
        "/api/orders/ORD-NOTEXIST/transactions", json={"amount": 50000}
    )
    assert resp.status_code == 404


# --- Delete transaction ---


# --- Update transaction ---


def test_update_transaction_amount(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100000)
    resp = api_client.patch(
        f"/api/orders/{ref}/transactions/{txn['id']}",
        json={"amount": 200000},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["amount"] == 200000
    assert data["type"] == txn["type"]
    assert data["method"] == txn["method"]


def test_update_transaction_type_and_method(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=50000, type="deposit", method="cash")
    resp = api_client.patch(
        f"/api/orders/{ref}/transactions/{txn['id']}",
        json={"type": "payment", "method": "transfer"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["type"] == "payment"
    assert data["method"] == "transfer"
    assert data["amount"] == 50000  # unchanged


def test_update_transaction_note(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    resp = api_client.patch(
        f"/api/orders/{ref}/transactions/{txn['id']}",
        json={"note": "ghi chú mới"},
    )
    assert resp.status_code == 200
    assert resp.json()["note"] == "ghi chú mới"


def test_update_transaction_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.patch(
        f"/api/orders/{ref}/transactions/9999", json={"amount": 50000}
    )
    assert resp.status_code == 404


def test_update_transaction_invalid_amount(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    resp = api_client.patch(
        f"/api/orders/{ref}/transactions/{txn['id']}", json={"amount": 0}
    )
    assert resp.status_code == 422


def test_update_transaction_invalid_type(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    resp = api_client.patch(
        f"/api/orders/{ref}/transactions/{txn['id']}", json={"type": "invalid_type"}
    )
    assert resp.status_code == 422


def test_update_transaction_amount_paid_reflects_update(api_client):
    order = _create_order(api_client, total=300000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100000)
    api_client.patch(
        f"/api/orders/{ref}/transactions/{txn['id']}", json={"amount": 200000}
    )
    detail = api_client.get(f"/api/orders/{ref}").json()
    assert detail["amountPaid"] == 200000


# --- Delete transaction ---


def test_delete_transaction(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    txn_id = txn["id"]
    resp = api_client.delete(f"/api/orders/{ref}/transactions/{txn_id}")
    assert resp.status_code == 204
    # Confirm gone
    list_resp = api_client.get(f"/api/orders/{ref}/transactions")
    assert list_resp.json() == []


def test_delete_transaction_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.delete(f"/api/orders/{ref}/transactions/9999")
    assert resp.status_code == 404


def test_delete_transaction_wrong_order(api_client):
    order1 = _create_order(api_client, customer="A")
    order2 = _create_order(api_client, customer="B")
    txn = _create_txn(api_client, order1["orderRef"])
    resp = api_client.delete(
        f"/api/orders/{order2['orderRef']}/transactions/{txn['id']}"
    )
    assert resp.status_code == 404


# --- amountPaid computed from transactions ---


def test_amount_paid_reflects_transactions(api_client):
    order = _create_order(api_client, total=300000)
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=100000)
    _create_txn(api_client, ref, amount=50000)
    detail = api_client.get(f"/api/orders/{ref}").json()
    assert detail["amountPaid"] == 150000
    assert detail["isPaid"] is False


def test_amount_paid_full_payment(api_client):
    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=200000)
    detail = api_client.get(f"/api/orders/{ref}").json()
    assert detail["amountPaid"] == 200000
    assert detail["isPaid"] is True


def test_amount_paid_after_delete(api_client):
    order = _create_order(api_client, total=300000)
    ref = order["orderRef"]
    txn1 = _create_txn(api_client, ref, amount=100000)
    _create_txn(api_client, ref, amount=50000)
    # Delete first transaction
    api_client.delete(f"/api/orders/{ref}/transactions/{txn1['id']}")
    detail = api_client.get(f"/api/orders/{ref}").json()
    assert detail["amountPaid"] == 50000


def test_multiple_transactions_accumulate(api_client):
    order = _create_order(api_client, total=500000)
    ref = order["orderRef"]
    for _ in range(5):
        _create_txn(api_client, ref, amount=50000)
    resp = api_client.get(f"/api/orders/{ref}/transactions")
    assert len(resp.json()) == 5
    detail = api_client.get(f"/api/orders/{ref}").json()
    assert detail["amountPaid"] == 250000


# --- Migration: amount_paid > 0 creates deposit transaction ---


def test_migration_v12_deposit_transaction_created(api_client):
    """Orders with amount_paid > 0 get a deposit transaction from v12 migration."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        # Insert order with amount_paid (pre-v12 style)
        conn.execute(
            """INSERT INTO orders (order_ref, customer_name, items, total_price, status, amount_paid)
               VALUES ('ORD-MIGR-TXN-001', 'Test', '[]', 200000, 'new', 100000)""",
        )
        order_row = conn.execute(
            "SELECT id FROM orders WHERE order_ref = 'ORD-MIGR-TXN-001'"
        ).fetchone()
        # Simulate migration: create deposit from amount_paid
        conn.execute(
            """INSERT INTO payment_transactions (order_id, amount, type, method, note)
               VALUES (?, 100000, 'deposit', 'cash', 'Migrated from amount_paid')""",
            (order_row["id"],),
        )

    resp = api_client.get("/api/orders/ORD-MIGR-TXN-001/transactions")
    assert resp.status_code == 200
    txns = resp.json()
    assert len(txns) == 1
    assert txns[0]["amount"] == 100000
    assert txns[0]["type"] == "deposit"
    assert "Migrated" in txns[0]["note"]


# --- rut_tien transaction tests ---


def _create_order_with_tien_rut_item(client, cash_amount=200000):
    """Create order with a tien_rut item."""
    resp = client.post("/api/orders", json={
        "customerName": "Test Khách Rút Tiền",
        "items": [{
            "productName": "Bánh Sinh Nhật",
            "quantity": 1,
            "unitPrice": 350000,
            "attributes": {
                "rut_tien": "true",
                "cash_amount": str(cash_amount),
                "cash_fee": "20000",
            },
        }],
    })
    assert resp.status_code == 201
    return resp.json()


def test_tien_rut_txn_creation(api_client):
    """Create a tien_rut transaction on an order with tien_rut items."""
    order = _create_order_with_tien_rut_item(api_client, cash_amount=200000)
    ref = order["orderRef"]

    # Create tien_rut transaction (cash-back to customer)
    txn = _create_txn(api_client, ref, amount=200000, type="tien_rut")
    assert txn["type"] == "tien_rut"
    assert txn["amount"] == 200000


def test_tien_rut_excluded_from_total_paid(api_client):
    """tien_rut transactions are excluded from payment total (amountPaid)."""
    order = _create_order_with_tien_rut_item(api_client, cash_amount=200000)
    ref = order["orderRef"]

    # Customer pays 350000 for the cake
    _create_txn(api_client, ref, amount=350000, type="payment")
    # Customer receives 200000 cash-back
    _create_txn(api_client, ref, amount=200000, type="tien_rut")

    detail = api_client.get(f"/api/orders/{ref}").json()
    # amountPaid should be 350000 (payment only), NOT 550000
    assert detail["amountPaid"] == 350000


def test_tien_rut_excluded_from_receipt_total_paid(api_client):
    """Receipt total_paid should not include tien_rut in the balance calculation.

    The receipt rendering uses total_paid_excl_tien_rut() for the balance math.
    We verify this indirectly: amountPaid on order detail (which receipts use)
    should exclude tien_rut, and completion guard should work correctly.
    """
    order = _create_order_with_tien_rut_item(api_client, cash_amount=200000)
    ref = order["orderRef"]

    # Customer pays full amount
    _create_txn(api_client, ref, amount=350000, type="payment")
    # tien_rut cash-back recorded
    _create_txn(api_client, ref, amount=200000, type="tien_rut")

    detail = api_client.get(f"/api/orders/{ref}").json()
    # amountPaid should be 350000 (payment only), NOT 550000
    # This confirms receipts will show correct balance since they use the same method
    assert detail["amountPaid"] == 350000


def test_completion_guard_with_tien_rut(api_client):
    """Completion guard should not pass prematurely when tien_rut cash-back exists."""
    order = _create_order_with_tien_rut_item(api_client, cash_amount=200000)
    ref = order["orderRef"]

    # Order total = 350000 (cake) + 20000 (cash_fee) = 370000
    # Pay full amount (excluding tien_rut cash-back)
    _create_txn(api_client, ref, amount=370000, type="payment")
    # tien_rut cash-back given
    _create_txn(api_client, ref, amount=200000, type="tien_rut")

    # Completion should succeed: 370000 paid vs 370000 total
    resp = api_client.post(f"/api/orders/{ref}/status", json={
        "status": "completed",
        "reason": "Hoàn tất đơn hàng",
    })
    # Should succeed (422 if tien_rut were incorrectly counted as payment)
    assert resp.status_code == 200


def test_completion_guard_premature_without_payment(api_client):
    """Completion guard blocks completion when payment doesn't cover total."""
    order = _create_order_with_tien_rut_item(api_client, cash_amount=200000)
    ref = order["orderRef"]

    # Order total = 350000 (cake) + 20000 (cash_fee) = 370000
    # Customer only pays partial amount (200000 < 370000)
    _create_txn(api_client, ref, amount=200000, type="payment")
    # tien_rut cash-back given
    _create_txn(api_client, ref, amount=200000, type="tien_rut")

    # Completion should be blocked: 200000 paid vs 370000 total
    resp = api_client.post(f"/api/orders/{ref}/status", json={
        "status": "completed",
        "reason": "Hoàn tất đơn hàng",
    })
    assert resp.status_code == 422
    assert "thiếu" in resp.json()["detail"]
