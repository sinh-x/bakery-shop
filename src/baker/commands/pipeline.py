"""``baker pipeline`` CLI group — revenue pipeline visibility reports (DG-190 Phase 4.1).

Provides five read-only subcommands that surface revenue-pipeline gaps without
mutating the database:

- ``undelivered-deposits`` — orders not yet delivered/completed/cancelled that hold deposits
- ``cancelled-unrefunded``  — cancelled orders where deposits exceed refunds
- ``deposit-revenue-gap``   — per-order reconciliation of net deposits vs 2100 debits
                              in revenue journal entries (surfaces the refund double-debit)
- ``refunds``               — all outflow (``refund``/``tien_rut``) transactions with order context
- ``new-no-deposit``        — new/pending orders with zero deposits

All commands print to stdout with exit code 0 on success and non-zero on error;
errors are written to stderr only — following the existing ``validate-accounts``
pattern. User-facing labels are in Vietnamese (VN label policy).
"""

import logging

import click

from baker.db.connection import get_db
from baker.db.schema import CUSTOMER_DEPOSITS_CODE, PAYMENT_OUTFLOW_TYPES, REVENUE_UPDATE_TOLERANCE

logger = logging.getLogger(__name__)


# Order statuses considered "delivered" for revenue-recognition purposes.
DELIVERED_STATUSES = ("delivered", "completed")
# Statuses excluded from the undelivered-deposits report (already recognised or voided).
UNDELIVERED_EXCLUDED = ("delivered", "completed", "cancelled")
# Statuses considered "new/pending" for the new-no-deposit report.
NEW_PENDING_STATUSES = ("new", "confirmed")
# Outflow transaction types (refund, tien_rut) as a tuple for deterministic SQL
# IN-clause parameterization. Mirrors baker.db.schema.PAYMENT_OUTFLOW_TYPES;
# kept as a tuple so the placeholder count is stable per process (review Mn-1).
_OUTFLOW_TYPES = tuple(PAYMENT_OUTFLOW_TYPES)
# Tolerance (VND) shared with repair/sync so the mismatch count and repair
# decisions use the same threshold (review finding Mn-1).
_GAP_MISMATCH_TOLERANCE = REVENUE_UPDATE_TOLERANCE


def _vn_amount(amount: float) -> str:
    """Format a VND amount with Vietnamese thousand separators (dot) and no decimals.

    VND is conventionally whole-dong; decimals are not used in practice.
    Example: 1500000 -> "1.500.000".
    """
    return f"{int(round(amount)):,}".replace(",", ".")


def _echo_header(title: str) -> None:
    click.echo(title)
    click.echo("=" * len(title))
    click.echo("")


def _report_cli_error() -> None:
    """Print a Vietnamese error message to stderr and exit with code 1.

    Used as a catch-all guard around read-only pipeline/repair commands so a
    missing, corrupted, or schema-mismatched database surfaces a readable
    message instead of a raw Python traceback (review finding Mn-3). Internal
    exception details are logged server-side via :func:`logger.exception`, not
    echoed to the user (review finding Mn-7). The active exception context is
    captured automatically by ``logger.exception`` (review finding Mn-2).
    """
    logger.exception("Pipeline CLI error")
    click.echo(
        "Lỗi khi truy vấn dữ liệu. Xem log máy chủ để biết chi tiết.",
        err=True,
    )
    raise SystemExit(1)


@click.group("pipeline")
def pipeline_cmd():
    """Báo cáo dòng tiền doanh thu — các báo cáo chỉ-đọc về dòng tiền đơn hàng."""


