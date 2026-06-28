"""Tests for accounting API — Phase 2 (DG-175).

Covers:
- GET /api/accounts (chart of accounts hierarchy)
- GET /api/accounts/journal (filter + pagination)
- GET /api/accounts/balances
- POST /api/accounts/journal/lock
- POST /api/accounts/owner-capital, /owner-draw, /staff-reimburse
- Auto journal generation for expense events (create/update/delete)
- Auto journal generation for payment_transactions (create/update/delete)
- Auto journal generation for delivered orders (revenue + COGS)
- Lock/unlock behavior: unlocked → in-place; locked → reversal + new
- Phase 1 foundation tests retained (seed + empty balances)
"""

from datetime import datetime

import pytest

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.models.account import Account
from baker.models.journal_entry import JournalEntry


# ---------------------------------------------------------------------------
# Phase 1 foundation (retained)
# ---------------------------------------------------------------------------


def test_accounts_seeded_after_migrate():
    with get_db() as conn:
        ensure_schema(conn)
        accounts = Account.list_all(conn)
        assert len(accounts) >= 21
        codes = {a.code for a in accounts}
        # Core required accounts per AC8
        for required in (
            "1100",  # Cash on Hand
            "1200",  # Bank Account
            "1300",  # Inventory
            "2300",  # Staff Payables (parent)
            "2100",  # Customer Deposits
            "3100",  # Owner's Equity
            "4100",  # Order Revenue
            "5900",  # COGS
            "5100",  # Ingredients expense
            "5800",  # Other Expenses
        ):
            assert required in codes, f"Required account {required} missing"


def test_journal_balances_empty_on_fresh_db():
    with get_db() as conn:
        ensure_schema(conn)
        balances = JournalEntry.get_balances(conn)
        assert len(balances) >= 21
        for b in balances:
            assert b["balance"] == 0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _account_id(conn, code: str) -> int:
    return int(conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0])


def _journal_for_source(conn, source_type: str, source_id: int):
    rows = conn.execute(
        "SELECT * FROM journal_entries WHERE source_type = ? AND source_id = ? ORDER BY id",
        (source_type, source_id),
    ).fetchall()
    return [JournalEntry.from_row(r) for r in rows]


def _lines_for_entry(conn, entry_id: int):
    from baker.models.journal_entry import JournalLine
    return JournalLine.list_for_entry(conn, entry_id)


