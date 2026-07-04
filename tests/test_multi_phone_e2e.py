"""End-to-end integration tests for DG-205 multi-phone support.

Exercises the full flow across layers:
  v58 migration → customer create (phones array) → GET returns phones →
  search by secondary phone → order links by secondary phone →
  update phones (replace) → primary sync → delete cascades to customer_phones.

Traceability: FR1-FR9, NFR1-NFR4, AC1-AC10 (backend portions).
"""

from baker.db.connection import get_db
from baker.db.schema import ensure_schema, MIGRATIONS


def _create_customer_with_phones(client, name, phones):
    payload = {"name": name, "phones": phones}
    resp = client.post("/api/customers", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_e2e_multi_phone_full_lifecycle(api_client):
    """Full lifecycle: create → fetch → search → order link → update → delete."""
    # 1. Create customer with two phones (AC3).
    created = _create_customer_with_phones(
        api_client,
        name="Khách E2E",
        phones=[
            {"phone": "0981111222", "isPrimary": True},
            {"phone": "0982222333", "isPrimary": False},
        ],
    )
    cid = created["id"]
    assert created["phone"] == "0981111222"  # legacy denormalized = primary
    assert len(created["phones"]) == 2

    # 2. GET by id returns phones array (AC5).
    fetched = api_client.get(f"/api/customers/{cid}").json()
    assert len(fetched["phones"]) == 2
    assert fetched["phone"] == "0981111222"

    # 3. Search by secondary phone returns the customer (AC6).
    results = api_client.get("/api/customers?search=0982222").json()
    assert any(r["id"] == cid for r in results)

    # 4. Order created with the secondary phone links to this customer (AC7).
    order_resp = api_client.post(
        "/api/orders",
        json={
            "customerName": "Khách E2E",
            "customerPhone": "0982222333",
            "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}],
            "dueDate": "2026-07-05",
        },
    )
    assert order_resp.status_code == 201
    assert order_resp.json()["customerId"] == cid

    # 5. Update phones: replace with a new single primary (AC4).
    patched = api_client.patch(
        f"/api/customers/{cid}",
        json={"phones": [{"phone": "0983333444", "isPrimary": True}]},
    )
    assert patched.status_code == 200
    body = patched.json()
    assert len(body["phones"]) == 1
    assert body["phone"] == "0983333444"  # NFR3 sync

    # 6. Denormalized customers.phone is synced (NFR3).
    with get_db() as conn:
        row = conn.execute(
            "SELECT phone FROM customers WHERE id = ?", (cid,)
        ).fetchone()
        assert row["phone"] == "0983333444"

    # 7. Old phone rows are gone after replace (FR5).
    with get_db() as conn:
        count = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?", (cid,)
        ).fetchone()[0]
        assert count == 1

    # 8. Delete cascades to customer_phones (FR9).
    del_resp = api_client.delete(f"/api/customers/{cid}")
    assert del_resp.status_code == 200
    with get_db() as conn:
        count = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?", (cid,)
        ).fetchone()[0]
        assert count == 0


def test_e2e_legacy_phone_backward_compat(api_client):
    """Legacy phone string still works end-to-end (NFR4, FR3)."""
    # Create with legacy phone string only.
    resp = api_client.post(
        "/api/customers", json={"name": "Cũ", "phone": "0912345678"}
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["phone"] == "0912345678"
    assert len(body["phones"]) == 1
    assert body["phones"][0] == {"phone": "0912345678", "isPrimary": True}

    # Update with legacy phone string.
    patched = api_client.patch(
        f"/api/customers/{body['id']}", json={"phone": "0987654321"}
    )
    assert patched.status_code == 200
    pbody = patched.json()
    assert pbody["phone"] == "0987654321"
    assert len(pbody["phones"]) == 1
    assert pbody["phones"][0] == {"phone": "0987654321", "isPrimary": True}


def test_e2e_v58_migration_backfills_existing_phone(api_client):
    """v58 migration moves existing customers.phone into customer_phones (AC1, AC2)."""
    # Insert a customer directly (bypassing API) with a phone value, then run v58.
    with get_db() as conn:
        ensure_schema(conn)
        # Wipe customer_phones rows to simulate pre-v58 state (table exists from DDL).
        conn.execute("DELETE FROM customer_phones")
        # Insert a customer with a phone value (no existing phone rows).
        conn.execute(
            "INSERT INTO customers (name, phone, created_at) VALUES (?, ?, ?)",
            ("Tiền v58", "0977111222", "2026-07-01 10:00:00"),
        )
        conn.commit()
        # Run v58 migration callable.
        v58 = MIGRATIONS[58]
        assert v58["callable"] is not None
        v58["callable"](conn)
        conn.commit()

        # Verify customer_phones has the backfilled row.
        rows = conn.execute(
            "SELECT customer_id, phone, is_primary FROM customer_phones"
        ).fetchall()
        assert len(rows) == 1
        assert rows[0]["phone"] == "0977111222"
        assert rows[0]["is_primary"] == 1

        # customers.phone retained as denormalized fallback (AC2).
        cust = conn.execute("SELECT phone FROM customers WHERE name = 'Tiền v58'").fetchone()
        assert cust["phone"] == "0977111222"


def test_e2e_v58_migration_idempotent(api_client):
    """Re-running v58 does not duplicate rows (NFR1)."""
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO customers (name, phone, created_at) VALUES (?, ?, ?)",
            ("Lặp lại", "0977333444", "2026-07-01 11:00:00"),
        )
        conn.commit()
        v58 = MIGRATIONS[58]
        v58["callable"](conn)
        conn.commit()
        before = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE phone = '0977333444'"
        ).fetchone()[0]
        # Re-run.
        v58["callable"](conn)
        conn.commit()
        after = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE phone = '0977333444'"
        ).fetchone()[0]
        assert before == after == 1