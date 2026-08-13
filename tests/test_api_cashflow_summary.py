"""Tests for GET /api/reports/cashflow-summary (DG-386 Phase 4).

Covers:
- Response structure validation (all required keys present, correct types)
- Operating inflow (payment_transaction debits to cash accounts)
- Operating outflow (expense + expense_settlement + order_shipping_release
  credits to cash accounts)
- Net operating cash flow = inflow - outflow
- Drawer-independence: no active cash drawer required (F2)
- Supplier category breakdown (expense + expense_settlement only;
  order_shipping_release excluded from breakdown but in supplier total)
- Subcategory breakdown for parents that have children
- Legacy normalization: subcategory stored in category field -> parent bucket
- Uncategorized supplier outflow reported separately
- Deleted expense events excluded
- Period-aware date filtering (week / month)
- Empty period returns zeros
- Default date is today
- childrenOf mapping returned for full tree rendering
- Cross-validation against ``baker report cashflow`` operating activities
- Invalid period / date validation (NF4 - Vietnamese error messages)
- Non-regression: period-summary, product-breakdown, expense-summary still work
"""

import json

import pytest

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.utils.time import now_utc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _today() -> str:
    return now_utc()[:10]


def _account_id(conn, code: str) -> int:
    return int(
        conn.execute(
            "SELECT id FROM accounts WHERE code = ?", (code,)
        ).fetchone()[0]
    )


def _insert_entry(
    conn,
    *,
    debit_account_id,
    credit_account_id,
    amount,
    source_type="manual",
    source_id=None,
    description="Test entry",
    created_at=None,
    transaction_date=None,
) -> int:
    """Insert a balanced two-line journal entry."""
    td = transaction_date or created_at
    if created_at or td:
        cur = conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, created_at, transaction_date) "
            "VALUES (?, ?, ?, ?, ?)",
            (description, source_type, source_id, created_at, td),
        )
    else:
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            (description, source_type, source_id),
        )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines "
        "(journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, debit_account_id, amount, 0.0, "d"),
    )
    conn.execute(
        "INSERT INTO journal_lines "
        "(journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, credit_account_id, 0.0, amount, "c"),
    )
    return entry_id


def _insert_expense_event(
    conn,
    *,
    category,
    amount=10000,
    created_at=None,
    subcategory=None,
    settlements=None,
) -> int:
    """Insert an expense event with a category and return its id."""
    payload = {
        "amount_vnd": amount,
        "category": category,
        "payment_source": "Shop tiền mặt",
    }
    if subcategory is not None:
        payload["subcategory"] = subcategory
    if settlements is not None:
        payload["settlements"] = settlements
    data = json.dumps(payload)
    if created_at:
        cur = conn.execute(
            "INSERT INTO events (type, summary, data, timestamp) "
            "VALUES (?, ?, ?, ?)",
            ("expense", f"Expense: {category}", data, created_at),
        )
    else:
        cur = conn.execute(
            "INSERT INTO events (type, summary, data) VALUES (?, ?, ?)",
            ("expense", f"Expense: {category}", data),
        )
    return int(cur.lastrowid)


