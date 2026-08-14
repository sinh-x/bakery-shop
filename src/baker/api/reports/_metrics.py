"""Shared summary-metrics query helpers for the reporting API.

Extracted from ``baker.api.reports`` (DG-386 review Mn2, cycle 5). The
four cash/bank/cash-in/cash-out aggregate metric queries were duplicated
nearly verbatim between ``get_today_summary`` and
``get_period_summary``. :func:`summary_metrics` collapses them into a
single helper parameterized by the timestamp bounds, so both endpoints
call it with their respective ``(start_ts, end_ts)`` pair.

DG-391 Phase 1 / cycle-1 fix: revenue is computed from ``journal_lines``
credits to account 4100 (Doanh thu bán hàng), bucketed by due date for
order-sourced entries — ``COALESCE(o.due_date, DATE(je.transaction_date))``
for entries whose ``source_type`` is ``order``/``order_cogs`` (LEFT JOIN
``orders`` on ``je.source_id = o.id``), and ``je.transaction_date`` for
non-order entries. This mirrors ``baker report income-statement
--date-basis due-date`` (``_income_statement_due_date``) so the summary
reconciles with the income-statement CLI, preserves the DG-376
partial-payment invariant (revenue = recognized journal credit, NOT
``total_price``), and satisfies FR3 (revenue bucketed by ``due_date``).
``period_start_date``/``period_end_date`` bound the order-sourced
date-string comparison; ``start_ts``/``end_ts`` bound the non-order
timestamp comparison.
"""

from __future__ import annotations

from baker.db.schema import _account_id_by_code


# Bank account codes used by payment_transaction journal routing.
BANK_ACCOUNT_CODES = ("1200", "1210", "1220", "1290")


def summary_metrics(
    conn,
    start_ts: str,
    end_ts: str,
    *,
    period_start_date: str,
    period_end_date: str,
    fallback_sources: tuple[str, ...] = (),
) -> dict[str, float]:
    """Return the six aggregate summary metrics for ``[start_ts, end_ts)``.

    Computes:

    - ``revenue`` — sum of ``journal_lines.credit`` for account 4100,
      bucketed by due date for order-sourced entries
      (``COALESCE(o.due_date, DATE(je.transaction_date))`` within
      ``[period_start_date, period_end_date]``) and by
      ``je.transaction_date`` for non-order entries (within
      ``[start_ts, end_ts)``). Mirrors
      ``_income_statement_due_date`` so the summary reconciles with the
      income-statement CLI (``--date-basis due-date``) and preserves the
      DG-376 partial-payment invariant (FR3 / AC3).
    - ``cashTotal`` — sum of debits to 1101 from ``payment_transaction``,
      via ``journal_lines`` + ``journal_entries`` join with a half-open
      ``>= start_ts AND < end_ts`` transaction-date bound.
    - ``bankTransferTotal`` — sum of debits to 1200/1210/1220/1290 from
      ``payment_transaction``.
    - ``cashInTotal`` — sum of debits to 1101 from
      ``cash_drawer_cash_in`` (DG-378).
    - ``cashOutTotal`` — sum of credits to 1101 from
      ``cash_drawer_cash_out`` (DG-378).

    ``fallback_sources`` is accepted for call-site compatibility but is
    no longer used now that revenue is journal-based (order-sourced
    entries are detected via ``je.source_type`` rather than
    ``orders.source``).

    Returns a dict keyed by those five names; values are ``float``.
    """
    revenue = _revenue_from_journal(
        conn,
        period_start_date=period_start_date,
        period_end_date=period_end_date,
        start_ts=start_ts,
        end_ts=end_ts,
    )

    cash_acc_id = _account_id_by_code(conn, "1101")
    cash_row = conn.execute(
        """SELECT COALESCE(SUM(jl.debit), 0) AS total
           FROM journal_lines jl
           JOIN journal_entries je ON je.id = jl.journal_entry_id
           WHERE jl.account_id = ?
             AND je.source_type = 'payment_transaction'
             AND je.transaction_date >= ?
             AND je.transaction_date < ?""",
        (cash_acc_id, start_ts, end_ts),
    ).fetchone()
    cash_total = float(cash_row["total"] or 0)

    bank_acc_ids = [_account_id_by_code(conn, code) for code in BANK_ACCOUNT_CODES]
    placeholders = ",".join("?" for _ in bank_acc_ids)
    bank_row = conn.execute(
        f"""SELECT COALESCE(SUM(jl.debit), 0) AS total
            FROM journal_lines jl
            JOIN journal_entries je ON je.id = jl.journal_entry_id
            WHERE jl.account_id IN ({placeholders})
              AND je.source_type = 'payment_transaction'
              AND je.transaction_date >= ?
              AND je.transaction_date < ?""",
        [*bank_acc_ids, start_ts, end_ts],
    ).fetchone()
    bank_total = float(bank_row["total"] or 0)

    cash_in_row = conn.execute(
        """SELECT COALESCE(SUM(jl.debit), 0) AS total
           FROM journal_lines jl
           JOIN journal_entries je ON je.id = jl.journal_entry_id
           WHERE jl.account_id = ?
             AND je.source_type = 'cash_drawer_cash_in'
             AND je.transaction_date >= ?
             AND je.transaction_date < ?""",
        (cash_acc_id, start_ts, end_ts),
    ).fetchone()
    cash_in_total = float(cash_in_row["total"] or 0)

    cash_out_row = conn.execute(
        """SELECT COALESCE(SUM(jl.credit), 0) AS total
           FROM journal_lines jl
           JOIN journal_entries je ON je.id = jl.journal_entry_id
           WHERE jl.account_id = ?
             AND je.source_type = 'cash_drawer_cash_out'
             AND je.transaction_date >= ?
             AND je.transaction_date < ?""",
        (cash_acc_id, start_ts, end_ts),
    ).fetchone()
    cash_out_total = float(cash_out_row["total"] or 0)

    return {
        "revenue": revenue,
        "cashTotal": cash_total,
        "bankTransferTotal": bank_total,
        "cashInTotal": cash_in_total,
        "cashOutTotal": cash_out_total,
    }


