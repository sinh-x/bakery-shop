"""``baker report`` CLI group — accounting financial reports (FR5).

Provides nine read-only subcommands that aggregate ``journal_entries`` /
``journal_lines`` into human-readable text reports printed to stdout:

- ``trial-balance``      — per-account debit/credit/balance totals for a date range
- ``income-statement``   — Revenue − COGS − Expenses = Net Income for a date range
- ``balance-sheet``      — Assets / Liabilities / Equity snapshot as of an end date
- ``general-ledger``     — all journal entries (with lines) in a date range
- ``account-ledger``     — per-account journal line history (requires ``--account-code``)
- ``expense-by-category``— expense totals grouped by source event category
- ``cogs-audit``         — per-order COGS completeness and ratio audit (FR4)
- ``order-status``       — order counts and total value grouped by status and delivery type
- ``cashflow``           — direct-method cash-flow statement (operating / investing / financing)

All commands accept ``--since`` and ``--until`` in ``YYYY-MM-DD`` format.
``--until`` is treated inclusively (end-of-day). Exit code is 0 on success
and non-zero on error; errors are written to stderr only — following the
existing ``validate-accounts`` pattern.
"""

import json
from datetime import datetime
from typing import Optional

import click

from baker.db.connection import get_db
from baker.db.schema import COGS_CODE, ORDER_REVENUE_CODE
from baker.labels.report_labels import (
    ACCOUNT_TYPE_LABELS,
    COGS_STATUS_LABELS,
    CASHFLOW_TITLE,
    INCOME_STATEMENT_DUE_DATE_TITLE,
    INCOME_STATEMENT_TITLE,
    TRIAL_BALANCE_TITLE,
    BALANCE_SHEET_TITLE,
    GENERAL_LEDGER_TITLE,
    ACCOUNT_LEDGER_TITLE,
    EXPENSE_BY_CATEGORY_TITLE,
    COGS_AUDIT_TITLE,
    ORDER_STATUS_TITLE,
    LBL_CODE,
    LBL_ACCOUNT,
    LBL_TYPE,
    LBL_DEBIT,
    LBL_CREDIT,
    LBL_TOTALS,
    LBL_REVENUE,
    LBL_COGS_5900,
    LBL_COGS_SHORT,
    LBL_GROSS_PROFIT,
    LBL_MARKUP_TRUNG_BAY,
    LBL_OPERATING_EXPENSES,
    LBL_NET_INCOME,
    LBL_ASSETS,
    LBL_LIABILITIES,
    LBL_EQUITY,
    LBL_TOTAL_ASSETS,
    LBL_TOTAL_LIABILITIES_EQUITY,
    LBL_CATEGORY,
    LBL_TOTAL,
    LBL_TOTAL_UPPER,
    LBL_UNCATEGORIZED,
    LBL_ORDER,
    LBL_ORDER_REF,
    LBL_RATIO,
    LBL_STATUS,
    LBL_DELIVERY_TYPE,
    LBL_COUNT,
    LBL_VALUE,
    LBL_SUBTOTAL,
    LBL_GRAND_TOTAL,
    LBL_ORDERS,
    LBL_DR,
    LBL_CR,
    LBL_PERIOD,
    LBL_SOURCE,
    LBL_BALANCE,
    LBL_LOCKED,
    LBL_NONE,
    LBL_NO_ACTIVITY,
    LBL_SUBTOTAL_UPPER,
    LBL_OPENING_BALANCE,
    LBL_CLOSING_BALANCE,
    LBL_NET_CASH_FLOW,
    LBL_TOTAL_INFLOWS,
    LBL_TOTAL_OUTFLOWS,
    LBL_NET_OPERATING_CASHFLOW,
    LBL_NET_INVESTING_CASHFLOW,
    LBL_NET_FINANCING_CASHFLOW,
    LBL_OPERATING_ACTIVITIES,
    LBL_CASH_FROM_CUSTOMERS,
    LBL_CASH_PAID_SUPPLIERS,
    LBL_INVESTING_ACTIVITIES,
    LBL_FINANCING_ACTIVITIES,
    LBL_PER_ACCOUNT_BREAKDOWN,
    LBL_INFLOWS,
    LBL_OUTFLOWS,
    LBL_NET,
    LBL_OPENING,
    LBL_CLOSING,
    LBL_RECONCILIATION_DETAIL,
    ORDER_STATUS_LABELS,
    MSG_NO_JOURNAL_ENTRIES,
    MSG_NO_JOURNAL_LINES_ACCOUNT,
    MSG_NO_EXPENSE_ENTRIES,
    MSG_NO_ORDERS,
    MSG_ALL_TIME,
    LBL_RECONCILE_OK,
    LBL_RECONCILE_MISMATCH,
)
from baker.models.order import OrderStatus
from baker.utils.time import utc_to_local


# Account types whose natural balance is debit - credit (asset/expense).
DEBIT_NORMAL_TYPES = ("asset", "expense")

# Statuses used by the COGS audit report (FR4 / AC4):
#   ok         — COGS entry exists, no zero-cost items, ratio >= COGS_LOW_RATIO
#   missing    — no order_cogs journal entry recorded for the order
#   zero-cost  — order_cogs entry exists but some non-gift order_items (incl.
#                sold extras) still have cost_at_sale = 0 (cost never resolved)
#   low        — COGS/revenue ratio below COGS_LOW_RATIO (baseline estimate is
#                30%; a much lower ratio flags a likely mispriced or mis-costed
#                order worth manual review)
COGS_LOW_RATIO = 0.15
COGS_STATUSES = ("ok", "missing", "zero-cost", "low")


def _normalize_date(date_str: Optional[str], *, end_of_day: bool = False) -> Optional[str]:
    """Convert a ``YYYY-MM-DD`` date into a comparable ``transaction_date`` bound.

    ``transaction_date`` is stored as ``YYYY-MM-DDTHH:MM:SS``; a bare date sorts
    before any timestamp on that day, so for ``--until`` we append
    ``T23:59:59`` to make the bound inclusive of the whole day.

    Raises ``click.BadParameter`` if ``date_str`` is non-empty but does not
    parse as ``YYYY-MM-DD`` — prevents silently passing arbitrary strings
    through to SQLite (DG-189 Phase 5.6-c1, CQ-3).
    """
    if not date_str:
        return None
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError as exc:
        raise click.BadParameter(
            f"{date_str!r} is not a valid YYYY-MM-DD date.",
            param_hint="Use the format YYYY-MM-DD (e.g. 2026-06-30).",
        ) from exc
    if end_of_day and len(date_str) == 10 and "T" not in date_str:
        return f"{date_str}T23:59:59"
    return date_str


def _balance_for_type(acc_type: str, debit: float, credit: float) -> float:
    if acc_type in DEBIT_NORMAL_TYPES:
        return debit - credit
    return credit - debit


def _fmt_date(date_str: Optional[str]) -> str:
    """Convert a ``YYYY-MM-DD`` (or ``YYYY-MM-DDTHH:MM:SS``) value to ``DD/MM/YYYY``.

    Returns the input unchanged when it is empty or does not match the
    expected shape — used by ``_echo_header`` for the period display so
    dates follow Vietnamese convention (FR6).
    """
    if not date_str:
        return ""
    core = date_str[:10] if len(date_str) >= 10 else date_str
    try:
        dt = datetime.strptime(core, "%Y-%m-%d")
    except ValueError:
        return date_str
    return dt.strftime("%d/%m/%Y")


