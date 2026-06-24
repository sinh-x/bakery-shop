"""Tests for DG-191 Phase 4 — payment journal re-sync on shipping_fee edit.

Covers:

- Bus order with a deposit payment: editing ``shippingFee`` via the
  ``PATCH /api/orders/{ref}`` endpoint re-syncs the payment journal entry so
  the 2100/2200 split reflects the new shipping fee.
- Pickup order: editing ``shippingFee`` does NOT trigger a 2200 line (no
  payment re-sync because the guard requires ``delivery_type == "bus"``).
- Multiple payments on a bus order: all are re-synced after the edit.
- Journal entry stays unique (updated in place, not duplicated).
- Double-entry integrity preserved after re-sync.
"""

from baker.db.connection import get_db
from baker.db.schema import (
    BUS_SHIPPING_HELD_CODE,
    CUSTOMER_DEPOSITS_CODE,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _account_id(conn, code: str) -> int:
    return int(
        conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0]
    )


def _payment_line_amounts(conn, txn_id: int) -> dict[str, dict[str, float]]:
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'payment_transaction' AND je.source_id = ?
        """,
        (txn_id,),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out[r["code"]] = {"debit": float(r["debit"] or 0), "credit": float(r["credit"] or 0)}
    return out


def _payment_entry_count(conn, txn_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries "
        "WHERE source_type = 'payment_transaction' AND source_id = ?",
        (txn_id,),
    ).fetchone()
    return int(row[0])


def _create_bus_order(client, *, shipping_fee: float, total_price: float = 100000.0):
    payload = {
        "customerName": "Khách thử bus",
        "items": [
            {
                "productName": "Bánh mì",
                "quantity": 1,
                "unitPrice": total_price - shipping_fee,
                "productId": "BKS-BUS-1",
            }
        ],
        "dueDate": "2026-06-25",
        "deliveryType": "bus",
        "shippingFee": shipping_fee,
    }
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _add_payment(client, order_ref: str, amount: float, ptype: str = "deposit") -> int:
    resp = client.post(
        f"/api/orders/{order_ref}/transactions",
        json={
            "amount": amount,
            "type": ptype,
            "method": "cash",
        },
    )
    assert resp.status_code == 201
    return int(resp.json()["id"])


def _edit_shipping_fee(client, order_ref: str, new_fee: float) -> None:
    resp = client.patch(
        f"/api/orders/{order_ref}",
        json={"shippingFee": new_fee, "changedBy": "test"},
    )
    assert resp.status_code == 200


# ---------------------------------------------------------------------------
# Bus order — re-sync after shipping_fee edit
# ---------------------------------------------------------------------------


def test_shipping_fee_edit_resyncs_payment_journal_bus_order(api_client):
    """Bus order, deposit 100000, shipping 25000 → edit shipping to 50000.
    After edit: 2100 credit = 50000, 2200 credit = 50000 (re-synced)."""
    order = _create_bus_order(api_client, shipping_fee=25000, total_price=100000)
    ref = order["orderRef"]
    txn_id = _add_payment(api_client, ref, 100000)

    with get_db() as conn:
        before = _payment_line_amounts(conn, txn_id)
        assert before[CUSTOMER_DEPOSITS_CODE]["credit"] == 75000.0
        assert before[BUS_SHIPPING_HELD_CODE]["credit"] == 25000.0

    _edit_shipping_fee(api_client, ref, 50000)

    with get_db() as conn:
        after = _payment_line_amounts(conn, txn_id)
        assert after["1100"]["debit"] == 100000.0
        assert after[CUSTOMER_DEPOSITS_CODE]["credit"] == 50000.0
        assert after[BUS_SHIPPING_HELD_CODE]["credit"] == 50000.0
        # Entry updated in place, not duplicated.
        assert _payment_entry_count(conn, txn_id) == 1
        # Double-entry integrity.
        total_debit = sum(v["debit"] for v in after.values())
        total_credit = sum(v["credit"] for v in after.values())
        assert abs(total_debit - total_credit) < 0.005


def test_shipping_fee_edit_below_payment_amount(api_client):
    """Bus order, deposit 100000, shipping 50000 → edit shipping down to 10000.
    After edit: 2100 credit = 90000, 2200 credit = 10000."""
    order = _create_bus_order(api_client, shipping_fee=50000, total_price=100000)
    ref = order["orderRef"]
    txn_id = _add_payment(api_client, ref, 100000)

    _edit_shipping_fee(api_client, ref, 10000)

    with get_db() as conn:
        after = _payment_line_amounts(conn, txn_id)
        assert after[CUSTOMER_DEPOSITS_CODE]["credit"] == 90000.0
        assert after[BUS_SHIPPING_HELD_CODE]["credit"] == 10000.0
        assert after["1100"]["debit"] == 100000.0
        assert _payment_entry_count(conn, txn_id) == 1


def test_shipping_fee_edit_zero_removes_2200_line(api_client):
    """Bus order, deposit 100000, shipping 25000 → edit shipping to 0.
    After edit: no 2200 line, all 100000 to 2100."""
    order = _create_bus_order(api_client, shipping_fee=25000, total_price=100000)
    ref = order["orderRef"]
    txn_id = _add_payment(api_client, ref, 100000)

    _edit_shipping_fee(api_client, ref, 0)

    with get_db() as conn:
        after = _payment_line_amounts(conn, txn_id)
        assert BUS_SHIPPING_HELD_CODE not in after
        assert after[CUSTOMER_DEPOSITS_CODE]["credit"] == 100000.0
        assert after["1100"]["debit"] == 100000.0


def test_shipping_fee_edit_resyncs_multiple_payments(api_client):
    """Bus order, shipping 25000, two deposits 50000 + 50000.
    Before edit: payment1 → 2200=25000, 2100=25000; payment2 → 2100=50000.
    After editing shipping to 50000: re-sync both payments.
      payment1 → 2200=50000, 2100=0 (full shipping covered by first payment)
      payment2 → 2100=50000 (no remaining shipping)."""
    order = _create_bus_order(api_client, shipping_fee=25000, total_price=100000)
    ref = order["orderRef"]
    txn1 = _add_payment(api_client, ref, 50000)
    txn2 = _add_payment(api_client, ref, 50000)

    with get_db() as conn:
        before1 = _payment_line_amounts(conn, txn1)
        assert before1[BUS_SHIPPING_HELD_CODE]["credit"] == 25000.0
        assert before1[CUSTOMER_DEPOSITS_CODE]["credit"] == 25000.0
        before2 = _payment_line_amounts(conn, txn2)
        assert BUS_SHIPPING_HELD_CODE not in before2
        assert before2[CUSTOMER_DEPOSITS_CODE]["credit"] == 50000.0

    _edit_shipping_fee(api_client, ref, 50000)

    with get_db() as conn:
        after1 = _payment_line_amounts(conn, txn1)
        assert after1[BUS_SHIPPING_HELD_CODE]["credit"] == 50000.0
        assert after1[CUSTOMER_DEPOSITS_CODE]["credit"] == 0.0
        assert after1["1100"]["debit"] == 50000.0
        assert _payment_entry_count(conn, txn1) == 1

        after2 = _payment_line_amounts(conn, txn2)
        assert BUS_SHIPPING_HELD_CODE not in after2
        assert after2[CUSTOMER_DEPOSITS_CODE]["credit"] == 50000.0
        assert after2["1100"]["debit"] == 50000.0
        assert _payment_entry_count(conn, txn2) == 1


# ---------------------------------------------------------------------------
# Pickup order — no re-sync (guard: delivery_type == "bus")
# ---------------------------------------------------------------------------


def test_pickup_order_shipping_fee_edit_no_2200_involvement(api_client):
    """Pickup order with shipping_fee: editing it must NOT create a 2200 line
    because the re-sync guard requires delivery_type == 'bus'."""
    payload = {
        "customerName": "Khách pickup",
        "items": [
            {"productName": "Bánh mì", "quantity": 1, "unitPrice": 75000, "productId": "BKS-PICK-1"}
        ],
        "dueDate": "2026-06-25",
        "deliveryType": "pickup",
        "shippingFee": 25000,
    }
    resp = api_client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    ref = resp.json()["orderRef"]
    txn_id = _add_payment(api_client, ref, 100000)

    with get_db() as conn:
        before = _payment_line_amounts(conn, txn_id)
        assert BUS_SHIPPING_HELD_CODE not in before
        assert before[CUSTOMER_DEPOSITS_CODE]["credit"] == 100000.0

    _edit_shipping_fee(api_client, ref, 50000)

    with get_db() as conn:
        after = _payment_line_amounts(conn, txn_id)
        assert BUS_SHIPPING_HELD_CODE not in after
        assert after[CUSTOMER_DEPOSITS_CODE]["credit"] == 100000.0
        assert after["1100"]["debit"] == 100000.0
        assert _payment_entry_count(conn, txn_id) == 1