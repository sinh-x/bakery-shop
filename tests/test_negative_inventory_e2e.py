"""DG-200 Phase 7 — End-to-end integration tests for the negative inventory
POS + reconciliation surplus inflow flow.

These tests exercise the full chain across API boundaries:
1. POS sale past zero stock → negative_balance row created (Phase 2).
2. Stock overview surfaces the net negative position (Phase 5).
3. Reconciliation draft reports the net negative expected_qty (Phase 3).
4. Reconciliation submit with surplus offsets the negative balance first,
   then restocks the remainder (Phase 3) and produces the correct journal
   entries (Phase 4).
5. Final stock overview reflects the corrected position.

Together these tests cover all FR-1..FR-9 and AC-1..AC-11 as an integrated
flow rather than isolated unit tests.
"""

from baker.db.connection import get_db
from baker.api.inventory_fifo import create_lot_with_items


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
        "customerName": "E2E POS",
        "items": items,
        "dueDate": "2026-07-10",
        "source": "Tại tiệm - POS",
        "status": status,
        "paymentMethod": "cash",
    }
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _neg_qty(conn, product_id: int, chip_id) -> int:
    row = conn.execute(
        "SELECT qty FROM negative_balance WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?",
        (product_id, chip_id),
    ).fetchone()
    return int(row["qty"]) if row else 0


def _available_qty(conn, product_id: int, chip_id) -> int:
    row = conn.execute(
        """SELECT COUNT(*) AS c FROM inventory_items ii
           JOIN stock_lots sl ON sl.id = ii.lot_id
           WHERE sl.product_id = ? AND sl.price_chip_id IS NOT DISTINCT FROM ?
             AND ii.status = 'available'""",
        (product_id, chip_id),
    ).fetchone()
    return int(row["c"])


def _submit_reconciliation(
    client,
    product_id: int,
    chip_id,
    expected_qty: int,
    counted_qty: int,
):
    return client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "E2E Staff",
            "lines": [
                {
                    "product_id": product_id,
                    "price_chip_id": chip_id,
                    "expected_qty": expected_qty,
                    "counted_qty": counted_qty,
                    "sale_qty": 0,
                    "waste_qty": 0,
                }
            ],
        },
    )


def test_e2e_negative_sale_then_surplus_clears_negative_and_restocks(api_client):
    """Full E2E: sell past zero → negative balance → reconciliation surplus
    offsets the negative and restocks the remainder.

    Covers FR-1..FR-9, AC-1, AC-3, AC-4, AC-5, AC-6, AC-7, AC-8, AC-9, AC-10.
    """
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "E2E Chip A", 20000)

    # --- Step 1: POS sale of 4 with zero stock → negative balance = 4. ---
    order = _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh kem",
            "quantity": 4,
            "unitPrice": 20000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        assert _neg_qty(conn, 1, chip_id) == 4
        assert _available_qty(conn, 1, chip_id) == 0
        neg = conn.execute(
            "SELECT quantity FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'negative_sale' AND product_id = 1 "
            "AND price_chip_id = ?",
            (ref, chip_id),
        ).fetchone()
        assert neg is not None and neg["quantity"] == -4

    # --- Step 2: stock overview reflects net negative position. ---
    resp = api_client.get("/api/stock/overview")
    assert resp.status_code == 200
    item = next(r for r in resp.json() if r["product_id"] == 1)
    assert item["quantity"] == -4
    chip_bucket = next(b for b in item["per_chip"] if b["price_chip_id"] == chip_id)
    assert chip_bucket["quantity"] == -4

    # --- Step 3: reconciliation draft reports net negative expected_qty. ---
    resp = api_client.get("/api/reconciliations/draft")
    assert resp.status_code == 200
    product = next(p for p in resp.json()["products"] if p["product_id"] == 1)
    # Find the chip-aware row; expected_qty should reflect net position.
    chip_row = next(
        (r for r in product.get("chip_rows", []) if r.get("price_chip_id") == chip_id),
        None,
    )
    if chip_row is not None:
        assert chip_row["expected_qty"] == -4
    else:
        # Some implementations surface expected at the product level.
        assert product["expected_qty"] == -4

    # --- Step 4: reconciliation surplus counted=10 → offsets 4, restocks 6. ---
    resp = _submit_reconciliation(
        api_client,
        product_id=1,
        chip_id=chip_id,
        expected_qty=-4,
        counted_qty=10,
    )
    assert resp.status_code == 201, resp.text
    session_id = resp.json()["id"]
    reference_id = f"reconciliation:{session_id}"

    with get_db() as conn:
        # Negative balance cleared.
        assert _neg_qty(conn, 1, chip_id) == 0
        # Restocked remainder = surplus(10) - negative(4) = 6.
        assert _available_qty(conn, 1, chip_id) == 6

        # restock movement logged with qty=+6.
        restock = conn.execute(
            "SELECT id, quantity FROM stock_movements "
            "WHERE movement_type = 'restock' AND reference_id = ? "
            "AND product_id = 1 AND price_chip_id = ? "
            "ORDER BY id DESC LIMIT 1",
            (reference_id, chip_id),
        ).fetchone()
        assert restock is not None
        assert restock["quantity"] == 6
        restock_movement_id = restock["id"]

        # AC-8: negative_sale_cogs journal entry created for the original
        # negative sale, keyed by the negative_sale stock_movement id.
        neg_movement = conn.execute(
            "SELECT id FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'negative_sale' AND product_id = 1 "
            "AND price_chip_id = ?",
            (ref, chip_id),
        ).fetchone()
        assert neg_movement is not None
        cogs_entry = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type = 'negative_sale_cogs' "
            "AND source_id = ? LIMIT 1",
            (neg_movement["id"],),
        ).fetchone()
        assert cogs_entry is not None, "negative_sale_cogs journal entry missing"

        # AC-9: restock_inflow journal entry created for the surplus inflow.
        inflow = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type = 'restock_inflow' "
            "AND source_id = ? LIMIT 1",
            (restock_movement_id,),
        ).fetchone()
        assert inflow is not None, "restock_inflow journal entry missing"

        # AC-7: inventory Event created for the restock movement.
        event = conn.execute(
            "SELECT id FROM events WHERE type = 'inventory' AND data LIKE ?",
            (f'%"reference_id": "{reference_id}"%',),
        ).fetchone()
        assert event is not None

    # --- Step 5: final stock overview reflects the restocked position. ---
    resp = api_client.get("/api/stock/overview")
    assert resp.status_code == 200
    item = next(r for r in resp.json() if r["product_id"] == 1)
    assert item["quantity"] == 6