def _echo_header(title: str, since: Optional[str], until: Optional[str]) -> None:
    click.echo(title)
    click.echo("=" * len(title))
    period = MSG_ALL_TIME
    if since and until:
        period = f"{_fmt_date(since)} → {_fmt_date(until)}"
    elif since:
        period = f"từ {_fmt_date(since)}"
    elif until:
        period = f"đến {_fmt_date(until)}"
    click.echo(f"{LBL_PERIOD} {period}")
    click.echo("")


def _validate_account_code(account_code: Optional[str]) -> str:
    if not account_code:
        raise click.UsageError(
            "--account-code is required for the account-ledger report."
        )
    return account_code


@click.group("report")
def report_cmd():
    """Accounting financial reports (trial balance, income statement, ...)."""


@report_cmd.command("trial-balance")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def trial_balance_cmd(since, until):
    """All active accounts with debit/credit/balance totals for a date range."""
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header(TRIAL_BALANCE_TITLE, since, until)

    params: list = []
    where_clauses = []
    if since_b:
        where_clauses.append("je.transaction_date >= ?")
        params.append(since_b)
    if until_b:
        where_clauses.append("je.transaction_date <= ?")
        params.append(until_b)
    date_filter = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

    with get_db() as conn:
        rows = conn.execute(
            f"""
            SELECT a.code  AS code,
                   a.name  AS name,
                   a.type  AS type,
                   COALESCE(SUM(jl.debit), 0)  AS total_debit,
                   COALESCE(SUM(jl.credit), 0) AS total_credit
            FROM accounts a
            LEFT JOIN journal_lines jl ON jl.account_id = a.id
            LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
            {date_filter}
            GROUP BY a.id
            HAVING a.is_active = 1
            ORDER BY a.code
            """,
            params,
        ).fetchall()

    if not rows:
        click.echo(MSG_NO_JOURNAL_ENTRIES)
        return

    total_debit = 0.0
    total_credit = 0.0
    click.echo(
        f"{LBL_CODE:<8}{LBL_ACCOUNT:<40}{LBL_TYPE:<14}{LBL_DEBIT:>14}{LBL_CREDIT:>14}"
    )
    click.echo("-" * 90)
    for r in rows:
        debit = float(r["total_debit"])
        credit = float(r["total_credit"])
        total_debit += debit
        total_credit += credit
        type_label = ACCOUNT_TYPE_LABELS.get(r["type"], r["type"])
        click.echo(
            f"{r['code']:<8}{r['name'][:39]:<40}{type_label:<14}"
            f"{debit:>14,.2f}{credit:>14,.2f}"
        )
    click.echo("-" * 90)
    click.echo(f"{LBL_TOTALS:<62}{total_debit:>14,.2f}{total_credit:>14,.2f}")


@report_cmd.command("income-statement")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
@click.option(
    "--date-basis",
    type=click.Choice(["transaction", "due-date"]),
    default="transaction",
    help="Date basis for order revenue/COGS (default: transaction). "
         "Use 'due-date' to bucket by COALESCE(order.due_date, delivered local date).",
)
def income_statement_cmd(since, until, date_basis):
    """Revenue − COGS − Expenses = Net Income for a date range."""
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    if date_basis == "due-date":
        _echo_header(INCOME_STATEMENT_DUE_DATE_TITLE, since, until)
    else:
        _echo_header(INCOME_STATEMENT_TITLE, since, until)

    if date_basis == "due-date":
        _income_statement_due_date(since_b, until_b)
    else:
        _income_statement_transaction(since_b, until_b)


def _income_statement_transaction(since_b: str | None, until_b: str | None) -> None:
    """Income statement using transaction_date basis (current behavior)."""
    with get_db() as conn:
        params: list = []
        where_clauses = []
        if since_b:
            where_clauses.append("je.transaction_date >= ?")
            params.append(since_b)
        if until_b:
            where_clauses.append("je.transaction_date <= ?")
            params.append(until_b)
        date_filter = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

        rows = conn.execute(
            f"""
            SELECT a.type AS type,
                   COALESCE(SUM(jl.debit), 0)  AS total_debit,
                   COALESCE(SUM(jl.credit), 0) AS total_credit
            FROM accounts a
            JOIN journal_lines jl ON jl.account_id = a.id
            JOIN journal_entries je ON je.id = jl.journal_entry_id
            {date_filter}
            GROUP BY a.type
            """,
            params,
        ).fetchall()

    by_type = {r["type"]: (float(r["total_debit"]), float(r["total_credit"])) for r in rows}

    def net(acc_type: str) -> float:
        d, c = by_type.get(acc_type, (0.0, 0.0))
        return _balance_for_type(acc_type, d, c)

    revenue = net("income")

    cogs_params: list = [COGS_CODE]
    cogs_where = ["a.code = ?"]
    if since_b:
        cogs_where.append("je.transaction_date >= ?")
        cogs_params.append(since_b)
    if until_b:
        cogs_where.append("je.transaction_date <= ?")
        cogs_params.append(until_b)
    cogs_sql = "WHERE " + " AND ".join(cogs_where)
    with get_db() as conn:
        cogs_row = conn.execute(
            f"""
            SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS cogs
            FROM journal_lines jl
            JOIN journal_entries je ON je.id = jl.journal_entry_id
            JOIN accounts a ON a.id = jl.account_id
            {cogs_sql}
            """,
            cogs_params,
        ).fetchone()
    cogs_amount = float(cogs_row["cogs"]) if cogs_row else 0.0

    total_expense = net("expense")
    operating_expenses = total_expense - cogs_amount

    markup = _compute_markup_total(since_b, until_b, due_date_basis=False)
    _echo_income_statement_body(revenue, cogs_amount, operating_expenses, markup)


