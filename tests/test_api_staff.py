"""Tests for staff list API role filter (DG-304 Phase 1 / FR1 / NFR4 / AC4)."""

from baker.db.connection import get_db


def _seed_staff(conn, name, role, active=1):
    conn.execute(
        "INSERT INTO staff (name, role, active) VALUES (?, ?, ?)",
        (name, role, active),
    )
    conn.commit()


def test_list_staff_role_filter_returns_only_matching(api_client):
    with get_db() as conn:
        _seed_staff(conn, "Người Giao A", "giao-hang")
        _seed_staff(conn, "Người Giao B", "giao-hang")
        _seed_staff(conn, "Thợ Nướng", "tho-nuong")
        _seed_staff(conn, "Thu Ngân", "thu-ngan")

    resp = api_client.get("/api/staff?role=giao-hang")
    assert resp.status_code == 200
    rows = resp.json()
    assert {r["name"] for r in rows} == {"Người Giao A", "Người Giao B"}
    assert all(r["role"] == "giao-hang" for r in rows)


def test_list_staff_role_filter_excludes_other_roles(api_client):
    """AC4: staff with other roles are excluded when role=giao-hang."""
    with get_db() as conn:
        _seed_staff(conn, "Giao Hàng 1", "giao-hang")
        _seed_staff(conn, "Quản Lý", "quan-ly")

    resp = api_client.get("/api/staff?role=giao-hang")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 1
    assert rows[0]["name"] == "Giao Hàng 1"
    assert rows[0]["role"] == "giao-hang"


def test_list_staff_role_filter_excludes_inactive(api_client):
    """Active-only filter still applies alongside role filter."""
    with get_db() as conn:
        _seed_staff(conn, "Giao Active", "giao-hang", active=1)
        _seed_staff(conn, "Giao Inactive", "giao-hang", active=0)

    resp = api_client.get("/api/staff?role=giao-hang")
    assert resp.status_code == 200
    rows = resp.json()
    assert {r["name"] for r in rows} == {"Giao Active"}


def test_list_staff_role_filter_empty_when_no_match(api_client):
    with get_db() as conn:
        _seed_staff(conn, "Thợ Nướng", "tho-nuong")

    resp = api_client.get("/api/staff?role=giao-hang")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_staff_no_role_returns_all_active(api_client):
    """Without role param, behavior is unchanged — all active staff returned."""
    with get_db() as conn:
        _seed_staff(conn, "Giao NoRole", "giao-hang")
        _seed_staff(conn, "Nướng NoRole", "tho-nuong")

    resp = api_client.get("/api/staff")
    assert resp.status_code == 200
    rows = resp.json()
    names = {r["name"] for r in rows}
    # Seeded staff are included alongside any schema-seeded defaults.
    assert {"Giao NoRole", "Nướng NoRole"}.issubset(names)


def test_list_staff_role_filter_uses_parameterized_query(api_client):
    """NFR4: ?role= value with SQL-special chars is treated as a literal."""
    with get_db() as conn:
        _seed_staff(conn, "Giao", "giao-hang")
        _seed_staff(conn, "Sneaky", "giao-hang' OR '1'='1")

    resp = api_client.get("/api/staff", params={"role": "giao-hang' OR '1'='1"})
    assert resp.status_code == 200
    rows = resp.json()
    # Only the staff whose role literally matches the injection string is returned;
    # the giao-hang staff must NOT leak through the OR.
    assert len(rows) == 1
    assert rows[0]["name"] == "Sneaky"