def _create_expense(client, amount=50000, category="Nguyên liệu", payment_source="Shop tiền mặt",
                    paid_by_name="Phượng", vendor="Chợ", note="ghi chu", summary="Chi phí test"):
    payload = {
        "summary": summary,
        "type": "expense",
        "data": {
            "amount_vnd": amount,
            "category": category,
            "payment_method": "Tiền mặt",
            "payment_source": payment_source,
            "vendor": vendor,
            "note": note,
            "paid_by_name": paid_by_name,
        },
    }
    resp = client.post("/api/events", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _create_order(client, customer="Nguyễn Văn A", total=300000, items=None, **kwargs):
    if items is None:
        items = [{"productName": "Bánh kem", "quantity": 1, "unitPrice": total, "productId": "BKS-16"}]
    payload = {"customerName": customer, "dueDate": "2026-03-25", "items": items, **kwargs}
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _create_txn(client, ref, amount=100000, **kwargs):
    payload = {"amount": amount, **kwargs}
    resp = client.post(f"/api/orders/{ref}/transactions", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _create_product(client, name="Bánh kem test", cost=0, category="cake", base_price=200000):
    resp = client.post("/api/products", json={
        "name": name, "category": category, "base_price": base_price, "cost": cost,
    })
    assert resp.status_code == 201
    return resp.json()


# ---------------------------------------------------------------------------
# GET /api/accounts — chart of accounts hierarchy (FR8)
# ---------------------------------------------------------------------------


def test_list_accounts_returns_hierarchy(api_client):
    resp = api_client.get("/api/accounts")
    assert resp.status_code == 200
    tree = resp.json()
    assert isinstance(tree, list)
    # Top-level accounts have parent_id null
    top_codes = {a["code"] for a in tree}
    assert {"1000", "2000", "3000", "4000", "5000"} <= top_codes
    # Each top-level node has children list
    for node in tree:
        assert "children" in node
        assert isinstance(node["children"], list)
    # Asset group 1000 should have Cash on Hand (1100) as a child
    asset_group = next(a for a in tree if a["code"] == "1000")
    child_codes = {c["code"] for c in asset_group["children"]}
    assert "1100" in child_codes
    assert "1200" in child_codes
    assert "1300" in child_codes
    # Staff Payables (2300) is a liability, not an asset child
    liability_group = next(a for a in tree if a["code"] == "2000")
    liability_child_codes = {c["code"] for c in liability_group["children"]}
    assert "2300" in liability_child_codes  # Staff Payables parent


# ---------------------------------------------------------------------------
# Auto journal: expense event (FR3, AC1)
# ---------------------------------------------------------------------------


def test_expense_creates_journal_entry(api_client):
    """AC1: expense with payment_source='Shop tiền mặt', amount_vnd=50000 →
    debit expense account, credit 1100."""
    ev = _create_expense(api_client, amount=50000, category="Nguyên liệu",
                        payment_source="Shop tiền mặt")
    eid = int(ev["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        assert len(entries) == 1
        lines = _lines_for_entry(conn, entries[0].id)
        assert len(lines) == 2
        # Find debit and credit lines
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        assert debit_line.debit == 50000.0
        assert credit_line.credit == 50000.0
        # "Nguyên liệu" is an inventory-purchase category → debit Inventory (1300)
        inventory_acc = Account.get_by_id(conn, debit_line.account_id)
        assert inventory_acc.code == "1300"
        # Credit should hit Cash on Hand (1100)
        cash_acc = Account.get_by_id(conn, credit_line.account_id)
        assert cash_acc.code == "1100"


def test_expense_staff_advance_creates_sub_account(api_client):
    """Expense with payment_source='Nhân viên ứng trước' debits a per-staff sub-account."""
    ev = _create_expense(api_client, amount=80000, category="Lương/phụ cấp",
                        payment_source="Nhân viên ứng trước", paid_by_name="Phượng")
    eid = int(ev["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        assert len(entries) == 1
        lines = _lines_for_entry(conn, entries[0].id)
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        # Credit account should be a sub-account under 2300 named "Phượng"
        staff_acc = Account.get_by_id(conn, credit_line.account_id)
        assert staff_acc.code.startswith("23")
        assert staff_acc.type == "liability"
        assert staff_acc.parent_id == _account_id(conn, "2300")
        assert staff_acc.name == "Phượng"


def test_expense_update_in_place_when_unlocked(api_client):
    """AC6: unlocked → update in-place (same entry id, new amount)."""
    ev = _create_expense(api_client, amount=50000)
    eid = int(ev["id"])
    with get_db() as conn:
        orig_entries = _journal_for_source(conn, "expense", eid)
        assert len(orig_entries) == 1
        orig_id = orig_entries[0].id

    # Update amount
    resp = api_client.patch(f"/api/events/{eid}", json={
        "data": {
            "amount_vnd": 75000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Chợ",
            "note": "updated",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 200
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        # In-place: still exactly one entry with the same id
        assert len(entries) == 1
        assert entries[0].id == orig_id
        lines = _lines_for_entry(conn, orig_id)
        debit_line = next(l for l in lines if l.debit > 0)
        assert debit_line.debit == 75000.0


def test_expense_update_locked_creates_reversal_and_new(api_client):
    """AC6: locked → reversal entry + new correct entry."""
    ev = _create_expense(api_client, amount=50000)
    eid = int(ev["id"])
    with get_db() as conn:
        entry_id = _journal_for_source(conn, "expense", eid)[0].id
        # Lock the entry manually
        conn.execute("UPDATE journal_entries SET locked_at = '2026-06-22T10:00:00' WHERE id = ?", (entry_id,))

    # Update amount
    resp = api_client.patch(f"/api/events/{eid}", json={
        "data": {
            "amount_vnd": 90000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Chợ",
            "note": "updated",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 200
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        # Original (locked) + reversal + new = 3 entries
        assert len(entries) == 3
        # Original is still locked
        assert entries[0].locked_at is not None
        # The newest entry should be unlocked and reflect the new amount
        newest = entries[-1]
        assert newest.locked_at is None
        lines = _lines_for_entry(conn, newest.id)
        debit_line = next(l for l in lines if l.debit > 0)
        assert debit_line.debit == 90000.0
        # The reversal entry: debit/credit swapped relative to original 50000
        reversal = entries[1]
        rev_lines = _lines_for_entry(conn, reversal.id)
        # Original debited Inventory 1300; reversal credits Inventory 1300
        rev_credit = next(l for l in rev_lines if l.credit > 0)
        assert rev_credit.credit == 50000.0
        rev_inventory_acc = Account.get_by_id(conn, rev_credit.account_id)
        assert rev_inventory_acc.code == "1300"


def test_expense_delete_unlocked_removes_journal(api_client):
    """FR7: delete unlocked expense → journal entry deleted."""
    ev = _create_expense(api_client, amount=50000)
    eid = int(ev["id"])
    with get_db() as conn:
        assert len(_journal_for_source(conn, "expense", eid)) == 1
    resp = api_client.delete(f"/api/events/{eid}")
    assert resp.status_code == 204
    with get_db() as conn:
        assert len(_journal_for_source(conn, "expense", eid)) == 0


def test_expense_delete_locked_creates_reversal(api_client):
    """FR7: delete locked expense → reversal entry (original kept)."""
    ev = _create_expense(api_client, amount=50000)
    eid = int(ev["id"])
    with get_db() as conn:
        entry_id = _journal_for_source(conn, "expense", eid)[0].id
        conn.execute("UPDATE journal_entries SET locked_at = '2026-06-22T10:00:00' WHERE id = ?", (entry_id,))
    resp = api_client.delete(f"/api/events/{eid}")
    assert resp.status_code == 204
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        # Original (locked) + reversal = 2 entries
        assert len(entries) == 2
        assert entries[0].locked_at is not None
        # Reversal net effect: original debit 50000 expense, reversal credits 50000
        rev_lines = _lines_for_entry(conn, entries[1].id)
        rev_credit_to_expense = next(l for l in rev_lines if l.credit > 0)
        assert rev_credit_to_expense.credit == 50000.0


def test_expense_non_expense_type_no_journal(api_client):
    """Non-expense events do NOT create journal entries."""
    resp = api_client.post("/api/events", json={"summary": "Ghi chú", "type": "note"})
    assert resp.status_code == 201
    eid = int(resp.json()["id"])
    with get_db() as conn:
        assert len(_journal_for_source(conn, "expense", eid)) == 0


# ---------------------------------------------------------------------------
# Auto journal: payment_transaction (FR4, AC2)
# ---------------------------------------------------------------------------


def test_payment_deposit_creates_journal_entry(api_client):
    """AC2: payment_transaction type='deposit', amount=200000, method='cash' →
    debit 1100, credit 2100."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000, type="deposit", method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "payment_transaction", txn_id)
        assert len(entries) == 1
        lines = _lines_for_entry(conn, entries[0].id)
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        assert debit_line.debit == 200000.0
        assert credit_line.credit == 200000.0
        asset_acc = Account.get_by_id(conn, debit_line.account_id)
        assert asset_acc.code == "1100"  # Cash on Hand
        deposits_acc = Account.get_by_id(conn, credit_line.account_id)
        assert deposits_acc.code == "2100"  # Customer Deposits


def test_payment_transfer_method_hits_bank_account(api_client):
    """method='transfer' debits Bank Account (1200), not Cash on Hand."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=150000, type="payment", method="transfer")
    txn_id = int(txn["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "payment_transaction", txn_id)
        lines = _lines_for_entry(conn, entries[0].id)
        debit_line = next(l for l in lines if l.debit > 0)
        asset_acc = Account.get_by_id(conn, debit_line.account_id)
        assert asset_acc.code == "1200"


def test_payment_refund_reverses_direction(api_client):
    """FR4: refund/tien_rut → debit Customer Deposits, credit Asset (reversed)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=50000, type="refund", method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "payment_transaction", txn_id)
        lines = _lines_for_entry(conn, entries[0].id)
        # For outflow: debit deposits, credit asset
        deposits_debit = next(l for l in lines if l.debit > 0)
        asset_credit = next(l for l in lines if l.credit > 0)
        deposits_acc = Account.get_by_id(conn, deposits_debit.account_id)
        asset_acc = Account.get_by_id(conn, asset_credit.account_id)
        assert deposits_acc.code == "2100"
        assert asset_acc.code == "1100"


def test_payment_update_in_place_when_unlocked(api_client):
    """AC6: unlocked payment update → in-place journal update."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100000, type="deposit", method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        orig_id = _journal_for_source(conn, "payment_transaction", txn_id)[0].id
    resp = api_client.patch(f"/api/orders/{ref}/transactions/{txn_id}", json={"amount": 250000})
    assert resp.status_code == 200
    with get_db() as conn:
        entries = _journal_for_source(conn, "payment_transaction", txn_id)
        assert len(entries) == 1
        assert entries[0].id == orig_id
        lines = _lines_for_entry(conn, orig_id)
        debit_line = next(l for l in lines if l.debit > 0)
        assert debit_line.debit == 250000.0


def test_payment_update_locked_creates_reversal_and_new(api_client):
    """AC6: locked payment update → reversal + new entry."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100000, type="deposit", method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        entry_id = _journal_for_source(conn, "payment_transaction", txn_id)[0].id
        conn.execute("UPDATE journal_entries SET locked_at = '2026-06-22T10:00:00' WHERE id = ?", (entry_id,))
    resp = api_client.patch(f"/api/orders/{ref}/transactions/{txn_id}", json={"amount": 300000})
    assert resp.status_code == 200
    with get_db() as conn:
        entries = _journal_for_source(conn, "payment_transaction", txn_id)
        assert len(entries) == 3  # original + reversal + new
        newest = entries[-1]
        lines = _lines_for_entry(conn, newest.id)
        debit_line = next(l for l in lines if l.debit > 0)
        assert debit_line.debit == 300000.0


def test_payment_delete_unlocked_removes_journal(api_client):
    """FR7: delete unlocked payment → journal entry deleted."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100000, type="deposit", method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        assert len(_journal_for_source(conn, "payment_transaction", txn_id)) == 1
    resp = api_client.delete(f"/api/orders/{ref}/transactions/{txn_id}")
    assert resp.status_code == 204
    with get_db() as conn:
        assert len(_journal_for_source(conn, "payment_transaction", txn_id)) == 0


def test_payment_delete_locked_creates_reversal(api_client):
    """FR7: delete locked payment → reversal entry (original kept)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=100000, type="deposit", method="cash")
    txn_id = int(txn["id"])
    with get_db() as conn:
        entry_id = _journal_for_source(conn, "payment_transaction", txn_id)[0].id
        conn.execute("UPDATE journal_entries SET locked_at = '2026-06-22T10:00:00' WHERE id = ?", (entry_id,))
    resp = api_client.delete(f"/api/orders/{ref}/transactions/{txn_id}")
    assert resp.status_code == 204
    with get_db() as conn:
        entries = _journal_for_source(conn, "payment_transaction", txn_id)
        assert len(entries) == 2  # original + reversal


# ---------------------------------------------------------------------------
# Auto journal: delivered order (FR5, FR5a, AC9)
# ---------------------------------------------------------------------------


def test_delivered_order_creates_revenue_journal(api_client):
    """FR5: order → 'delivered' → journal moves net payments from 2100 to 4100."""
    order = _create_order(api_client, total=300000)
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=300000, type="payment", method="cash")
    order_id = int(order["id"])

    # Transition to delivered via the status endpoint
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200
    with get_db() as conn:
        entries = _journal_for_source(conn, "order", order_id)
        assert len(entries) == 1
        lines = _lines_for_entry(conn, entries[0].id)
        # debit Customer Deposits (2100), credit Order Revenue (4100)
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        deposits_acc = Account.get_by_id(conn, debit_line.account_id)
        revenue_acc = Account.get_by_id(conn, credit_line.account_id)
        assert deposits_acc.code == "2100"
        assert revenue_acc.code == "4100"
        assert debit_line.debit == 300000.0
        assert credit_line.credit == 300000.0


def test_delivered_order_cogs_for_product_with_cost(api_client):
    """AC3: delivered order → COGS entry debit 5900, credit 1300, using
    cost_at_sale populated at delivery time from cost_history (via
    resolve_product_cost).

    Seeds an explicit cost_history row so cost_at_sale is resolved from it
    rather than the baseline rule.
    """
    product = _create_product(api_client, name="Bột mì", cost=25000, base_price=50000)
    pid = int(product["id"])
    # Seed cost_history so resolve_product_cost returns the recorded cost.
    with get_db() as conn:
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) "
            "VALUES (?, ?, ?)",
            (pid, 25000, "2020-01-01T00:00:00"),
        )
    order = _create_order(
        api_client,
        items=[{"productName": "Bột mì", "quantity": 2, "unitPrice": 50000, "productId": str(pid)}],
    )
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=100000, type="payment", method="cash")
    order_id = int(order["id"])

    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200
    with get_db() as conn:
        # cost_at_sale should be populated from cost_history (25000) per item.
        oi = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE order_id = ?", (order_id,)
        ).fetchone()
        assert float(oi["cost_at_sale"] or 0) == 25000.0
        cogs_entries = _journal_for_source(conn, "order_cogs", order_id)
        assert len(cogs_entries) == 1
        lines = _lines_for_entry(conn, cogs_entries[0].id)
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        cogs_acc = Account.get_by_id(conn, debit_line.account_id)
        inv_acc = Account.get_by_id(conn, credit_line.account_id)
        assert cogs_acc.code == "5900"
        assert inv_acc.code == "1300"
        # cost_at_sale 25000 × qty 2 = 50000
        assert debit_line.debit == 50000.0
        assert credit_line.credit == 50000.0


def test_delivered_order_cogs_uses_baseline_fallback(api_client):
    """AC3: when no cost_history row exists, cost_at_sale falls back to the
    baseline rule (30% of base_price for non-phụ-kiện) and COGS is computed
    from that value.
    """
    product = _create_product(api_client, name="Bánh kem", cost=0, base_price=100000)
    pid = int(product["id"])
    order = _create_order(
        api_client,
        items=[{"productName": "Bánh kem", "quantity": 1, "unitPrice": 100000, "productId": str(pid)}],
    )
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=100000, type="payment", method="cash")
    order_id = int(order["id"])

    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200
    with get_db() as conn:
        oi = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE order_id = ?", (order_id,)
        ).fetchone()
        # baseline: 30% of 100000 = 30000
        assert float(oi["cost_at_sale"] or 0) == 30000.0
        cogs_entries = _journal_for_source(conn, "order_cogs", order_id)
        assert len(cogs_entries) == 1
        lines = _lines_for_entry(conn, cogs_entries[0].id)
        debit_line = next(l for l in lines if l.debit > 0)
        assert debit_line.debit == 30000.0


def test_delivered_order_no_cogs_when_product_cost_zero(api_client):
    """AC4: product with cost=0 AND base_price=0 → baseline resolves to 0 →
    cost_at_sale stays 0 → no COGS entry.
    """
    product = _create_product(api_client, name="Bánh mẫu", cost=0, base_price=0)
    pid = str(product["id"])
    order = _create_order(
        api_client,
        items=[{"productName": "Bánh mẫu", "quantity": 1, "unitPrice": 0, "productId": pid}],
        status="delivered",
        paymentMethod="cash",
    )
    order_id = int(order["id"])

    with get_db() as conn:
        oi = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE order_id = ?", (order_id,)
        ).fetchone()
        assert float(oi["cost_at_sale"] or 0) == 0.0
        cogs_entries = _journal_for_source(conn, "order_cogs", order_id)
        assert len(cogs_entries) == 0


def test_delivered_order_multi_item_cogs_single_entry(api_client):
    """Regression for review finding C-1: a multi-item delivered order with
    multiple cost-bearing items must produce exactly ONE order_cogs journal
    entry whose debit/credit equals the accumulated total_cogs across all
    items — not one entry per item with partial running totals.

    Before the fix, the COGS insert lived inside the per-item loop, producing
    N duplicate order_cogs entries (one per cost-bearing item) with growing
    partial totals (item1, item1+item2, item1+item2+item3).
    """
    product_a = _create_product(api_client, name="Bột mì", cost=0, base_price=50000)
    product_b = _create_product(api_client, name="Đường", cost=0, base_price=40000)
    product_c = _create_product(api_client, name="Trứng", cost=0, base_price=30000)
    pid_a = int(product_a["id"])
    pid_b = int(product_b["id"])
    pid_c = int(product_c["id"])
    # Seed cost_history with distinct per-unit costs for each product so the
    # resolved cost_at_sale is non-zero for every item.
    with get_db() as conn:
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (pid_a, 10000, "2020-01-01T00:00:00"),
        )
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (pid_b, 8000, "2020-01-01T00:00:00"),
        )
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (pid_c, 6000, "2020-01-01T00:00:00"),
        )
    order = _create_order(
        api_client,
        items=[
            {"productName": "Bột mì", "quantity": 2, "unitPrice": 50000, "productId": str(pid_a)},
            {"productName": "Đường", "quantity": 3, "unitPrice": 40000, "productId": str(pid_b)},
            {"productName": "Trứng", "quantity": 4, "unitPrice": 30000, "productId": str(pid_c)},
        ],
    )
    ref = order["orderRef"]
    order_id = int(order["id"])
    _create_txn(api_client, ref, amount=400000, type="payment", method="cash")

    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200
    with get_db() as conn:
        cogs_entries = _journal_for_source(conn, "order_cogs", order_id)
        # Exactly one COGS entry for the whole order, not one per item.
        assert len(cogs_entries) == 1, (
            f"expected exactly 1 order_cogs entry, got {len(cogs_entries)}"
        )
        lines = _lines_for_entry(conn, cogs_entries[0].id)
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        cogs_acc = Account.get_by_id(conn, debit_line.account_id)
        inv_acc = Account.get_by_id(conn, credit_line.account_id)
        assert cogs_acc.code == "5900"
        assert inv_acc.code == "1300"
        # Accumulated total: (10000×2) + (8000×3) + (6000×4) = 20000 + 24000 + 24000 = 68000
        expected_total = 10000 * 2 + 8000 * 3 + 6000 * 4
        assert debit_line.debit == pytest.approx(expected_total)
        assert credit_line.credit == pytest.approx(expected_total)


def test_delivered_order_journal_idempotent(api_client):
    """Re-transitioning to delivered does not duplicate journal entries."""
    order = _create_order(api_client, total=200000)
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=200000, type="payment", method="cash")
    order_id = int(order["id"])
    api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    with get_db() as conn:
        n1 = len(_journal_for_source(conn, "order", order_id))
    # Re-deliver (transition away then back)
    api_client.post(f"/api/orders/{ref}/status", json={"status": "ready", "reason": "test"})
    api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    with get_db() as conn:
        n2 = len(_journal_for_source(conn, "order", order_id))
    assert n2 == n1


def test_create_order_with_delivered_status_creates_journal(api_client):
    """POS quick-sale path (create_order with status='delivered') also journals."""
    order = _create_order(
        api_client,
        total=150000,
        status="delivered",
        paymentMethod="cash",
    )
    order_id = int(order["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "order", order_id)
        assert len(entries) == 1


# ---------------------------------------------------------------------------
# GET /api/accounts/journal — filter + pagination (FR9, AC3, NFR5)
# ---------------------------------------------------------------------------


def test_journal_filter_by_source_type(api_client):
    _create_expense(api_client, amount=50000)
    order = _create_order(api_client)
    _create_txn(api_client, order["orderRef"], amount=100000, type="deposit", method="cash")
    resp = api_client.get("/api/accounts/journal", params={"source_type": "expense"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] >= 1
    for item in body["items"]:
        assert item["sourceType"] == "expense"


def test_journal_filter_by_source_id(api_client):
    ev = _create_expense(api_client, amount=50000)
    eid = int(ev["id"])
    resp = api_client.get("/api/accounts/journal", params={
        "source_type": "expense", "source_id": eid,
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 1
    assert int(body["items"][0]["sourceId"]) == eid


def test_journal_filter_by_account_id(api_client):
    """Filter journal entries that touch a specific account."""
    ev = _create_expense(api_client, amount=50000, category="Nguyên liệu")
    eid = int(ev["id"])
    with get_db() as conn:
        expense_entry = _journal_for_source(conn, "expense", eid)[0]
        # "Nguyên liệu" debits Inventory (1300), not Expense (5100)
        inventory_acc_id = _account_id(conn, "1300")
    resp = api_client.get("/api/accounts/journal", params={"account_id": inventory_acc_id})
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] >= 1
    # Each entry must touch account 1300 in one of its lines
    for item in body["items"]:
        codes = {line.get("accountCode") for line in item["lines"]}
        assert "1300" in codes


def test_journal_pagination(api_client):
    """NFR5: limit/offset pagination works."""
    for i in range(5):
        _create_expense(api_client, amount=10000 + i, summary=f"Expense {i}")
    resp = api_client.get("/api/accounts/journal", params={"limit": 2, "offset": 0, "source_type": "expense"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["limit"] == 2
    assert body["offset"] == 0
    assert body["total"] >= 5
    assert len(body["items"]) == 2
    # Page 2
    resp2 = api_client.get("/api/accounts/journal", params={"limit": 2, "offset": 2, "source_type": "expense"})
    body2 = resp2.json()
    assert len(body2["items"]) == 2
    # Ensure no overlap: ids differ
    page1_ids = {item["id"] for item in body["items"]}
    page2_ids = {item["id"] for item in body2["items"]}
    assert not (page1_ids & page2_ids)


def test_journal_entries_include_account_info(api_client):
    """Journal line dicts are enriched with accountCode/accountName/accountType."""
    _create_expense(api_client, amount=50000)
    resp = api_client.get("/api/accounts/journal", params={"source_type": "expense", "limit": 1})
    body = resp.json()
    assert body["total"] >= 1
    line = body["items"][0]["lines"][0]
    assert "accountCode" in line
    assert "accountName" in line
    assert "accountType" in line


# ---------------------------------------------------------------------------
# GET /api/accounts/balances (FR10, AC4)
# ---------------------------------------------------------------------------


def test_balances_reflect_transactions(api_client):
    """AC4: balances computed correctly from journal_lines."""
    # Expense 50000 cash, "Nguyên liệu" → debit 1300 (Inventory), credit 1100
    _create_expense(api_client, amount=50000, category="Nguyên liệu",
                    payment_source="Shop tiền mặt")
    # Deposit 200000 cash → debit 1100, credit 2100
    order = _create_order(api_client)
    _create_txn(api_client, order["orderRef"], amount=200000, type="deposit", method="cash")
    resp = api_client.get("/api/accounts/balances")
    assert resp.status_code == 200
    balances = {b["code"]: b for b in resp.json()}
    # Cash on Hand (asset): debit 200000 (deposit) - credit 50000 (expense) = 150000
    assert balances["1100"]["balance"] == 150000.0
    # 1300 inventory: debit 50000 - credit 0 = 50000
    assert balances["1300"]["balance"] == 50000.0
    # 2100 liability: credit 200000 - debit 0 = 200000
    assert balances["2100"]["balance"] == 200000.0


def test_balances_include_all_accounts(api_client):
    """Even accounts with no activity show balance 0."""
    resp = api_client.get("/api/accounts/balances")
    assert resp.status_code == 200
    balances = resp.json()
    codes = {b["code"] for b in balances}
    for required in ("1100", "1200", "1300", "2100", "3100", "4100", "5100", "5900"):
        assert required in codes


# ---------------------------------------------------------------------------
# POST /api/accounts/journal/lock (FR11)
# ---------------------------------------------------------------------------


def test_journal_lock_locks_entries_in_range(api_client):
    """FR11: lock entries in a date range."""
    ev = _create_expense(api_client, amount=50000)
    eid = int(ev["id"])
    with get_db() as conn:
        entry_id = _journal_for_source(conn, "expense", eid)[0].id
        transaction_date = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (entry_id,)
        ).fetchone()["transaction_date"]
    # Lock a wide range around transaction_date (FR9: lock filters on transaction_date)
    since = transaction_date[:10] + "T00:00:00"
    until = transaction_date[:10] + "T23:59:59"
    resp = api_client.post("/api/accounts/journal/lock", json={"since": since, "until": until, "lockedBy": "sinh"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["lockedCount"] >= 1
    with get_db() as conn:
        locked_at = conn.execute("SELECT locked_at FROM journal_entries WHERE id = ?", (entry_id,)).fetchone()["locked_at"]
        assert locked_at is not None


def test_journal_lock_skips_already_locked(api_client):
    """Locking a range twice only locks new entries; already-locked stay."""
    ev = _create_expense(api_client, amount=50000)
    eid = int(ev["id"])
    with get_db() as conn:
        entry_id = _journal_for_source(conn, "expense", eid)[0].id
        transaction_date = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (entry_id,)
        ).fetchone()["transaction_date"]
    since = transaction_date[:10] + "T00:00:00"
    until = transaction_date[:10] + "T23:59:59"
    r1 = api_client.post("/api/accounts/journal/lock", json={"since": since, "until": until})
    assert r1.json()["lockedCount"] >= 1
    r2 = api_client.post("/api/accounts/journal/lock", json={"since": since, "until": until})
    assert r2.json()["lockedCount"] == 0


# ---------------------------------------------------------------------------
# POST /api/accounts/owner-capital, /owner-draw, /staff-reimburse (FR12, FR13)
# ---------------------------------------------------------------------------


def test_owner_capital_creates_journal_entry(api_client):
    """FR12: owner capital in → debit Cash, credit Owner's Equity (3100)."""
    resp = api_client.post("/api/accounts/owner-capital", json={"amount": 5000000, "method": "cash", "note": "vốn đầu"})
    assert resp.status_code == 201
    body = resp.json()
    assert body["sourceType"] == "owner_capital"
    with get_db() as conn:
        lines = _lines_for_entry(conn, int(body["id"]))
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        assert Account.get_by_id(conn, debit_line.account_id).code == "1100"
        assert Account.get_by_id(conn, credit_line.account_id).code == "3100"
        assert debit_line.debit == 5000000.0


def test_owner_capital_transfer_hits_bank_account(api_client):
    """method='transfer' debits Bank Account (1200)."""
    resp = api_client.post("/api/accounts/owner-capital", json={"amount": 1000000, "method": "transfer"})
    assert resp.status_code == 201
    with get_db() as conn:
        lines = _lines_for_entry(conn, int(resp.json()["id"]))
        debit_line = next(l for l in lines if l.debit > 0)
        assert Account.get_by_id(conn, debit_line.account_id).code == "1200"


def test_owner_draw_creates_journal_entry(api_client):
    """FR12: owner draw → debit Owner's Equity (3100), credit Cash."""
    resp = api_client.post("/api/accounts/owner-draw", json={"amount": 200000, "method": "cash"})
    assert resp.status_code == 201
    with get_db() as conn:
        lines = _lines_for_entry(conn, int(resp.json()["id"]))
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        assert Account.get_by_id(conn, debit_line.account_id).code == "3100"
        assert Account.get_by_id(conn, credit_line.account_id).code == "1100"
        assert credit_line.credit == 200000.0


def test_staff_reimburse_creates_journal_entry(api_client):
    """FR13: staff reimburse → debit Staff Advances sub-account, credit Cash."""
    resp = api_client.post("/api/accounts/staff-reimburse", json={
        "staffName": "Lan", "amount": 100000, "method": "cash", "note": "hoàn ứng",
    })
    assert resp.status_code == 201
    with get_db() as conn:
        lines = _lines_for_entry(conn, int(resp.json()["id"]))
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        staff_acc = Account.get_by_id(conn, debit_line.account_id)
        assert staff_acc.code.startswith("23")
        assert staff_acc.type == "liability"
        assert staff_acc.parent_id == _account_id(conn, "2300")
        assert staff_acc.name == "Lan"
        assert Account.get_by_id(conn, credit_line.account_id).code == "1100"
        assert debit_line.debit == 100000.0


def test_staff_reimburse_creates_sub_account_idempotent(api_client):
    """Reimbursing the same staff twice reuses the same sub-account."""
    api_client.post("/api/accounts/staff-reimburse", json={"staffName": "Mai", "amount": 50000, "method": "cash"})
    api_client.post("/api/accounts/staff-reimburse", json={"staffName": "Mai", "amount": 30000, "method": "cash"})
    with get_db() as conn:
        rows = conn.execute(
            "SELECT id FROM accounts WHERE parent_id = ? AND name = 'Mai'",
            (_account_id(conn, "2300"),),
        ).fetchall()
        assert len(rows) == 1


# ---------------------------------------------------------------------------
# Double-entry integrity (NFR4)
# ---------------------------------------------------------------------------


def test_every_journal_entry_debit_equals_credit(api_client):
    """NFR4: debit = credit for every journal entry across all source types."""
    _create_expense(api_client, amount=50000)
    order = _create_order(api_client)
    _create_txn(api_client, order["orderRef"], amount=100000, type="deposit", method="cash")
    api_client.post("/api/accounts/owner-capital", json={"amount": 1000000, "method": "cash"})
    api_client.post("/api/accounts/staff-reimburse", json={"staffName": "Lan", "amount": 50000, "method": "cash"})
    with get_db() as conn:
        rows = conn.execute(
            "SELECT je.id AS eid, SUM(jl.debit) AS td, SUM(jl.credit) AS tc "
            "FROM journal_entries je JOIN journal_lines jl ON jl.journal_entry_id = je.id "
            "GROUP BY je.id"
        ).fetchall()
        assert len(rows) > 0
        for r in rows:
            assert abs(float(r["td"]) - float(r["tc"])) < 0.01, (
                f"Entry {r['eid']}: debit={r['td']} credit={r['tc']}"
            )


# ---------------------------------------------------------------------------
# No regression (NFR3) — existing flows still work
# ---------------------------------------------------------------------------


def test_expense_api_still_returns_correct_shape(api_client):
    """NFR3: expense create still returns the same response shape."""
    ev = _create_expense(api_client, amount=50000)
    assert "id" in ev
    assert "summary" in ev
    assert ev["type"] == "expense"
    assert ev["data"]["amount_vnd"] == 50000


def test_payment_txn_api_still_returns_correct_shape(api_client):
    """NFR3: payment create still returns the same response shape."""
    order = _create_order(api_client)
    txn = _create_txn(api_client, order["orderRef"], amount=100000, type="deposit", method="cash")
    assert "id" in txn
    assert txn["amount"] == 100000
    assert txn["type"] == "deposit"
    assert txn["method"] == "cash"


def test_order_create_still_works(api_client):
    """NFR3: order create unaffected."""
    order = _create_order(api_client, total=250000)
    assert "orderRef" in order
    assert order["totalPrice"] == 250000


# ---------------------------------------------------------------------------
# Phase 3 — Downstream consumers: journal listing excludes invalidated (FR7, AC8)
# ---------------------------------------------------------------------------


def _invalidate_txn(conn, txn_id: int, invalidated_by: str = "tester") -> None:
    """Simulate the invalidated state for Phase 3 consumer-filter tests.

    Sets ``invalidated_at`` on the payment transaction. The journal entry is
    left in place so the consumer filter (FR7) can be tested independently of
    Phase 2's journal cleanup behavior.
    """
    conn.execute(
        "UPDATE payment_transactions SET invalidated_at = ?, invalidated_by = ? WHERE id = ?",
        (datetime.now().isoformat(), invalidated_by, txn_id),
    )


def test_journal_excludes_invalidated_payment_by_default(api_client):
    """AC8: journal entries from invalidated transactions are excluded by default."""
    order = _create_order(api_client, total=200000)
    txn = _create_txn(api_client, order["orderRef"], amount=200000, type="deposit", method="cash")
    txn_id = int(txn["id"])

    # Before invalidation: the payment journal entry is visible.
    resp = api_client.get("/api/accounts/journal", params={"source_type": "payment_transaction"})
    assert resp.status_code == 200
    assert resp.json()["total"] >= 1

    # Invalidate the transaction (sets invalidated_at + reverses journal entry).
    with get_db() as conn:
        _invalidate_txn(conn, txn_id)

    # After invalidation: default listing excludes payment_transaction entries
    # whose source transaction is invalidated.
    resp = api_client.get("/api/accounts/journal", params={"source_type": "payment_transaction"})
    assert resp.status_code == 200
    body = resp.json()
    for item in body["items"]:
        assert int(item["sourceId"]) != txn_id, (
            f"Invalidated txn {txn_id} journal entry leaked into default listing"
        )

    # Explicit opt-in includes the invalidated-source entry.
    resp_inc = api_client.get(
        "/api/accounts/journal",
        params={"source_type": "payment_transaction", "include_invalidated": "true"},
    )
    assert resp_inc.status_code == 200
    body_inc = resp_inc.json()
    assert any(int(item["sourceId"]) == txn_id for item in body_inc["items"]), (
        "include_invalidated=true should surface the invalidated-source entry"
    )


def test_journal_invalidated_filter_preserves_other_sources(api_client):
    """FR7: the invalidated filter does not affect non-payment sources."""
    _create_expense(api_client, amount=50000)
    order = _create_order(api_client, total=100000)
    txn = _create_txn(api_client, order["orderRef"], amount=100000, type="deposit", method="cash")
    with get_db() as conn:
        _invalidate_txn(conn, int(txn["id"]))

    # Expense entries are still visible (not affected by the payment-invalidated filter).
    resp = api_client.get("/api/accounts/journal", params={"source_type": "expense"})
    assert resp.status_code == 200
    assert resp.json()["total"] >= 1


# ---------------------------------------------------------------------------
# Phase 3 — Accounting integrity after invalidation (NFR1, AC10)
# ---------------------------------------------------------------------------


def test_validate_passes_after_invalidation(api_client):
    """AC10: GET /api/accounts/validate passes all checks after a transaction is invalidated.

    The invalidated transaction's journal entry is reversed (unlocked → deleted),
    and ``source_completeness`` must exclude invalidated transactions so the
    accounting integrity report stays clean (NFR1).
    """
    order = _create_order(api_client, total=150000)
    txn = _create_txn(api_client, order["orderRef"], amount=150000, type="deposit", method="cash")
    txn_id = int(txn["id"])

    # Full invalidation: set invalidated_at and reverse/remove the journal entry.
    with get_db() as conn:
        conn.execute(
            "UPDATE payment_transactions SET invalidated_at = ?, invalidated_by = ? WHERE id = ?",
            (datetime.now().isoformat(), "tester", txn_id),
        )
        from baker.services.journal_sync import _sync_payment_journal
        row = conn.execute("SELECT * FROM payment_transactions WHERE id = ?", (txn_id,)).fetchone()
        _sync_payment_journal(
            conn,
            txn_id,
            float(row["amount"]),
            row["type"],
            row["method"],
            order_id=int(row["order_id"]),
            deleted=True,
        )

    resp = api_client.get("/api/accounts/validate")
    assert resp.status_code == 200
    body = resp.json()
    summary = body["summary"]
    assert summary["total_checks"] == 16, f"Expected 16 checks, got {summary['total_checks']}"
    failed = [c for c in body["checks"] if c["status"] != "pass"]
    assert not failed, (
        "Accounting integrity checks failed after invalidation: "
        + ", ".join(c.get("name", str(c)) for c in failed)
    )