def _income_statement_due_date(since_b: str | None, until_b: str | None) -> None:
    """Income statement using due-date basis for order-sourced entries.

    Order revenue/COGS bucket by COALESCE(order.due_date, DATE(transaction_date)).
    Operating expenses remain on transaction_date (FR5).
    """
    with get_db() as conn:
        params: list = []
        filter_parts = []

        def _add_date_filter(
            date_expr: str, params: list, filter_parts: list,
        ) -> None:
            if since_b:
                filter_parts.append(f"{date_expr} >= ?")
                params.append(since_b)
            if until_b:
                filter_parts.append(f"{date_expr} <= ?")
                params.append(until_b)

        order_conditions: list = ["je.source_type IN ('order', 'order_cogs')"]
        order_date = "COALESCE(o.due_date, DATE(je.transaction_date))"
        _add_date_filter(order_date, params, order_conditions)

        other_conditions: list = ["je.source_type NOT IN ('order', 'order_cogs')"]
        _add_date_filter("je.transaction_date", params, other_conditions)

        date_filter = (
            "WHERE (" + " AND ".join(order_conditions) + ") OR (" + " AND ".join(other_conditions) + ")"
        ) if (order_conditions[1:] or other_conditions[1:]) else ""

        rows = conn.execute(
            f"""
            SELECT a.type AS type,
                   COALESCE(SUM(jl.debit), 0)  AS total_debit,
                   COALESCE(SUM(jl.credit), 0) AS total_credit
            FROM accounts a
            JOIN journal_lines jl ON jl.account_id = a.id
            JOIN journal_entries je ON je.id = jl.journal_entry_id
            LEFT JOIN orders o ON je.source_type IN ('order', 'order_cogs') AND je.source_id = o.id
            {date_filter}
            GROUP BY a.type
            """,
            params,
        ).fetchall()

    by_type = {r["type"]: (float(r["total_debit"]), float(r["total_credit"])) for r in rows}

    def net(acc_type: str) -> float:
        d, c = by_type.get(acc_type, (0.0, 0.0))
        return _balance_for_type(acc_type, d, c)

    revenue = net("income")

    cogs_params: list = [COGS_CODE]
    cogs_filter_parts = ["a.code = ?"]
    cogs_order_conditions: list = ["je.source_type IN ('order', 'order_cogs')"]
    cogs_other_conditions: list = ["je.source_type NOT IN ('order', 'order_cogs')"]
    cogs_order_date = "COALESCE(o.due_date, DATE(je.transaction_date))"
    if since_b:
        cogs_order_conditions.append(f"{cogs_order_date} >= ?")
        cogs_other_conditions.append("je.transaction_date >= ?")
        cogs_params.extend([since_b, since_b])
    if until_b:
        cogs_order_conditions.append(f"{cogs_order_date} <= ?")
        cogs_other_conditions.append("je.transaction_date <= ?")
        cogs_params.extend([until_b, until_b])
    cogs_filter_parts.append(
        "(( " + " AND ".join(cogs_order_conditions) + ") OR ("
        + " AND ".join(cogs_other_conditions) + "))"
    )

    with get_db() as conn:
        cogs_row = conn.execute(
            f"""
            SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS cogs
            FROM journal_lines jl
            JOIN journal_entries je ON je.id = jl.journal_entry_id
            JOIN accounts a ON a.id = jl.account_id
            LEFT JOIN orders o ON je.source_type IN ('order', 'order_cogs') AND je.source_id = o.id
            WHERE {" AND ".join(cogs_filter_parts)}
            """,
            cogs_params,
        ).fetchone()
    cogs_amount = float(cogs_row["cogs"]) if cogs_row else 0.0

    total_expense = net("expense")
    operating_expenses = total_expense - cogs_amount

    markup = _compute_markup_total(since_b, until_b, due_date_basis=True)
    _echo_income_statement_body(revenue, cogs_amount, operating_expenses, markup)


def _compute_markup_total(
    since_b: str | None, until_b: str | None, *, due_date_basis: bool,
) -> float:
    """Sum trưng bày markup (unit_price − assigned_price) for delivered/completed
    orders in the date range.

    Only rows where ``assigned_price IS NOT NULL AND assigned_price < unit_price``
    contribute (per FR7: historical data with NULL assigned_price is treated as
    no markup). Date scoping mirrors the income-statement basis: due-date basis
    uses ``COALESCE(o.due_date, o.created_at)``; transaction basis uses
    ``o.created_at``. (DG-296 Phase 5)
    """
    params: list = []
    where = ["o.status IN ('delivered', 'completed')",
             "oi.assigned_price IS NOT NULL",
             "oi.assigned_price < oi.unit_price"]
    date_expr = "COALESCE(NULLIF(o.due_date, ''), o.created_at)" if due_date_basis else "o.created_at"
    if since_b:
        where.append(f"{date_expr} >= ?")
        params.append(since_b)
    if until_b:
        where.append(f"{date_expr} <= ?")
        params.append(until_b)
    where_sql = " AND ".join(where)
    with get_db() as conn:
        row = conn.execute(
            f"""
            SELECT COALESCE(SUM(oi.unit_price - oi.assigned_price), 0) AS markup
            FROM order_items oi
            JOIN orders o ON o.id = oi.order_id
            WHERE {where_sql}
            """,
            params,
        ).fetchone()
    return float(row["markup"]) if row else 0.0


def _echo_income_statement_body(
    revenue: float, cogs_amount: float, operating_expenses: float,
    markup: float = 0.0,
) -> None:
    """Print the income statement body lines (shared between bases).

    ``markup`` is the total trưng bày markup (unit_price − assigned_price) for
    the period — an informational line, not part of the net income calculation
    (DG-296 Phase 5, FR7). It is shown only when non-zero.
    """
    click.echo(f"{LBL_REVENUE:<40}{revenue:>20,.2f}")
    cogs_ratio = (cogs_amount / revenue * 100.0) if revenue > 0 else 0.0
    click.echo(
        f"{LBL_COGS_5900:<40}{cogs_amount:>20,.2f}"
        f"  ({cogs_ratio:.1f}%)"
    )
    click.echo(f"{LBL_GROSS_PROFIT:<40}{(revenue - cogs_amount):>20,.2f}")
    if markup > 0:
        click.echo(
            f"{LBL_MARKUP_TRUNG_BAY:<40}{markup:>20,.2f}"
        )
    click.echo("")
    click.echo(f"{LBL_OPERATING_EXPENSES:<40}{operating_expenses:>20,.2f}")
    click.echo("")
    net_income = revenue - cogs_amount - operating_expenses
    click.echo(f"{LBL_NET_INCOME:<40}{net_income:>20,.2f}")


@report_cmd.command("balance-sheet")
@click.option("--until", help="As-of date (YYYY-MM-DD, inclusive)")
def balance_sheet_cmd(until):
    """Assets, Liabilities, Equity snapshot as of the end date."""
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header(BALANCE_SHEET_TITLE, None, until)

    with get_db() as conn:
        params: list = []
        where_clauses = []
        if until_b:
            where_clauses.append("je.transaction_date <= ?")
            params.append(until_b)
        date_filter = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

        rows = conn.execute(
            f"""
            SELECT a.code  AS code,
                   a.name  AS name,
                   a.type  AS type,
                   COALESCE(SUM(jl.debit), 0)  AS total_debit,
                   COALESCE(SUM(jl.credit), 0) AS total_credit
            FROM accounts a
            LEFT JOIN journal_lines jl ON jl.account_id = a.id
            LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
            {date_filter}
            GROUP BY a.id
            HAVING a.is_active = 1
            ORDER BY a.code
            """,
            params,
        ).fetchall()

    def section(title: str, acc_type: str, total_label: str) -> float:
        click.echo(title)
        click.echo("-" * len(title))
        section_total = 0.0
        for r in rows:
            if r["type"] != acc_type:
                continue
            bal = _balance_for_type(r["type"], float(r["total_debit"]), float(r["total_credit"]))
            if abs(bal) < 0.005:
                continue
            section_total += bal
            click.echo(f"  {r['code']:<8}{r['name'][:39]:<40}{bal:>14,.2f}")
        click.echo(f"  {total_label:<48}{section_total:>14,.2f}")
        click.echo("")
        return section_total

    total_assets = section(LBL_ASSETS, "asset", LBL_TOTAL_ASSETS)
    total_liabilities = section(
        LBL_LIABILITIES, "liability", f"{LBL_TOTAL} {LBL_LIABILITIES}",
    )
    total_equity = section(LBL_EQUITY, "equity", f"{LBL_TOTAL} {LBL_EQUITY}")
    click.echo("=" * 62)
    click.echo(f"{LBL_TOTAL_ASSETS:<48}{total_assets:>14,.2f}")
    click.echo(f"{LBL_TOTAL_LIABILITIES_EQUITY:<48}"
               f"{(total_liabilities + total_equity):>14,.2f}")


