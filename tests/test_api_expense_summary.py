"""Tests for GET /api/reports/expense-summary (DG-386 Phase 3).

Covers:
- Response structure validation (all required keys present, correct types)
- Total expenses aggregation from expense journal debits (F1)
- Full parent/child category tree from expense_categories (F2 / AC4)
- Subcategory breakdown for parents that have children
- Legacy normalization: subcategory stored in category field → parent bucket
- Uncategorized expenses reported separately
- Deleted expense events excluded (F2 — match expense screen filter logic)
- Period-aware date filtering (week / month)
- Empty period returns zero total and empty categories
- Default date is today
- childrenOf mapping returned for full tree rendering
- Non-regression: period-summary and product-breakdown still work
- Invalid period / date validation (NF4 — Vietnamese error messages)
"""

import pytest

from baker.db.connection import get_db
from baker.utils.time import now_utc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _today() -> str:
    return now_utc()[:10]


def _create_expense(
    client,
    *,
    category,
    subcategory=None,
    amount=100000,
    payment_source="Tiền mặt tại quầy",
    payment_method="TM",
    summary="Test expense",
    vendor="",
    paid_by_name="",
):
    data = {
        "amount_vnd": amount,
        "category": category,
        "payment_source": payment_source,
        "payment_method": payment_method,
        "vendor": vendor,
        "note": "",
        "paid_by_name": paid_by_name,
    }
    if subcategory is not None:
        data["subcategory"] = subcategory
    resp = client.post(
        "/api/events",
        json={"summary": summary, "type": "expense", "data": data},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def _delete_expense(client, event_id):
    resp = client.delete(f"/api/events/{event_id}", params={"deleted_by": "test"})
    assert resp.status_code == 204, resp.text


def _get_summary(client, **params):
    return client.get("/api/reports/expense-summary", params=params).json()


# ---------------------------------------------------------------------------
# Response structure validation (F1, F3)
# ---------------------------------------------------------------------------


def test_expense_summary_response_structure_week(api_client):
    """F1: GET /api/reports/expense-summary?period=week returns all
    required keys with correct types."""
    resp = api_client.get(
        "/api/reports/expense-summary",
        params={"period": "week", "date": _today()},
    )
    assert resp.status_code == 200
    body = resp.json()
    for key in (
        "period",
        "startDate",
        "endDate",
        "date",
        "totalExpenses",
        "categories",
        "uncategorized",
        "childrenOf",
    ):
        assert key in body, f"Missing key: {key}"
    assert body["period"] == "week"
    assert body["date"] == _today()
    assert isinstance(body["totalExpenses"], (int, float))
    assert isinstance(body["categories"], list)
    assert isinstance(body["uncategorized"], (int, float))
    assert isinstance(body["childrenOf"], dict)


def test_expense_summary_default_date_is_today(api_client):
    """When no date param is passed, the API defaults to today's date."""
    resp = api_client.get(
        "/api/reports/expense-summary", params={"period": "week"}
    )
    assert resp.status_code == 200
    assert resp.json()["date"] == _today()


# ---------------------------------------------------------------------------
# Empty period (F1)
# ---------------------------------------------------------------------------


def test_expense_summary_empty_period(api_client):
    """No expenses → zero total, empty categories list, zero uncategorized."""
    body = _get_summary(api_client, period="week", date=_today())
    assert body["totalExpenses"] == 0
    assert body["categories"] == []
    assert body["uncategorized"] == 0
    # childrenOf is still populated from expense_categories seed
    assert "Nguyên liệu" in body["childrenOf"]
    assert "Trứng" in body["childrenOf"]["Nguyên liệu"]


# ---------------------------------------------------------------------------
# Total expenses aggregation (F1)
# ---------------------------------------------------------------------------


def test_expense_summary_total_aggregates_multiple_expenses(api_client):
    """F1: two expenses in the same week → totalExpenses = sum of both."""
    _create_expense(api_client, category="Vận chuyển", amount=50000, summary="Ship 1")
    _create_expense(api_client, category="Điện/nước", amount=80000, summary="Điện")

    body = _get_summary(api_client, period="week", date=_today())
    assert body["totalExpenses"] == pytest.approx(130000.0)


def test_expense_summary_category_amounts_sum_to_total(api_client):
    """F1: sum of category amounts + uncategorized == totalExpenses."""
    _create_expense(
        api_client,
        category="Nguyên liệu",
        subcategory="Trứng",
        amount=40000,
    )
    _create_expense(api_client, category="Vận chuyển", amount=60000)

    body = _get_summary(api_client, period="week", date=_today())
    cat_sum = sum(c["amount"] for c in body["categories"])
    assert cat_sum + body["uncategorized"] == pytest.approx(body["totalExpenses"])


# ---------------------------------------------------------------------------
# Full parent/child category tree (F2 / AC4)
# ---------------------------------------------------------------------------


def test_expense_summary_subcategory_breakdown(api_client):
    """F2/AC4: expense with category=Nguyên liệu, subcategory=Trứng →
    appears under the Nguyên liệu parent with the Trứng subcategory line."""
    _create_expense(
        api_client,
        category="Nguyên liệu",
        subcategory="Trứng",
        amount=30000,
        summary="Mua trứng",
    )

    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["categories"]}
    assert "Nguyên liệu" in by_name
    nl = by_name["Nguyên liệu"]
    assert nl["amount"] == pytest.approx(30000.0)
    subs = {s["name"]: s for s in nl["subcategories"]}
    assert "Trứng" in subs
    assert subs["Trứng"]["amount"] == pytest.approx(30000.0)


