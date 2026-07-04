"""Tests for negative inventory sale flow (DG-200 Phase 2).

Covers AC-1, AC-2, AC-6: POS sale past zero creates negative_balance row,
negative_sale stock_movement, and inventory Event. Partial deficit (AC-2)
consumes available FIFO items first then records the remainder as negative.
"""

from baker.db.connection import get_db


def _ensure_trung_bay(product_id: int) -> None:
    with get_db() as conn:
        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, 'trung_bay', 'true')
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (product_id,),
        )


def _create_chip(client, product_id: int, label: str, price: float) -> int:
    resp = client.post(
        f"/api/products/{product_id}/price-chips",
        json={"label": label, "price": price},
    )
    assert resp.status_code == 201
    return int(resp.json()["id"])


def _create_pos_order(client, items, status="delivered"):
    payload = {
        "customerName": "POS Tester",
        "items": items,
        "dueDate": "2026-07-10",
        "source": "Tại tiệm - POS",
        "status": status,
        "paymentMethod": "cash",
    }
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _negative_balance_qty(conn, product_id: int, chip_id) -> int:
    row = conn.execute(
        "SELECT qty FROM negative_balance WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?",
        (product_id, chip_id),
    ).fetchone()
    return int(row["qty"]) if row else 0


def test_negative_sale_zero_stock_creates_negative_balance(api_client):
    """AC-1: POS order on product with 0 stock succeeds; stock shows -N and
    a negative_sale stock_movement is created."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "AC1 Chip", 15000)

    order = _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh kem",
            "quantity": 3,
            "unitPrice": 15000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        # No available items were consumed (none existed).
        available = conn.execute(
            """SELECT COUNT(*) AS c FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = 1 AND sl.price_chip_id = ? AND ii.status = 'available'""",
            (chip_id,),
        ).fetchone()["c"]
        assert available == 0

        # Negative balance row exists with qty=3.
        assert _negative_balance_qty(conn, 1, chip_id) == 3

        # negative_sale movement logged with correct reference and qty.
        neg = conn.execute(
            """SELECT id, quantity FROM stock_movements
               WHERE reference_id = ? AND movement_type = 'negative_sale'
                 AND product_id = 1 AND price_chip_id = ?""",
            (ref, chip_id),
        ).fetchone()
        assert neg is not None
        assert neg["quantity"] == -3

        # sale movement also exists for the full sold qty.
        sale = conn.execute(
            """SELECT quantity FROM stock_movements
               WHERE reference_id = ? AND movement_type = 'sale'
                 AND product_id = 1 AND price_chip_id = ?""",
            (ref, chip_id),
        ).fetchone()
        assert sale is not None
        assert sale["quantity"] == -3


def test_negative_sale_partial_deficit_consumes_fifo_first(api_client):
    """AC-2: product with 3 available, POS order for 5 → 3 FIFO consumed,
    2 recorded as negative balance; net stock shows -2."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "AC2 Chip", 18000)

    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    order = _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh kem",
            "quantity": 5,
            "unitPrice": 18000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        consumed = conn.execute(
            """SELECT COUNT(*) AS c FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = 1 AND sl.price_chip_id = ? AND ii.status = 'consumed'""",
            (chip_id,),
        ).fetchone()["c"]
        assert consumed == 3

        available = conn.execute(
            """SELECT COUNT(*) AS c FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = 1 AND sl.price_chip_id = ? AND ii.status = 'available'""",
            (chip_id,),
        ).fetchone()["c"]
        assert available == 0

        # Net stock = available(0) - negative(2) = -2.
        from baker.api.inventory_fifo import net_available_quantity
        assert net_available_quantity(conn, 1, chip_id) == -2

        assert _negative_balance_qty(conn, 1, chip_id) == 2

        neg = conn.execute(
            """SELECT quantity FROM stock_movements
               WHERE reference_id = ? AND movement_type = 'negative_sale'
                 AND product_id = 1 AND price_chip_id = ?""",
            (ref, chip_id),
        ).fetchone()
        assert neg is not None
        assert neg["quantity"] == -2