@report_cmd.command("general-ledger")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def general_ledger_cmd(since, until):
    """All journal entries in a date range, human-readable with lines."""
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header(GENERAL_LEDGER_TITLE, since, until)

    with get_db() as conn:
        params: list = []
        where_clauses = []
        if since_b:
            where_clauses.append("je.transaction_date >= ?")
            params.append(since_b)
        if until_b:
            where_clauses.append("je.transaction_date <= ?")
            params.append(until_b)
        where_sql = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

        entries = conn.execute(
            f"""
            SELECT je.id          AS id,
                   je.description  AS description,
                   je.source_type  AS source_type,
                   je.source_id    AS source_id,
                   je.transaction_date AS transaction_date,
                   je.locked_at    AS locked_at
            FROM journal_entries je
            {where_sql}
            ORDER BY je.transaction_date ASC, je.id ASC
            """,
            params,
        ).fetchall()

        if not entries:
            click.echo(MSG_NO_JOURNAL_ENTRIES)
            return

        for je in entries:
            click.echo(
                f"#{je['id']}  {utc_to_local(je['transaction_date'])}  {je['description']}  "
                f"[{LBL_SOURCE}{je['source_type']}:{je['source_id']}]"
                + (f"  ({LBL_LOCKED})" if je["locked_at"] else "")
            )
            lines = conn.execute(
                """
                SELECT a.code AS code, a.name AS name, jl.debit AS debit,
                       jl.credit AS credit, jl.description AS description
                FROM journal_lines jl
                JOIN accounts a ON a.id = jl.account_id
                WHERE jl.journal_entry_id = ?
                ORDER BY jl.id
                """,
                (je["id"],),
            ).fetchall()
            for jl in lines:
                debit = float(jl["debit"])
                credit = float(jl["credit"])
                if debit:
                    click.echo(f"    {LBL_DR}  {jl['code']:<8}{jl['name'][:30]:<32}{debit:>14,.2f}  {jl['description']}")
                else:
                    click.echo(f"    {LBL_CR}  {jl['code']:<8}{jl['name'][:30]:<32}{credit:>14,.2f}  {jl['description']}")
            click.echo("")


@report_cmd.command("account-ledger")
@click.option("--account-code", help="Account code (e.g. 1100)", required=False)
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def account_ledger_cmd(account_code, since, until):
    """Per-account journal line history (requires --account-code)."""
    code = _validate_account_code(account_code)
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)

    with get_db() as conn:
        account = conn.execute(
            "SELECT id, code, name, type FROM accounts WHERE code = ?", (code,)
        ).fetchone()
        if account is None:
            raise click.UsageError(f"Account code '{code}' not found in chart of accounts.")

        _echo_header(f"{ACCOUNT_LEDGER_TITLE} — {account['code']} {account['name']}", since, until)

        params: list = [account["id"]]
        where_clauses = ["jl.account_id = ?"]
        if since_b:
            where_clauses.append("je.transaction_date >= ?")
            params.append(since_b)
        if until_b:
            where_clauses.append("je.transaction_date <= ?")
            params.append(until_b)
        where_sql = "WHERE " + " AND ".join(where_clauses)

        rows = conn.execute(
            f"""
            SELECT je.id          AS entry_id,
                   je.transaction_date AS transaction_date,
                   je.description AS entry_description,
                   jl.debit        AS debit,
                   jl.credit       AS credit,
                   jl.description  AS line_description
            FROM journal_lines jl
            JOIN journal_entries je ON je.id = jl.journal_entry_id
            {where_sql}
            ORDER BY je.transaction_date ASC, je.id ASC, jl.id ASC
            """,
            params,
        ).fetchall()

        if not rows:
            click.echo(MSG_NO_JOURNAL_LINES_ACCOUNT)
            return

        running = 0.0
        for r in rows:
            debit = float(r["debit"])
            credit = float(r["credit"])
            if account["type"] in DEBIT_NORMAL_TYPES:
                running += debit - credit
            else:
                running += credit - debit
            if debit:
                movement = f"{LBL_DR} {debit:>12,.2f}"
            else:
                movement = f"{LBL_CR} {credit:>12,.2f}"
            click.echo(
                f"{utc_to_local(r['transaction_date'])}  #{r['entry_id']:<6}{movement}  "
                f"{LBL_BALANCE}={running:>14,.2f}  {r['line_description']}"
            )


@report_cmd.command("expense-by-category")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def expense_by_category_cmd(since, until):
    """Expense totals grouped by source event category for a date range.

    When a parent category has subcategories (per the ``expense_categories``
    table — DG-302), the report prints a breakdown by subcategory below the
    parent row (FR3 / AC3). Expenses that carry a ``subcategory`` field in
    ``events.data`` are bucketed under their subcategory; the parent row's
    total still includes those subcategory amounts so column totals are
    consistent. Expenses without a subcategory (legacy rows, FR6) are
    attributed to the parent category directly.
    """
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header(EXPENSE_BY_CATEGORY_TITLE, since, until)

    with get_db() as conn:
        params: list = []
        where_clauses = ["je.source_type = 'expense'", "jl.debit > 0"]
        if since_b:
            where_clauses.append("je.transaction_date >= ?")
            params.append(since_b)
        if until_b:
            where_clauses.append("je.transaction_date <= ?")
            params.append(until_b)
        where_sql = "WHERE " + " AND ".join(where_clauses)

        rows = conn.execute(
            f"""
            SELECT je.source_id AS event_id,
                   je.transaction_date AS transaction_date,
                   a.code        AS account_code,
                   a.name        AS account_name,
                   jl.debit      AS debit
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id
            {where_sql}
            ORDER BY je.transaction_date ASC
            """,
            params,
        ).fetchall()

        if not rows:
            click.echo(MSG_NO_EXPENSE_ENTRIES)
            return

        # Map subcategory name -> parent category name (DG-302 Phase 1).
        # Only categories with children get a breakdown block (FR3).
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
            child = cr["child_name"]
            parent = cr["parent_name"]
            parent_of[child] = parent
            children_of.setdefault(parent, []).append(child)
        for parent in children_of:
            children_of[parent].sort()

        # Aggregate by category (and subcategory when present) from
        # events.data JSON, falling back to the debited account name when
        # the event/data is unavailable.
        # totals[parent_category] = total (incl. all subcategories)
        # sub_totals[parent_category][subcategory] = subtotal
        totals: dict[str, float] = {}
        sub_totals: dict[str, dict[str, float]] = {}
        uncategorized = 0.0
        for r in rows:
            category = None
            subcategory = None
            event_id = r["event_id"]
            if event_id is not None:
                ev = conn.execute(
                    "SELECT data FROM events WHERE id = ?", (int(event_id),)
                ).fetchone()
                if ev and ev["data"]:
                    try:
                        data = json.loads(ev["data"])
                        cat = data.get("category")
                        if isinstance(cat, str) and cat:
                            category = cat
                        sub = data.get("subcategory")
                        if isinstance(sub, str) and sub:
                            subcategory = sub
                    except (json.JSONDecodeError, TypeError):
                        pass
            if category:
                # If the "category" itself is a subcategory name (legacy
                # rows where subcategory was stored in category), normalize
                # it back to the parent so it lands in the right bucket.
                if category in parent_of:
                    parent = parent_of[category]
                    sub_totals.setdefault(parent, {})
                    sub_totals[parent][category] = (
                        sub_totals[parent].get(category, 0.0) + float(r["debit"])
                    )
                    totals[parent] = totals.get(parent, 0.0) + float(r["debit"])
                else:
                    totals[category] = totals.get(category, 0.0) + float(r["debit"])
                    if subcategory:
                        sub_totals.setdefault(category, {})
                        sub_totals[category][subcategory] = (
                            sub_totals[category].get(subcategory, 0.0)
                            + float(r["debit"])
                        )
            else:
                uncategorized += float(r["debit"])

        click.echo(f"{LBL_CATEGORY:<32}{LBL_TOTAL:>20}")
        click.echo("-" * 52)
        grand_total = 0.0
        for category in sorted(totals):
            amount = totals[category]
            grand_total += amount
            click.echo(f"{category[:31]:<32}{amount:>20,.2f}")
            # FR3 / AC3: subcategory breakdown for parent categories that
            # have children defined in the expense_categories table.
            subs = sub_totals.get(category, {})
            if category in children_of:
                for sub_name in children_of[category]:
                    sub_amount = subs.get(sub_name, 0.0)
                    click.echo(f"  {sub_name[:30]:<30}{sub_amount:>20,.2f}")
                # Legacy/other subcategory values not in the seed tree.
                known = set(children_of[category])
                for sub_name in sorted(subs):
                    if sub_name not in known:
                        sub_amount = subs[sub_name]
                        click.echo(f"  {sub_name[:30]:<30}{sub_amount:>20,.2f}")
        if uncategorized:
            grand_total += uncategorized
            click.echo(f"{LBL_UNCATEGORIZED:<32}{uncategorized:>20,.2f}")
        click.echo("-" * 52)
        click.echo(f"{LBL_TOTAL_UPPER:<32}{grand_total:>20,.2f}")


