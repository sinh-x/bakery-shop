"""Tests for Baker API — payment transactions endpoints."""

import pytest


# --- Helpers ---

def _create_order(client, customer="Nguyễn Văn A", total=300000):
    resp = client.post("/api/orders", json={
        "customerName": customer,
        "dueDate": "2026-03-25",
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
        "dueDate": "2026-03-25",
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
    """Create a tien_rut transaction on an order with tien_rut items.

    DG-198 reversal: tien_rut is a deposit inflow (customer gives cash to the
    shop for safekeeping), no longer guarded by available deposits.
    """
    order = _create_order_with_tien_rut_item(api_client, cash_amount=200000)
    ref = order["orderRef"]

    # Create tien_rut transaction (customer gives cash for safekeeping).
    txn = _create_txn(api_client, ref, amount=200000, type="tien_rut")
    assert txn["type"] == "tien_rut"
    assert txn["amount"] == 200000


def test_tien_rut_included_in_total_paid(api_client):
    """tien_rut is a deposit inflow (DG-198 reversal), so it IS included in
    amountPaid (total_paid_excl_outflows). Only refund is excluded."""
    order = _create_order_with_tien_rut_item(api_client, cash_amount=200000)
    ref = order["orderRef"]

    # Customer pays 350000 for the cake
    _create_txn(api_client, ref, amount=350000, type="payment")
    # Customer gives 200000 cash for safekeeping (tien_rut deposit inflow)
    _create_txn(api_client, ref, amount=200000, type="tien_rut")

    detail = api_client.get(f"/api/orders/{ref}").json()
    # amountPaid = 350000 + 200000 = 550000 (tien_rut is included)
    assert detail["amountPaid"] == 550000


def test_tien_rut_included_in_receipt_total_paid(api_client):
    """Receipt total_paid includes tien_rut (DG-198 reversal: deposit inflow).

    The receipt rendering uses total_paid_excl_outflows() for the balance math,
    which now includes tien_rut. Verified indirectly via amountPaid on order
    detail (which receipts use).
    """
    order = _create_order_with_tien_rut_item(api_client, cash_amount=200000)
    ref = order["orderRef"]

    # Customer pays full amount
    _create_txn(api_client, ref, amount=350000, type="payment")
    # tien_rut cash given for safekeeping
    _create_txn(api_client, ref, amount=200000, type="tien_rut")

    detail = api_client.get(f"/api/orders/{ref}").json()
    # amountPaid = 350000 + 200000 = 550000 (tien_rut included)
    assert detail["amountPaid"] == 550000


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
    """Completion guard blocks completion when payment doesn't cover total.

    DG-198 reversal: tien_rut is now a deposit inflow (counted in amountPaid),
    so an order with 200k payment + 200k tien_rut (total 370k) has amountPaid
    = 400k and SHOULD complete. This test now uses a refund (true outflow) to
    verify the guard still blocks when the net is insufficient.
    """
    order = _create_order_with_tien_rut_item(api_client, cash_amount=200000)
    ref = order["orderRef"]

    # Order total = 350000 (cake) + 20000 (cash_fee) = 370000
    # Customer pays 200000, then a 200000 refund is issued (outflow).
    # Net deposits = 200000 - 200000 = 0 < 370000 → completion blocked.
    _create_txn(api_client, ref, amount=200000, type="payment")
    _create_txn(api_client, ref, amount=200000, type="refund")

    # Completion should be blocked: 0 net paid vs 370000 total
    resp = api_client.post(f"/api/orders/{ref}/status", json={
        "status": "completed",
        "reason": "Hoàn tất đơn hàng",
    })
    assert resp.status_code == 422
    assert "thiếu" in resp.json()["detail"]


# --- DG-198 reversal — guardrail removed (tien_rut is an inflow) ---


def test_tien_rut_no_deposit_required_succeeds(api_client):
    """DG-198 reversal: tien_rut is a deposit inflow, so the API no longer
    requires available deposits before creation. A 600k tien_rut with zero
    deposits is accepted (the customer is giving cash to the shop)."""
    order = _create_order(api_client, total=600000)
    ref = order["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/transactions",
        json={"amount": 600000, "type": "tien_rut"},
    )
    assert resp.status_code == 201
    txn = resp.json()
    assert txn["type"] == "tien_rut"
    assert txn["amount"] == 600000


def test_tien_rut_exceeds_deposits_succeeds(api_client):
    """DG-198 reversal: the guardrail that rejected tien_rut > available is
    removed. 500k deposit + 600k tien_rut is accepted (no 422)."""
    order = _create_order(api_client, total=600000)
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=500000, type="payment")
    resp = api_client.post(
        f"/api/orders/{ref}/transactions",
        json={"amount": 600000, "type": "tien_rut"},
    )
    assert resp.status_code == 201


def test_tien_rut_guardrail_does_not_affect_other_types(api_client):
    """tien_rut and deposit/payment all succeed regardless of prior deposits."""
    order = _create_order(api_client, total=600000)
    ref = order["orderRef"]
    # A deposit/payment with no prior deposits must succeed (not guarded).
    resp = api_client.post(
        f"/api/orders/{ref}/transactions",
        json={"amount": 500000, "type": "payment"},
    )
    assert resp.status_code == 201


# --- Invalidate / Restore endpoints (DG-196 Phase 2) ---


def _invalidate(client, ref, txn_id, invalidated_by="sinh", reason=""):
    return client.post(
        f"/api/orders/{ref}/transactions/{txn_id}/invalidate",
        json={"invalidatedBy": invalidated_by, "reason": reason},
    )


def _restore(client, ref, txn_id):
    return client.post(f"/api/orders/{ref}/transactions/{txn_id}/restore")


def _journal_entries_for_txn(conn, txn_id):
    """Return all journal_entries rows for a payment_transaction source."""
    return conn.execute(
        "SELECT * FROM journal_entries "
        "WHERE source_type = 'payment_transaction' AND source_id = ? "
        "ORDER BY id",
        (txn_id,),
    ).fetchall()


def _journal_lines_sum(conn, entry_id, account_code):
    """Return net (debit - credit) for an account code on a journal entry."""
    row = conn.execute(
        "SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS net "
        "FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id "
        "WHERE jl.journal_entry_id = ? AND a.code = ?",
        (entry_id, account_code),
    ).fetchone()
    return float(row["net"] or 0)


def test_invalidate_sets_fields_and_reverses_journal(api_client):
    """AC1/AC2: invalidate sets invalidated_at/by and reverses (unlocked) journal."""
    from baker.db.connection import get_db

    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    txn_id = txn["id"]

    # Confirm a journal entry exists before invalidation.
    with get_db() as conn:
        entries = _journal_entries_for_txn(conn, int(txn_id))
        assert len(entries) == 1

    resp = _invalidate(api_client, ref, txn_id, invalidated_by="sinh",
                       reason="nhập nhầm")
    assert resp.status_code == 200
    data = resp.json()
    assert data["invalidatedAt"] is not None
    assert data["invalidatedBy"] == "sinh"

    # AC2: unlocked entry → deleted (reversal preserves original date, but
    # _sync_payment_journal(deleted=True) on an unlocked entry deletes it).
    with get_db() as conn:
        entries = _journal_entries_for_txn(conn, int(txn_id))
        assert len(entries) == 0


def test_invalidate_idempotent_rejected(api_client):
    """Invalidating an already-invalidated txn returns 422."""
    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    txn_id = txn["id"]

    resp = _invalidate(api_client, ref, txn_id)
    assert resp.status_code == 200
    resp2 = _invalidate(api_client, ref, txn_id)
    assert resp2.status_code == 422


def test_invalidate_txn_not_found(api_client):
    """Invalidating a non-existent txn returns 404."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = _invalidate(api_client, ref, 9999)
    assert resp.status_code == 404


def test_invalidate_wrong_order(api_client):
    """Invalidating a txn from another order returns 404."""
    order1 = _create_order(api_client, customer="A")
    order2 = _create_order(api_client, customer="B")
    txn = _create_txn(api_client, order1["orderRef"])
    resp = _invalidate(api_client, order2["orderRef"], txn["id"])
    assert resp.status_code == 404


def test_invalidate_logs_order_history(api_client):
    """FR10: invalidation is recorded in order_history with action_type='invalidate'."""
    from baker.db.connection import get_db

    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    _invalidate(api_client, ref, txn["id"], invalidated_by="sinh")

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM order_history WHERE order_id = ? AND action_type = 'invalidate'",
            (order["id"],),
        ).fetchone()
    assert row is not None
    assert row["field_name"] == "payment_transaction"


def test_invalidate_locked_journal_creates_reversal_with_current_timestamp(api_client):
    """AC3: locked journal entry → new reversal entry preserving original
    transaction_date (same-timestamp reversal via _reverse_journal_entry)."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    txn_id = int(txn["id"])

    # Lock the journal entry directly to simulate a reconciled period.
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "UPDATE journal_entries SET locked_at = '2026-06-25T00:00:00' "
            "WHERE source_type = 'payment_transaction' AND source_id = ?",
            (txn_id,),
        )
        orig = conn.execute(
            "SELECT id, transaction_date FROM journal_entries "
            "WHERE source_type = 'payment_transaction' AND source_id = ?",
            (txn_id,),
        ).fetchone()
        assert orig is not None
        orig_id = orig["id"]
        orig_date = orig["transaction_date"]

    resp = _invalidate(api_client, ref, txn["id"])
    assert resp.status_code == 200

    # AC3: the original locked entry remains, and a reversal entry is created
    # with the SAME transaction_date as the original (same-timestamp reversal).
    with get_db() as conn:
        entries = _journal_entries_for_txn(conn, txn_id)
        # original (locked) + reversal
        assert len(entries) == 2
        reversal = entries[-1]
        assert reversal["id"] != orig_id
        assert reversal["transaction_date"] == orig_date
        assert "Reversal" in reversal["description"]