def test_expense_summary_parent_total_includes_subcategories(api_client):
    """F2: parent total includes all subcategory amounts."""
    _create_expense(
        api_client,
        category="Nguyên liệu",
        subcategory="Trứng",
        amount=20000,
    )
    _create_expense(
        api_client,
        category="Nguyên liệu",
        subcategory="Kem",
        amount=15000,
    )

    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["categories"]}
    nl = by_name["Nguyên liệu"]
    assert nl["amount"] == pytest.approx(35000.0)
    subs = {s["name"]: s for s in nl["subcategories"]}
    assert subs["Trứng"]["amount"] == pytest.approx(20000.0)
    assert subs["Kem"]["amount"] == pytest.approx(15000.0)


def test_expense_summary_parent_without_subcategory_children(api_client):
    """F2: a parent category with no children (e.g. Vận chuyển) has an
    empty subcategories list but still reports its amount."""
    _create_expense(api_client, category="Vận chuyển", amount=45000)

    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["categories"]}
    assert "Vận chuyển" in by_name
    vc = by_name["Vận chuyển"]
    assert vc["amount"] == pytest.approx(45000.0)
    assert vc["subcategories"] == []


def test_expense_summary_children_of_returned_for_full_tree(api_client):
    """F2: childrenOf maps parent → list of child names from
    expense_categories, enabling the client to render the full tree even
    when a subcategory had zero expenses."""
    body = _get_summary(api_client, period="week", date=_today())
    children_of = body["childrenOf"]
    # Known seed parents with children
    assert "Nguyên liệu" in children_of
    assert "Trứng" in children_of["Nguyên liệu"]
    assert "Kem" in children_of["Nguyên liệu"]
    assert "Bột" in children_of["Nguyên liệu"]
    assert "Bao bì" in children_of
    assert "Hộp & đế" in children_of["Bao bì"]
    # Parents without children are not in childrenOf
    assert "Vận chuyển" not in children_of


# ---------------------------------------------------------------------------
# Legacy normalization: subcategory stored in category field (F2)
# ---------------------------------------------------------------------------


def test_expense_summary_legacy_subcategory_in_category_normalized(api_client):
    """F2: an expense whose ``category`` field holds a subcategory name
    (e.g. 'Trứng') is normalized back to its parent ('Nguyên liệu')."""
    _create_expense(api_client, category="Trứng", amount=25000, summary="Legacy trứng")

    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["categories"]}
    # Should land under Nguyên liệu, not under a top-level "Trứng" category
    assert "Nguyên liệu" in by_name
    assert by_name["Nguyên liệu"]["amount"] == pytest.approx(25000.0)
    assert "Trứng" not in by_name
    # The Trứng subcategory line should reflect the amount
    subs = {s["name"]: s for s in by_name["Nguyên liệu"]["subcategories"]}
    assert subs["Trứng"]["amount"] == pytest.approx(25000.0)


# ---------------------------------------------------------------------------
# Uncategorized expenses (F2)
# ---------------------------------------------------------------------------


def test_expense_summary_uncategorized_when_category_missing(api_client):
    """F2: an expense whose event data has no resolvable category is
    reported under ``uncategorized``."""
    # Create a valid expense first to get a journal entry, then corrupt
    # the event data to remove the category so it falls into uncategorized.
    exp = _create_expense(api_client, category="Vận chuyển", amount=70000)
    eid = int(exp["id"])
    with get_db() as conn:
        import json as _json

        row = conn.execute("SELECT data FROM events WHERE id = ?", (eid,)).fetchone()
        data = _json.loads(row["data"])
        data.pop("category", None)
        conn.execute(
            "UPDATE events SET data = ? WHERE id = ?",
            (_json.dumps(data), eid),
        )

    body = _get_summary(api_client, period="week", date=_today())
    assert body["uncategorized"] == pytest.approx(70000.0)
    # No categorized entry for Vận chuyển
    by_name = {c["name"]: c for c in body["categories"]}
    assert "Vận chuyển" not in by_name


# ---------------------------------------------------------------------------
# Deleted expense events excluded (F2 — match expense screen filter logic)
# ---------------------------------------------------------------------------


def test_expense_summary_excludes_deleted_expenses(api_client):
    """F2: a soft-deleted expense event does not contribute to the
    summary (its journal entry is reversed on delete)."""
    exp = _create_expense(api_client, category="Vận chuyển", amount=50000)
    eid = int(exp["id"])
    _delete_expense(api_client, eid)

    body = _get_summary(api_client, period="week", date=_today())
    assert body["totalExpenses"] == 0
    assert body["categories"] == []