def _revenue_from_journal(
    conn,
    *,
    period_start_date: str,
    period_end_date: str,
    start_ts: str,
    end_ts: str,
) -> float:
    """Sum ``journal_lines.credit`` for account 4100, bucketed by due date.

    Order-sourced entries (``je.source_type IN ('order', 'order_cogs')``)
    are bucketed by ``COALESCE(o.due_date, DATE(je.transaction_date))``
    within ``[period_start_date, period_end_date]`` (inclusive
    date-string comparison). Non-order entries are bucketed by
    ``je.transaction_date`` within ``[start_ts, end_ts)`` (half-open
    timestamp comparison).

    This mirrors ``_income_statement_due_date`` in
    ``baker.commands.report`` so the summary reconciles with the
    income-statement CLI in ``--date-basis due-date`` mode, preserves the
    DG-376 partial-payment invariant (revenue = recognized journal
    credit — NOT ``orders.total_price``), and satisfies FR3 (revenue
    bucketed by ``due_date``).
    """
    revenue_acc_id = _account_id_by_code(conn, "4100")
    row = conn.execute(
        """SELECT COALESCE(SUM(jl.credit), 0) AS total
             FROM journal_lines jl
             JOIN journal_entries je ON je.id = jl.journal_entry_id
             LEFT JOIN orders o
               ON je.source_type IN ('order', 'order_cogs')
              AND je.source_id = o.id
            WHERE jl.account_id = ?
              AND (
                (je.source_type IN ('order', 'order_cogs')
                 AND COALESCE(o.due_date, DATE(je.transaction_date)) >= ?
                 AND COALESCE(o.due_date, DATE(je.transaction_date)) <= ?)
                OR
                (je.source_type NOT IN ('order', 'order_cogs')
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?)
              )""",
        (
            revenue_acc_id,
            period_start_date, period_end_date,
            start_ts, end_ts,
        ),
    ).fetchone()
    return float(row["total"] or 0)