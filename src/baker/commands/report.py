"""``baker report`` CLI group — accounting financial reports (FR5).

Provides six read-only subcommands that aggregate ``journal_entries`` /
``journal_lines`` into human-readable text reports printed to stdout:

- ``trial-balance``      — per-account debit/credit/balance totals for a date range
- ``income-statement``   — Revenue − COGS − Expenses = Net Income for a date range
- ``balance-sheet``      — Assets / Liabilities / Equity snapshot as of an end date
- ``general-ledger``     — all journal entries (with lines) in a date range
- ``account-ledger``     — per-account journal line history (requires ``--account-code``)
- ``expense-by-category``— expense totals grouped by source event category

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
from baker.db.schema import COGS_CODE


# Account types whose natural balance is debit - credit (asset/expense).
DEBIT_NORMAL_TYPES = ("asset", "expense")


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
def income_statement_cmd(since, until):
    """Revenue − COGS − Expenses = Net Income for a date range."""
    since_b = _normalize_date(since)
    until_b = _normalize_date(until, end_of_day=True)
    _echo_header("Income Statement", since, until)

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

    # COGS is account code COGS_CODE (an expense sub-account). Report it
    # separately from operating expenses for clarity.
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

    total_expense = net("expense")  # includes COGS (debit - credit for expense accounts)
    operating_expenses = total_expense - cogs_amount

    click.echo(f"{'Revenue':<40}{revenue:>20,.2f}")
    click.echo(f"{'Cost of Goods Sold (5900)':<40}{cogs_amount:>20,.2f}")
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
                f"#{je['id']}  {je['transaction_date']}  {je['description']}  "
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
                f"{r['transaction_date']}  #{r['entry_id']:<6}{movement}  "
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