def _seed_operating_dataset(conn, ts=None):
    """Seed a known dataset exercising operating inflow and outflow.

    All entries dated ``ts`` (defaults to today) unless noted. Amounts
    chosen so each section has a distinct, easily-asserted total.

    Layout (cash side on account 1100 unless noted):
      - Customer payment (operating inflow):
          DR 1100 200000 / CR 2100 200000
          source_type='payment_transaction'
      - Customer refund (operating outflow, customer section):
          DR 2100 50000 / CR 1210 50000
          source_type='payment_transaction'
      - Expense paid in cash (operating outflow, supplier section):
          DR 5300 (Vận chuyển) 30000 / CR 1100 30000
          source_type='expense'
      - Expense settlement (operating outflow, supplier section):
          DR 2500 (AP) 40000 / CR 1100 40000
          source_type='expense_settlement'
      - Shipping release (operating outflow, supplier section):
          DR 2200 25000 / CR 1100 25000
          source_type='order_shipping_release'

    Expected:
      - operatingInflow  = 200000 (customer debit to 1100)
      - operatingOutflow = 50000 + 30000 + 40000 + 25000 = 145000
      - netOperatingCashFlow = 200000 - 145000 = 55000
      - customers.inflow = 200000, customers.outflow = 50000
      - suppliers.outflow = 30000 + 40000 + 25000 = 95000
      - supplierCategories total = 30000 (Vận chuyển) + 40000 (Bao bì)
        = 70000 (shipping release excluded from breakdown)
      - uncategorizedSupplier = 0
    """
    if ts is None:
        ts = f"{_today()}T10:00:00Z"
    cash = _account_id(conn, "1100")
    phuong = _account_id(conn, "1210")
    deposits = _account_id(conn, "2100")
    transport = _account_id(conn, "5300")
    ap = _account_id(conn, "2500")
    shipping = _account_id(conn, "2200")

    # Customer payment (inflow).
    _insert_entry(
        conn, debit_account_id=cash, credit_account_id=deposits,
        amount=200000.0, source_type="payment_transaction", source_id=1,
        description="Customer deposit", created_at=ts, transaction_date=ts,
    )
    # Customer refund (outflow, customer section).
    _insert_entry(
        conn, debit_account_id=deposits, credit_account_id=phuong,
        amount=50000.0, source_type="payment_transaction", source_id=2,
        description="Customer refund", created_at=ts, transaction_date=ts,
    )
    # Expense paid in cash (supplier section, Vận chuyển).
    eid_vc = _insert_expense_event(
        conn, category="Vận chuyển", amount=30000, created_at=ts,
    )
    _insert_entry(
        conn, debit_account_id=transport, credit_account_id=cash,
        amount=30000.0, source_type="expense", source_id=eid_vc,
        description="Expense: Vận chuyển", created_at=ts, transaction_date=ts,
    )
    # Expense settlement (supplier section, Bao bì / Hộp & đế).
    settlement_id = 1
    eid_bao = _insert_expense_event(
        conn, category="Bao bì", amount=100000, subcategory="Hộp & đế",
        settlements=[{
            "id": settlement_id, "amount": 40000,
            "payment_method": "cash", "payment_source": "Shop tiền mặt",
            "note": "partial", "timestamp": ts,
        }],
        created_at=ts,
    )
    _insert_entry(
        conn, debit_account_id=ap, credit_account_id=cash,
        amount=40000.0, source_type="expense_settlement",
        source_id=settlement_id,
        description=f"Settlement of expense event {eid_bao}",
        created_at=ts, transaction_date=ts,
    )
    # Shipping release (supplier section, no category data).
    _insert_entry(
        conn, debit_account_id=shipping, credit_account_id=cash,
        amount=25000.0, source_type="order_shipping_release", source_id=None,
        description="Shipping release", created_at=ts, transaction_date=ts,
    )


def _get_summary(client, **params):
    return client.get("/api/reports/cashflow-summary", params=params).json()


# ---------------------------------------------------------------------------
# Response structure validation (F1, F3)
# ---------------------------------------------------------------------------


def test_cashflow_summary_response_structure_week(api_client):
    """F1: GET /api/reports/cashflow-summary?period=week returns all
    required keys with correct types."""
    resp = api_client.get(
        "/api/reports/cashflow-summary",
        params={"period": "week", "date": _today()},
    )
    assert resp.status_code == 200
    body = resp.json()
    for key in (
        "period",
        "startDate",
        "endDate",
        "date",
        "operatingInflow",
        "operatingOutflow",
        "netOperatingCashFlow",
        "customers",
        "suppliers",
        "supplierCategories",
        "uncategorizedSupplier",
        "childrenOf",
    ):
        assert key in body, f"Missing key: {key}"
    assert body["period"] == "week"
    assert body["date"] == _today()
    assert isinstance(body["operatingInflow"], (int, float))
    assert isinstance(body["operatingOutflow"], (int, float))
    assert isinstance(body["netOperatingCashFlow"], (int, float))
    assert isinstance(body["customers"], dict)
    assert isinstance(body["suppliers"], dict)
    assert isinstance(body["supplierCategories"], list)
    assert isinstance(body["uncategorizedSupplier"], (int, float))
    assert isinstance(body["childrenOf"], dict)
    # Section sub-structure
    for section in (body["customers"], body["suppliers"]):
        assert "inflow" in section
        assert "outflow" in section
        assert "perAccount" in section
        assert isinstance(section["perAccount"], list)


