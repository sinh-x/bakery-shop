"""Tests for DG-244 Phase 4 — payment_source routing for payment transactions.

Covers:
- FR4: API accepts ``payment_source`` on create/update payloads (omit-when-empty
  semantics; absent/null/empty all accepted → NFR3).
- FR5: transactions without a target account journal to the un-allocated bank
  account (1290) when method='transfer'; cash/card unchanged (1100).
- FR8: distinct CoA codes 1210 (Phượng VCB), 1220 (Ân VCB), 1290 (un-allocated)
  are seeded, all sub-accounts of 1200.
- AC3: payment_source='TK Phượng VCB' → debit/credit lines reference 1210.
- AC4: empty payment_source + transfer → lines reference 1290.
- AC7: payment_source='TK Ân VCB' + transfer → lines reference 1220 (POS path
  converges on the same POST /api/orders/{ref}/transactions endpoint).
- AC8: empty payment_source + transfer → lines reference 1290.
- Regression: EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE routes VCB labels to
  their bank sub-accounts (1210/1220) in expense journal entries (DG-285).
- Edge: unknown payment_source value is treated as un-allocated (transfer)
  rather than rejected.
- Update on payment_source re-syncs the journal entry to the new account.
- Tien rut return credits the same bank sub-account as the original deposit
  when payment_source is set on the tien_rut transaction.
"""

from baker.db.connection import get_db
from baker.db.schema import (
    EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE,
    TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE,
    UNALLOCATED_BANK_CODE,
    ensure_schema,
)
from baker.models.payment_transaction import PaymentTransaction


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _create_order(client, customer="Nguyễn Văn A", total=300000):
    resp = client.post("/api/orders", json={
        "customerName": customer,
        "dueDate": "2026-07-25",
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": total}],
    })
    assert resp.status_code == 201
    return resp.json()


def _create_txn(client, ref, amount=100000, **kwargs):
    payload = {"amount": amount, **kwargs}
    resp = client.post(f"/api/orders/{ref}/transactions", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _patch_txn(client, ref, txn_id, payload):
    resp = client.patch(f"/api/orders/{ref}/transactions/{txn_id}", json=payload)
    assert resp.status_code == 200
    return resp.json()


def _journal_line_amounts(conn, txn_id) -> dict[str, dict[str, float]]:
    """Return per-account debit/credit for the txn's payment_journal entry."""
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


def _account_id(conn, code: str) -> int:
    return int(conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0])


# ---------------------------------------------------------------------------
# FR8 — Distinct CoA codes seeded
# ---------------------------------------------------------------------------


def test_distinct_bank_sub_accounts_seeded(api_client):
    """FR8: 1210, 1220, 1290 exist under parent 1200."""
    with get_db() as conn:
        ensure_schema(conn)
        for code, name, parent in [
            ("1210", "TK Phượng VCB (Bank — Phượng)", "1200"),
            ("1220", "TK Ân VCB (Bank — Ân)", "1200"),
            ("1290", "TK ngân hàng chưa phân bổ (Un-allocated Bank)", "1200"),
        ]:
            row = conn.execute(
                "SELECT a.id, a.name, a.type, p.code AS parent_code "
                "FROM accounts a LEFT JOIN accounts p ON p.id = a.parent_id "
                "WHERE a.code = ?",
                (code,),
            ).fetchone()
            assert row is not None, f"account {code} missing"
            assert row["name"] == name
            assert row["type"] == "asset"
            assert row["parent_code"] == parent


def test_transaction_source_mapping_has_distinct_codes():
    """FR8: TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE maps VCB labels to
    distinct codes (1210/1220), aligned with the expense mapping (1210/1220)."""
    assert TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE == {
        "TK Phượng VCB": "1210",
        "TK Ân VCB": "1220",
    }
    # DG-285: expense mapping now routes VCB labels to sub-accounts (1210/1220),
    # aligned with the payment-side routing.
    assert EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE["TK Phượng VCB"] == "1210"
    assert EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE["TK Ân VCB"] == "1220"
    assert UNALLOCATED_BANK_CODE == "1290"


# ---------------------------------------------------------------------------
# FR4 / NFR3 — API accepts payment_source
# ---------------------------------------------------------------------------


def test_create_transaction_accepts_payment_source(api_client):
    """FR4: payment_source is persisted and surfaced in the API response."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(
        api_client, ref, amount=150000, type="payment",
        method="transfer", payment_source="TK Phượng VCB",
    )
    assert txn["paymentSource"] == "TK Phượng VCB"


def test_create_transaction_absent_payment_source_defaults_empty(api_client):
    """NFR3: payload without payment_source is accepted (defaults to '')."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/transactions", json={"amount": 50000})
    assert resp.status_code == 201
    assert resp.json()["paymentSource"] == ""


def test_create_transaction_null_payment_source_accepted(api_client):
    """NFR3: explicit null payment_source is accepted (treated as empty)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/transactions",
        json={"amount": 50000, "payment_source": None},
    )
    assert resp.status_code == 201
    assert resp.json()["paymentSource"] == ""


def test_create_transaction_empty_string_payment_source_accepted(api_client):
    """NFR3: empty-string payment_source is accepted."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/transactions",
        json={"amount": 50000, "payment_source": ""},
    )
    assert resp.status_code == 201
    assert resp.json()["paymentSource"] == ""


