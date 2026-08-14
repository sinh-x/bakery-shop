"""Shared summary-metrics query helpers for the reporting API.

Extracted from ``baker.api.reports`` (DG-386 review Mn2, cycle 5). The
five aggregate metric queries (revenue 4100 credit, cash 1101 debit,
bank debit, cash-in 1101 debit, cash-out 1101 credit) were duplicated
nearly verbatim between ``get_today_summary`` and
``get_period_summary``. :func:`summary_metrics` collapses them into a
single helper parameterized by the timestamp bounds, so both endpoints
call it with their respective ``(start_ts, end_ts)`` pair.

Behavior is identical to the prior inline implementation — only the
module location changed. The order-list query is intentionally NOT
included here because its parameters differ between the day and period
endpoints (single ``due_date`` vs. ``due_date`` range) and the day
endpoint returns a different response shape.
"""

from __future__ import annotations

from baker.db.schema import _account_id_by_code


# Bank account codes used by payment_transaction journal routing.
BANK_ACCOUNT_CODES = ("1200", "1210", "1220", "1290")


def summary_metrics(
    conn, start_ts: str, end_ts: str,
) -> dict[str, float]:
    """Return the six aggregate summary metrics for ``[start_ts, end_ts)``.

    Computes, with the ``journal_lines`` + ``journal_entries`` join and a
    half-open ``>= start_ts AND < end_ts`` transaction-date bound:

    - ``revenue`` — sum of credits to account 4100 (Doanh thu bán hàng).
    - ``cashTotal`` — sum of debits to 1101 from ``payment_transaction``.
    - ``bankTransferTotal`` — sum of debits to 1200/1210/1220/1290 from
      ``payment_transaction``.
    - ``cashInTotal`` — sum of debits to 1101 from
      ``cash_drawer_cash_in`` (DG-378).
    - ``cashOutTotal`` — sum of credits to 1101 from
      ``cash_drawer_cash_out`` (DG-378).

    Returns a dict keyed by those five names; values are ``float``.
    """
    revenue_acc_id = _account_id_by_code(conn, "4100")
    revenue_row = conn.execute(
        """SELECT COALESCE(SUM(jl.credit), 0) AS total
           FROM journal_lines jl
           JOIN journal_entries je ON je.id = jl.journal_entry_id
           WHERE jl.account_id = ?
             AND je.transaction_date >= ?
             AND je.transaction_date < ?""",
        (revenue_acc_id, start_ts, end_ts),
    ).fetchone()
    revenue = float(revenue_row["total"] or 0)

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