def test_cashflow_summary_default_date_is_today(api_client):
    """When no date param is passed, the API defaults to today's date."""
    resp = api_client.get(
        "/api/reports/cashflow-summary", params={"period": "week"}
    )
    assert resp.status_code == 200
    assert resp.json()["date"] == _today()


# ---------------------------------------------------------------------------
# Empty period (F1)
# ---------------------------------------------------------------------------


def test_cashflow_summary_empty_period(api_client):
    """No journal activity -> zero totals, empty lists."""
    body = _get_summary(api_client, period="week", date=_today())
    assert body["operatingInflow"] == 0
    assert body["operatingOutflow"] == 0
    assert body["netOperatingCashFlow"] == 0
    assert body["customers"]["inflow"] == 0
    assert body["customers"]["outflow"] == 0
    assert body["customers"]["perAccount"] == []
    assert body["suppliers"]["inflow"] == 0
    assert body["suppliers"]["outflow"] == 0
    assert body["suppliers"]["perAccount"] == []
    assert body["supplierCategories"] == []
    assert body["uncategorizedSupplier"] == 0
    # childrenOf is still populated from expense_categories seed
    assert "Nguyên liệu" in body["childrenOf"]
    assert "Trứng" in body["childrenOf"]["Nguyên liệu"]


# ---------------------------------------------------------------------------
# Operating inflow / outflow (F1, F2)
# ---------------------------------------------------------------------------


def test_cashflow_summary_operating_inflow_from_payment_transactions(api_client):
    """F1: payment_transaction debits to cash accounts are operating inflow."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date=_today())
    assert body["operatingInflow"] == pytest.approx(200000.0)
    assert body["customers"]["inflow"] == pytest.approx(200000.0)


def test_cashflow_summary_operating_outflow_includes_all_source_types(api_client):
    """F1: outflow aggregates payment_transaction refunds + expense +
    expense_settlement + order_shipping_release."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date=_today())
    # 50000 refund + 30000 expense + 40000 settlement + 25000 shipping
    assert body["operatingOutflow"] == pytest.approx(145000.0)
    # Customer section outflow = refund only
    assert body["customers"]["outflow"] == pytest.approx(50000.0)
    # Supplier section outflow = expense + settlement + shipping
    assert body["suppliers"]["outflow"] == pytest.approx(95000.0)


def test_cashflow_summary_net_operating_cash_flow(api_client):
    """F1: netOperatingCashFlow = operatingInflow - operatingOutflow."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date=_today())
    assert body["netOperatingCashFlow"] == pytest.approx(200000.0 - 145000.0)


def test_cashflow_summary_per_account_breakdown(api_client):
    """F1: perAccount lists each cash account with its inflow/outflow."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date=_today())
    cust_by_code = {a["code"]: a for a in body["customers"]["perAccount"]}
    # 1100 receives the 200000 customer debit
    assert "1100" in cust_by_code
    assert cust_by_code["1100"]["inflow"] == pytest.approx(200000.0)
    # 1210 receives the 50000 refund credit
    assert "1210" in cust_by_code
    assert cust_by_code["1210"]["outflow"] == pytest.approx(50000.0)
    sup_by_code = {a["code"]: a for a in body["suppliers"]["perAccount"]}
    # 1100 receives expense+settlement+shipping credits = 30000+40000+25000
    assert "1100" in sup_by_code
    assert sup_by_code["1100"]["outflow"] == pytest.approx(95000.0)


# ---------------------------------------------------------------------------
# Drawer-independence (F2)
# ---------------------------------------------------------------------------