def test_negative_sale_logs_inventory_event(api_client):
    """AC-6: a negative sale creates an Event of type 'inventory' with
    movement_type='negative_sale' and the correct qty."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "AC6 Chip", 22000)

    order = _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh kem",
            "quantity": 2,
            "unitPrice": 22000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        event = conn.execute(
            """SELECT summary, type, data FROM events
               WHERE type = 'inventory' AND data LIKE ?""",
            (f'%"reference_id": "{ref}"%',),
        ).fetchall()
        neg_events = [
            e for e in event
            if '"movement_type": "negative_sale"' in (e["data"] or "")
        ]
        assert len(neg_events) >= 1
        assert '"quantity": -2' in neg_events[0]["data"]


def test_negative_sale_non_pos_source_still_blocked(api_client):
    """NFR-3: non-POS source without useInventory cannot oversell — the
    historical FIFO-blocks-at-zero behaviour must remain (allow_negative=False
    for non-POS sources)."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "NonPOS Chip", 9000)

    payload = {
        "customerName": "NonPOS Tester",
        "items": [{
            "productId": "1",
            "productName": "Bánh kem",
            "quantity": 1,
            "unitPrice": 9000,
            "priceChipId": chip_id,
        }],
        "dueDate": "2026-07-10",
        "source": "Online",
        "status": "delivered",
        "paymentMethod": "cash",
    }
    resp = api_client.post("/api/orders", json=payload)
    # Order creation itself succeeds; the stock decrement happens at delivered
    # status. Non-POS source without useInventory should not consume FIFO at
    # all (should_consume_fifo=False), so no negative balance is created and
    # no 422 is raised.
    assert resp.status_code == 201
    ref = resp.json()["orderRef"]

    with get_db() as conn:
        assert _negative_balance_qty(conn, 1, chip_id) == 0
        neg = conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ? AND movement_type = 'negative_sale'",
            (ref,),
        ).fetchone()
        assert neg is None


def test_restore_order_with_negative_sale_reduces_negative_balance(api_client):
    """Restore of an order that produced a negative sale must reduce the
    negative_balance by the deficit portion (not create spurious new stock)."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "Restore Chip", 13000)

    # Restock 2, sell 5 → 2 FIFO consumed, 3 negative.
    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 2, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    order = _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh kem",
            "quantity": 5,
            "unitPrice": 13000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        assert _negative_balance_qty(conn, 1, chip_id) == 3

    cancel = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "test"},
    )
    assert cancel.status_code == 200

    with get_db() as conn:
        # Negative balance should be back to 0 after restore.
        assert _negative_balance_qty(conn, 1, chip_id) == 0
        # FIFO-consumed 2 items should have been restored as available.
        available = conn.execute(
            """SELECT COUNT(*) AS c FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = 1 AND sl.price_chip_id = ? AND ii.status = 'available'""",
            (chip_id,),
        ).fetchone()["c"]
        assert available == 2


# ---------------------------------------------------------------------------
# DG-200 Phase 4 — Accounting Entries (AC-8: COGS journal for negative sales)
# ---------------------------------------------------------------------------


def _negative_sale_cogs_entries(conn, movement_id: int):
    return conn.execute(
        "SELECT * FROM journal_entries WHERE source_type = 'negative_sale_cogs' "
        "AND source_id = ? ORDER BY id",
        (movement_id,),
    ).fetchall()


def _entry_lines(conn, entry_id: int):
    return conn.execute(
        "SELECT * FROM journal_lines WHERE journal_entry_id = ? ORDER BY id",
        (entry_id,),
    ).fetchall()


def test_negative_sale_creates_cogs_journal_entry_ac8(api_client):
    """AC-8: a negative sale produces a COGS journal entry debiting 5900 and
    crediting 1300 for the oversold quantity (baseline cost)."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "AC8 Chip", 15000)

    order = _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh mì trắng",
            "quantity": 3,
            "unitPrice": 15000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        neg = conn.execute(
            """SELECT id FROM stock_movements
               WHERE reference_id = ? AND movement_type = 'negative_sale'
                 AND product_id = 1 AND price_chip_id = ?""",
            (ref, chip_id),
        ).fetchone()
        assert neg is not None
        movement_id = neg["id"]

        entries = _negative_sale_cogs_entries(conn, movement_id)
        assert len(entries) == 1

        lines = _entry_lines(conn, entries[0]["id"])
        debit_line = next(l for l in lines if l["debit"] > 0)
        credit_line = next(l for l in lines if l["credit"] > 0)
        cogs_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (debit_line["account_id"],)
        ).fetchone()
        inv_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (credit_line["account_id"],)
        ).fetchone()
        assert cogs_acc["code"] == "5900"
        assert inv_acc["code"] == "1300"
        # Product 1 base_price=10000 → baseline 30% = 3000 × 3 = 9000
        assert debit_line["debit"] == 9000.0
        assert credit_line["credit"] == 9000.0


