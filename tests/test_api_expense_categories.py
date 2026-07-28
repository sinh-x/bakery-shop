"""Tests for DG-302 Phase 2: API — expense categories endpoint + subcategory filter.

Verifies:
- ``GET /api/expense-categories`` returns the parent/child tree (FR5) with
  the expected shape and seed data (8 parents, 7 subcategories under
  Nguyên liệu/Bao bì).
- ``GET /api/events?expense_subcategory=Trứng`` filters expenses by the
  ``subcategory`` field stored in the event data JSON (FR2 / AC2).
- Expenses without a subcategory are excluded when a subcategory filter is
  applied (FR6 — backward compat: a subcategory filter is explicit, so
  old expenses do not match).
- A subcategory filter combined with a category filter works together.
"""

import pytest

pytestmark = pytest.mark.critical


def _create_expense(client, *, summary, category, subcategory=None, payment_method="Tiền mặt",
                    payment_source="Shop tiền mặt", vendor="NCC", note="ghi chú",
                    staff_name="Lan", paid_by_name="Phượng", amount_vnd=50000):
    data = {
        "amount_vnd": amount_vnd,
        "category": category,
        "payment_method": payment_method,
        "payment_source": payment_source,
        "vendor": vendor,
        "note": note,
        "staff_name": staff_name,
        "paid_by_name": paid_by_name,
    }
    if subcategory is not None:
        data["subcategory"] = subcategory
    return client.post(
        "/api/events",
        json={"summary": summary, "type": "expense", "data": data},
    )


# ---------------------------------------------------------------------------
# GET /api/expense-categories (FR5)
# ---------------------------------------------------------------------------


def test_expense_categories_endpoint_returns_tree(api_client):
    resp = api_client.get("/api/expense-categories")
    assert resp.status_code == 200
    tree = resp.json()
    parents = [n for n in tree if n["parent_id"] is None]
    assert len(parents) == 8
    # Each parent has a children list (possibly empty for parents without
    # subcategories).
    for parent in parents:
        assert isinstance(parent["children"], list)
        assert parent["account_code"]
    nguyen_lieu = next(p for p in parents if p["name"] == "Nguyên liệu")
    bao_bi = next(p for p in parents if p["name"] == "Bao bì")
    assert {c["name"] for c in nguyen_lieu["children"]} == {
        "Trứng", "Kem", "Bột", "Phụ gia khác",
    }
    assert {c["name"] for c in bao_bi["children"]} == {
        "Hộp & đế", "Phụ kiện", "Bọc nilon",
    }


def test_expense_categories_endpoint_subcategory_account_codes(api_client):
    resp = api_client.get("/api/expense-categories")
    tree = resp.json()
    by_name = {n["name"]: n for n in tree}
    expected = {
        "Trứng": "5110", "Kem": "5120", "Bột": "5130", "Phụ gia khác": "5140",
        "Hộp & đế": "5210", "Phụ kiện": "5220", "Bọc nilon": "5230",
    }
    for sub_name, code in expected.items():
        parent_name = "Nguyên liệu" if code.startswith("51") else "Bao bì"
        parent = by_name[parent_name]
        child = next(c for c in parent["children"] if c["name"] == sub_name)
        assert child["account_code"] == code, sub_name
        assert child["parent_id"] == parent["id"], sub_name


def test_expense_categories_endpoint_parents_without_children(api_client):
    """Parents other than Nguyên liệu/Bao bì have empty children lists."""
    resp = api_client.get("/api/expense-categories")
    tree = resp.json()
    parents = [n for n in tree if n["parent_id"] is None]
    for parent in parents:
        if parent["name"] in ("Nguyên liệu", "Bao bì"):
            assert len(parent["children"]) == 4 if parent["name"] == "Nguyên liệu" else 3
        else:
            assert parent["children"] == [], parent["name"]


def test_expense_categories_endpoint_total_subcategory_count(api_client):
    resp = api_client.get("/api/expense-categories")
    tree = resp.json()
    total_children = sum(len(p["children"]) for p in tree if p["parent_id"] is None)
    assert total_children == 7


# ---------------------------------------------------------------------------
# GET /api/events?expense_subcategory=... (FR2 / AC2)
# ---------------------------------------------------------------------------


def test_list_events_filter_by_subcategory(api_client):
    _create_expense(api_client, summary="Mua trứng", category="Nguyên liệu", subcategory="Trứng")
    _create_expense(api_client, summary="Mua kem", category="Nguyên liệu", subcategory="Kem")
    _create_expense(api_client, summary="Mua bột", category="Nguyên liệu", subcategory="Bột")

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_subcategory": "Trứng",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["subcategory"] == "Trứng"


def test_list_events_filter_by_subcategory_case_insensitive(api_client):
    _create_expense(api_client, summary="Mua trứng", category="Nguyên liệu", subcategory="Trứng")

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_subcategory": "trứng",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["subcategory"] == "Trứng"


def test_list_events_subcategory_filter_excludes_expenses_without_subcategory(api_client):
    """FR6: a subcategory filter is explicit — expenses without subcategory
    do not match (their COALESCE'd value is '')."""
    _create_expense(api_client, summary="Mua trứng", category="Nguyên liệu", subcategory="Trứng")
    # Old expense without subcategory field
    _create_expense(api_client, summary="Mua đường cũ", category="Nguyên liệu")

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_subcategory": "Trứng",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["subcategory"] == "Trứng"


def test_list_events_subcategory_filter_combines_with_category(api_client):
    _create_expense(api_client, summary="Trứng NL", category="Nguyên liệu", subcategory="Trứng")
    _create_expense(api_client, summary="Hộp BB", category="Bao bì", subcategory="Hộp & đế")

    # category=Nguyên liệu + subcategory=Trứng → only the first
    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_category": "Nguyên liệu",
        "expense_subcategory": "Trứng",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["summary"] == "Trứng NL"


def test_list_events_no_subcategory_filter_returns_all(api_client):
    """When no subcategory filter is supplied, all expenses are returned (FR6)."""
    _create_expense(api_client, summary="Có sub", category="Nguyên liệu", subcategory="Trứng")
    _create_expense(api_client, summary="Không sub", category="Nguyên liệu")

    resp = api_client.get("/api/events", params={"type": "expense"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 2


def test_list_events_subcategory_filter_no_match_returns_empty(api_client):
    _create_expense(api_client, summary="Mua trứng", category="Nguyên liệu", subcategory="Trứng")

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_subcategory": "Kem",
    })
    assert resp.status_code == 200
    assert resp.json() == []