def test_cashflow_summary_does_not_require_active_cash_drawer(api_client):
    """F2: the endpoint returns data even when no cash drawer is open.
    The dataset is seeded with journal entries directly (no drawer opened),
    and the endpoint still returns the operating totals."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    # No /api/cash-drawer/open call — drawer is closed.
    body = _get_summary(api_client, period="week", date=_today())
    assert body["operatingInflow"] == pytest.approx(200000.0)
    assert body["operatingOutflow"] == pytest.approx(145000.0)


# ---------------------------------------------------------------------------
# Supplier category breakdown (F1 / AC5)
# ---------------------------------------------------------------------------


def test_cashflow_summary_supplier_categories_exclude_shipping_release(api_client):
    """AC5: order_shipping_release is excluded from the category breakdown
    (it carries no category data) but is included in suppliers.outflow."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date=_today())
    # Supplier categories total = 30000 (Vận chuyển) + 40000 (Bao bì) = 70000
    cat_sum = sum(c["amount"] for c in body["supplierCategories"])
    assert cat_sum + body["uncategorizedSupplier"] == pytest.approx(70000.0)
    # suppliers.outflow includes the 25000 shipping release -> 95000
    assert body["suppliers"]["outflow"] == pytest.approx(95000.0)


def test_cashflow_summary_supplier_category_with_subcategory(api_client):
    """AC5: expense_settlement with category Bao bì / subcategory
    Hộp & đế appears under the Bao bì parent with the subcategory line."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["supplierCategories"]}
    assert "Bao bì" in by_name
    assert by_name["Bao bì"]["amount"] == pytest.approx(40000.0)
    subs = {s["name"]: s for s in by_name["Bao bì"]["subcategories"]}
    assert "Hộp & đế" in subs
    assert subs["Hộp & đế"]["amount"] == pytest.approx(40000.0)


def test_cashflow_summary_supplier_category_without_children(api_client):
    """AC5: a parent category with no children (Vận chuyển) reports its
    amount with an empty subcategories list."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["supplierCategories"]}
    assert "Vận chuyển" in by_name
    assert by_name["Vận chuyển"]["amount"] == pytest.approx(30000.0)
    assert by_name["Vận chuyển"]["subcategories"] == []


def test_cashflow_summary_supplier_categories_sorted_by_name(api_client):
    """AC5: supplier categories are returned sorted by parent name."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date=_today())
    names = [c["name"] for c in body["supplierCategories"]]
    assert names == sorted(names)


def test_cashflow_summary_children_of_returned_for_full_tree(api_client):
    """AC5: childrenOf maps parent -> list of child names from
    expense_categories for full tree rendering."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date=_today())
    children_of = body["childrenOf"]
    assert "Nguyên liệu" in children_of
    assert "Trứng" in children_of["Nguyên liệu"]
    assert "Bao bì" in children_of
    assert "Hộp & đế" in children_of["Bao bì"]


# ---------------------------------------------------------------------------
# Legacy normalization (AC5)
# ---------------------------------------------------------------------------


def test_cashflow_summary_legacy_subcategory_in_category_normalized(api_client):
    """AC5: an expense whose category field holds a subcategory name
    (e.g. 'Trứng') is normalized back to its parent ('Nguyên liệu')."""
    with get_db() as conn:
        ensure_schema(conn)
        cash = _account_id(conn, "1100")
        eggs = _account_id(conn, "5110")
        ts = f"{_today()}T10:00:00Z"
        eid = _insert_expense_event(
            conn, category="Trứng", amount=25000, created_at=ts,
        )
        _insert_entry(
            conn, debit_account_id=eggs, credit_account_id=cash,
            amount=25000.0, source_type="expense", source_id=eid,
            description="Legacy trứng", created_at=ts, transaction_date=ts,
        )
    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["supplierCategories"]}
    assert "Nguyên liệu" in by_name
    assert by_name["Nguyên liệu"]["amount"] == pytest.approx(25000.0)
    assert "Trứng" not in by_name
    subs = {s["name"]: s for s in by_name["Nguyên liệu"]["subcategories"]}
    assert subs["Trứng"]["amount"] == pytest.approx(25000.0)


