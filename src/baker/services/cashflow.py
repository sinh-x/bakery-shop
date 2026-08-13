"""Shared cash-flow query helpers and constants (DG-386 review Mn-2).

Promoted from ``baker.commands.report`` so the reporting API
(``baker.api.reports``) and the ``baker report`` CLI share a single source
of truth for operating-activity cash-flow aggregation. Behavior is
unchanged from the original ``baker.commands.report`` implementation —
only the module location and visibility (private → public) changed.
"""

import json


# Cash accounts tracked by the direct-method cashflow statement. Cash held in
# 1200 (the parent bank account, used by the expense flow and owner-capital
# transfers) is included alongside the DG-244 Phase 4 bank sub-accounts so the
# report matches the cash-flow integrity check in accounting_validation.py.
CASH_ACCOUNT_CODES = ("1100", "1101", "1102", "1200", "1210", "1220", "1290")

# Fixed-asset account seeded by DG-300 Phase 1 — investing-activity cash flows
# land on this account.
FIXED_ASSETS_CODE = "1600"

# Reconciliation tolerance (VND). Matches DEBIT_CREDIT_TOLERANCE used by the
# accounting-validation cash-flow integrity check.
CASHFLOW_RECONCILIATION_TOLERANCE = 0.01

# source_type values that represent operating-activity cash inflows on cash
# accounts. ``payment_transaction`` covers customer deposits/payments and
# refunds (refunds credit cash → outflow, but they still belong to operating).
OPERATING_INFLOW_SOURCE_TYPES = ("payment_transaction",)

# source_type values that represent operating-activity cash outflows on cash
# accounts. ``expense`` debits an expense/inventory account and credits a
# cash account; ``expense_settlement`` debits Accounts Payable (2500) and
# credits a cash account when a debt expense is paid off.
# ``order_shipping_release`` releases a held bus shipping fee back to the bus
# driver/supplier (DR 2200 / CR 1100) — crediting cash is an operating outflow,
# i.e. cash paid to suppliers/services, so it belongs with the other outflows.
OPERATING_OUTFLOW_SOURCE_TYPES = (
    "expense",
    "expense_settlement",
    "order_shipping_release",
)

# source_type values that represent financing-activity cash movements.
FINANCING_SOURCE_TYPES = ("owner_capital", "owner_draw")


def cash_account_placeholders(codes: tuple[str, ...]) -> str:
    """Return a SQL ``IN (...)`` placeholder list for the given account codes."""
    return ",".join("?" * len(codes))


def query_cash_period_activity(
    conn, since_b: str | None, until_b: str | None,
    *, exclusive_until: bool = False,
) -> dict[str, dict[str, dict[str, float]]]:
    """Aggregate period cash-account movements grouped by ``source_type``.

    Returns ``{source_type: {cash_account_code: {"inflow": float, "outflow": float}}}``.
    Only journal lines whose account is one of ``CASH_ACCOUNT_CODES`` and whose
    journal entry's ``transaction_date`` falls within ``[since_b, until_b]`` are
    summed. Entries that also touch the fixed-asset account 1600 are excluded —
    those are reported under investing activities to avoid double-counting.

    ``exclusive_until`` controls the upper-bound operator:

    - ``False`` (default, CLI behavior) — upper bound is inclusive
      (``je.transaction_date <= until_b``), matching ``baker report cashflow``
      which treats ``--until`` as end-of-day inclusive.
    - ``True`` (used by the cashflow-summary API) — upper bound is exclusive
      (``je.transaction_date < until_b``) so a journal entry timestamped
      exactly at the next period's ``T00:00:00`` is not double-counted by
      both the closing period and the opening period (Mn3, DG-386 cycle 5).
      The API passes ``end_next_day_ts`` as ``until_b``; making the bound
      exclusive keeps it consistent with the period-summary / expense-summary /
      product-breakdown endpoints which all use ``< end_next_day_ts``.
    """
    placeholders = cash_account_placeholders(CASH_ACCOUNT_CODES)
    params: list = list(CASH_ACCOUNT_CODES)
    where_clauses = [f"a.code IN ({placeholders})"]
    if since_b:
        where_clauses.append("je.transaction_date >= ?")
        params.append(since_b)
    if until_b:
        op = "<" if exclusive_until else "<="
        where_clauses.append(f"je.transaction_date {op} ?")
        params.append(until_b)
    # Exclude entries that touch the fixed-asset account — those are investing.
    where_clauses.append(
        "NOT EXISTS ("
        " SELECT 1 FROM journal_lines jl2"
        " JOIN accounts a2 ON a2.id = jl2.account_id"
        " WHERE jl2.journal_entry_id = je.id AND a2.code = ?"
        ")"
    )
    params.append(FIXED_ASSETS_CODE)
    where_sql = " AND ".join(where_clauses)

    rows = conn.execute(
        f"""
        SELECT je.source_type AS source_type,
               a.code         AS account_code,
               COALESCE(SUM(jl.debit), 0)  AS inflow,
               COALESCE(SUM(jl.credit), 0) AS outflow
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE {where_sql}
        GROUP BY je.source_type, a.code
        """,
        params,
    ).fetchall()

    activity: dict[str, dict[str, dict[str, float]]] = {}
    for r in rows:
        source_type = r["source_type"] or ""
        code = r["account_code"]
        activity.setdefault(source_type, {}).setdefault(
            code, {"inflow": 0.0, "outflow": 0.0}
        )
        activity[source_type][code]["inflow"] += float(r["inflow"])
        activity[source_type][code]["outflow"] += float(r["outflow"])
    return activity