@report_cmd.command("cogs-audit")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def cogs_audit_cmd(since, until):
    """Audit COGS completeness and ratio per delivered/completed order.

    Outputs a table (order_id, revenue, cogs, ratio, status) for every
    delivered/completed order in the date range. Status flags:

      ok         — COGS entry exists, no zero-cost items, ratio in range
      missing    — no order_cogs journal entry recorded
      zero-cost  — order has non-gift items (incl. sold extras) with cost_at_sale = 0
      low        — COGS/revenue ratio below the baseline estimate threshold

    A summary line reports totals and the count of orders in each status.
    Exit code is 0 on success (regardless of flagged orders — this is a
    read-only audit report, not a pass/fail gate).
    """
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header(COGS_AUDIT_TITLE, since, until)

    # Single-pass query joining orders → order_items → journal entries. We
    # gather, per order:
    #   - total revenue from `order` journal entries (4100 credit side)
    #   - total COGS from `order_cogs` journal entries (5900 debit side)
    #   - count of non-gift order_items (incl. sold extras) with cost_at_sale = 0
    #   - whether an order_cogs journal entry exists at all
    #
    # The query filters to delivered/completed orders only, scoped by the
    # order's due_date (fallback created_at) — the same business-event date
    # used by `_sync_delivered_order_journal` (FR11). Orders with no
    # due_date/created_at in range are excluded.
    params: list = []
    order_where = ["o.status IN ('delivered', 'completed')"]
    if since_b:
        order_where.append("COALESCE(NULLIF(o.due_date, ''), o.created_at) >= ?")
        params.append(since_b)
    if until_b:
        order_where.append("COALESCE(NULLIF(o.due_date, ''), o.created_at) <= ?")
        params.append(until_b)
    order_sql = " AND ".join(order_where)

    with get_db() as conn:
        rows = conn.execute(
            f"""
            SELECT o.id           AS order_id,
                   o.order_ref    AS order_ref,
                   COALESCE(NULLIF(o.due_date, ''), o.created_at) AS order_date,
                   (
                     SELECT COALESCE(SUM(jl.credit), 0)
                     FROM journal_entries je
                     JOIN journal_lines jl ON jl.journal_entry_id = je.id
                     JOIN accounts a ON a.id = jl.account_id
                     WHERE je.source_type = 'order' AND je.source_id = o.id
                       AND a.code = ?
                   ) AS revenue,
                   (
                     SELECT COALESCE(SUM(jl.debit - jl.credit), 0)
                     FROM journal_entries je
                     JOIN journal_lines jl ON jl.journal_entry_id = je.id
                     JOIN accounts a ON a.id = jl.account_id
                     WHERE je.source_type = 'order_cogs' AND je.source_id = o.id
                       AND a.code = ?
                   ) AS cogs,
                   EXISTS (
                     SELECT 1 FROM journal_entries je
                     WHERE je.source_type = 'order_cogs' AND je.source_id = o.id
                   ) AS has_cogs_entry,
                   (
                     SELECT COUNT(*)
                    FROM order_items oi
                      WHERE oi.order_id = o.id
                        AND oi.is_gift = 0
                        AND (oi.cost_at_sale IS NULL OR oi.cost_at_sale = 0)
                    ) AS zero_cost_items
            FROM orders o
            WHERE {order_sql}
            ORDER BY o.id ASC
            """,
            [ORDER_REVENUE_CODE, COGS_CODE, *params],
        ).fetchall()

    if not rows:
        click.echo(MSG_NO_ORDERS)
        return

    # Header
    click.echo(
        f"{LBL_ORDER:<10}{LBL_ORDER_REF:<18}{LBL_REVENUE:>16}{LBL_COGS_SHORT:>16}"
        f"{LBL_RATIO:>10}{LBL_STATUS:>16}"
    )
    click.echo("-" * 86)

    totals = {status: 0 for status in COGS_STATUSES}
    total_revenue = 0.0
    total_cogs = 0.0

    for r in rows:
        revenue = float(r["revenue"] or 0)
        cogs = float(r["cogs"] or 0)
        has_cogs_entry = bool(r["has_cogs_entry"])
        zero_items = int(r["zero_cost_items"] or 0)

        if not has_cogs_entry:
            status = "missing"
        elif zero_items > 0:
            status = "zero-cost"
        elif revenue > 0 and (cogs / revenue) < COGS_LOW_RATIO:
            status = "low"
        else:
            status = "ok"

        ratio = (cogs / revenue) if revenue > 0 else 0.0
        totals[status] += 1
        total_revenue += revenue
        total_cogs += cogs

        status_label = COGS_STATUS_LABELS.get(status, status)
        click.echo(
            f"{r['order_id']:<10}{r['order_ref'][:17]:<18}"
            f"{revenue:>16,.2f}{cogs:>16,.2f}{ratio*100:>9.1f}%{status_label:>16}"
        )

    click.echo("-" * 86)
    overall_ratio = (total_cogs / total_revenue) if total_revenue > 0 else 0.0
    click.echo(
        f"{LBL_TOTAL_UPPER:<28}{total_revenue:>16,.2f}{total_cogs:>16,.2f}"
        f"{overall_ratio*100:>9.1f}%"
    )
    click.echo("")
    summary_parts = [
        f"{COGS_STATUS_LABELS[status]}={totals[status]}" for status in COGS_STATUSES
    ]
    click.echo(f"{LBL_ORDERS} {len(rows)}  {LBL_STATUS}: {', '.join(summary_parts)}")


# Order lifecycle statuses in canonical display order (FR2/FR6). All 7
# OrderStatus enum values appear in the report output even when no orders
# are present in that status.
ORDER_REPORT_STATUSES = (
    OrderStatus.NEW.value,
    OrderStatus.CONFIRMED.value,
    OrderStatus.IN_PROGRESS.value,
    OrderStatus.READY.value,
    OrderStatus.DELIVERED.value,
    OrderStatus.COMPLETED.value,
    OrderStatus.CANCELLED.value,
)