# ---------------------------------------------------------------------------
# Uncategorized supplier outflow (AC5)
# ---------------------------------------------------------------------------


def test_cashflow_summary_uncategorized_supplier_when_category_missing(api_client):
    """AC5: an expense whose event data has no resolvable category is
    reported under uncategorizedSupplier."""
    with get_db() as conn:
        ensure_schema(conn)
        cash = _account_id(conn, "1100")
        transport = _account_id(conn, "5300")
        ts = f"{_today()}T10:00:00Z"
        eid = _insert_expense_event(
            conn, category="Vận chuyển", amount=70000, created_at=ts,
        )
        _insert_entry(
            conn, debit_account_id=transport, credit_account_id=cash,
            amount=70000.0, source_type="expense", source_id=eid,
            description="Expense: Vận chuyển", created_at=ts, transaction_date=ts,
        )
        # Corrupt the event data to remove the category.
        row = conn.execute(
            "SELECT data FROM events WHERE id = ?", (eid,)
        ).fetchone()
        data = json.loads(row["data"])
        data.pop("category", None)
        conn.execute(
            "UPDATE events SET data = ? WHERE id = ?",
            (json.dumps(data), eid),
        )
    body = _get_summary(api_client, period="week", date=_today())
    assert body["uncategorizedSupplier"] == pytest.approx(70000.0)
    by_name = {c["name"]: c for c in body["supplierCategories"]}
    assert "Vận chuyển" not in by_name


# ---------------------------------------------------------------------------
# Deleted expense events excluded (AC5)
# ---------------------------------------------------------------------------


def test_cashflow_summary_excludes_deleted_expense_events(api_client):
    """AC5: a soft-deleted expense event (via the API, which reverses its
    journal entry) does not contribute to the supplier breakdown or the
    supplier outflow total."""
    with get_db() as conn:
        ensure_schema(conn)
    # Create an expense via the API so its journal entry is posted, then
    # delete it via the API so the journal entry is reversed (net zero).
    exp = _create_expense_via_api(api_client, category="Vận chuyển", amount=50000)
    resp = api_client.delete(
        f"/api/events/{exp['id']}", params={"deleted_by": "test"}
    )
    assert resp.status_code == 204, resp.text

    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["supplierCategories"]}
    assert "Vận chuyển" not in by_name
    assert body["uncategorizedSupplier"] == 0
    # The reversed journal entry nets to zero, so the supplier outflow
    # from this deleted expense is zero.
    # (Other tests seed activity via SQL directly; this test isolates the
    # deleted-expense path, so no other activity is present.)
    assert body["suppliers"]["outflow"] == pytest.approx(0.0)


def _create_expense_via_api(client, *, category, amount=100000, subcategory=None):
    """Create an expense via the events API and return the response body."""
    data = {
        "amount_vnd": amount,
        "category": category,
        "payment_source": "Tiền mặt tại quầy",
        "payment_method": "TM",
        "vendor": "",
        "note": "",
        "paid_by_name": "",
    }
    if subcategory is not None:
        data["subcategory"] = subcategory
    resp = client.post(
        "/api/events",
        json={"summary": "Test expense", "type": "expense", "data": data},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


# ---------------------------------------------------------------------------
# Fixed-asset (1600) exclusion from supplier breakdown (Mn2)
# ---------------------------------------------------------------------------


def test_cashflow_summary_supplier_categories_exclude_1600_expense(api_client):
    """Mn2 (DG-386 cycle 5): an expense/expense_settlement journal entry that
    also touches the fixed-asset account 1600 is excluded from the supplier
    category breakdown, mirroring the 1600 NOT EXISTS filter already applied
    to query_cash_period_activity (suppliers.outflow). Without this filter
    the entry would appear in supplierCategories but not in suppliers.outflow.
    """
    with get_db() as conn:
        ensure_schema(conn)
        cash = _account_id(conn, "1100")
        transport = _account_id(conn, "5300")
        fixed_asset = _account_id(conn, "1600")
        ts = f"{_today()}T10:00:00Z"
        eid = _insert_expense_event(
            conn, category="Vận chuyển", amount=30000, created_at=ts,
        )
        entry_id = _insert_entry(
            conn, debit_account_id=transport, credit_account_id=cash,
            amount=30000.0, source_type="expense", source_id=eid,
            description="Expense: Vận chuyển (cash side)", created_at=ts,
            transaction_date=ts,
        )
        # Add a 1600 debit line to the same journal entry so the entry now
        # touches the fixed-asset account. query_cash_period_activity would
        # exclude the whole entry (NOT EXISTS 1600), so suppliers.outflow
        # must not include it; supplierCategories must also exclude it.
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, fixed_asset, 0.0, 5000.0, "fixed-asset credit line"),
        )
        # Re-balance: add an offsetting debit on 1600 is not needed for the
        # filter test — the NOT EXISTS check is what matters.

    body = _get_summary(api_client, period="week", date=_today())
    by_name = {c["name"]: c for c in body["supplierCategories"]}
    assert "Vận chuyển" not in by_name
    # suppliers.outflow also excludes it (1600-touching entry), so the
    # two views stay consistent.
    assert body["suppliers"]["outflow"] == pytest.approx(0.0)