def test_restore_clears_fields_and_recreates_journal(api_client):
    """AC4: restore clears invalidation and re-creates journal entry with
    the original created_at as transaction_date."""
    from baker.db.connection import get_db

    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    txn_id = int(txn["id"])

    # Capture original created_at + journal transaction_date before invalidation.
    with get_db() as conn:
        orig_txn = conn.execute(
            "SELECT created_at FROM payment_transactions WHERE id = ?", (txn_id,)
        ).fetchone()
        orig_created_at = orig_txn["created_at"]

    _invalidate(api_client, ref, txn["id"])
    # Journal entry deleted (unlocked path).
    with get_db() as conn:
        assert len(_journal_entries_for_txn(conn, txn_id)) == 0

    resp = _restore(api_client, ref, txn["id"])
    assert resp.status_code == 200
    data = resp.json()
    assert data["invalidatedAt"] is None
    assert data["invalidatedBy"] == ""

    # AC4: journal entry re-created with original created_at as transaction_date.
    with get_db() as conn:
        entries = _journal_entries_for_txn(conn, txn_id)
        assert len(entries) == 1
        assert entries[0]["transaction_date"] == orig_created_at


def test_restore_not_invalidated_rejected(api_client):
    """Restoring a txn that was never invalidated returns 422."""
    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    resp = _restore(api_client, ref, txn["id"])
    assert resp.status_code == 422