@pipeline_cmd.command("undelivered-deposits")
def undelivered_deposits_cmd():
    """Đơn hàng chưa giao nhưng đã có tiền đặt — doanh thu tiềm năng tương lai."""
    _echo_header("Đơn chưa giao có tiền đặt (Doanh thu tiềm năng)")

    try:
        with get_db() as conn:
            rows = conn.execute(
                f"""
                SELECT o.order_ref     AS order_ref,
                       o.customer_name AS customer_name,
                       o.status        AS status,
                       o.due_date      AS due_date,
                       o.total_price   AS total_price,
                       COALESCE(pt.total_deposits, 0) AS total_deposits
                FROM orders o
                LEFT JOIN (
                    SELECT order_id, SUM(amount) AS total_deposits
                    FROM payment_transactions
                    WHERE type NOT IN ({",".join("?" * len(_OUTFLOW_TYPES))})
                    GROUP BY order_id
                ) pt ON pt.order_id = o.id
                WHERE o.status NOT IN ({",".join("?" * len(UNDELIVERED_EXCLUDED))})
                  AND COALESCE(pt.total_deposits, 0) > 0
                ORDER BY o.due_date IS NULL, o.due_date ASC, o.order_ref ASC
                """,
                [*_OUTFLOW_TYPES, *UNDELIVERED_EXCLUDED],
            ).fetchall()
    except Exception as exc:  # noqa: BLE001 — top-level CLI guard
        _report_cli_error()

    if not rows:
        click.echo("(không có đơn hàng chưa giao có tiền đặt)")
        return

    click.echo(
        f"{'Mã đơn':<20}{'Khách hàng':<24}{'Trạng thái':<14}"
        f"{'Ngày giao':<14}{'Tiền đặt':>16}{'Tổng tiền':>16}"
    )
    click.echo("-" * 104)
    total_deposits = 0.0
    for r in rows:
        deposits = float(r["total_deposits"])
        total_deposits += deposits
        click.echo(
            f"{r['order_ref'][:19]:<20}{r['customer_name'][:23]:<24}"
            f"{r['status']:<14}{(r['due_date'] or '-')[:13]:<14}"
            f"{_vn_amount(deposits):>16}{_vn_amount(float(r['total_price'] or 0)):>16}"
        )
    click.echo("-" * 104)
    click.echo(f"{'TỔNG TIỀN ĐẶT':<72}{_vn_amount(total_deposits):>16}")


@pipeline_cmd.command("cancelled-unrefunded")
def cancelled_unrefunded_cmd():
    """Đơn đã huỷ nhưng tiền đặt chưa hoàn — cọc chưa hoàn trả."""
    _echo_header("Đơn đã huỷ có cọc chưa hoàn")

    try:
        with get_db() as conn:
            rows = conn.execute(
                f"""
                SELECT o.order_ref     AS order_ref,
                       o.customer_name AS customer_name,
                       COALESCE(d.total_deposits, 0) AS total_deposits,
                       COALESCE(r.total_refunds, 0)  AS total_refunds
                FROM orders o
                LEFT JOIN (
                    SELECT order_id, SUM(amount) AS total_deposits
                    FROM payment_transactions
                    WHERE type NOT IN ({",".join("?" * len(_OUTFLOW_TYPES))})
                    GROUP BY order_id
                ) d ON d.order_id = o.id
                LEFT JOIN (
                    SELECT order_id, SUM(amount) AS total_refunds
                    FROM payment_transactions
                    WHERE type IN ({",".join("?" * len(_OUTFLOW_TYPES))})
                    GROUP BY order_id
                ) r ON r.order_id = o.id
                WHERE o.status = 'cancelled'
                  AND COALESCE(d.total_deposits, 0) > COALESCE(r.total_refunds, 0)
                ORDER BY o.order_ref ASC
                """,
                [*_OUTFLOW_TYPES, *_OUTFLOW_TYPES],
            ).fetchall()
    except Exception as exc:  # noqa: BLE001 — top-level CLI guard
        _report_cli_error()

    if not rows:
        click.echo("(không có đơn đã huỷ có cọc chưa hoàn)")
        return

    click.echo(
        f"{'Mã đơn':<20}{'Khách hàng':<24}{'Tiền đặt':>16}{'Đã hoàn':>16}{'Chưa hoàn':>16}"
    )
    click.echo("-" * 92)
    total_net = 0.0
    for r in rows:
        deposits = float(r["total_deposits"])
        refunds = float(r["total_refunds"])
        net = deposits - refunds
        total_net += net
        click.echo(
            f"{r['order_ref'][:19]:<20}{r['customer_name'][:23]:<24}"
            f"{_vn_amount(deposits):>16}{_vn_amount(refunds):>16}{_vn_amount(net):>16}"
        )
    click.echo("-" * 92)
    click.echo(f"{'TỔNG CHƯA HOÀN':<44}{_vn_amount(total_net):>16}")


