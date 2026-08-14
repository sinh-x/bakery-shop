"""Shared summary-metrics query helpers for the reporting API.

Extracted from ``baker.api.reports`` (DG-386 review Mn2, cycle 5). The
four cash/bank/cash-in/cash-out aggregate metric queries were duplicated
nearly verbatim between ``get_today_summary`` and
``get_period_summary``. :func:`summary_metrics` collapses them into a
single helper parameterized by the timestamp bounds, so both endpoints
call it with their respective ``(start_ts, end_ts)`` pair.

DG-391 Phase 1: revenue is now computed from ``orders.total_price`` for
orders whose effective date (``due_date`` with POS/reconciliation
fallback to ``created_at``) falls within the period — mirroring the
order-list query and aligning revenue with cash-in over the same period.
Previously revenue summed ``journal_lines`` credits to account 4100
filtered by ``journal_entries.transaction_date``, which bucketed by the
recognition date rather than the business-event (due) date. The order-list
query is intentionally NOT included here because its parameters differ
between the day and period endpoints (single ``due_date`` vs.
``due_date`` range) and the day endpoint returns a different response
shape.
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

    - ``revenue`` — sum of ``orders.total_price`` for orders whose effective
      date (``due_date``; POS/reconciliation sources fall back to
      ``created_at`` when ``due_date`` is NULL/empty) falls within the
      period ``[period_start_date, period_end_date]`` (inclusive). This
      aligns revenue with the order-list and cash-in over the same period
      (DG-391 Phase 1 / FR3). ``fallback_sources`` is the tuple of source
      labels whose orders use ``created_at`` when ``due_date`` is empty.
    - ``cashTotal`` — sum of debits to 1101 from ``payment_transaction``,
      via ``journal_lines`` + ``journal_entries`` join with a half-open
      ``>= start_ts AND < end_ts`` transaction-date bound.
    - ``bankTransferTotal`` — sum of debits to 1200/1210/1220/1290 from
      ``payment_transaction``.
    - ``cashInTotal`` — sum of debits to 1101 from
      ``cash_drawer_cash_in`` (DG-378).
    - ``cashOutTotal`` — sum of credits to 1101 from
      ``cash_drawer_cash_out`` (DG-378).

    Returns a dict keyed by those five names; values are ``float``.
    """
    revenue = _revenue_from_orders(
        conn,
        period_start_date=period_start_date,
        period_end_date=period_end_date,
        start_ts=start_ts,
        end_ts=end_ts,
        fallback_sources=fallback_sources,
    )

    cash_acc_id = _account_id_by_code(conn, "1101")

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


def _revenue_from_orders(
    conn,
    *,
    period_start_date: str,
    period_end_date: str,
    start_ts: str,
    end_ts: str,
    fallback_sources: tuple[str, ...],
) -> float:
    """Sum ``orders.total_price`` for orders due within the period.

    Orders with a non-empty ``due_date`` in ``[period_start_date,
    period_end_date]`` (inclusive date-string comparison) contribute their
    ``total_price``. Orders whose ``due_date`` is NULL/empty and whose
    ``source`` is in ``fallback_sources`` (POS / reconciliation) fall back
    to ``created_at`` within ``[start_ts, end_ts)`` — mirroring the
    order-list query in ``period.py`` and ``today-summary`` (FR3 / AC3).

    The ``fallback_sources`` tuple may be empty, in which case the
    fallback branch is omitted from the query.
    """
    fallback_branch = ""
    fallback_params: list = []
    if fallback_sources:
        placeholders = ",".join("?" for _ in fallback_sources)
        fallback_branch = (
            " OR ("
            "  (orders.due_date IS NULL OR orders.due_date = '')"
            f"  AND orders.source IN ({placeholders})"
            "  AND orders.created_at >= ?"
            "  AND orders.created_at < ?"
            ")"
        )
        fallback_params = [*fallback_sources, start_ts, end_ts]

    row = conn.execute(
        f"""SELECT COALESCE(SUM(orders.total_price), 0) AS total
            FROM orders
            WHERE (
                orders.due_date >= ? AND orders.due_date <= ?
                {fallback_branch}
            )""",
        [period_start_date, period_end_date, *fallback_params],
    ).fetchone()
    return float(row["total"] or 0)