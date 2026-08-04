"""Tests for cash drawer auto-link — DG-351 Phase 4.4 (rewritten for journal model).

DG-347 replaced the per-row ``cash_drawer_id`` linking on ``payment_transactions``
and ``events`` with a journal-entry-level link via the ``cash_drawer_journal_entries``
join table. Balance derivation now flows from 1101 (Cash in Drawer) journal lines
linked to the active drawer at creation time via ``_insert_journal_entry(drawer_id=...)``
(see ``baker.db.schema._helpers._insert_journal_entry`` and
``baker.services.journal_sync._common._active_drawer_id``).

These tests cover the auto-link behavior end-to-end through the public API:
    - AC4: cash payment_transactions auto-link to the active drawer — the
      resulting journal entry has a 1101 line and the drawer's
      ``expected_balance`` increases by the payment amount.
    - AC5: cash expense events paid from ``"Tiền mặt tại quầy"`` auto-link —
      the journal entry has a 1101 credit line and the drawer's
      ``expected_balance`` decreases by the expense amount.
    - Non-cash payments/expenses do not touch 1101, so the drawer's
      ``expected_balance`` is unchanged (the journal entry may still be linked
      to the drawer via the join table, but it carries no 1101 line).
    - No active drawer → ``_active_drawer_id`` returns ``None`` → no link row
      is created and no error is raised.
    - Update/delete/invalidate reverses the prior 1101 contribution.
    - NFR1: ``expected_balance`` reflects the sum of linked 1101 lines.
    - NFR3: all drawer journal entries remain balanced (debit sum = credit sum).
"""

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


def _drawer_1101_net(conn, drawer_id: int) -> int:
    """Return the drawer's net 1101 balance via the join table.

    Mirrors the query in ``CashDrawer.expected_balance`` so the tests
    independently verify the same derivation path.
    """
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
        FROM cash_drawer_journal_entries cdje
        JOIN journal_lines jl ON jl.journal_entry_id = cdje.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE cdje.cash_drawer_id = ? AND a.code = '1101'
        """,
        (drawer_id,),
    ).fetchone()
    return int(row["balance"])


def _drawer(conn, drawer_id: int) -> CashDrawer | None:
    return CashDrawer.get_by_id(conn, drawer_id)


def _je_has_1101_line(conn, journal_entry_id: int) -> bool:
    row = conn.execute(
        """
        SELECT 1 FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE jl.journal_entry_id = ? AND a.code = '1101'
        LIMIT 1
        """,
        (journal_entry_id,),
    ).fetchone()
    return row is not None


def _je_linked_to_drawer(conn, journal_entry_id: int, drawer_id: int) -> bool:
    row = conn.execute(
        "SELECT 1 FROM cash_drawer_journal_entries "
        "WHERE journal_entry_id = ? AND cash_drawer_id = ?",
        (journal_entry_id, drawer_id),
    ).fetchone()
    return row is not None


def _je_id_for_source(conn, source_type: str, source_id: int) -> int | None:
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = ? AND source_id = ? ORDER BY id DESC LIMIT 1",
        (source_type, source_id),
    ).fetchone()
    return int(row["id"]) if row else None


# ---------------------------------------------------------------------------
# AC4: cash payment_transactions auto-link
# ---------------------------------------------------------------------------


def test_cash_payment_links_to_active_drawer_ac4(api_client):
    """AC4: active drawer exists → cash payment → journal entry linked to the
    drawer via cash_drawer_journal_entries, has a 1101 line, and the drawer's
    expected_balance increases by the payment amount.

    The drawer-open JE already contributes opening_balance to 1101 (DR 1101 /
    CR 3100), so the net 1101 balance after a +150,000 cash payment is
    1,000,000 + 150,000 = 1,150,000."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"], amount=150_000,
                      method="cash", type="deposit")
    txn_id = int(txn["id"])
    with get_db() as conn:
        je_id = _je_id_for_source(conn, "payment_transaction", txn_id)
        assert je_id is not None
        assert _je_linked_to_drawer(conn, je_id, drawer_id)
        assert _je_has_1101_line(conn, je_id)
        # NFR1: expected balance now includes the cash sale (1101 debit) on
        # top of the opening-balance DR 1101 from the drawer-open JE.
        assert _drawer_1101_net(conn, drawer_id) == 1_000_000 + 150_000
        d = _drawer(conn, drawer_id)
        assert d is not None
        assert d.expected_balance(conn) == 1_000_000 + 150_000