def test_negative_sale_cogs_uses_cost_history_when_present_ac8(api_client):
    """AC-8: when a cost_history row exists, it overrides the baseline cost."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "AC8b Chip", 17000)

    with get_db() as conn:
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 25000, "2020-01-01T00:00:00Z"),
        )

    order = _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh mì trắng",
            "quantity": 2,
            "unitPrice": 17000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        neg = conn.execute(
            """SELECT id FROM stock_movements
               WHERE reference_id = ? AND movement_type = 'negative_sale'
                 AND product_id = 1 AND price_chip_id = ?""",
            (ref, chip_id),
        ).fetchone()
        movement_id = neg["id"]
        entries = _negative_sale_cogs_entries(conn, movement_id)
        assert len(entries) == 1
        lines = _entry_lines(conn, entries[0]["id"])
        debit_line = next(l for l in lines if l["debit"] > 0)
        # cost_history cost 25000 × qty 2 = 50000
        assert debit_line["debit"] == 50000.0


def test_negative_sale_cogs_idempotent_ac8(api_client):
    """AC-8: re-invoking the sync helper directly must not duplicate entries."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "AC8c Chip", 19000)

    order = _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh mì trắng",
            "quantity": 2,
            "unitPrice": 19000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        neg = conn.execute(
            """SELECT id FROM stock_movements
               WHERE reference_id = ? AND movement_type = 'negative_sale'
                 AND product_id = 1 AND price_chip_id = ?""",
            (ref, chip_id),
        ).fetchone()
        movement_id = neg["id"]

        from baker.services.journal_sync import _sync_negative_sale_cogs_journal

        _sync_negative_sale_cogs_journal(conn, 1, movement_id, 2)
        entries = _negative_sale_cogs_entries(conn, movement_id)
        assert len(entries) == 1


def test_negative_sale_no_cogs_when_cost_zero_ac8(api_client):
    """AC-8 edge: a product with zero base_price and no cost_history produces
    no negative_sale_cogs entry."""
    prod = api_client.post(
        "/api/products",
        json={"name": "AC8 Zero", "category": "cake", "base_price": 0, "cost": 0},
    )
    assert prod.status_code == 201
    pid = prod.json()["id"]
    _ensure_trung_bay(pid)
    chip_id = _create_chip(api_client, pid, "AC8z Chip", 5000)

    order = _create_pos_order(
        api_client,
        items=[{
            "productId": str(pid),
            "productName": "AC8 Zero",
            "quantity": 1,
            "unitPrice": 5000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        neg = conn.execute(
            """SELECT id FROM stock_movements
               WHERE reference_id = ? AND movement_type = 'negative_sale'
                 AND product_id = ? AND price_chip_id = ?""",
            (ref, pid, chip_id),
        ).fetchone()
        assert neg is not None
        entries = _negative_sale_cogs_entries(conn, neg["id"])
        assert len(entries) == 0