@pipeline_cmd.command("deposit-revenue-gap")
def deposit_revenue_gap_cmd():
    """Đối chiếu cọc thực tế (cọc − tiền rút) với nợ 2100 trong bút toán doanh thu — phát hiện lệch."""
    _echo_header("Đối chiếu cọc ↔ doanh thu (2100)")

    try:
        with get_db() as conn:
            # Per delivered/completed order: net deposits (deposits − tien_rut
            # refunds) vs the 2100 debit recorded in the order revenue journal
            # entry. Revenue recognition (Phase 4.3) debits 2100 for net deposits,
            # so this is the correct reconciliation basis.
            rows = conn.execute(
                f"""
                SELECT o.id            AS order_id,
                       o.order_ref     AS order_ref,
                       o.customer_name AS customer_name,
                       COALESCE(d.total_deposits, 0) - COALESCE(r.total_refunds, 0) AS net_deposits,
                       COALESCE(rev.debit_2100, 0)    AS debit_2100
                FROM orders o
                LEFT JOIN (
                    SELECT order_id, SUM(amount) AS total_deposits
                    FROM payment_transactions
                    WHERE type NOT IN ({",".join("?" * len(_OUTFLOW_TYPES))})
                    GROUP BY order_id
                ) d ON d.order_id = o.id
                LEFT JOIN (
                    SELECT order_id, SUM(amount) AS total_refunds
                    FROM payment_transactions
                    WHERE type IN ({",".join("?" * len(_OUTFLOW_TYPES))})
                    GROUP BY order_id
                ) r ON r.order_id = o.id
                LEFT JOIN (
                    SELECT je.source_id AS order_id, SUM(jl.debit) AS debit_2100
                    FROM journal_entries je
                    JOIN journal_lines jl ON jl.journal_entry_id = je.id
                    JOIN accounts a ON a.id = jl.account_id
                    WHERE je.source_type = 'order'
                      AND a.code = ?
                    GROUP BY je.source_id
                ) rev ON rev.order_id = o.id
                WHERE o.status IN ({",".join("?" * len(DELIVERED_STATUSES))})
                ORDER BY o.order_ref ASC
                """,
                [*_OUTFLOW_TYPES, *_OUTFLOW_TYPES, CUSTOMER_DEPOSITS_CODE, *DELIVERED_STATUSES],
            ).fetchall()
    except Exception as exc:  # noqa: BLE001 — top-level CLI guard
        _report_cli_error()

    if not rows:
        click.echo("(không có đơn đã giao để đối chiếu)")
        return

    click.echo(
        f"{'Mã đơn':<20}{'Khách hàng':<24}{'Cọc thực tế':>16}{'Nợ 2100':>16}{'Lệch':>16}"
    )
    click.echo("-" * 92)
    agg_deposits = 0.0
    agg_debit = 0.0
    agg_gap = 0.0
    mismatch_count = 0
    for r in rows:
        deposits = float(r["net_deposits"])
        debit = float(r["debit_2100"])
        gap = deposits - debit
        agg_deposits += deposits
        agg_debit += debit
        agg_gap += gap
        if abs(gap) > _GAP_MISMATCH_TOLERANCE:
            mismatch_count += 1
        click.echo(
            f"{r['order_ref'][:19]:<20}{r['customer_name'][:23]:<24}"
            f"{_vn_amount(deposits):>16}{_vn_amount(debit):>16}{_vn_amount(gap):>16}"
        )
    click.echo("-" * 92)
    click.echo(
        f"{'TỔNG':<44}{_vn_amount(agg_deposits):>16}{_vn_amount(agg_debit):>16}"
        f"{_vn_amount(agg_gap):>16}"
    )
    click.echo("")
    click.echo(
        f"Số đơn lệch: {mismatch_count}/{len(rows)}  |  Chênh lệch tổng: {_vn_amount(agg_gap)}"
    )


