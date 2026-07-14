"""Tests for DG-029 Phase 5.6-c2 — AC14/FR17 actor derivation.

Verifies that the acting username is derived from the authenticated JWT
session (``request.state.auth_username``) instead of free-text client input
across the checklist toggle, event log, and stock reconciliation write
paths. Also verifies the grace-period fallback (NFR6): when
``AUTH_REQUIRED=false`` and no token is present, the client-provided name
is still used so legacy unauthenticated flows keep working.
"""

from __future__ import annotations

from baker.db.connection import get_db

# DG-029 Phase 5.6-c3 / CQ-2: shared auth test helpers (_create_test_user,
# _make_token, _seed_user, _auth_headers) live in tests/auth_helpers.py and
# the _reset_auth / auth_client / anon_client fixtures live in
# tests/conftest.py — both auto-discovered by pytest, so no duplicate
# definitions remain in this module.
from tests.auth_helpers import _auth_headers, _seed_user


TODAY = "2026-07-14"


# ---------------------------------------------------------------------------
# F1 — Checklist toggle (POST /api/checklist/daily/{entry_id}/toggle)
# ---------------------------------------------------------------------------


def test_checklist_toggle_authenticated_uses_jwt_username(auth_client):
    """AC14: when authenticated, completed_by = JWT sub, not free-text."""
    with get_db() as conn:
        token = _seed_user(conn, "checkliststaff", "staff")
    headers = _auth_headers(token)

    resp = auth_client.get(f"/api/checklist/daily?date={TODAY}", headers=headers)
    entry_id = resp.json()["entries"][0]["id"]

    resp = auth_client.post(
        f"/api/checklist/daily/{entry_id}/toggle",
        json={"staff_name": "FreeTextImposter"},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["completed"] is True
    # AC14: authenticated username wins over free-text input
    assert resp.json()["completed_by"] == "checkliststaff"


def test_checklist_toggle_grace_period_falls_back_to_staff_name(anon_client):
    """NFR6: AUTH_REQUIRED=false + no token → client-provided name is used."""
    resp = anon_client.get(f"/api/checklist/daily?date={TODAY}")
    entry_id = resp.json()["entries"][0]["id"]

    resp = anon_client.post(
        f"/api/checklist/daily/{entry_id}/toggle",
        json={"staff_name": "Ân"},
    )
    assert resp.status_code == 200
    assert resp.json()["completed_by"] == "Ân"


def test_checklist_toggle_grace_period_with_token_uses_jwt_username(anon_client):
    """Grace period + token present → JWT username still wins (updated client)."""
    with get_db() as conn:
        token = _seed_user(conn, "checkliststaff2", "staff")

    resp = anon_client.get(f"/api/checklist/daily?date={TODAY}")
    entry_id = resp.json()["entries"][0]["id"]

    resp = anon_client.post(
        f"/api/checklist/daily/{entry_id}/toggle",
        json={"staff_name": "Imposter"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200
    assert resp.json()["completed_by"] == "checkliststaff2"


# ---------------------------------------------------------------------------
# F2 — Event log create (POST /api/events)
# ---------------------------------------------------------------------------


def test_event_create_authenticated_uses_jwt_username(auth_client):
    """FR17: when authenticated, logged_by = JWT sub, not free-text."""
    with get_db() as conn:
        token = _seed_user(conn, "eventstaff", "staff")

    resp = auth_client.post(
        "/api/events",
        json={"summary": "Test event", "logged_by": "Imposter"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["logged_by"] == "eventstaff"

    # event_history audit actor should also be the JWT username
    with get_db() as conn:
        rows = conn.execute(
            "SELECT actor FROM event_history WHERE event_id = ? AND action_type = 'create'",
            (ev["id"],),
        ).fetchall()
    assert len(rows) == 1
    assert rows[0]["actor"] == "eventstaff"


def test_event_create_grace_period_falls_back_to_logged_by(anon_client):
    """NFR6: AUTH_REQUIRED=false + no token → client-provided logged_by is used."""
    resp = anon_client.post(
        "/api/events",
        json={"summary": "Grace event", "logged_by": "Ngân"},
    )
    assert resp.status_code == 201
    assert resp.json()["logged_by"] == "Ngân"


def test_event_create_grace_period_no_logged_by_actor_empty(anon_client):
    """Grace period + no token + no logged_by → actor is empty (legacy contract)."""
    resp = anon_client.post(
        "/api/events",
        json={"summary": "No logger", "source": "app"},
    )
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["logged_by"] == ""

    with get_db() as conn:
        rows = conn.execute(
            "SELECT actor FROM event_history WHERE event_id = ? AND action_type = 'create'",
            (ev["id"],),
        ).fetchall()
    assert rows[0]["actor"] == ""


def test_event_patch_authenticated_actor_derived_from_jwt(auth_client):
    """FR17: PATCH event audit actor = JWT sub when authenticated."""
    with get_db() as conn:
        token = _seed_user(conn, "eventstaff2", "staff")

    create = auth_client.post(
        "/api/events",
        json={"summary": "Original"},
        headers=_auth_headers(token),
    )
    event_id = create.json()["id"]

    resp = auth_client.patch(
        f"/api/events/{event_id}",
        json={"summary": "Updated", "logged_by": "Imposter"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200
    assert resp.json()["logged_by"] == "eventstaff2"

    with get_db() as conn:
        rows = conn.execute(
            "SELECT actor FROM event_history WHERE event_id = ? AND action_type = 'edit'",
            (event_id,),
        ).fetchall()
    assert len(rows) >= 1
    assert all(r["actor"] == "eventstaff2" for r in rows)


def test_event_delete_authenticated_actor_derived_from_jwt(auth_client):
    """FR17: DELETE event soft-delete actor = JWT sub when authenticated."""
    with get_db() as conn:
        token = _seed_user(conn, "eventadmin", "admin")

    create = auth_client.post(
        "/api/events",
        json={"summary": "To delete"},
        headers=_auth_headers(token),
    )
    event_id = create.json()["id"]

    resp = auth_client.delete(
        f"/api/events/{event_id}?deleted_by=Imposter",
        headers=_auth_headers(token),
    )
    assert resp.status_code == 204

    with get_db() as conn:
        row = conn.execute(
            "SELECT deleted_by, actor FROM events e "
            "JOIN event_history h ON h.event_id = e.id AND h.action_type = 'delete' "
            "WHERE e.id = ?",
            (event_id,),
        ).fetchone()
    assert row["deleted_by"] == "eventadmin"
    assert row["actor"] == "eventadmin"


# ---------------------------------------------------------------------------
# F3 — Stock reconciliation submit (POST /api/reconciliations/submit)
# ---------------------------------------------------------------------------


def _mark_product_display(conn, product_id: int, value: str = "true"):
    conn.execute(
        """INSERT INTO product_attribute_values (product_id, attribute_type, value)
           VALUES (?, 'trung_bay', ?)
           ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
        (product_id, value),
    )


def _set_stock(conn, product_id: int, quantity: int):
    from baker.api.inventory_fifo import create_lot_with_items

    conn.execute(
        "DELETE FROM inventory_items WHERE lot_id IN (SELECT id FROM stock_lots WHERE product_id = ?)",
        (product_id,),
    )
    conn.execute("DELETE FROM stock_lots WHERE product_id = ?", (product_id,))
    if quantity > 0:
        create_lot_with_items(conn, product_id, None, quantity)


def _reconciliation_payload(staff_name: str = "Imposter") -> dict:
    return {
        "staff_name": staff_name,
        "payment_method": "cash",
        "waste_reason": "",
        "lines": [
            {
                "product_id": 1,
                "expected_qty": 5,
                "counted_qty": 4,
                "sale_qty": 1,
                "waste_qty": 0,
                "manual_unit_price": 15000,
            }
        ],
    }


def test_reconciliation_submit_authenticated_uses_jwt_username(auth_client):
    """FR17: when authenticated, reconciliation staff_name = JWT sub."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)
        token = _seed_user(conn, "reconadmin", "admin")

    resp = auth_client.post(
        "/api/reconciliations/submit",
        json=_reconciliation_payload(staff_name="Imposter"),
        headers=_auth_headers(token),
    )
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        session = conn.execute(
            "SELECT staff_name FROM reconciliation_sessions WHERE id = ?",
            (session_id,),
        ).fetchone()
    assert session["staff_name"] == "reconadmin"


def test_reconciliation_submit_staff_role_uses_jwt_username(auth_client):
    """DG-029 Phase 5.6 follow-up Item 3 (Sinh-approved 2026-07-14):
    STAFF role may now submit reconciliations (admin gate removed). The
    JWT-derived actor (AC14/FR17) still applies — staff_name = JWT sub."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)
        token = _seed_user(conn, "reconstaff", "staff")

    resp = auth_client.post(
        "/api/reconciliations/submit",
        json=_reconciliation_payload(staff_name="Imposter"),
        headers=_auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    session_id = resp.json()["id"]

    with get_db() as conn:
        session = conn.execute(
            "SELECT staff_name FROM reconciliation_sessions WHERE id = ?",
            (session_id,),
        ).fetchone()
    assert session["staff_name"] == "reconstaff"


def test_reconciliation_submit_grace_period_falls_back_to_staff_name(anon_client):
    """NFR6: AUTH_REQUIRED=false + no token → client-provided staff_name is used."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    resp = anon_client.post(
        "/api/reconciliations/submit",
        json=_reconciliation_payload(staff_name="Tân"),
    )
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        session = conn.execute(
            "SELECT staff_name FROM reconciliation_sessions WHERE id = ?",
            (session_id,),
        ).fetchone()
    assert session["staff_name"] == "Tân"


def test_reconciliation_submit_grace_period_with_token_uses_jwt_username(anon_client):
    """Grace period + token present → JWT username wins."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)
        token = _seed_user(conn, "reconadmin2", "admin")

    resp = anon_client.post(
        "/api/reconciliations/submit",
        json=_reconciliation_payload(staff_name="Imposter"),
        headers=_auth_headers(token),
    )
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        session = conn.execute(
            "SELECT staff_name FROM reconciliation_sessions WHERE id = ?",
            (session_id,),
        ).fetchone()
    assert session["staff_name"] == "reconadmin2"