def test_transfer_payment_not_linked(api_client):
    """Bank transfers do not touch 1101 — the drawer's expected_balance is
    unchanged (the journal entry may still be linked via the join table, but
    it carries no 1101 line). The drawer-open JE contributes opening_balance
    to 1101, so the net 1101 balance equals opening_balance."""
    _open_drawer(api_client)
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"], amount=100_000,
                      method="transfer", type="deposit")
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        assert drawer is not None
        # Transfer debits 1200 (or a 12xx sub-account), never 1101. The only
        # 1101 contribution is the drawer-open DR 1101 / CR 3100 entry.
        assert _drawer_1101_net(conn, drawer.id) == drawer.opening_balance
        assert drawer.expected_balance(conn) == drawer.opening_balance


def test_card_payment_not_linked(api_client):
    """Card payments do not touch 1101 — the drawer's expected_balance is
    unchanged. The drawer-open JE contributes opening_balance to 1101, so the
    net 1101 balance equals opening_balance."""
    _open_drawer(api_client)
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"], amount=100_000,
                      method="card", type="deposit")
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        assert drawer is not None
        # Card debits 1100, never 1101. Only the drawer-open entry contributes.
        assert _drawer_1101_net(conn, drawer.id) == drawer.opening_balance
        assert drawer.expected_balance(conn) == drawer.opening_balance


def test_cash_payment_without_active_drawer_not_linked(api_client):
    """No active drawer → _active_drawer_id returns None → the journal entry
    is not linked to any drawer (no link row, no 1101 contribution)."""
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"], amount=50_000, method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert CashDrawer.get_active(conn) is None
        je_id = _je_id_for_source(conn, "payment_transaction", txn_id)
        assert je_id is not None
        # No drawer open → no link row should exist for this JE.
        row = conn.execute(
            "SELECT COUNT(*) AS c FROM cash_drawer_journal_entries "
            "WHERE journal_entry_id = ?",
            (je_id,),
        ).fetchone()
        assert int(row["c"]) == 0


def test_refund_cash_payment_reduces_1101_balance(api_client):
    """An outflow (refund) cash transaction credits 1101, reducing the drawer's
    expected_balance. The drawer-open JE contributes opening_balance to 1101,
    so the net after a +200,000 deposit and a −50,000 refund is
    1,000,000 + 200,000 − 50,000 = 1,150,000."""
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
        assert drawer is not None
        # 1,000,000 (open) + 200,000 (deposit DR 1101) − 50,000 (refund CR 1101)
        assert _drawer_1101_net(conn, drawer.id) == 1_150_000
        assert drawer.expected_balance(conn) == 1_150_000


def test_update_cash_payment_amount_adjusts_1101_balance(api_client):
    """Updating a linked cash transaction's amount recomputes the drawer's
    1101 balance via the (replaced) journal entry."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100_000, method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 1_100_000

    # Update amount to 250,000
    resp = api_client.patch(f"/api/orders/{ref}/transactions/{txn_id}",
                            json={"amount": 250_000})
    assert resp.status_code == 200, resp.text
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 1_250_000
        d = _drawer(conn, drawer_id)
        assert d.expected_balance(conn) == 1_250_000
        # The (replaced) journal entry must still be linked to the drawer.
        je_id = _je_id_for_source(conn, "payment_transaction", txn_id)
        assert je_id is not None
        assert _je_linked_to_drawer(conn, je_id, drawer_id)


def test_update_payment_method_to_transfer_unlinks_1101_contribution(api_client):
    """Changing a cash payment to transfer removes the 1101 line — the drawer's
    expected_balance drops back to the opening balance (only the drawer-open
    JE continues to contribute opening_balance to 1101)."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100_000, method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 1_100_000

    resp = api_client.patch(f"/api/orders/{ref}/transactions/{txn_id}",
                            json={"method": "transfer"})
    assert resp.status_code == 200, resp.text
    with get_db() as conn:
        # Transfer debits 1200 — no 1101 line — drawer balance back to opening.
        assert _drawer_1101_net(conn, drawer_id) == 1_000_000
        d = _drawer(conn, drawer_id)
        assert d.expected_balance(conn) == 1_000_000