@pipeline_cmd.command("refunds")
def refunds_cmd():
    """Tất cả giao dịch tiền rút (refund/tien_rut) kèm thông tin đơn hàng."""
    _echo_header("Giao dịch tiền rút (refund / tien_rut)")

    try:
        with get_db() as conn:
            placeholders = ",".join("?" * len(_OUTFLOW_TYPES))
            rows = conn.execute(
                f"""
                SELECT pt.id          AS pt_id,
                       pt.amount       AS amount,
                       pt.type         AS type,
                       pt.method       AS method,
                       pt.created_at   AS created_at,
                       pt.note         AS note,
                       o.order_ref     AS order_ref,
                       o.customer_name AS customer_name,
                       o.status        AS status
                FROM payment_transactions pt
                JOIN orders o ON o.id = pt.order_id
                WHERE pt.type IN ({placeholders})
                ORDER BY pt.created_at DESC, pt.id DESC
                """,
                _OUTFLOW_TYPES,
            ).fetchall()
    except Exception as exc:  # noqa: BLE001 — top-level CLI guard
        _report_cli_error()

    if not rows:
        click.echo("(không có giao dịch tiền rút)")
        return

    click.echo(
        f"{'Mã đơn':<20}{'Khách hàng':<24}{'Loại':<10}{'Số tiền':>16}{'PT#':>8}"
        f"{'Ngày':<20}{'Trạng thái':<14}"
    )
    click.echo("-" * 112)
    total = 0.0
    for r in rows:
        amount = float(r["amount"])
        total += amount
        click.echo(
            f"{r['order_ref'][:19]:<20}{r['customer_name'][:23]:<24}"
            f"{r['type']:<10}{_vn_amount(amount):>16}{r['pt_id']:>8}"
            f"{(r['created_at'] or '-')[:19]:<20}{r['status']:<14}"
        )
    click.echo("-" * 112)
    click.echo(f"{'TỔNG TIỀN RÚT':<54}{_vn_amount(total):>16}")


@pipeline_cmd.command("new-no-deposit")
def new_no_deposit_cmd():
    """Đơn mới/chờ xác nhận chưa có tiền đặt — cần theo dõi."""
    _echo_header("Đơn mới chưa có tiền đặt")

    try:
        with get_db() as conn:
            placeholders = ",".join("?" * len(NEW_PENDING_STATUSES))
            refund_placeholders = ",".join("?" * len(_OUTFLOW_TYPES))
            rows = conn.execute(
                f"""
                SELECT o.order_ref     AS order_ref,
                       o.customer_name AS customer_name,
                       o.total_price   AS total_price,
                       o.created_at     AS created_at
                FROM orders o
                LEFT JOIN (
                    SELECT order_id, SUM(amount) AS total_deposits
                    FROM payment_transactions
                    WHERE type NOT IN ({refund_placeholders})
                    GROUP BY order_id
                ) pt ON pt.order_id = o.id
                WHERE o.status IN ({placeholders})
                  AND COALESCE(pt.total_deposits, 0) = 0
                ORDER BY o.created_at DESC, o.order_ref ASC
                """,
                [*_OUTFLOW_TYPES, *NEW_PENDING_STATUSES],
            ).fetchall()
    except Exception as exc:  # noqa: BLE001 — top-level CLI guard
        _report_cli_error()

    if not rows:
        click.echo("(không có đơn mới chưa có tiền đặt)")
        return

    click.echo(
        f"{'Mã đơn':<20}{'Khách hàng':<24}{'Tổng tiền':>16}{'Ngày tạo':<20}"
    )
    click.echo("-" * 80)
    total_price = 0.0
    for r in rows:
        price = float(r["total_price"] or 0)
        total_price += price
        click.echo(
            f"{r['order_ref'][:19]:<20}{r['customer_name'][:23]:<24}"
            f"{_vn_amount(price):>16}{(r['created_at'] or '-')[:19]:<20}"
        )
    click.echo("-" * 80)
    click.echo(f"{'TỔNG GIÁ TRỊ':<44}{_vn_amount(total_price):>16}")