# ---------------------------------------------------------------------------
# Exclusive upper bound (Mn3) — next-period T00:00:00 not double-counted
# ---------------------------------------------------------------------------


def test_cashflow_summary_upper_bound_excludes_next_period_midnight(api_client):
    """Mn3 (DG-386 cycle 5): a journal entry timestamped exactly at the
    next period's T00:00:00 (e.g. the midnight starting the week after the
    reference date's week) is not counted by the closing period. The
    cashflow-summary API uses an exclusive upper bound so the entry is
    attributed only to the period that opens at that timestamp.
    """
    from datetime import datetime, timedelta

    ref = datetime.strptime(_today(), "%Y-%m-%d")
    # Monday of the reference week and the next Monday (exclusive end).
    monday = ref - timedelta(days=ref.weekday())
    next_monday = monday + timedelta(days=7)
    next_monday_ts = next_monday.strftime("%Y-%m-%dT00:00:00")

    with get_db() as conn:
        ensure_schema(conn)
        cash = _account_id(conn, "1100")
        deposits = _account_id(conn, "2100")
        # Customer deposit timestamped exactly at next Monday T00:00:00.
        _insert_entry(
            conn, debit_account_id=cash, credit_account_id=deposits,
            amount=200000.0, source_type="payment_transaction", source_id=999,
            description="Boundary entry", created_at=next_monday_ts,
            transaction_date=next_monday_ts,
        )

    # The closing period (reference week) must NOT include the boundary entry.
    body = _get_summary(api_client, period="week", date=_today())
    assert body["operatingInflow"] == pytest.approx(0.0)
    # The opening period (next week) DOES include it.
    body_next = _get_summary(
        api_client, period="week", date=next_monday.strftime("%Y-%m-%d"),
    )
    assert body_next["operatingInflow"] == pytest.approx(200000.0)


# ---------------------------------------------------------------------------
# Period-aware date filtering (F1)
# ---------------------------------------------------------------------------


def test_cashflow_summary_period_aware_excludes_other_weeks(api_client):
    """F1: activity in the current week does not appear in a far-future
    week's summary."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="week", date="2099-06-15")
    assert body["operatingInflow"] == 0
    assert body["operatingOutflow"] == 0
    assert body["supplierCategories"] == []


def test_cashflow_summary_month_period_aggregates_full_month(api_client):
    """F1: month period aggregates activity across the full month."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = _get_summary(api_client, period="month", date=_today())
    assert body["period"] == "month"
    assert body["operatingInflow"] == pytest.approx(200000.0)
    assert body["operatingOutflow"] == pytest.approx(145000.0)


# ---------------------------------------------------------------------------
# Cross-validation against CLI ``baker report cashflow`` (AC5)
# ---------------------------------------------------------------------------