def test_delete_cash_payment_reverses_1101_balance(api_client):
    """Deleting a linked cash transaction reverses its 1101 contribution,
    leaving only the drawer-open JE's opening_balance contribution."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=120_000, method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 1_120_000

    resp = api_client.delete(f"/api/orders/{ref}/transactions/{txn_id}")
    assert resp.status_code == 204, resp.text
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 1_000_000
        d = _drawer(conn, drawer_id)
        assert d.expected_balance(conn) == 1_000_000


def test_invalidate_cash_payment_reverses_1101_balance(api_client):
    """Invalidating a linked cash transaction reverses its 1101 contribution,
    leaving only the drawer-open JE's opening_balance contribution."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=80_000, method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 1_080_000

    resp = api_client.post(
        f"/api/orders/{ref}/transactions/{txn_id}/invalidate",
        json={"invalidatedBy": "test", "reason": "sai"},
    )
    assert resp.status_code == 200, resp.text
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 1_000_000
        d = _drawer(conn, drawer_id)
        assert d.expected_balance(conn) == 1_000_000


# ---------------------------------------------------------------------------
# AC5: cash expense events auto-link
# ---------------------------------------------------------------------------


def test_cash_expense_links_to_active_drawer_ac5(api_client):
    """AC5: active drawer exists → cash expense paid from "Tiền mặt tại quầy"
    → journal entry linked to the drawer via cash_drawer_journal_entries, has
    a 1101 credit line, and the drawer's expected_balance decreases by the
    expense amount. The drawer-open JE contributes opening_balance to 1101
    (DR 1101 / CR 3100), so the net 1101 balance after a −50,000 cash expense
    is 1,000,000 − 50,000 = 950,000."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    ev = _create_expense(api_client, amount=50_000,
                         payment_source="Tiền mặt tại quầy")
    event_id = int(ev["id"])
    with get_db() as conn:
        je_id = _je_id_for_source(conn, "expense", event_id)
        assert je_id is not None
        assert _je_linked_to_drawer(conn, je_id, drawer_id)
        assert _je_has_1101_line(conn, je_id)
        # 1,000,000 (open DR 1101) − 50,000 (expense CR 1101) = 950,000 net.
        assert _drawer_1101_net(conn, drawer_id) == 950_000
        d = _drawer(conn, drawer_id)
        assert d is not None
        # NFR1: expected balance = opening - cash_expenses
        assert d.expected_balance(conn) == 1_000_000 - 50_000


def test_bank_expense_not_linked(api_client):
    """Expenses paid from a bank source (TK Phượng VCB → 1210) do not touch
    1101 — the drawer's expected_balance is unchanged. The drawer-open JE
    contributes opening_balance to 1101, so the net 1101 balance equals
    opening_balance."""
    _open_drawer(api_client)
    ev = _create_expense(api_client, amount=50_000,
                         payment_source="TK Phượng VCB")
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        assert drawer is not None
        # Bank expense credits 1210, never 1101. Only the drawer-open entry
        # contributes to 1101.
        assert _drawer_1101_net(conn, drawer.id) == drawer.opening_balance
        assert drawer.expected_balance(conn) == drawer.opening_balance


def test_debt_expense_not_linked(api_client):
    """Debt expenses credit Accounts Payable (2500), not 1101 — the drawer's
    expected_balance is unchanged. The drawer-open JE contributes
    opening_balance to 1101, so the net 1101 balance equals opening_balance."""
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
        drawer = CashDrawer.get_active(conn)
        assert drawer is not None
        # Debt expense credits 2500, never 1101. Only the drawer-open entry
        # contributes to 1101.
        assert _drawer_1101_net(conn, drawer.id) == drawer.opening_balance
        assert drawer.expected_balance(conn) == drawer.opening_balance


def test_cash_expense_without_active_drawer_not_linked(api_client):
    """No active drawer → cash expense journal entry is not linked to any
    drawer (no link row, no 1101 contribution)."""
    ev = _create_expense(api_client, amount=50_000,
                         payment_source="Tiền mặt tại quầy")
    event_id = int(ev["id"])
    with get_db() as conn:
        assert CashDrawer.get_active(conn) is None
        je_id = _je_id_for_source(conn, "expense", event_id)
        assert je_id is not None
        # No drawer open → no link row should exist for this JE.
        row = conn.execute(
            "SELECT COUNT(*) AS c FROM cash_drawer_journal_entries "
            "WHERE journal_entry_id = ?",
            (je_id,),
        ).fetchone()
        assert int(row["c"]) == 0


def test_update_cash_expense_amount_adjusts_1101_balance(api_client):
    """Updating a linked cash expense's amount recomputes the drawer's 1101
    balance via the (replaced) journal entry."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    ev = _create_expense(api_client, amount=50_000,
                         payment_source="Tiền mặt tại quầy")
    event_id = int(ev["id"])
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 950_000

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
        # 1,000,000 (open) − 120,000 (updated expense CR 1101) = 880,000.
        assert _drawer_1101_net(conn, drawer_id) == 880_000
        d = _drawer(conn, drawer_id)
        assert d.expected_balance(conn) == 880_000
        # The (replaced) journal entry must still be linked to the drawer.
        je_id = _je_id_for_source(conn, "expense", event_id)
        assert je_id is not None
        assert _je_linked_to_drawer(conn, je_id, drawer_id)


