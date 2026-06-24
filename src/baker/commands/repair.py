"""``baker repair-order-revenue`` CLI command (DG-190 Phase 4.2).

Repairs stale order-revenue journal entries whose 2100 (Customer Deposits)
debit no longer matches the order's current net deposits
(deposits − tien_rut refunds; ``PaymentTransaction.total_paid_net``).

The repair deletes the existing ``source_type = 'order'`` journal entry and
re-runs :func:`_sync_delivered_order_journal` to recreate it with the current
net deposit amounts. The command is idempotent: entries already within 0.005 of
the net deposits are skipped.

Modes:
- ``--order-id <id>`` — repair a single order
- ``--all``           — repair every delivered/completed order with a stale entry
- ``--dry-run``       — show what would change without mutating the database
  (works with both ``--order-id`` and ``--all``)

Only delivered/completed orders are considered. Orders without a revenue entry
(or with an accounts-receivable entry that has no 2100 debit) are reported as
"không áp dụng" (not applicable).

All user-facing labels are in Vietnamese (VN label policy). Exit code is 0 on
success and 1 on error; errors are written to stderr only — following the
existing ``validate-accounts`` pattern.
"""

import click

from baker.db.connection import get_db
from baker.models.payment_transaction import PaymentTransaction
from baker.services.journal_sync import (
    _delete_journal_entry_cascade,
    _is_locked,
    _sync_delivered_order_journal,
)


# Order statuses eligible for revenue repair.
DELIVERED_STATUSES = ("delivered", "completed")
# Customer Deposits account code — the debit side of a paid-order revenue entry.
CUSTOMER_DEPOSITS_CODE = "2100"
# Tolerance (VND) below which an entry is considered already correct.
MISMATCH_TOLERANCE = 0.005


def _vn_amount(amount: float) -> str:
    """Format a VND amount with Vietnamese thousand separators (dot) and no decimals.

    Example: 1500000 -> "1.500.000".
    """
    return f"{int(round(amount)):,}".replace(",", ".")


def _order_revenue_2100_debit(conn, order_id: int):
    """Return ``(entry_id, debit_2100)`` for the order's revenue journal entry.

    Looks up the ``source_type = 'order'`` entry and sums the debit on the
    2100 (Customer Deposits) account. Returns ``(None, 0.0)`` when the order has
    no revenue entry or the entry has no 2100 debit line (e.g. an AR entry).
    """
    row = conn.execute(
        """
        SELECT je.id AS entry_id, COALESCE(SUM(jl.debit), 0) AS debit_2100
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ? AND a.code = ?
        GROUP BY je.id
        """,
        (order_id, CUSTOMER_DEPOSITS_CODE),
    ).fetchone()
    if row is None:
        return None, 0.0
    return int(row["entry_id"]), float(row["debit_2100"])


def _order_ref(conn, order_id: int) -> str:
    row = conn.execute(
        "SELECT order_ref FROM orders WHERE id = ?", (order_id,)
    ).fetchone()
    return row["order_ref"] if row else f"#{order_id}"


def _process_order(conn, order_id: int, *, dry_run: bool) -> dict:
    """Evaluate and optionally repair one order's revenue entry.

    Returns a result dict with keys: order_id, order_ref, old_debit, net_deposits,
    action (one of 'repaired', 'skipped', 'not-applicable', 'locked', 'will-repair').
    """
    order_ref = _order_ref(conn, order_id)
    entry_id, old_debit = _order_revenue_2100_debit(conn, order_id)
    net = PaymentTransaction.total_paid_net(conn, order_id)

    if entry_id is None:
        # No revenue entry with a 2100 debit — nothing to repair.
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "old_debit": old_debit,
            "net_deposits": net,
            "action": "not-applicable",
        }

    mismatch = abs(old_debit - net)
    if mismatch <= MISMATCH_TOLERANCE:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "old_debit": old_debit,
            "net_deposits": net,
            "action": "skipped",
        }

    if _is_locked(conn, entry_id):
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "old_debit": old_debit,
            "net_deposits": net,
            "action": "locked",
        }

    if dry_run:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "old_debit": old_debit,
            "net_deposits": net,
            "action": "will-repair",
        }

    _delete_journal_entry_cascade(conn, entry_id)
    _sync_delivered_order_journal(conn, order_id, order_ref)
    return {
        "order_id": order_id,
        "order_ref": order_ref,
        "old_debit": old_debit,
        "net_deposits": net,
        "action": "repaired",
    }


# Vietnamese action labels for the report table.
_ACTION_LABELS = {
    "repaired": "đã sửa",
    "skipped": "bỏ qua",
    "not-applicable": "không áp dụng",
    "locked": "khoá",
    "will-repair": "sẽ sửa",
}


@click.command("repair-order-revenue")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần sửa.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả đơn đã giao có bút toán lệch.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_order_revenue_cmd(order_id, repair_all, dry_run):
    """Sửa bút toán doanh thu đơn hàng bị lệch (nợ 2100 ≠ cọc thực tế)."""
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    with get_db() as conn:
        if repair_all:
            rows = conn.execute(
                f"""
                SELECT DISTINCT je.source_id AS order_id
                FROM journal_entries je
                JOIN journal_lines jl ON jl.journal_entry_id = je.id
                JOIN accounts a ON a.id = jl.account_id
                JOIN orders o ON o.id = je.source_id
                WHERE je.source_type = 'order'
                  AND a.code = ?
                  AND o.status IN ({",".join("?" * len(DELIVERED_STATUSES))})
                ORDER BY je.source_id ASC
                """,
                [CUSTOMER_DEPOSITS_CODE, *DELIVERED_STATUSES],
            ).fetchall()
            order_ids = [int(r["order_id"]) for r in rows]
        else:
            order_ids = [order_id]

        results = []
        for oid in order_ids:
            results.append(_process_order(conn, oid, dry_run=dry_run))
        if not dry_run:
            conn.commit()

    if not results:
        click.echo("(không có đơn hàng nào để kiểm tra)")
        return

    click.echo("Sửa bút toán doanh thu đơn hàng")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Nợ 2100 cũ':>16}{'Cọc thực tế':>16}{'Hành động':<16}"
    )
    click.echo("-" * 68)
    for r in results:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{_vn_amount(r['old_debit']):>16}"
            f"{_vn_amount(r['net_deposits']):>16}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 68)

    repaired = sum(1 for r in results if r["action"] == "repaired")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")
    skipped = sum(1 for r in results if r["action"] == "skipped")
    not_applicable = sum(1 for r in results if r["action"] == "not-applicable")
    locked = sum(1 for r in results if r["action"] == "locked")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair}")
    else:
        parts.append(f"đã sửa: {repaired}")
    parts.append(f"bỏ qua: {skipped}")
    parts.append(f"không áp dụng: {not_applicable}")
    if locked:
        parts.append(f"khoá: {locked}")
    click.echo(f"Tổng: {len(results)} đơn  |  " + ", ".join(parts))