def test_cashflow_summary_matches_cli_operating_activities(api_client):
    """AC5: the endpoint's operating totals match the CLI ``baker report
    cashflow`` operating section for the same date range.

    The CLI prints operating inflow/outflow in its "Hoạt động kinh doanh"
    section. We seed the same dataset, run both the API and the CLI, and
    assert the operating totals agree.
    """
    from click.testing import CliRunner

    from baker.commands.report import report_cmd

    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)

    body = _get_summary(api_client, period="month", date=_today())

    # Derive the month bounds the API used.
    from datetime import datetime
    import calendar as _cal

    ref = datetime.strptime(_today(), "%Y-%m-%d")
    since = ref.replace(day=1).strftime("%Y-%m-%d")
    last_day = _cal.monthrange(ref.year, ref.month)[1]
    until = ref.replace(day=last_day).strftime("%Y-%m-%d")

    runner = CliRunner()
    result = runner.invoke(
        report_cmd, ["cashflow", "--since", since, "--until", until],
    )
    assert result.exit_code == 0, result.output

    # The CLI operating section prints a "Dòng tiền thuần từ hoạt động
    # kinh doanh" row with inflow, outflow, and net columns. Parse the
    # numbers from that row.
    output = result.output
    marker = "Dòng tiền thuần từ hoạt động kinh doanh"
    assert marker in output
    line = next(ln for ln in output.splitlines() if marker in ln)
    # The line looks like: "  Dòng tiền thuần...    200000.00   145000.00   55000.00"
    parts = [p for p in line.split() if p]
    nums = [p for p in parts if _is_number(p)]
    assert len(nums) >= 3, f"Could not parse 3 numbers from CLI line: {line!r}"
    cli_inflow = float(nums[-3].replace(",", ""))
    cli_outflow = float(nums[-2].replace(",", ""))
    cli_net = float(nums[-1].replace(",", ""))

    assert cli_inflow == pytest.approx(body["operatingInflow"], rel=1e-6)
    assert cli_outflow == pytest.approx(body["operatingOutflow"], rel=1e-6)
    assert cli_net == pytest.approx(body["netOperatingCashFlow"], rel=1e-6)


def _is_number(s: str) -> bool:
    try:
        float(s.replace(",", ""))
        return True
    except ValueError:
        return False


# ---------------------------------------------------------------------------
# Validation (F1, NF4 - Vietnamese error messages)
# ---------------------------------------------------------------------------


def test_cashflow_summary_invalid_period_returns_422(api_client):
    """F1: an invalid period value is rejected by the pattern validator."""
    resp = api_client.get(
        "/api/reports/cashflow-summary",
        params={"period": "year", "date": _today()},
    )
    assert resp.status_code == 422


def test_cashflow_summary_invalid_date_format_returns_422(api_client):
    """NF4: a malformed date is rejected with a 422."""
    resp = api_client.get(
        "/api/reports/cashflow-summary",
        params={"period": "week", "date": "2026/08/12"},
    )
    assert resp.status_code == 422


def test_cashflow_summary_missing_period_returns_422(api_client):
    """F1: period is required - omitting it returns 422."""
    resp = api_client.get(
        "/api/reports/cashflow-summary",
        params={"date": _today()},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Non-regression - prior phase endpoints still work
# ---------------------------------------------------------------------------


def test_cashflow_summary_does_not_break_period_summary(api_client):
    """Adding the cashflow-summary endpoint does not affect period-summary."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_operating_dataset(conn)
    body = api_client.get(
        "/api/reports/period-summary", params={"period": "week", "date": _today()}
    ).json()
    assert body["period"] == "week"


def test_cashflow_summary_does_not_break_product_breakdown(api_client):
    """Adding the cashflow-summary endpoint does not affect product-breakdown."""
    body = api_client.get(
        "/api/reports/product-breakdown", params={"period": "week", "date": _today()}
    ).json()
    assert body["period"] == "week"


def test_cashflow_summary_does_not_break_expense_summary(api_client):
    """Adding the cashflow-summary endpoint does not affect expense-summary."""
    body = api_client.get(
        "/api/reports/expense-summary", params={"period": "week", "date": _today()}
    ).json()
    assert body["period"] == "week"