def test_e2e_partial_deficit_sale_then_surplus_only_offsets_negative(api_client):
    """E2E: partial deficit sale (some FIFO consumed, some negative) followed
    by a reconciliation surplus that fully offsets the negative but does NOT
    create restock (counted == |negative|, available == 0).

    Covers AC-2, AC-3.
    """
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "E2E Chip B", 18000)

    # Restock 3, sell 5 → 3 FIFO consumed, 2 negative.
    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh kem",
            "quantity": 5,
            "unitPrice": 18000,
            "priceChipId": chip_id,
        }],
    )

    with get_db() as conn:
        assert _available_qty(conn, 1, chip_id) == 0
        assert _neg_qty(conn, 1, chip_id) == 2

    # Reconciliation: counted=2, available=0 → surplus=2, offsets 2 negative,
    # remainder 0 restocked (pure netting, AC-3).
    resp = _submit_reconciliation(
        api_client,
        product_id=1,
        chip_id=chip_id,
        expected_qty=-2,
        counted_qty=2,
    )
    assert resp.status_code == 201, resp.text
    session_id = resp.json()["id"]
    reference_id = f"reconciliation:{session_id}"

    with get_db() as conn:
        assert _neg_qty(conn, 1, chip_id) == 0
        # Pure netting: no restock created.
        assert _available_qty(conn, 1, chip_id) == 0
        restock = conn.execute(
            "SELECT 1 FROM stock_movements WHERE movement_type = 'restock' "
            "AND reference_id = ? AND product_id = 1 AND price_chip_id = ?",
            (reference_id, chip_id),
        ).fetchone()
        assert restock is None


def test_e2e_surplus_on_no_negative_balance_pure_restock(api_client):
    """E2E: product with positive available stock, no negative balance, counted
    > expected → pure restock inflow (no netting). Covers AC-5."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "E2E Chip C", 25000)

    with get_db() as conn:
        create_lot_with_items(conn, 1, chip_id, 10)

    resp = _submit_reconciliation(
        api_client,
        product_id=1,
        chip_id=chip_id,
        expected_qty=10,
        counted_qty=14,
    )
    assert resp.status_code == 201, resp.text
    session_id = resp.json()["id"]
    reference_id = f"reconciliation:{session_id}"

    with get_db() as conn:
        assert _neg_qty(conn, 1, chip_id) == 0
        assert _available_qty(conn, 1, chip_id) == 14
        restock = conn.execute(
            "SELECT quantity FROM stock_movements WHERE movement_type = 'restock' "
            "AND reference_id = ? AND product_id = 1 AND price_chip_id = ? "
            "ORDER BY id DESC LIMIT 1",
            (reference_id, chip_id),
        ).fetchone()
        assert restock is not None and restock["quantity"] == 4


def test_e2e_existing_flows_unaffected_no_negative_balance_introduced(api_client):
    """NFR-3 / backward compatibility: a normal POS sale with sufficient stock
    must not create a negative_balance row and must not log a negative_sale
    movement. Ensures prior phases did not regress existing flows."""
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "E2E Sufficient Chip", 15000)

    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 10, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    order = _create_pos_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh kem",
            "quantity": 4,
            "unitPrice": 15000,
            "priceChipId": chip_id,
        }],
    )
    ref = order["orderRef"]

    with get_db() as conn:
        assert _neg_qty(conn, 1, chip_id) == 0
        assert _available_qty(conn, 1, chip_id) == 6
        neg = conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'negative_sale'",
            (ref,),
        ).fetchone()
        assert neg is None
        sale = conn.execute(
            "SELECT quantity FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'sale' AND product_id = 1 AND price_chip_id = ?",
            (ref, chip_id),
        ).fetchone()
        assert sale is not None and sale["quantity"] == -4