def test_update_transaction_payment_source_re_syncs_journal(api_client):
    """Edge: updating payment_source re-syncs the journal entry to the new
    bank sub-account."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(
        api_client, ref, amount=100000, type="payment",
        method="transfer", payment_source="TK Phượng VCB",
    )
    txn_id = int(txn["id"])

    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        assert "1210" in lines
        assert lines["1210"]["debit"] == 100000.0

    # Update to Ân VCB
    _patch_txn(api_client, ref, txn_id, {"payment_source": "TK Ân VCB"})
    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        assert "1220" in lines
        assert lines["1220"]["debit"] == 100000.0
        # 1210 line removed (in-place re-sync replaces the entry)
        assert "1210" not in lines

    # Update to empty → un-allocated fallback
    _patch_txn(api_client, ref, txn_id, {"payment_source": ""})
    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        assert "1290" in lines
        assert lines["1290"]["debit"] == 100000.0


# ---------------------------------------------------------------------------
# AC3 / AC4 / AC7 / AC8 — Journal routing
# ---------------------------------------------------------------------------


def test_ac3_transfer_with_phuong_vcb_routes_to_1210(api_client):
    """AC3: payment_source='TK Phượng VCB' + transfer → journal references
    Phượng VCB's account (1210)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(
        api_client, ref, amount=200000, type="payment",
        method="transfer", payment_source="TK Phượng VCB",
    )
    txn_id = int(txn["id"])
    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        # Debit side: 1210 (Phượng VCB sub-account)
        assert lines["1210"]["debit"] == 200000.0
        # Credit side: 2100 (Customer Deposits)
        assert lines["2100"]["credit"] == 200000.0
        # 1200 not involved
        assert "1200" not in lines


def test_ac7_transfer_with_an_vcb_routes_to_1220(api_client):
    """AC7: payment_source='TK Ân VCB' + transfer → journal references
    Ân VCB's account (1220). POS and order flows converge on this endpoint."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(
        api_client, ref, amount=250000, type="payment",
        method="transfer", payment_source="TK Ân VCB",
    )
    txn_id = int(txn["id"])
    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        assert lines["1220"]["debit"] == 250000.0
        assert lines["2100"]["credit"] == 250000.0
        assert "1200" not in lines


def test_ac4_ac8_transfer_without_payment_source_routes_to_1290(api_client):
    """AC4/AC8: transfer with no payment_source → un-allocated bank (1290)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    # No payment_source field at all
    txn = _create_txn(
        api_client, ref, amount=180000, type="payment", method="transfer",
    )
    txn_id = int(txn["id"])
    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        assert lines["1290"]["debit"] == 180000.0
        assert lines["2100"]["credit"] == 180000.0
        assert "1200" not in lines


def test_transfer_with_empty_payment_source_routes_to_1290(api_client):
    """AC4: empty-string payment_source + transfer → 1290 (un-allocated)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(
        api_client, ref, amount=75000, type="deposit",
        method="transfer", payment_source="",
    )
    txn_id = int(txn["id"])
    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        assert lines["1290"]["debit"] == 75000.0


def test_cash_with_payment_source_routes_to_bank_sub_account(api_client):
    """When payment_source is set, the asset side routes to that bank
    sub-account regardless of method (the explicit selection wins)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(
        api_client, ref, amount=60000, type="deposit",
        method="cash", payment_source="TK Phượng VCB",
    )
    txn_id = int(txn["id"])
    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        # Explicit payment_source overrides cash default
        assert lines["1210"]["debit"] == 60000.0
        assert "1100" not in lines


def test_cash_without_payment_source_routes_to_1100(api_client):
    """FR5: cash/card transactions without payment_source keep their existing
    behavior (1100). Only transfers get the un-allocated fallback."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(
        api_client, ref, amount=50000, type="deposit", method="cash",
    )
    txn_id = int(txn["id"])
    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        assert lines["1100"]["debit"] == 50000.0
        assert "1290" not in lines


def test_unknown_payment_source_treated_as_unallocated(api_client):
    """Edge: an unrecognized payment_source value is treated as un-allocated
    rather than rejected — journal sync must never break on a stale label."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(
        api_client, ref, amount=90000, type="deposit",
        method="transfer", payment_source="TK Ngân VCB",
    )
    txn_id = int(txn["id"])
    with get_db() as conn:
        lines = _journal_line_amounts(conn, txn_id)
        # Unknown source + transfer → 1290
        assert lines["1290"]["debit"] == 90000.0


# ---------------------------------------------------------------------------
# Regression — expense mapping unchanged (FR8 note)
# ---------------------------------------------------------------------------


def test_expense_payment_source_mapping_unchanged():
    """Regression: EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE maps VCB labels to
    their bank sub-accounts (1210/1220) per DG-285 FR1/FR2."""
    assert EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE == {
        "Shop tiền mặt": "1100",
        "TK Phượng VCB": "1210",
        "TK Ân VCB": "1220",
        "Nhân viên ứng trước": "2300",
    }