@report_cmd.command("order-status")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def order_status_cmd(since, until):
    """Order counts and total value grouped by status and delivery type.

    Outputs a text table to stdout. Orders are grouped by lifecycle status
    (new, confirmed, in_progress, ready, delivered, completed, cancelled)
    with a sub-breakdown by ``delivery_type`` inside each status group,
    showing order count (COUNT) and total value (SUM of total_price) per
    group. A grand total row reports the overall count and value across
    all statuses. All 7 statuses always appear, even when count=0.

    ``--since`` / ``--until`` filter orders by ``COALESCE(NULLIF(due_date,
    ''), created_at)`` — the same business-event date used by the
    cogs-audit report. Cancelled orders are included.
    """
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header(ORDER_STATUS_TITLE, since, until)

    params: list = []
    where_clauses: list = []
    if since_b:
        where_clauses.append("COALESCE(NULLIF(o.due_date, ''), o.created_at) >= ?")
        params.append(since_b)
    if until_b:
        where_clauses.append("COALESCE(NULLIF(o.due_date, ''), o.created_at) <= ?")
        params.append(until_b)
    where_sql = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

    with get_db() as conn:
        rows = conn.execute(
            f"""
            SELECT o.status          AS status,
                   COALESCE(o.delivery_type, '') AS delivery_type,
                   COUNT(*)           AS cnt,
                   COALESCE(SUM(o.total_price), 0) AS total_value
            FROM orders o
            {where_sql}
            GROUP BY o.status, COALESCE(o.delivery_type, '')
            """,
            params,
        ).fetchall()

    # Build a lookup: status -> {delivery_type -> (count, value)}.
    by_status: dict[str, dict[str, tuple[int, float]]] = {
        s: {} for s in ORDER_REPORT_STATUSES
    }
    for r in rows:
        status = r["status"]
        dtype = r["delivery_type"] or ""
        count = int(r["cnt"])
        value = float(r["total_value"] or 0)
        by_status[status][dtype] = (count, value)

    click.echo(
        f"{LBL_STATUS:<16}{LBL_DELIVERY_TYPE:<22}{LBL_COUNT:>10}{LBL_VALUE:>20}"
    )
    click.echo("-" * 68)

    grand_count = 0
    grand_value = 0.0
    for status in ORDER_REPORT_STATUSES:
        status_count = 0
        status_value = 0.0
        sub = by_status.get(status, {})
        status_label = ORDER_STATUS_LABELS.get(status, status)
        # Sort delivery types with empty-string (NULL) first for stable output.
        for dtype in sorted(sub, key=lambda d: (d == "", d)):
            count, value = sub[dtype]
            status_count += count
            status_value += value
            display_dt = dtype if dtype else LBL_NONE
            click.echo(
                f"{status_label:<16}{display_dt[:21]:<22}{count:>10,}{value:>20,.2f}"
            )
        if not sub:
            click.echo(f"{status_label:<16}{LBL_NONE:<22}{0:>10,}{0.0:>20,.2f}")
        click.echo(f"  {LBL_SUBTOTAL:<14}{'':<22}{status_count:>10,}{status_value:>20,.2f}")
        click.echo("-" * 68)
        grand_count += status_count
        grand_value += status_value

    click.echo(
        f"{LBL_GRAND_TOTAL:<38}{grand_count:>10,}{grand_value:>20,.2f}"
    )


# ---------------------------------------------------------------------------
# cashflow (DG-300 Phase 1)
# ---------------------------------------------------------------------------
# Constants and operating-activity query helpers live in the shared
# ``baker.services.cashflow`` module (DG-386 review Mn-2) so the reporting API
# and this CLI share a single source of truth. Re-imported here for the
# CLI-only cashflow command below; behavior is unchanged.
from baker.services.cashflow import (  # noqa: E402
    CASH_ACCOUNT_CODES,
    CASHFLOW_RECONCILIATION_TOLERANCE,
    FINANCING_SOURCE_TYPES,
    FIXED_ASSETS_CODE,
    OPERATING_INFLOW_SOURCE_TYPES,
    OPERATING_OUTFLOW_SOURCE_TYPES,
    cash_account_placeholders,
    query_cash_period_activity,
    query_supplier_category_breakdown,
    sum_section,
)


def _query_investing_cash_activity(
    conn, since_b: str | None, until_b: str | None,
) -> tuple[float, float, dict[str, dict[str, float]]]:
    """Investing-activity cash flows: cash-side movements of entries touching 1600.

    A journal entry is treated as investing when at least one of its lines is
    on the fixed-asset account 1600. The cash side of that entry (debit to a
    cash account = inflow from disposal, credit from a cash account = outflow
    for purchase) is reported here. Returns
    ``(total_inflow, total_outflow, per_account)``.
    """
    placeholders = cash_account_placeholders(CASH_ACCOUNT_CODES)
    params: list = list(CASH_ACCOUNT_CODES)
    where_clauses = [f"a.code IN ({placeholders})"]
    if since_b:
        where_clauses.append("je.transaction_date >= ?")
        params.append(since_b)
    if until_b:
        where_clauses.append("je.transaction_date <= ?")
        params.append(until_b)
    where_clauses.append(
        "EXISTS ("
        " SELECT 1 FROM journal_lines jl2"
        " JOIN accounts a2 ON a2.id = jl2.account_id"
        " WHERE jl2.journal_entry_id = je.id AND a2.code = ?"
        ")"
    )
    params.append(FIXED_ASSETS_CODE)
    where_sql = " AND ".join(where_clauses)

    rows = conn.execute(
        f"""
        SELECT a.code         AS account_code,
               COALESCE(SUM(jl.debit), 0)  AS inflow,
               COALESCE(SUM(jl.credit), 0) AS outflow
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE {where_sql}
        GROUP BY a.code
        """,
        params,
    ).fetchall()

    total_in = 0.0
    total_out = 0.0
    per_account: dict[str, dict[str, float]] = {}
    for r in rows:
        code = r["account_code"]
        inflow = float(r["inflow"])
        outflow = float(r["outflow"])
        total_in += inflow
        total_out += outflow
        per_account[code] = {"inflow": inflow, "outflow": outflow}
    return total_in, total_out, per_account


def _query_cash_account_names(conn) -> dict[str, str]:
    """Return ``{code: name}`` for all cash accounts (DG-300 Phase 2)."""
    placeholders = cash_account_placeholders(CASH_ACCOUNT_CODES)
    rows = conn.execute(
        f"""
        SELECT a.code AS code, a.name AS name
        FROM accounts a
        WHERE a.code IN ({placeholders})
        """,
        list(CASH_ACCOUNT_CODES),
    ).fetchall()
    return {r["code"]: r["name"] for r in rows}