def test_update_expense_to_bank_unlinks_1101_contribution(api_client):
    """Changing a cash expense to a bank source removes the 1101 line — the
    drawer's expected_balance returns to the opening balance (only the
    drawer-open JE continues to contribute opening_balance to 1101)."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    ev = _create_expense(api_client, amount=60_000,
                         payment_source="Tiền mặt tại quầy")
    event_id = int(ev["id"])
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 940_000

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
        # Bank expense credits 1210 — no 1101 line — drawer balance back to opening.
        assert _drawer_1101_net(conn, drawer_id) == 1_000_000
        d = _drawer(conn, drawer_id)
        assert d.expected_balance(conn) == 1_000_000


def test_delete_cash_expense_reverses_1101_balance(api_client):
    """Soft-deleting a linked cash expense reverses its 1101 contribution,
    leaving only the drawer-open JE's opening_balance contribution."""
    drawer = _open_drawer(api_client, opening=1_000_000)
    drawer_id = int(drawer["id"])
    ev = _create_expense(api_client, amount=70_000,
                         payment_source="Tiền mặt tại quầy")
    event_id = int(ev["id"])
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 930_000

    resp = api_client.delete(f"/api/events/{event_id}")
    assert resp.status_code == 204, resp.text
    with get_db() as conn:
        assert _drawer_1101_net(conn, drawer_id) == 1_000_000
        d = _drawer(conn, drawer_id)
        assert d.expected_balance(conn) == 1_000_000


# ---------------------------------------------------------------------------
# NFR1 + NFR3: combined balance + journal entries still balance
# ---------------------------------------------------------------------------


def test_expected_balance_includes_cash_payment_and_cash_expense(api_client):
    """NFR1: expected_balance = opening + cash_payment − cash_expense after
    both a cash payment and a cash expense auto-link to the active drawer."""
    _open_drawer(api_client, opening=1_000_000)
    order = _create_order(api_client)
    _create_txn(api_client, order["orderRef"], amount=500_000, method="cash")
    _create_expense(api_client, amount=50_000, payment_source="Tiền mặt tại quầy")
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    body = resp.json()
    # 1,000,000 + 500,000 (cash payment DR 1101) − 50,000 (cash expense CR 1101)
    # = 1,450,000
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