def test_expense_summary_excludes_locked_deleted_expense(api_client):
    """M1 (DG-386 cycle 5): a soft-deleted expense whose journal entry is
    locked (so delete reverses it instead of cascade-deleting) must still
    be excluded from ``totalExpenses``. The original debit line lingers
    after reversal, so the SQL must join ``events`` and filter
    ``deleted_at`` to drop both the original and the reversal's debit."""
    from baker.db.connection import get_db

    exp = _create_expense(api_client, category="Vận chuyển", amount=60000)
    eid = int(exp["id"])

    # Lock the expense's journal entry so the delete path takes the
    # reverse-entry branch instead of cascade-delete.
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type = 'expense' AND source_id = ? "
            "ORDER BY id DESC LIMIT 1",
            (eid,),
        ).fetchone()
        assert row is not None, "expense journal entry not found"
        entry_id = int(row["id"])
        conn.execute(
            "UPDATE journal_entries SET locked_at = ? WHERE id = ?",
            ("2026-08-13T00:00:00Z", entry_id),
        )

    _delete_expense(api_client, eid)

    body = _get_summary(api_client, period="week", date=_today())
    assert body["totalExpenses"] == 0
    assert body["categories"] == []
    assert body["uncategorized"] == 0


# ---------------------------------------------------------------------------
# Period-aware date filtering (F1)
# ---------------------------------------------------------------------------


def test_expense_summary_period_aware_excludes_other_weeks(api_client):
    """F1: expenses recognized in the current week do not appear in a
    far-future week's summary."""
    _create_expense(api_client, category="Vận chuyển", amount=50000)

    body = _get_summary(api_client, period="week", date="2099-06-15")
    assert body["totalExpenses"] == 0
    assert body["categories"] == []


def test_expense_summary_month_period_aggregates_full_month(api_client):
    """F1: month period aggregates expenses across the full month."""
    _create_expense(api_client, category="Điện/nước", amount=120000)

    body = _get_summary(api_client, period="month", date=_today())
    assert body["period"] == "month"
    assert body["totalExpenses"] == pytest.approx(120000.0)
    by_name = {c["name"]: c for c in body["categories"]}
    assert by_name["Điện/nước"]["amount"] == pytest.approx(120000.0)


# ---------------------------------------------------------------------------
# Debt expense (payment_method = 'Nợ') — debit side still counted (F1)
# ---------------------------------------------------------------------------


def test_expense_summary_includes_debt_expenses(api_client):
    """F1: a debt expense (payment_method='Nợ') still debits the expense
    account and should be included in the summary total."""
    _create_expense(
        api_client,
        category="Nguyên liệu",
        subcategory="Bột",
        amount=90000,
        payment_method="Nợ",
        vendor="Nhà cung cấp A",
    )

    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["categories"]}
    assert "Nguyên liệu" in by_name
    assert by_name["Nguyên liệu"]["amount"] == pytest.approx(90000.0)


# ---------------------------------------------------------------------------
# Multiple parent categories sorted by name (F2)
# ---------------------------------------------------------------------------


def test_expense_summary_categories_sorted_by_name(api_client):
    """F2: categories are returned sorted by parent category name."""
    _create_expense(api_client, category="Vận chuyển", amount=10000)
    _create_expense(api_client, category="Nguyên liệu", amount=20000)
    _create_expense(api_client, category="Điện/nước", amount=30000)

    body = _get_summary(api_client, period="week", date=_today())
    names = [c["name"] for c in body["categories"]]
    assert names == sorted(names)


# ---------------------------------------------------------------------------
# Validation (F1, NF4 — Vietnamese error messages)
# ---------------------------------------------------------------------------


def test_expense_summary_invalid_period_returns_422(api_client):
    """F1: an invalid period value is rejected by the pattern validator."""
    resp = api_client.get(
        "/api/reports/expense-summary",
        params={"period": "year", "date": _today()},
    )
    assert resp.status_code == 422


def test_expense_summary_invalid_date_format_returns_422(api_client):
    """NF4: a malformed date is rejected with a 422."""
    resp = api_client.get(
        "/api/reports/expense-summary",
        params={"period": "week", "date": "2026/08/12"},
    )
    assert resp.status_code == 422


def test_expense_summary_missing_period_returns_422(api_client):
    """F1: period is required — omitting it returns 422."""
    resp = api_client.get(
        "/api/reports/expense-summary",
        params={"date": _today()},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Non-regression — period-summary and product-breakdown still work
# ---------------------------------------------------------------------------


def test_expense_summary_does_not_break_period_summary(api_client):
    """Adding the expense-summary endpoint does not affect period-summary."""
    _create_expense(api_client, category="Vận chuyển", amount=50000)
    body = api_client.get(
        "/api/reports/period-summary", params={"period": "week", "date": _today()}
    ).json()
    assert body["period"] == "week"


def test_expense_summary_does_not_break_product_breakdown(api_client):
    """Adding the expense-summary endpoint does not affect product-breakdown."""
    body = api_client.get(
        "/api/reports/product-breakdown", params={"period": "week", "date": _today()}
    ).json()
    assert body["period"] == "week"