def query_supplier_category_breakdown(
    conn, since_b: str | None, until_b: str | None,
    *, exclusive_until: bool = False,
) -> dict:
    """Category/subcategory breakdown of cash paid to suppliers/employees.

    Queries cash-side journal lines (debit=0, credit>0) for ``expense`` and
    ``expense_settlement`` source types on cash accounts within the date
    range, then resolves each entry's category/subcategory from the
    originating expense event's ``data`` JSON:

      - ``expense`` entries: ``source_id`` is the ``events.id`` — the
        event's ``data`` carries ``category`` / ``subcategory`` directly.
      - ``expense_settlement`` entries: ``source_id`` is a settlement id,
        not an event id. The settlement lives inside an expense event's
        ``data.settlements`` list (a list of ``{id, amount, ...}`` dicts);
        we scan all non-deleted expense events, find the one whose
        ``data.settlements`` contains a matching ``id``, and extract
        ``category`` / ``subcategory`` from that parent event's ``data``.

    ``order_shipping_release`` entries are excluded (FR3) — only
    ``expense`` and ``expense_settlement`` source types are queried.

    Journal entries that also touch the fixed-asset account 1600 are
    excluded — those are investing-activity flows and would otherwise
    appear here in ``supplierCategories`` but not in ``suppliers.outflow``
    (which is aggregated by ``query_cash_period_activity`` and already
    excludes 1600). Mirroring the 1600 ``NOT EXISTS`` filter here keeps
    the two views consistent (Mn2, DG-386 cycle 5).

    ``exclusive_until`` controls the upper-bound operator — see
    :func:`query_cash_period_activity`. Default ``False`` matches the CLI
    (inclusive ``<=``); the cashflow-summary API passes ``True`` so the
    next period's ``T00:00:00`` is not double-counted (Mn3).

    Aggregation follows the same tree pattern as ``expense_by_category_cmd``
    (report.py:756-823): ``expense_categories`` parent/child mappings are
    loaded, totals are accumulated per parent category (including all
    subcategory amounts), and legacy rows where the subcategory is stored
    in the ``category`` field are normalized back to the parent
    (report.py:806-813). Returns::

        {
            "totals": {parent_category: amount},
            "sub_totals": {parent_category: {subcategory: amount}},
            "uncategorized": float,
            "children_of": {parent_category: [child_category, ...]},
        }
    """
    placeholders = cash_account_placeholders(CASH_ACCOUNT_CODES)
    params: list = list(CASH_ACCOUNT_CODES)
    where_clauses = [
        f"a.code IN ({placeholders})",
        "je.source_type IN ('expense', 'expense_settlement')",
        "jl.debit = 0",
        "jl.credit > 0",
    ]
    if since_b:
        where_clauses.append("je.transaction_date >= ?")
        params.append(since_b)
    if until_b:
        op = "<" if exclusive_until else "<="
        where_clauses.append(f"je.transaction_date {op} ?")
        params.append(until_b)
    # Exclude entries that touch the fixed-asset account 1600 — those are
    # investing-activity flows. Mirrors query_cash_period_activity so the
    # breakdown stays consistent with suppliers.outflow (Mn2).
    where_clauses.append(
        "NOT EXISTS ("
        " SELECT 1 FROM journal_lines jl2"
        " JOIN accounts a2 ON a2.id = jl2.account_id"
        " WHERE jl2.journal_entry_id = je.id AND a2.code = ?"
        ")"
    )
    params.append(FIXED_ASSETS_CODE)
    where_sql = " AND ".join(where_clauses)

    rows = conn.execute(
        f"""
        SELECT je.source_type AS source_type,
               je.source_id   AS source_id,
               jl.credit      AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE {where_sql}
        ORDER BY je.transaction_date ASC
        """,
        params,
    ).fetchall()

    # Parent/child category mappings (DG-302 Phase 1). Only categories with
    # children get a breakdown block; legacy subcategory names stored in the
    # category field are normalized back to the parent via parent_of.
    # ``children_of`` (parent -> sorted list of child names) is derived from
    # the same rows and returned to the caller so it does not re-issue this
    # identical query (DG-327 deduplication).
    parent_of: dict[str, str] = {}
    children_of: dict[str, list[str]] = {}
    cat_rows = conn.execute(
        """
        SELECT child.name AS child_name,
               parent.name AS parent_name
        FROM expense_categories child
        JOIN expense_categories parent ON parent.id = child.parent_id
        """
    ).fetchall()
    for cr in cat_rows:
        parent_of[cr["child_name"]] = cr["parent_name"]
        children_of.setdefault(cr["parent_name"], []).append(
            cr["child_name"]
        )
    for parent in children_of:
        children_of[parent].sort()

    # Pre-load all non-deleted expense events once so expense_settlement
    # resolution (which needs to scan every expense event's data.settlements
    # array) does not issue one query per settlement row. ``events_by_id``
    # maps event id -> parsed data dict (None when data is missing/invalid).
    events_by_id: dict[int, dict | None] = {}
    event_rows = conn.execute(
        """
        SELECT id, data
        FROM events
        WHERE type = 'expense'
          AND (deleted_at IS NULL OR deleted_at = '')
        """
    ).fetchall()
    for er in event_rows:
        data: dict | None = None
        if er["data"]:
            try:
                parsed = json.loads(er["data"])
                if isinstance(parsed, dict):
                    data = parsed
            except (json.JSONDecodeError, TypeError):
                pass
        events_by_id[int(er["id"])] = data

    # Build a settlement-id -> event-data lookup so expense_settlement rows
    # resolve in O(1) rather than scanning every event per settlement row.
    settlement_to_event_data: dict[int, dict] = {}
    for ev_id, ev_data in events_by_id.items():
        if not ev_data:
            continue
        settlements = ev_data.get("settlements")
        if not isinstance(settlements, list):
            continue
        for s in settlements:
            if not isinstance(s, dict):
                continue
            sid = s.get("id")
            if isinstance(sid, int):
                settlement_to_event_data[sid] = ev_data

    totals: dict[str, float] = {}
    sub_totals: dict[str, dict[str, float]] = {}
    uncategorized = 0.0

    for r in rows:
        source_type = r["source_type"]
        source_id = r["source_id"]
        amount = float(r["credit"])
        category: str | None = None
        subcategory: str | None = None

        if source_type == "expense" and isinstance(source_id, int):
            ev_data = events_by_id.get(source_id)
            if ev_data:
                cat = ev_data.get("category")
                if isinstance(cat, str) and cat:
                    category = cat
                sub = ev_data.get("subcategory")
                if isinstance(sub, str) and sub:
                    subcategory = sub
        elif source_type == "expense_settlement" and isinstance(source_id, int):
            ev_data = settlement_to_event_data.get(source_id)
            if ev_data:
                cat = ev_data.get("category")
                if isinstance(cat, str) and cat:
                    category = cat
                sub = ev_data.get("subcategory")
                if isinstance(sub, str) and sub:
                    subcategory = sub

        if category:
            # Legacy normalization: when the category field is actually a
            # subcategory name, normalize it back to the parent so it lands
            # in the right bucket (matches report.py:806-813).
            if category in parent_of:
                parent = parent_of[category]
                sub_totals.setdefault(parent, {})
                sub_totals[parent][category] = (
                    sub_totals[parent].get(category, 0.0) + amount
                )
                totals[parent] = totals.get(parent, 0.0) + amount
            else:
                totals[category] = totals.get(category, 0.0) + amount
                if subcategory:
                    sub_totals.setdefault(category, {})
                    sub_totals[category][subcategory] = (
                        sub_totals[category].get(subcategory, 0.0) + amount
                    )
        else:
            uncategorized += amount

    return {
        "totals": totals,
        "sub_totals": sub_totals,
        "uncategorized": uncategorized,
        "children_of": children_of,
    }


def sum_section(
    activity: dict[str, dict[str, dict[str, float]]],
    source_types: tuple[str, ...],
) -> tuple[float, float, dict[str, dict[str, float]]]:
    """Sum inflow/outflow across the given ``source_types``.

    Returns ``(total_inflow, total_outflow, per_account)`` where
    ``per_account`` is ``{cash_account_code: {"inflow": float, "outflow": float}}``.
    """
    total_in = 0.0
    total_out = 0.0
    per_account: dict[str, dict[str, float]] = {}
    for st in source_types:
        for code, mov in activity.get(st, {}).items():
            inflow = mov["inflow"]
            outflow = mov["outflow"]
            total_in += inflow
            total_out += outflow
            per_account.setdefault(code, {"inflow": 0.0, "outflow": 0.0})
            per_account[code]["inflow"] += inflow
            per_account[code]["outflow"] += outflow
    return total_in, total_out, per_account