# ---------------------------------------------------------------------------
# Tien rut return — credits the same sub-account as the original deposit
# ---------------------------------------------------------------------------


def _insert_order_with_delivery(conn, *, order_ref="ORD-RUT-1") -> int:
    cur = conn.execute(
        "INSERT INTO orders "
        "(order_ref, customer_name, total_price, status, due_date, "
        " delivery_type, shipping_fee) "
        "VALUES (?, 'Khách thử', 100000, 'delivered', '2026-07-20', 'pickup', 0)",
        (order_ref,),
    )
    return int(cur.lastrowid)


def _insert_payment_txn(
    conn, *, order_id: int, amount: float, ptype: str, method: str,
    payment_source: str = "",
) -> int:
    cur = conn.execute(
        "INSERT INTO payment_transactions "
        "(order_id, amount, type, method, note, payment_source) "
        "VALUES (?, ?, ?, ?, '', ?)",
        (order_id, amount, ptype, method, payment_source),
    )
    return int(cur.lastrowid)


def test_tien_rut_return_credits_same_bank_sub_account():
    """When a tien_rut transaction carries payment_source, the return entry
    at delivery credits the same bank sub-account the deposit debited, so
    the held balance and its return net to zero on that account."""
    from baker.services.journal_sync import (
        _reconcile_tien_rut_return_entry,
        _sync_payment_journal,
    )

    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order_with_delivery(conn, order_ref="ORD-RUT-PHUOC")
        rut_txn = _insert_payment_txn(
            conn, order_id=oid, amount=120000, ptype="tien_rut",
            method="transfer", payment_source="TK Phượng VCB",
        )
        _sync_payment_journal(
            conn, rut_txn, 120000, "tien_rut", "transfer",
            order_id=oid, payment_source="TK Phượng VCB",
        )

        # Verify the tien_rut deposit debited 1210
        deposit_lines = _journal_line_amounts(conn, rut_txn)
        assert deposit_lines["1210"]["debit"] == 120000.0
        assert deposit_lines["2400"]["credit"] == 120000.0

        # Trigger the return entry
        tien_rut_account_id = _account_id(conn, "2400")
        _reconcile_tien_rut_return_entry(
            conn,
            order_id=oid,
            order_ref="ORD-RUT-PHUOC",
            tien_rut_account_id=tien_rut_account_id,
            tien_rut_held=120000.0,
            order_transaction_date="2026-07-20T00:00:00Z",
            respect_locks=True,
        )

        # Find the return entry: source_type='order', description starts with
        # 'Tien rut return:' — its asset credit line must reference 1210.
        return_rows = conn.execute(
            """
            SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id
            WHERE je.source_type = 'order' AND je.source_id = ?
              AND je.description LIKE 'Tien rut return:%'
            """,
            (oid,),
        ).fetchall()
        assert return_rows, "no tien rut return entry was created"
        asset_credit = next(
            (r for r in return_rows if float(r["credit"] or 0) > 0), None
        )
        assert asset_credit is not None
        assert asset_credit["code"] == "1210"
        assert float(asset_credit["credit"]) == 120000.0


# ---------------------------------------------------------------------------
# Model layer — payment_source persisted on save/from_row
# ---------------------------------------------------------------------------


def test_payment_transaction_model_persists_payment_source():
    """PaymentTransaction.save persists payment_source and from_row reads it."""
    with get_db() as conn:
        ensure_schema(conn)
        cur = conn.execute(
            "INSERT INTO orders "
            "(order_ref, customer_name, total_price, status, due_date) "
            "VALUES ('ORD-MODEL-1', 'Khách', 50000, 'new', '2026-07-25')"
        )
        order_id = int(cur.lastrowid)

        txn = PaymentTransaction(
            order_id=order_id,
            amount=50000,
            type="deposit",
            method="transfer",
            payment_source="TK Ân VCB",
        )
        txn.save(conn)
        assert txn.id is not None

        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn.id,)
        ).fetchone()
        fetched = PaymentTransaction.from_row(row)
        assert fetched.payment_source == "TK Ân VCB"
        assert fetched.to_api_dict()["paymentSource"] == "TK Ân VCB"


def test_payment_transaction_model_default_payment_source_empty():
    """PaymentTransaction without explicit payment_source defaults to ''."""
    with get_db() as conn:
        ensure_schema(conn)
        cur = conn.execute(
            "INSERT INTO orders "
            "(order_ref, customer_name, total_price, status, due_date) "
            "VALUES ('ORD-MODEL-2', 'Khách', 50000, 'new', '2026-07-25')"
        )
        order_id = int(cur.lastrowid)

        txn = PaymentTransaction(
            order_id=order_id, amount=50000, type="deposit", method="cash",
        )
        txn.save(conn)
        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn.id,)
        ).fetchone()
        fetched = PaymentTransaction.from_row(row)
        assert fetched.payment_source == ""
        assert fetched.to_api_dict()["paymentSource"] == ""