"""Endpoint coverage for revenue reconciliation after payment mutations."""

import pytest

from baker.db.connection import get_db
from baker.services.journal_sync import _sync_delivered_order_journal

pytestmark = pytest.mark.critical


def _create_order(client):
    response = client.post("/api/orders", json={
        "customerName": "Revenue test",
        "dueDate": "2026-06-25",
        "items": [{"productName": "Bánh", "quantity": 1, "unitPrice": 300000}],
    })
    assert response.status_code == 201
    return response.json()


def _create_payment(client, ref, amount):
    response = client.post(
        f"/api/orders/{ref}/transactions", json={"amount": amount}
    )
    assert response.status_code == 201
    return response.json()


def _prepare_delivered_order(client, amount=100000):
    order = _create_order(client)
    txn = _create_payment(client, order["orderRef"], amount)
    with get_db() as conn:
        conn.execute("UPDATE orders SET status = 'delivered' WHERE id = ?", (order["id"],))
        _sync_delivered_order_journal(conn, int(order["id"]), order["orderRef"])
    return order, txn


def _revenue_balance(conn, order_id, account_code="2100"):
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ? AND a.code = ?
        """,
        (order_id, account_code),
    ).fetchone()
    return float(row["balance"])


def _order_entries(conn, order_id):
    return conn.execute(
        "SELECT id, locked_at, description FROM journal_entries "
        "WHERE source_type = 'order' AND source_id = ? ORDER BY id",
        (order_id,),
    ).fetchall()


def test_create_recalculates_delivered_order_revenue(api_client):
    order, _ = _prepare_delivered_order(api_client)
    _create_payment(api_client, order["orderRef"], 50000)
    with get_db() as conn:
        assert _revenue_balance(conn, int(order["id"])) == 150000.0


def test_update_recalculates_delivered_order_revenue(api_client):
    order, txn = _prepare_delivered_order(api_client)
    response = api_client.patch(
        f"/api/orders/{order['orderRef']}/transactions/{txn['id']}",
        json={"amount": 200000},
    )
    assert response.status_code == 200
    with get_db() as conn:
        assert _revenue_balance(conn, int(order["id"])) == 200000.0


def test_delete_recalculates_delivered_order_revenue(api_client):
    order, txn = _prepare_delivered_order(api_client, 200000)
    response = api_client.delete(
        f"/api/orders/{order['orderRef']}/transactions/{txn['id']}"
    )
    assert response.status_code == 204
    with get_db() as conn:
        assert _revenue_balance(conn, int(order["id"])) == 0.0


def test_non_delivered_payment_mutation_does_not_create_revenue_entry(api_client):
    order = _create_order(api_client)
    txn = _create_payment(api_client, order["orderRef"], 100000)
    with get_db() as conn:
        assert _order_entries(conn, int(order["id"])) == []

    response = api_client.patch(
        f"/api/orders/{order['orderRef']}/transactions/{txn['id']}",
        json={"amount": 150000},
    )
    assert response.status_code == 200
    with get_db() as conn:
        assert _order_entries(conn, int(order["id"])) == []


def test_locked_stale_revenue_entry_is_reversed_and_replaced(api_client):
    order, txn = _prepare_delivered_order(api_client)
    with get_db() as conn:
        original = next(
            row for row in _order_entries(conn, int(order["id"]))
            if row["description"].startswith("Order revenue:")
        )
        conn.execute(
            "UPDATE journal_entries SET locked_at = '2026-06-25T10:00:00Z' WHERE id = ?",
            (original["id"],),
        )

    response = api_client.patch(
        f"/api/orders/{order['orderRef']}/transactions/{txn['id']}",
        json={"amount": 200000},
    )
    assert response.status_code == 200
    with get_db() as conn:
        revenue_entries = [
            row for row in _order_entries(conn, int(order["id"]))
            if row["description"].startswith("Order revenue:")
        ]
        assert len(revenue_entries) == 2
        assert revenue_entries[0]["id"] == original["id"]
        assert revenue_entries[0]["locked_at"] is not None
        assert len(_order_entries(conn, int(order["id"]))) == 3
        assert _revenue_balance(conn, int(order["id"])) == 200000.0


def test_revenue_recalc_failure_does_not_block_payment_mutation(api_client, monkeypatch):
    order, txn = _prepare_delivered_order(api_client)
    import baker.services.journal_sync as journal_sync

    before = journal_sync.journal_sync_failures

    def fail(*args, **kwargs):
        raise RuntimeError("revenue test failure")

    monkeypatch.setattr(journal_sync, "_reconcile_order_revenue_entry", fail)
    response = api_client.patch(
        f"/api/orders/{order['orderRef']}/transactions/{txn['id']}",
        json={"amount": 200000},
    )
    assert response.status_code == 200
    assert response.json()["amount"] == 200000
    assert journal_sync.journal_sync_failures == before + 1
    with get_db() as conn:
        failure = conn.execute(
            "SELECT source_type, source_id, error_message FROM journal_sync_failure_log "
            "WHERE source_type = 'order' AND source_id = ? ORDER BY id DESC LIMIT 1",
            (order["id"],),
        ).fetchone()
        assert failure is not None
        assert "revenue test failure" in failure["error_message"]