def _query_cash_balance(
    conn, until_b: str | None, *, inclusive: bool = False,
) -> dict[str, float]:
    """Cumulative cash-account balances (debit − credit).

    When ``until_b`` is given and ``inclusive`` is False (the opening-balance
    case), only entries with ``transaction_date < until_b`` are summed. When
    ``inclusive`` is True (the closing-balance case), entries with
    ``transaction_date <= until_b`` are summed. A ``None`` ``until_b`` means
    "all time" (no upper bound).
    """
    placeholders = cash_account_placeholders(CASH_ACCOUNT_CODES)
    params: list = list(CASH_ACCOUNT_CODES)
    where_clauses = [f"a.code IN ({placeholders})"]
    if until_b:
        op = "<=" if inclusive else "<"
        where_clauses.append(f"je.transaction_date {op} ?")
        params.append(until_b)
    where_sql = " AND ".join(where_clauses)

    rows = conn.execute(
        f"""
        SELECT a.code AS account_code,
               COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
        FROM accounts a
        LEFT JOIN journal_lines jl ON jl.account_id = a.id
        LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
        WHERE {where_sql}
        GROUP BY a.code
        """,
        params,
    ).fetchall()
    return {r["account_code"]: float(r["balance"]) for r in rows}


def _echo_cashflow_subsection(
    title: str, per_account: dict[str, dict[str, float]],
    total_inflow: float, total_outflow: float, indent: str = "  ",
) -> None:
    """Print a cashflow sub-section: title, per-account lines, subtotal."""
    click.echo(f"{indent}{title}")
    click.echo(f"{indent}{'-' * len(title)}")
    if not per_account:
        click.echo(f"{indent}{LBL_NO_ACTIVITY}")
    else:
        for code in sorted(per_account):
            mov = per_account[code]
            net = mov["inflow"] - mov["outflow"]
            click.echo(
                f"{indent}  {code:<8}{mov['inflow']:>20,.2f}"
                f"{mov['outflow']:>20,.2f}{net:>20,.2f}"
            )
    click.echo(
        f"{indent}  {LBL_SUBTOTAL_UPPER:<8}{total_inflow:>20,.2f}"
        f"{total_outflow:>20,.2f}{(total_inflow - total_outflow):>20,.2f}"
    )
    click.echo("")


def _echo_supplier_category_breakdown(
    breakdown: dict, children_of: dict[str, list[str]], indent: str = "    ",
) -> None:
    """Print the category/subcategory tree for cash paid to suppliers.

    Mirrors the formatting pattern of ``expense_by_category_cmd``
    (report.py:825-848): a header row, one line per parent category (with
    its total), indented subcategory lines for parents that have children
    defined in ``expense_categories``, an uncategorized line when present,
    and a grand-total row. ``indent`` shifts the whole block right so it
    aligns with the cashflow subsection's per-account lines (4 spaces).

    The breakdown totals are purely additive — they do NOT replace the
    section subtotal printed by ``_echo_cashflow_subsection`` (which comes
    from ``sum_section`` over ``OPERATING_OUTFLOW_SOURCE_TYPES`` and
    includes ``order_shipping_release`` entries that carry no category
    data).
    """
    totals: dict[str, float] = breakdown["totals"]
    sub_totals: dict[str, dict[str, float]] = breakdown["sub_totals"]
    uncategorized: float = breakdown["uncategorized"]

    if not totals and not uncategorized:
        return

    click.echo(f"{indent}{LBL_CATEGORY:<32}{LBL_TOTAL:>20}")
    click.echo(f"{indent}{'-' * 52}")
    grand_total = 0.0
    for category in sorted(totals):
        amount = totals[category]
        grand_total += amount
        click.echo(f"{indent}{category[:31]:<32}{amount:>20,.2f}")
        # FR5/AC5: subcategory breakdown for parent categories that have
        # children defined in the expense_categories table.
        subs = sub_totals.get(category, {})
        if category in children_of:
            for sub_name in children_of[category]:
                sub_amount = subs.get(sub_name, 0.0)
                click.echo(f"{indent}  {sub_name[:30]:<30}{sub_amount:>20,.2f}")
            # Legacy/other subcategory values not in the seed tree (AC6).
            known = set(children_of[category])
            for sub_name in sorted(subs):
                if sub_name not in known:
                    sub_amount = subs[sub_name]
                    click.echo(f"{indent}  {sub_name[:30]:<30}{sub_amount:>20,.2f}")
    if uncategorized:
        grand_total += uncategorized
        click.echo(f"{indent}{LBL_UNCATEGORIZED:<32}{uncategorized:>20,.2f}")
    click.echo(f"{indent}{'-' * 52}")
    click.echo(f"{indent}{LBL_TOTAL_UPPER:<32}{grand_total:>20,.2f}")
    click.echo("")


