"""``baker report`` CLI group — accounting financial reports (FR5).

Provides six read-only subcommands that aggregate ``journal_entries`` /
``journal_lines`` into human-readable text reports printed to stdout:

- ``trial-balance``      — per-account debit/credit/balance totals for a date range
- ``income-statement``   — Revenue − COGS − Expenses = Net Income for a date range
- ``balance-sheet``      — Assets / Liabilities / Equity snapshot as of an end date
- ``general-ledger``     — all journal entries (with lines) in a date range
- ``account-ledger``     — per-account journal line history (requires ``--account-code``)
- ``expense-by-category``— expense totals grouped by source event category
- ``cogs-audit``         — per-order COGS completeness and ratio audit (FR4)

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
from baker.models.order import OrderStatus
from baker.utils.time import utc_to_local


# Account types whose natural balance is debit - credit (asset/expense).
DEBIT_NORMAL_TYPES = ("asset", "expense")

# Statuses used by the COGS audit report (FR4 / AC4):
#   ok         — COGS entry exists, no zero-cost items, ratio >= COGS_LOW_RATIO
#   missing    — no order_cogs journal entry recorded for the order
#   zero-cost  — order_cogs entry exists but some non-extra/non-gift order_items
#                still have cost_at_sale = 0 (cost never resolved at delivery)
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


def _echo_header(title: str, since: Optional[str], until: Optional[str]) -> None:
    click.echo(title)
    click.echo("=" * len(title))
    period = "All time"
    if since and until:
        period = f"{since} → {until}"
    elif since:
        period = f"since {since}"
    elif until:
        period = f"until {until}"
    click.echo(f"Period: {period}")
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
    _echo_header("Trial Balance", since, until)

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
        click.echo("(no journal entries in range)")
        return

    total_debit = 0.0
    total_credit = 0.0
    click.echo(f"{'Code':<8}{'Account':<40}{'Type':<10}{'Debit':>14}{'Credit':>14}")
    click.echo("-" * 86)
    for r in rows:
        debit = float(r["total_debit"])
        credit = float(r["total_credit"])
        total_debit += debit
        total_credit += credit
        click.echo(
            f"{r['code']:<8}{r['name'][:39]:<40}{r['type']:<10}"
            f"{debit:>14,.2f}{credit:>14,.2f}"
        )
    click.echo("-" * 86)
    click.echo(f"{'TOTALS':<58}{total_debit:>14,.2f}{total_credit:>14,.2f}")


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
        _echo_header("Income Statement (due-date basis)", since, until)
    else:
        _echo_header("Income Statement", since, until)

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

    _echo_income_statement_body(revenue, cogs_amount, operating_expenses)


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

    _echo_income_statement_body(revenue, cogs_amount, operating_expenses)


def _echo_income_statement_body(
    revenue: float, cogs_amount: float, operating_expenses: float,
) -> None:
    """Print the income statement body lines (shared between bases)."""
    click.echo(f"{'Revenue':<40}{revenue:>20,.2f}")
    cogs_ratio = (cogs_amount / revenue * 100.0) if revenue > 0 else 0.0
    click.echo(
        f"{'Cost of Goods Sold (5900)':<40}{cogs_amount:>20,.2f}"
        f"  ({cogs_ratio:.1f}%)"
    )
    click.echo(f"{'Gross Profit':<40}{(revenue - cogs_amount):>20,.2f}")
    click.echo("")
    click.echo(f"{'Operating Expenses':<40}{operating_expenses:>20,.2f}")
    click.echo("")
    net_income = revenue - cogs_amount - operating_expenses
    click.echo(f"{'Net Income':<40}{net_income:>20,.2f}")


@report_cmd.command("balance-sheet")
@click.option("--until", help="As-of date (YYYY-MM-DD, inclusive)")
def balance_sheet_cmd(until):
    """Assets, Liabilities, Equity snapshot as of the end date."""
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header("Balance Sheet", None, until)

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

    def section(title: str, acc_type: str) -> float:
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
        click.echo(f"  {'Total ' + title:<48}{section_total:>14,.2f}")
        click.echo("")
        return section_total

    total_assets = section("Assets", "asset")
    total_liabilities = section("Liabilities", "liability")
    total_equity = section("Equity", "equity")
    click.echo("=" * 62)
    click.echo(f"{'Total Assets':<48}{total_assets:>14,.2f}")
    click.echo(f"{'Total Liabilities + Equity':<48}"
               f"{(total_liabilities + total_equity):>14,.2f}")


@report_cmd.command("general-ledger")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def general_ledger_cmd(since, until):
    """All journal entries in a date range, human-readable with lines."""
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header("General Ledger", since, until)

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
            click.echo("(no journal entries in range)")
            return

        for je in entries:
            click.echo(
                f"#{je['id']}  {utc_to_local(je['transaction_date'])}  {je['description']}  "
                f"[source={je['source_type']}:{je['source_id']}]"
                + ("  (LOCKED)" if je["locked_at"] else "")
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
                    click.echo(f"    DR  {jl['code']:<8}{jl['name'][:30]:<32}{debit:>14,.2f}  {jl['description']}")
                else:
                    click.echo(f"    CR  {jl['code']:<8}{jl['name'][:30]:<32}{credit:>14,.2f}  {jl['description']}")
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

        _echo_header(f"Account Ledger — {account['code']} {account['name']}", since, until)

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
            click.echo("(no journal lines for this account in range)")
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
                movement = f"DR {debit:>12,.2f}"
            else:
                movement = f"CR {credit:>12,.2f}"
            click.echo(
                f"{utc_to_local(r['transaction_date'])}  #{r['entry_id']:<6}{movement}  "
                f"balance={running:>14,.2f}  {r['line_description']}"
            )


@report_cmd.command("expense-by-category")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def expense_by_category_cmd(since, until):
    """Expense totals grouped by source event category for a date range."""
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header("Expense by Category", since, until)

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
            click.echo("(no expense journal entries in range)")
            return

        # Aggregate by category from events.data JSON, falling back to the
        # debited account name when the event/data is unavailable.
        totals: dict[str, float] = {}
        uncategorized = 0.0
        for r in rows:
            category = None
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
                    except (json.JSONDecodeError, TypeError):
                        pass
            if category:
                totals[category] = totals.get(category, 0.0) + float(r["debit"])
            else:
                uncategorized += float(r["debit"])

        click.echo(f"{'Category':<32}{'Total':>20}")
        click.echo("-" * 52)
        grand_total = 0.0
        for category in sorted(totals):
            amount = totals[category]
            grand_total += amount
            click.echo(f"{category[:31]:<32}{amount:>20,.2f}")
        if uncategorized:
            grand_total += uncategorized
            click.echo(f"{'(uncategorized)':<32}{uncategorized:>20,.2f}")
        click.echo("-" * 52)
        click.echo(f"{'TOTAL':<32}{grand_total:>20,.2f}")


@report_cmd.command("cogs-audit")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD, inclusive)")
def cogs_audit_cmd(since, until):
    """Audit COGS completeness and ratio per delivered/completed order.

    Outputs a table (order_id, revenue, cogs, ratio, status) for every
    delivered/completed order in the date range. Status flags:

      ok         — COGS entry exists, no zero-cost items, ratio in range
      missing    — no order_cogs journal entry recorded
      zero-cost  — order has non-extra/non-gift items with cost_at_sale = 0
      low        — COGS/revenue ratio below the baseline estimate threshold

    A summary line reports totals and the count of orders in each status.
    Exit code is 0 on success (regardless of flagged orders — this is a
    read-only audit report, not a pass/fail gate).
    """
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header("COGS Audit", since, until)

    # Single-pass query joining orders → order_items → journal entries. We
    # gather, per order:
    #   - total revenue from `order` journal entries (4100 credit side)
    #   - total COGS from `order_cogs` journal entries (5900 debit side)
    #   - count of non-extra/non-gift order_items with cost_at_sale = 0
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
                       AND oi.is_extra = 0
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
        click.echo("(no delivered/completed orders in range)")
        return

    # Header
    click.echo(
        f"{'Order':<10}{'Order Ref':<18}{'Revenue':>16}{'COGS':>16}"
        f"{'Ratio':>10}{'Status':>14}"
    )
    click.echo("-" * 84)

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

        click.echo(
            f"{r['order_id']:<10}{r['order_ref'][:17]:<18}"
            f"{revenue:>16,.2f}{cogs:>16,.2f}{ratio*100:>9.1f}%{status:>14}"
        )

    click.echo("-" * 84)
    overall_ratio = (total_cogs / total_revenue) if total_revenue > 0 else 0.0
    click.echo(
        f"{'TOTAL':<28}{total_revenue:>16,.2f}{total_cogs:>16,.2f}"
        f"{overall_ratio*100:>9.1f}%"
    )
    click.echo("")
    summary_parts = [f"{status}={totals[status]}" for status in COGS_STATUSES]
    click.echo(f"Orders: {len(rows)}  Status: {', '.join(summary_parts)}")


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
    _echo_header("Order Status Report", since, until)

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
        # Preserve unknown statuses as-is (defensive — schema enum should
        # cover all values, but the report must not drop unknown data).
        by_status.setdefault(status, {})[dtype] = (count, value)

    click.echo(
        f"{'Status':<14}{'Delivery Type':<20}{'Count':>10}{'Value':>20}"
    )
    click.echo("-" * 64)

    grand_count = 0
    grand_value = 0.0
    for status in ORDER_REPORT_STATUSES:
        status_count = 0
        status_value = 0.0
        sub = by_status.get(status, {})
        # Sort delivery types with empty-string (NULL) first for stable output.
        for dtype in sorted(sub, key=lambda d: (d == "", d)):
            count, value = sub[dtype]
            status_count += count
            status_value += value
            display_dt = dtype if dtype else "(none)"
            click.echo(
                f"{status:<14}{display_dt[:19]:<20}{count:>10,}{value:>20,.2f}"
            )
        if not sub:
            click.echo(f"{status:<14}{'(none)':<20}{0:>10,}{0.0:>20,.2f}")
        click.echo(f"{'  subtotal':<14}{'':<20}{status_count:>10,}{status_value:>20,.2f}")
        click.echo("-" * 64)
        grand_count += status_count
        grand_value += status_value

    click.echo(
        f"{'GRAND TOTAL':<34}{grand_count:>10,}{grand_value:>20,.2f}"
    )