def test_restore_txn_not_found(api_client):
    """Restoring a non-existent txn returns 404."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = _restore(api_client, ref, 9999)
    assert resp.status_code == 404


def test_restore_logs_order_history(api_client):
    """FR10: restore is recorded in order_history with action_type='restore'."""
    from baker.db.connection import get_db

    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    _invalidate(api_client, ref, txn["id"], invalidated_by="sinh")
    _restore(api_client, ref, txn["id"])

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM order_history WHERE order_id = ? AND action_type = 'restore'",
            (order["id"],),
        ).fetchone()
    assert row is not None


def test_invalidate_then_restore_roundtrip_totals(api_client):
    """Invalidation removes the txn from totals; restore brings it back."""
    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    txn_id = txn["id"]

    # Before invalidation: amountPaid == 200000.
    assert api_client.get(f"/api/orders/{ref}").json()["amountPaid"] == 200000

    _invalidate(api_client, ref, txn_id)
    # After invalidation: amountPaid == 0 (invalidated excluded).
    assert api_client.get(f"/api/orders/{ref}").json()["amountPaid"] == 0

    _restore(api_client, ref, txn_id)
    # After restore: amountPaid == 200000 again.
    assert api_client.get(f"/api/orders/{ref}").json()["amountPaid"] == 200000


def test_invalidate_visible_in_list_with_fields(api_client):
    """AC7: invalidated txn still appears in GET list with invalidatedAt/By."""
    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    _invalidate(api_client, ref, txn["id"], invalidated_by="sinh")

    resp = api_client.get(f"/api/orders/{ref}/transactions")
    assert resp.status_code == 200
    txns = resp.json()
    assert len(txns) == 1
    assert txns[0]["invalidatedAt"] is not None
    assert txns[0]["invalidatedBy"] == "sinh"


def test_invalidate_journal_failure_does_not_block_api(api_client, monkeypatch):
    """NFR2: journal sync failure does not block the invalidation response."""
    from baker.services import journal_sync

    def _boom(*a, **kw):
        raise RuntimeError("journal down")

    monkeypatch.setattr(journal_sync, "_sync_payment_journal", _boom)

    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    resp = _invalidate(api_client, ref, txn["id"])
    assert resp.status_code == 200
    assert resp.json()["invalidatedAt"] is not None


def test_restore_journal_failure_does_not_block_api(api_client, monkeypatch):
    """NFR2: journal sync failure does not block the restore response."""
    from baker.services import journal_sync

    def _boom(*a, **kw):
        raise RuntimeError("journal down")

    monkeypatch.setattr(journal_sync, "_sync_payment_journal", _boom)

    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000)
    _invalidate(api_client, ref, txn["id"])
    # Restore with broken journal sync — should still succeed.
    resp = _restore(api_client, ref, txn["id"])
    assert resp.status_code == 200
    assert resp.json()["invalidatedAt"] is None