@report_cmd.command("cashflow")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def cashflow_cmd(since, until):
    """Direct-method cashflow statement for a date range.

    Classifies cash movements on the bakery's cash accounts (1100, 1200,
    1210, 1220, 1290) into operating, investing, and financing activities and
    reconciles the net cash flow against the change in cash-account balances
    for the period.

    Operating activities are sub-sectioned into:
      - Cash from customers (payment_transaction inflows + refunds)
      - Cash paid to suppliers/employees (expense + expense_settlement outflows)

    Investing activities capture cash flows on account 1600 (Tài sản cố định):
    journal entries that touch account 1600 are reported here, and the cash
    side of those entries is excluded from operating to avoid double-counting.

    Financing activities capture owner_capital contributions and owner_draw
    withdrawals on cash accounts.

    The report is read-only (SELECT only). Journal sync must be current for
    accurate numbers — run ``baker repair-payment-journal`` if totals look off.
    """
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    # Reject an inverted range (--since later than --until) up front rather
    # than emitting a confusing report with a [MISMATCH] reconciliation
    # (DG-300 Phase 3, edge case #6). Same-day ranges are allowed: the
    # normalized ``until_b`` carries a ``T23:59:59`` suffix so it always
    # sorts after the bare ``since_b`` for the same calendar day.
    if since_b and until_b and since_b > until_b:
        raise click.BadParameter(
            f"--since ({since}) must not be later than --until ({until}).",
            param_hint="Use a date range where --since is on or before --until.",
        )
    _echo_header(CASHFLOW_TITLE, since, until)

    with get_db() as conn:
        # Opening balance: cumulative cash-account balances before --since.
        # `_query_cash_balance` applies ``je.transaction_date < since_b`` so a
        # None since_b means no opening bound (opening = 0 for all accounts).
        if since_b:
            opening_by_account = _query_cash_balance(conn, since_b, inclusive=False)
        else:
            # No --since ⇒ the period starts at the beginning of time, so the
            # opening balance is zero by definition (there is nothing before
            # the first entry). Querying with no upper bound would otherwise
            # sum every entry ever recorded and produce a false [MISMATCH].
            opening_by_account = {code: 0.0 for code in CASH_ACCOUNT_CODES}
        # Closing balance: cumulative cash-account balances up to and including
        # --until (inclusive upper bound). None until_b → all-time balance.
        closing_by_account = _query_cash_balance(conn, until_b, inclusive=True)
        # Period activity grouped by source_type (excludes 1600-touching entries).
        period_activity = query_cash_period_activity(conn, since_b, until_b)
        # Investing activity: cash side of entries that touch account 1600.
        investing_in, investing_out, investing_per = _query_investing_cash_activity(
            conn, since_b, until_b
        )
        # Account names for the per-account breakdown table (DG-300 Phase 2).
        account_names = _query_cash_account_names(conn)
        # Category/subcategory tree for the supplier section (DG-327 Phase 2).
        # ``children_of`` maps parent category -> sorted list of child
        # subcategory names; only categories with children get an indented
        # subcategory block (FR5/AC5). ``supplier_breakdown`` is the
        # totals/sub_totals/uncategorized tree from
        # ``query_supplier_category_breakdown`` (Phase 1), which also
        # returns ``children_of`` so we do not re-issue the identical
        # ``expense_categories`` parent/child query here (DG-327
        # deduplication — previously this block ran a second query at
        # report.py:1648-1662).
        supplier_breakdown = query_supplier_category_breakdown(
            conn, since_b, until_b,
        )
        children_of: dict[str, list[str]] = supplier_breakdown["children_of"]

    # ---- Aggregate sections ----
    cust_in, cust_out, cust_per = sum_section(
        period_activity, OPERATING_INFLOW_SOURCE_TYPES,
    )
    sup_in, sup_out, sup_per = sum_section(
        period_activity, OPERATING_OUTFLOW_SOURCE_TYPES,
    )
    oper_in = cust_in + sup_in
    oper_out = cust_out + sup_out

    fin_in, fin_out, fin_per = sum_section(
        period_activity, FINANCING_SOURCE_TYPES,
    )

    total_inflow = oper_in + investing_in + fin_in
    total_outflow = oper_out + investing_out + fin_out
    net_cash_flow = total_inflow - total_outflow

    opening_total = sum(opening_by_account.values())
    closing_total = sum(closing_by_account.values())

    # ---- Per-account period activity (DG-300 Phase 2, FR6/AC6) ----
    # Aggregate inflows/outflows across operating, investing, and financing
    # sections for each cash account so the standalone breakdown table shows
    # the total period movement per account.
    per_account_activity: dict[str, dict[str, float]] = {}
    for per in (cust_per, sup_per, investing_per, fin_per):
        for code, mov in per.items():
            per_account_activity.setdefault(
                code, {"inflow": 0.0, "outflow": 0.0}
            )
            per_account_activity[code]["inflow"] += mov["inflow"]
            per_account_activity[code]["outflow"] += mov["outflow"]

    # ---- Print sections ----
    click.echo(LBL_OPERATING_ACTIVITIES)
    click.echo("=" * len(LBL_OPERATING_ACTIVITIES))
    _echo_cashflow_subsection(
        LBL_CASH_FROM_CUSTOMERS, cust_per, cust_in, cust_out, indent="  ",
    )
    _echo_cashflow_subsection(
        LBL_CASH_PAID_SUPPLIERS, sup_per, sup_in, sup_out, indent="  ",
    )
    # Category/subcategory tree for cash paid to suppliers (DG-327 Phase 2,
    # FR1/FR5/FR6). Purely additive output — the section subtotal above
    # comes from ``sum_section`` over ``OPERATING_OUTFLOW_SOURCE_TYPES``
    # (includes ``order_shipping_release``) and is unchanged.
    _echo_supplier_category_breakdown(supplier_breakdown, children_of)
    click.echo(
        f"  {LBL_NET_OPERATING_CASHFLOW:<28}{oper_in:>20,.2f}"
        f"{oper_out:>20,.2f}{(oper_in - oper_out):>20,.2f}"
    )
    click.echo("")

    click.echo(LBL_INVESTING_ACTIVITIES)
    click.echo("=" * len(LBL_INVESTING_ACTIVITIES))
    if not investing_per:
        click.echo(f"  {LBL_NO_ACTIVITY}")
    else:
        for code in sorted(investing_per):
            mov = investing_per[code]
            net = mov["inflow"] - mov["outflow"]
            click.echo(
                f"  {code:<8}{mov['inflow']:>20,.2f}{mov['outflow']:>20,.2f}"
                f"{net:>20,.2f}"
            )
    click.echo(
        f"  {LBL_NET_INVESTING_CASHFLOW:<28}{investing_in:>20,.2f}"
        f"{investing_out:>20,.2f}{(investing_in - investing_out):>20,.2f}"
    )
    click.echo("")

    click.echo(LBL_FINANCING_ACTIVITIES)
    click.echo("=" * len(LBL_FINANCING_ACTIVITIES))
    if not fin_per:
        click.echo(f"  {LBL_NO_ACTIVITY}")
    else:
        for code in sorted(fin_per):
            mov = fin_per[code]
            net = mov["inflow"] - mov["outflow"]
            click.echo(
                f"  {code:<8}{mov['inflow']:>20,.2f}{mov['outflow']:>20,.2f}"
                f"{net:>20,.2f}"
            )
    click.echo(
        f"  {LBL_NET_FINANCING_CASHFLOW:<28}{fin_in:>20,.2f}"
        f"{fin_out:>20,.2f}{(fin_in - fin_out):>20,.2f}"
    )
    click.echo("")

    # ---- Reconciliation ----
    click.echo("=" * 88)
    click.echo(f"{LBL_TOTAL_INFLOWS:<48}{total_inflow:>20,.2f}")
    click.echo(f"{LBL_TOTAL_OUTFLOWS:<48}{total_outflow:>20,.2f}")
    click.echo(f"{LBL_NET_CASH_FLOW:<48}{net_cash_flow:>20,.2f}")
    click.echo("")
    click.echo(f"{LBL_OPENING_BALANCE:<48}{opening_total:>20,.2f}")
    click.echo(f"{LBL_CLOSING_BALANCE:<48}{closing_total:>20,.2f}")
    expected_change = closing_total - opening_total
    imbalance = abs(net_cash_flow - expected_change)
    status = LBL_RECONCILE_OK if imbalance <= CASHFLOW_RECONCILIATION_TOLERANCE else LBL_RECONCILE_MISMATCH
    click.echo(
        f"{LBL_RECONCILIATION_DETAIL:<48}{expected_change:>20,.2f}"
        f"  [{status}]"
    )
    click.echo("")

    # ---- Per-account breakdown (DG-300 Phase 2, FR6/AC6) ----
    # Standalone table showing each cash account's inflows, outflows, net
    # change, opening balance, and closing balance for the period. Aggregates
    # across operating, investing, and financing activity.
    click.echo(LBL_PER_ACCOUNT_BREAKDOWN)
    click.echo("=" * len(LBL_PER_ACCOUNT_BREAKDOWN))
    click.echo(
        f"{LBL_CODE:<8}{LBL_ACCOUNT:<32}{LBL_INFLOWS:>14}{LBL_OUTFLOWS:>14}"
        f"{LBL_NET:>14}{LBL_OPENING:>14}{LBL_CLOSING:>14}"
    )
    click.echo("-" * 110)
    total_in = 0.0
    total_out = 0.0
    total_opening = 0.0
    total_closing = 0.0
    for code in CASH_ACCOUNT_CODES:
        name = account_names.get(code, "")
        mov = per_account_activity.get(code, {"inflow": 0.0, "outflow": 0.0})
        inflow = mov["inflow"]
        outflow = mov["outflow"]
        net = inflow - outflow
        opening = opening_by_account.get(code, 0.0)
        closing = closing_by_account.get(code, 0.0)
        total_in += inflow
        total_out += outflow
        total_opening += opening
        total_closing += closing
        click.echo(
            f"{code:<8}{name[:31]:<32}{inflow:>14,.2f}{outflow:>14,.2f}"
            f"{net:>14,.2f}{opening:>14,.2f}{closing:>14,.2f}"
        )
    click.echo("-" * 110)
    click.echo(
        f"{LBL_TOTAL_UPPER:<40}{total_in:>14,.2f}{total_out:>14,.2f}"
        f"{(total_in - total_out):>14,.2f}{total_opening:>14,.2f}"
        f"{total_closing:>14,.2f}"
    )