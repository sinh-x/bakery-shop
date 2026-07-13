"""``baker repair-order-revenue`` CLI command (DG-190 Phase 4.2).

Repairs stale order-revenue journal entries whose 2100 (Customer Deposits)
debit no longer matches the order's effective deposit balance
(``total_paid_net − total_tien_rut``). ``tien_rut`` journals to 2400
(Tien Rut Held) and is returned separately at delivery, so it must be
excluded from the 2100 debit comparison — matching the logic in
:func:`_reconcile_order_revenue_entry`.

The repair deletes the existing ``source_type = 'order'`` journal entry and
re-runs :func:`_sync_delivered_order_journal` to recreate it with the current
net deposit amounts. The command is idempotent: entries already within 0.005 of
the effective deposit balance are skipped.

Modes:
- ``--order-id <id>`` — repair a single order
- ``--all``           — repair every delivered/completed order with a stale entry
- ``--cogs``          — repair/backfill the ``order_cogs`` journal entry instead
  of the revenue (2100) entry. With ``--cogs --all`` the backfill is scoped to
  delivered/completed orders whose COGS entry is missing or stale; with
  ``--cogs --order-id <id>`` a single order is processed. Idempotent — entries
  within ``REVENUE_UPDATE_TOLERANCE`` (0.005 VND) of the expected total are
  skipped (DG-208 Phase 5, FR8/FR9, NFR1/NFR5, AC6).
- ``--dry-run``       — show what would change without mutating the database
  (works with both ``--order-id`` and ``--all``)

Only delivered/completed orders are considered. Orders without a revenue
entry (or with an accounts-receivable entry that has no 2100 debit) are now
created (action ``"created"`` / ``"will-create"`` in dry-run) instead of being
reported as "không áp dụng". Use ``--since DATE`` to scope ``--all`` repairs
to orders with ``due_date >= DATE`` (requires ``--all``). The companion
``check-revenue-gaps`` command provides a read-only scan of orders missing
revenue entries.

All user-facing labels are in Vietnamese (VN label policy). Exit code is 0 on
success and 1 on error; errors are written to stderr only — following the
existing ``validate-accounts`` pattern.
"""

import json
import logging

import click

from baker.db.connection import get_db
from baker.db.schema import (
    CUSTOMER_DEPOSITS_CODE,
    INVENTORY_PURCHASE_CATEGORIES,
    REVENUE_UPDATE_TOLERANCE,
    TIEN_RUT_HELD_CODE,
)
from baker.formatters import format_vnd_amount
from baker.utils.time import now_utc
from baker.models.payment_transaction import PaymentTransaction
from baker.services.journal_sync import (
    _compute_order_cogs_total,
    _delete_journal_entry_cascade,
    _is_locked,
    _order_cogs_entry,
    _reconcile_order_revenue_entry,
    _reverse_journal_entry,
    _sync_cancelled_order_journal,
    _sync_delivered_order_journal,
    _sync_expense_journal,
    _sync_order_cogs_entry,
    _sync_payment_journal,
    run_journal_sync,
)

logger = logging.getLogger(__name__)


# Order statuses eligible for revenue repair.
DELIVERED_STATUSES = ("delivered", "completed")
# Tolerance (VND) below which an entry is considered already correct.
# Aliased to the centralized constant so repair decisions and the pipeline
# report share one threshold (review finding Mn-1).
MISMATCH_TOLERANCE = REVENUE_UPDATE_TOLERANCE


def _vn_amount(amount: float) -> str:
    """Format a VND amount (thin wrapper over baker.formatters.format_vnd_amount)."""
    return format_vnd_amount(amount)


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
    action (one of 'repaired', 'skipped', 'not-applicable', 'locked', 'will-repair',
    'created', 'will-create').
    """
    order_ref = _order_ref(conn, order_id)
    entry_id, old_debit = _order_revenue_2100_debit(conn, order_id)
    net_deposits = PaymentTransaction.total_paid_net(conn, order_id)
    tien_rut = PaymentTransaction.total_tien_rut(conn, order_id)
    shipping_held = 0.0
    order_row = conn.execute(
        "SELECT delivery_type, shipping_fee FROM orders WHERE id = ?", (order_id,)
    ).fetchone()
    if order_row and (order_row["delivery_type"] or "pickup") == "bus" and float(order_row["shipping_fee"] or 0) > 0:
        shipping_held = float(order_row["shipping_fee"])
    net = max(0.0, net_deposits - tien_rut - shipping_held)

    if entry_id is None:
        if net <= 0:
            return {
                "order_id": order_id,
                "order_ref": order_ref,
                "old_debit": old_debit,
                "net_deposits": net,
                "action": "not-applicable",
            }
        if dry_run:
            return {
                "order_id": order_id,
                "order_ref": order_ref,
                "old_debit": old_debit,
                "net_deposits": net,
                "action": "will-create",
            }
        _sync_delivered_order_journal(conn, order_id, order_ref)
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "old_debit": old_debit,
            "net_deposits": net,
            "action": "created",
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
    "created": "đã tạo",
    "will-create": "sẽ tạo",
    "backfilled": "đã sửa",
    "will-backfill": "sẽ sửa",
    "repaired-with-errors": "đã sửa, có lỗi",
    "cash-only": "chỉ có tiền mặt — cần xem xét",
}


# ---------------------------------------------------------------------------
# ``baker repair-order-revenue --cogs`` — DG-208 Phase 5 COGS backfill
# (FR8, FR9, NFR1, NFR5, AC6)
# ---------------------------------------------------------------------------


def _delivered_orders_with_cogs(conn):
    """Return ids of all delivered/completed orders (FR8 ``--cogs --all`` scan).

    The COGS repair scans every delivered/completed order and reports its
    action (``repaired`` / ``backfilled`` / ``skipped`` / ``locked`` /
    ``not-applicable``). This mirrors the revenue repair's ``--all``
    semantics and is required for AC6: the second idempotent run must
    report every order as ``skipped`` rather than returning an empty list.
    Orders without an ``order_cogs`` entry are also included so a missing
    COGS entry is backfilled on the first run.
    """
    rows = conn.execute(
        f"""
        SELECT DISTINCT o.id AS order_id
        FROM orders o
        WHERE o.status IN ({",".join("?" * len(DELIVERED_STATUSES))})
        ORDER BY o.id ASC
        """,
        list(DELIVERED_STATUSES),
    ).fetchall()
    return [int(r["order_id"]) for r in rows]


def _process_cogs_order(conn, order_id: int, *, dry_run: bool, force: bool = False) -> dict:
    """Evaluate and optionally repair one order's COGS entry (FR8/FR9).

    Idempotent delete-and-recreate pattern (mirrors the revenue repair):
      1. Compute the expected COGS total via :func:`_compute_order_cogs_total`
         (writing back ``cost_at_sale`` for zero-cost items using the current
         cost_history / baseline rule with ``unit_price`` as the anchor).
         When ``force`` is True, re-resolves ALL items (not just zero-cost ones).
      2. Look up the existing ``order_cogs`` entry. When none exists and the
         expected total > 0, create it (action ``backfilled``).
      3. When an entry exists and its COGS debit is within
         ``MISMATCH_TOLERANCE`` of the expected total, skip (action
         ``skipped`` — idempotent no-op, AC6).
      4. When an entry exists but is locked, report ``locked`` (do not mutate).
      5. When an entry exists and is stale, delete it and re-run
         :func:`_sync_order_cogs_entry` to recreate with the current total
         (action ``repaired`` / ``will-repair`` in dry-run).

    Returns a result dict with keys: order_id, order_ref, old_cogs,
    expected_cogs, action.
    """
    order_ref = _order_ref(conn, order_id)
    entry_id, old_cogs = _order_cogs_entry(conn, order_id)
    expected = _compute_order_cogs_total(
        conn, order_id, populate_cost_at_sale=False, force=force
    )

    if entry_id is None:
        if expected <= 0:
            return {
                "order_id": order_id,
                "order_ref": order_ref,
                "old_cogs": old_cogs,
                "expected_cogs": expected,
                "action": "not-applicable",
            }
        if dry_run:
            return {
                "order_id": order_id,
                "order_ref": order_ref,
                "old_cogs": old_cogs,
                "expected_cogs": expected,
                "action": "will-backfill",
            }
        # Populate cost_at_sale and create the missing COGS entry in a single
        # compute pass — the resolved total is passed to _sync_order_cogs_entry
        # via total_cogs_override so it does not re-scan order_items
        # (DG-208 review finding CQ-3).
        actual_total = _compute_order_cogs_total(
            conn, order_id, populate_cost_at_sale=True, force=force
        )
        _sync_order_cogs_entry(
            conn, order_id, order_ref, total_cogs_override=actual_total
        )
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "old_cogs": old_cogs,
            "expected_cogs": expected,
            "action": "backfilled",
        }

    if abs(old_cogs - expected) <= MISMATCH_TOLERANCE:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "old_cogs": old_cogs,
            "expected_cogs": expected,
            "action": "skipped",
        }

    if _is_locked(conn, entry_id):
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "old_cogs": old_cogs,
            "expected_cogs": expected,
            "action": "locked",
        }

    if dry_run:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "old_cogs": old_cogs,
            "expected_cogs": expected,
            "action": "will-repair",
        }

    # Delete the stale COGS entry and recreate with the current total.
    # Populate cost_at_sale once and pass the computed total via
    # total_cogs_override so _sync_order_cogs_entry skips its internal
    # re-scan of order_items (DG-208 review finding CQ-3).
    _delete_journal_entry_cascade(conn, entry_id)
    actual_total = _compute_order_cogs_total(
        conn, order_id, populate_cost_at_sale=True, force=force
    )
    _sync_order_cogs_entry(
        conn, order_id, order_ref, total_cogs_override=actual_total
    )
    return {
        "order_id": order_id,
        "order_ref": order_ref,
        "old_cogs": old_cogs,
        "expected_cogs": expected,
        "action": "repaired",
    }


def _run_cogs_repair(conn, *, order_id, repair_all, dry_run, force=False):
    """Drive the COGS repair for either a single order or all delivered orders.

    Mirrors the revenue repair's ``--all`` semantics: every
    delivered/completed order is scanned and reported with its action
    (``repaired`` / ``backfilled`` / ``skipped`` / ``locked`` /
    ``not-applicable``). This is required for AC6 — the second idempotent
    run must report every order as ``skipped`` rather than an empty list.

    When ``force`` is True, re-resolves ALL items (not just zero-cost ones)
    using the current unit_price-anchored baseline.
    """
    if repair_all:
        order_ids = _delivered_orders_with_cogs(conn)
    else:
        order_ids = [order_id]
    return [
        _process_cogs_order(conn, oid, dry_run=dry_run, force=force) for oid in order_ids
    ]


def _print_cogs_report(results, *, dry_run):
    """Print the COGS repair report table and summary."""
    click.echo("Sửa bút toán giá vốn hàng bán (COGS)")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'COGS cũ':>16}{'COGS dự kiến':>18}{'Hành động':<16}"
    )
    click.echo("-" * 70)
    for r in results:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{_vn_amount(r['old_cogs']):>16}"
            f"{_vn_amount(r['expected_cogs']):>18}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 70)

    repaired = sum(1 for r in results if r["action"] == "repaired")
    backfilled = sum(1 for r in results if r["action"] == "backfilled")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")
    will_backfill = sum(1 for r in results if r["action"] == "will-backfill")
    skipped = sum(1 for r in results if r["action"] == "skipped")
    not_applicable = sum(1 for r in results if r["action"] == "not-applicable")
    locked = sum(1 for r in results if r["action"] == "locked")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair + will_backfill}")
    else:
        parts.append(f"đã sửa: {repaired + backfilled}")
    parts.append(f"bỏ qua: {skipped}")
    parts.append(f"không áp dụng: {not_applicable}")
    if locked:
        parts.append(f"khoá: {locked}")
    click.echo(f"Tổng: {len(results)} đơn  |  " + ", ".join(parts))


@click.command("repair-order-revenue")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần sửa.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả đơn đã giao có bút toán lệch.")
@click.option("--cogs", "repair_cogs", is_flag=True, default=False, help="Sửa/bổ sung bút toán giá vốn (COGS) thay vì doanh thu.")
@click.option("--force", "force_cogs", is_flag=True, default=False, help="Tính lại toàn bộ cost_at_sale (không chỉ dòng = 0). Chỉ dùng với --cogs.")
@click.option("--since", "since_date", type=str, default=None, help="Chỉ xử lý đơn có ngày giao từ DATE trở đi (YYYY-MM-DD). Chỉ dùng với --all.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_order_revenue_cmd(order_id, repair_all, repair_cogs, force_cogs, since_date, dry_run):
    """Sửa bút toán doanh thu đơn hàng bị lệch (nợ 2100 ≠ cọc thực tế).

    Với ``--cogs``, sửa/bổ sung bút toán giá vốn (COGS) cho đơn đã giao:
    bỏ qua đơn đã có bút toán COGS khớp với chi phí dự kiến (idempotent).

    Với ``--cogs --force``, tính lại toàn bộ cost_at_sale cho tất cả mặt hàng
    (kể cả những dòng đã có cost_at_sale > 0) dùng công thức unit_price × 30%.
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)
    if force_cogs and not repair_cogs:
        click.echo("--force chỉ dùng với --cogs.", err=True)
        raise SystemExit(1)
    if since_date and not repair_all:
        click.echo("--since chỉ dùng với --all.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            if repair_cogs:
                results = _run_cogs_repair(
                    conn, order_id=order_id, repair_all=repair_all, dry_run=dry_run, force=force_cogs
                )
            elif repair_all:
                sql = f"""
                    SELECT o.id AS order_id
                    FROM orders o
                    WHERE o.status IN ({",".join("?" * len(DELIVERED_STATUSES))})
                """
                params = list(DELIVERED_STATUSES)
                if since_date:
                    sql += " AND o.due_date >= ?"
                    params.append(since_date)
                sql += " ORDER BY o.id ASC"
                rows = conn.execute(sql, params).fetchall()
                order_ids = [int(r["order_id"]) for r in rows]
                results = [
                    _process_order(conn, oid, dry_run=dry_run) for oid in order_ids
                ]
            else:
                results = [_process_order(conn, order_id, dry_run=dry_run)]

            if not dry_run:
                conn.commit()
    except Exception as exc:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair CLI error")
        click.echo(
            "Lỗi khi sửa bút toán. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng nào để kiểm tra)")
        return

    if repair_cogs:
        _print_cogs_report(results, dry_run=dry_run)
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
    created = sum(1 for r in results if r["action"] == "created")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")
    will_create = sum(1 for r in results if r["action"] == "will-create")
    skipped = sum(1 for r in results if r["action"] == "skipped")
    not_applicable = sum(1 for r in results if r["action"] == "not-applicable")
    locked = sum(1 for r in results if r["action"] == "locked")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair + will_create}")
    else:
        parts.append(f"đã sửa: {repaired + created}")
    parts.append(f"bỏ qua: {skipped}")
    parts.append(f"không áp dụng: {not_applicable}")
    if locked:
        parts.append(f"khoá: {locked}")
    click.echo(f"Tổng: {len(results)} đơn  |  " + ", ".join(parts))


# ---------------------------------------------------------------------------
# ``baker repair-tien-rut-gap`` — DG-198 Phase 5 backfill (FR4, AC4)
# ---------------------------------------------------------------------------


def _tien_rut_orders_needing_backfill(conn):
    """Return order ids with a deposit-revenue gap caused by pre-fix tien_rut.

    An order is affected when it has at least one valid ``tien_rut`` payment
    transaction whose journal entry does NOT credit account 2400 (Tien Rut
    Held). Before the DG-198 reversal, ``tien_rut`` was treated as an outflow
    and debited 2100 (Customer Deposits) directly, overdrawing 2100 and
    skipping revenue recognition. The current correct routing is DR Asset /
    CR 2400 (a deposit inflow).

    The detection is idempotent: once the backfill re-syncs a tien_rut payment
    journal entry to credit 2400, the order drops out of this list, so a
    second run is a no-op (NFR3).
    """
    from baker.models.payment_transaction import _invalidation_filter

    tien_rut_acc_id_row = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (TIEN_RUT_HELD_CODE,)
    ).fetchone()
    if not tien_rut_acc_id_row:
        return []
    tien_rut_acc_id = int(tien_rut_acc_id_row["id"])
    invalidation = _invalidation_filter(conn)

    # payment_transactions with type='tien_rut' whose journal entry has no 2400
    # credit line. An invalidated tien_rut has no journal entry (it was
    # reversed/deleted), so it is naturally excluded.
    rows = conn.execute(
        f"""
        SELECT DISTINCT pt.order_id
        FROM payment_transactions pt
        JOIN journal_entries je
          ON je.source_type = 'payment_transaction' AND je.source_id = pt.id
        WHERE pt.type = 'tien_rut'
          {invalidation}
          AND NOT EXISTS (
              SELECT 1 FROM journal_lines jl
              WHERE jl.journal_entry_id = je.id
                AND jl.account_id = ?
                AND jl.credit > 0
          )
        ORDER BY pt.order_id ASC
        """,
        (tien_rut_acc_id,),
    ).fetchall()
    return [int(r["order_id"]) for r in rows]


def _process_tien_rut_gap_order(conn, order_id: int, *, dry_run: bool) -> dict:
    """Backfill one order's tien_rut deposit-revenue gap (FR4).

    Steps for the live run:
      1. Re-sync each ``tien_rut`` payment journal entry so it credits 2400
         (DR Asset / CR 2400 — the DG-198 reversal inflow routing) instead of
         debiting 2100. Idempotent: re-syncing an entry already on 2400 is a
         no-op.
      2. Reconcile the order's journal entries so deposits→revenue (DR 2100 /
         CR 4100) and tien_rut→return (DR 2400 / CR Asset) are created
         separately via ``_reconcile_order_revenue_entry``. Idempotent within
         ``REVENUE_UPDATE_TOLERANCE``.

    Dry-run reports the gap and the planned actions without mutating.
    """
    from baker.models.payment_transaction import _invalidation_filter

    order_ref = _order_ref(conn, order_id)
    invalidation = _invalidation_filter(conn)
    tien_rut_total = float(
        conn.execute(
            f"""
            SELECT COALESCE(SUM(amount), 0) AS total
            FROM payment_transactions
            WHERE order_id = ? AND type = 'tien_rut'
              {invalidation}
            """,
            (order_id,),
        ).fetchone()["total"]
    )
    net_deposits = PaymentTransaction.total_paid_net(conn, order_id)

    result = {
        "order_id": order_id,
        "order_ref": order_ref,
        "tien_rut_total": tien_rut_total,
        "net_deposits": net_deposits,
        "action": "will-backfill" if dry_run else "backfilled",
    }
    if dry_run:
        return result

    # (1) Re-sync each tien_rut payment journal entry → route to 2400.
    tien_rut_txns = conn.execute(
        f"""
        SELECT id, amount, method
        FROM payment_transactions
        WHERE order_id = ? AND type = 'tien_rut'
          {invalidation}
        ORDER BY id ASC
        """,
        (order_id,),
    ).fetchall()
    for t in tien_rut_txns:
        _sync_payment_journal(
            conn,
            int(t["id"]),
            float(t["amount"]),
            "tien_rut",
            t["method"] or "cash",
            order_id=order_id,
        )

    # (2) Reconcile the revenue entry so it clears 2400 and balances 2100/4100.
    _reconcile_order_revenue_entry(
        conn, order_id, order_ref, respect_locks=True
    )
    return result


@click.command("repair-tien-rut-gap")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần sửa.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả đơn có khoảng trống tiền rút.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_tien_rut_gap_cmd(order_id, repair_all, dry_run):
    """Sửa khoảng trống kế toán tiền rút (chuyển tien_rut sang 2400, cân đối lại doanh thu)."""
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            if repair_all:
                order_ids = _tien_rut_orders_needing_backfill(conn)
            else:
                # Single order: only include it if it actually has the gap.
                affected = set(_tien_rut_orders_needing_backfill(conn))
                order_ids = [order_id] if order_id in affected else []

            results = []
            for oid in order_ids:
                results.append(
                    _process_tien_rut_gap_order(conn, oid, dry_run=dry_run)
                )
            if not dry_run:
                conn.commit()
    except Exception as exc:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair tien-rut-gap CLI error")
        click.echo(
            "Lỗi khi sửa khoảng trống tiền rút. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng nào cần sửa khoảng trống tiền rút)")
        return

    click.echo("Sửa khoảng trống kế toán tiền rút")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Tiền rút':>16}{'Cọc ròng':>16}{'Hành động':<16}"
    )
    click.echo("-" * 68)
    for r in results:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{_vn_amount(r['tien_rut_total']):>16}"
            f"{_vn_amount(r['net_deposits']):>16}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 68)
    click.echo(f"Tổng: {len(results)} đơn cần sửa khoảng trống tiền rút")


# ---------------------------------------------------------------------------
# ``baker check-revenue-gaps`` — DG-229 Phase 4.3 read-only gap detection
# (FR3, NFR3, AC3)
# ---------------------------------------------------------------------------


@click.command("check-revenue-gaps")
def check_revenue_gaps_cmd():
    """Kiểm tra đơn hàng đã giao/hoàn thành thiếu bút toán doanh thu (chỉ đọc)."""
    try:
        with get_db() as conn:
            rows = conn.execute(
                f"""
                SELECT o.id, o.order_ref, o.due_date, o.status, o.total_price
                FROM orders o
                WHERE o.status IN ({",".join("?" * len(DELIVERED_STATUSES))})
                  AND NOT EXISTS (
                      SELECT 1 FROM journal_entries je
                      WHERE je.source_type = 'order' AND je.source_id = o.id
                  )
                ORDER BY o.id ASC
                """,
                list(DELIVERED_STATUSES),
            ).fetchall()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Check revenue gaps CLI error")
        click.echo(
            "Lỗi khi kiểm tra khoảng trống doanh thu. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not rows:
        click.echo("(không có đơn hàng nào thiếu bút toán doanh thu)")
        return

    click.echo("Kiểm tra khoảng trống doanh thu đơn hàng")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Ngày giao':>12}{'Tổng tiền':>14}{'Trạng thái':<14}"
    )
    click.echo("-" * 60)
    for r in rows:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{r['due_date'] or '':>12}"
            f"{_vn_amount(r['total_price']):>14}"
            f"{r['status']:<14}"
        )
    click.echo("-" * 60)
    click.echo(f"Tổng: {len(rows)} đơn thiếu bút toán doanh thu")


# ---------------------------------------------------------------------------
# ``baker repair-payment-journal`` — DG-233 Phase 1 payment journal backfill
# (FR1, AC2, AC7, AC9)
# ---------------------------------------------------------------------------


def _payment_transactions_needing_backfill(conn, order_id=None):
    """Payment transactions without journal entries (non-invalidated).

    Returns rows from payment_transactions that have no matching journal entry
    with source_type = 'payment_transaction'. Invalidated transactions are
    excluded (their journal entry is intentionally reversed/removed).
    """
    sql = """
        SELECT pt.id, pt.amount, pt.type, pt.method, pt.order_id
        FROM payment_transactions pt
        WHERE (pt.invalidated_at IS NULL OR pt.invalidated_at = '')
          AND NOT EXISTS (
              SELECT 1 FROM journal_entries je
              WHERE je.source_type = 'payment_transaction' AND je.source_id = pt.id
          )
    """
    params = []
    if order_id is not None:
        sql += " AND pt.order_id = ?"
        params.append(order_id)
    sql += " ORDER BY pt.id ASC"
    return conn.execute(sql, params).fetchall()


@click.command("repair-payment-journal")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần bổ sung bút toán thanh toán.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Bổ sung bút toán cho tất cả giao dịch thanh toán còn thiếu.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_payment_journal_cmd(order_id, repair_all, dry_run):
    """Bổ sung bút toán nhật ký cho các giao dịch thanh toán còn thiếu.

    Tìm tất cả payment_transactions chưa có bút toán nhật ký tương ứng
    (source_type = 'payment_transaction') và gọi ``_sync_payment_journal``
    để tạo bút toán. Lệnh idempotent: chạy lần hai sẽ không tìm thấy giao
    dịch nào cần bổ sung.
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            txns = _payment_transactions_needing_backfill(
                conn, order_id=order_id
            )

            results = []
            for t in txns:
                txn_id = int(t["id"])
                amount = float(t["amount"] or 0)
                ptype = t["type"]
                method = t["method"] or "cash"
                txn_order_id = int(t["order_id"]) if t["order_id"] is not None else None
                order_ref = _order_ref(conn, txn_order_id) if txn_order_id else "-"

                if dry_run:
                    results.append({
                        "txn_id": txn_id,
                        "amount": amount,
                        "type": ptype,
                        "order_ref": order_ref,
                        "action": "will-backfill",
                    })
                else:
                    _sync_payment_journal(
                        conn, txn_id, amount, ptype, method,
                        order_id=txn_order_id,
                    )
                    results.append({
                        "txn_id": txn_id,
                        "amount": amount,
                        "type": ptype,
                        "order_ref": order_ref,
                        "action": "backfilled",
                    })

            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair payment-journal CLI error")
        click.echo(
            "Lỗi khi bổ sung bút toán thanh toán. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có giao dịch thanh toán nào cần bổ sung bút toán)")
        return

    click.echo("Bổ sung bút toán nhật ký thanh toán")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã GD':<10}{'Số tiền':>16}{'Loại':<14}{'Đơn hàng':<12}{'Hành động':<16}"
    )
    click.echo("-" * 68)
    for r in results:
        order_ref = r.get("order_ref", "-")
        click.echo(
            f"#{r['txn_id']:<9}"
            f"{_vn_amount(r['amount']):>16}"
            f"{r['type']:<14}"
            f"{order_ref[:11]:<12}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 68)

    backfilled = sum(1 for r in results if r["action"] == "backfilled")
    will_backfill = sum(1 for r in results if r["action"] == "will-backfill")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_backfill}")
    else:
        parts.append(f"đã sửa: {backfilled}")
    click.echo(f"Tổng: {len(results)} giao dịch  |  " + ", ".join(parts))


# ---------------------------------------------------------------------------
# ``baker repair-ar-entries`` — DG-233 Phase 2 AR entry backfill
# (FR2, AC8, AC7, AC9)
# ---------------------------------------------------------------------------


def _orders_needing_ar_entry(conn, order_id=None):
    """Find delivered/completed orders needing AR entries.

    Returns orders with total_price > 0, status in DELIVERED_STATUSES,
    no existing ``source_type='order'`` journal entry, and
    ``deposits_in - tien_rut_total <= 0`` (zero net deposits after
    excluding tien_rut — truly unpaid orders that need AR recognition).
    """
    sql = f"""
        SELECT o.id, o.order_ref, o.total_price
        FROM orders o
        WHERE o.status IN ({','.join('?' * len(DELIVERED_STATUSES))})
          AND o.total_price > 0
          AND NOT EXISTS (
              SELECT 1 FROM journal_entries je
              WHERE je.source_type = 'order' AND je.source_id = o.id
          )
    """
    params = list(DELIVERED_STATUSES)
    if order_id is not None:
        sql += " AND o.id = ?"
        params.append(order_id)
    sql += " ORDER BY o.id ASC"

    rows = conn.execute(sql, params).fetchall()

    result = []
    for r in rows:
        oid = int(r["id"])
        deposits_in = PaymentTransaction.total_paid_excl_outflows(conn, oid)
        tien_rut_total = PaymentTransaction.total_tien_rut(conn, oid)
        if deposits_in - tien_rut_total <= 0:
            result.append(r)

    return result


@click.command("repair-ar-entries")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần bổ sung bút toán công nợ.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Bổ sung bút toán công nợ cho tất cả đơn hàng còn thiếu.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_ar_entries_cmd(order_id, repair_all, dry_run):
    """Bổ sung bút toán công nợ phải thu (AR) cho đơn hàng đã giao không có cọc.

    Tìm các đơn hàng đã giao/hoàn thành với total_price > 0, không có
    bút toán doanh thu (source_type = 'order'), và không có cọc thực tế
    (deposits_in - tien_rut_total <= 0). Tạo bút toán công nợ DR 1500 /
    CR 4100 qua ``_reconcile_order_revenue_entry``. Lệnh idempotent: chạy
    lần hai sẽ không tìm thấy đơn hàng nào cần bổ sung.
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            orders = _orders_needing_ar_entry(conn, order_id=order_id)

            results = []
            for o in orders:
                oid = int(o["id"])
                order_ref = o["order_ref"]
                total_price = float(o["total_price"] or 0)

                if dry_run:
                    results.append({
                        "order_id": oid,
                        "order_ref": order_ref,
                        "total_price": total_price,
                        "action": "will-create",
                    })
                else:
                    _reconcile_order_revenue_entry(
                        conn, oid, order_ref, total_price=total_price,
                    )
                    results.append({
                        "order_id": oid,
                        "order_ref": order_ref,
                        "total_price": total_price,
                        "action": "created",
                    })

            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair AR entries CLI error")
        click.echo(
            "Lỗi khi bổ sung bút toán công nợ. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng nào cần bổ sung bút toán công nợ)")
        return

    click.echo("Bổ sung bút toán công nợ phải thu (AR)")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Tổng tiền':>16}{'Hành động':<16}"
    )
    click.echo("-" * 52)
    for r in results:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{_vn_amount(r['total_price']):>16}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 52)

    created = sum(1 for r in results if r["action"] == "created")
    will_create = sum(1 for r in results if r["action"] == "will-create")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_create}")
    else:
        parts.append(f"đã sửa: {created}")
    click.echo(f"Tổng: {len(results)} đơn  |  " + ", ".join(parts))


# ---------------------------------------------------------------------------
# ``baker repair-future-dates`` — DG-233 Phase 5 future-dated entries fix
# (FR5, AC5, AC7, AC9)
# ---------------------------------------------------------------------------


def _future_dated_entries(conn):
    """Return journal entries whose ``created_at`` is in the future."""
    rows = conn.execute(
        """
        SELECT je.id          AS entry_id,
               je.description AS description,
               je.source_type AS source_type,
               je.source_id   AS source_id,
               je.created_at  AS created_at,
               je.locked_at   AS locked_at
        FROM journal_entries je
        WHERE je.created_at > ?
        ORDER BY je.id
        """,
        (now_utc(),),
    ).fetchall()
    return [
        {
            "entry_id": int(r["entry_id"]),
            "description": r["description"],
            "source_type": r["source_type"],
            "source_id": int(r["source_id"]) if r["source_id"] is not None else None,
            "created_at": r["created_at"],
            "locked": bool(r["locked_at"]),
        }
        for r in rows
    ]


@click.command("repair-future-dates")
@click.option("--entry-id", "entry_id", type=int, default=None, help="ID bút toán cần sửa ngày.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả bút toán có ngày trong tương lai.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_future_dates_cmd(entry_id, repair_all, dry_run):
    """Sửa bút toán nhật ký có created_at trong tương lai về thời điểm hiện tại.

    Các bút toán có ``created_at > now_utc()`` (thường do lỗi múi giờ khi
    dùng ``strftime`` trong SQLite) sẽ được đặt lại ``created_at`` về thời
    điểm hiện tại. Bút toán đã khoá sẽ bị bỏ qua. Lệnh idempotent: chạy
    lần hai sẽ không tìm thấy bút toán nào cần sửa.
    """
    if entry_id is None and not repair_all:
        click.echo("Cần chỉ định --entry-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if entry_id is not None and repair_all:
        click.echo("Không thể dùng --entry-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            entries = _future_dated_entries(conn)
            if entry_id is not None:
                entries = [e for e in entries if e["entry_id"] == entry_id]
                if not entries:
                    click.echo(f"(không tìm thấy bút toán #{entry_id} hoặc bút toán không có ngày trong tương lai)")
                    return

            results = []
            now = now_utc()
            for e in entries:
                eid = e["entry_id"]
                if e["locked"]:
                    results.append({
                        "entry_id": eid,
                        "description": e["description"],
                        "source_type": e["source_type"],
                        "source_id": e["source_id"],
                        "created_at": e["created_at"],
                        "action": "locked",
                    })
                    continue

                if dry_run:
                    results.append({
                        "entry_id": eid,
                        "description": e["description"],
                        "source_type": e["source_type"],
                        "source_id": e["source_id"],
                        "created_at": e["created_at"],
                        "action": "will-repair",
                    })
                else:
                    conn.execute(
                        "UPDATE journal_entries SET created_at = ? WHERE id = ?",
                        (now, eid),
                    )
                    results.append({
                        "entry_id": eid,
                        "description": e["description"],
                        "source_type": e["source_type"],
                        "source_id": e["source_id"],
                        "created_at": now,
                        "action": "repaired",
                    })

            if not dry_run:
                conn.commit()
    except Exception:
        logger.exception("Repair future-dates CLI error")
        click.echo(
            "Lỗi khi sửa bút toán có ngày trong tương lai. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có bút toán nào cần sửa ngày)")
        return

    click.echo("Sửa bút toán có ngày trong tương lai")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'ID bút toán':<12}{'Mô tả':<30}{'Ngày cũ':<22}{'Hành động':<16}"
    )
    click.echo("-" * 80)
    for r in results:
        desc = (r["description"] or "")[:29]
        old_date = r["created_at"] or ""
        click.echo(
            f"{r['entry_id']:<12}"
            f"{desc:<30}"
            f"{old_date:<22}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 80)

    repaired = sum(1 for r in results if r["action"] == "repaired")
    locked = sum(1 for r in results if r["action"] == "locked")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair}")
    else:
        if repaired:
            parts.append(f"đã sửa: {repaired}")
        if locked:
            parts.append(f"khoá: {locked}")
    click.echo(f"Tổng: {len(results)} bút toán  |  " + ", ".join(parts))


# ---------------------------------------------------------------------------
# ``baker repair-inventory`` — DG-233 Phase 4 inventory balance fix
# (FR4, AC4, AC7, AC9)
# ---------------------------------------------------------------------------


def _expense_events_needing_inventory_backfill(conn, event_id=None):
    """Find expense events with inventory purchase categories missing journal entries.

    Inventory purchase categories (``Nguyên liệu``, ``Bao bì``) debit Account 1300
    (Inventory) instead of an expense account. Missing journal entries for these
    events mean the purchase debit to 1300 was never recorded, which can cause a
    negative inventory balance.
    """
    import json

    sql = """
        SELECT e.id, e.summary, e.data
        FROM events e
        WHERE e.type = 'expense'
          AND (e.deleted_at IS NULL OR e.deleted_at = '')
          AND NOT EXISTS (
              SELECT 1 FROM journal_entries je
              WHERE je.source_type = 'expense' AND je.source_id = e.id
          )
    """
    params = []
    if event_id is not None:
        sql += " AND e.id = ?"
        params.append(event_id)
    sql += " ORDER BY e.id ASC"

    rows = conn.execute(sql, params).fetchall()

    result = []
    for r in rows:
        data = json.loads(r["data"] or "{}")
        category = data.get("category")
        if category in INVENTORY_PURCHASE_CATEGORIES:
            result.append({
                "id": int(r["id"]),
                "summary": r["summary"],
                "data": data,
            })
    return result


def _process_inventory_backfill(conn, expense_event, *, dry_run):
    """Process one inventory expense event backfill.

    Calls :func:`_sync_expense_journal` to create the missing journal entry.
    Idempotent: resyncing an already-correct entry is a no-op.
    """
    event_id = expense_event["id"]
    summary = expense_event["summary"]
    data = expense_event["data"]
    category = data.get("category", "")
    amount = data.get("amount_vnd", 0)

    if dry_run:
        return {
            "event_id": event_id,
            "summary": summary,
            "category": category,
            "amount": float(amount) if amount else 0.0,
            "action": "will-backfill",
        }

    _sync_expense_journal(conn, event_id, data, summary)
    return {
        "event_id": event_id,
        "summary": summary,
        "category": category,
        "amount": float(amount) if amount else 0.0,
        "action": "backfilled",
    }


@click.command("repair-inventory")
@click.option("--event-id", "event_id", type=int, default=None, help="ID sự kiện chi phí cần bổ sung bút toán nhập kho.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Bổ sung bút toán cho tất cả sự kiện nhập kho còn thiếu.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_inventory_cmd(event_id, repair_all, dry_run):
    """Sửa số dư âm của tài khoản Hàng tồn kho (1300).

    Tìm các sự kiện chi phí thuộc danh mục nhập kho (``Nguyên liệu``,
    ``Bao bì``) chưa có bút toán nhật ký tương ứng và tạo bút toán
    Nợ 1300 / Có tài khoản thanh toán. Lệnh idempotent: chạy lần hai
    sẽ không tìm thấy sự kiện nào cần bổ sung.
    """
    if event_id is None and not repair_all:
        click.echo("Cần chỉ định --event-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if event_id is not None and repair_all:
        click.echo("Không thể dùng --event-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            events = _expense_events_needing_inventory_backfill(
                conn, event_id=event_id
            )

            results = []
            for e in events:
                results.append(
                    _process_inventory_backfill(conn, e, dry_run=dry_run)
                )

            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair inventory CLI error")
        click.echo(
            "Lỗi khi sửa bút toán nhập kho. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có sự kiện nhập kho nào cần bổ sung bút toán)")
        return

    click.echo("Sửa bút toán nhập kho (Hàng tồn kho 1300)")
    click.echo("=" * 50)
    click.echo("")
    click.echo(
        f"{'Mã SK':<10}{'Danh mục':<16}{'Số tiền':>16}{'Hành động':<16}"
    )
    click.echo("-" * 58)
    for r in results:
        click.echo(
            f"#{r['event_id']:<9}"
            f"{r['category'][:15]:<16}"
            f"{_vn_amount(r['amount']):>16}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 58)

    backfilled = sum(1 for r in results if r["action"] == "backfilled")
    will_backfill = sum(1 for r in results if r["action"] == "will-backfill")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_backfill}")
    else:
        parts.append(f"đã sửa: {backfilled}")
    click.echo(f"Tổng: {len(results)} sự kiện  |  " + ", ".join(parts))


# ---------------------------------------------------------------------------
# ``baker repair-deposit-balance`` — DG-233 Phase 6 deposit balance cleanup
# (FR6, AC6, AC7, AC9)
# ---------------------------------------------------------------------------


def _orders_with_deposit_balance_issue(conn, order_id=None):
    """Return orders flagged by the deposit_balance_integrity check.

    Mirrors :func:`_check_deposit_balance_integrity` — returns rows with
    ``net_2100 != 0`` for terminal/overdue orders. Excludes active orders
    that haven't passed their due date.
    """
    deposits_code = CUSTOMER_DEPOSITS_CODE
    sql = f"""
        SELECT o.id, o.order_ref, o.status, o.due_date,
               COALESCE(pt.dep_credit, 0) AS deposits_in,
               COALESCE(pt.ref_debit, 0) AS refunds_out,
               COALESCE(ord.rev_debit, 0) AS revenue_cleared,
               COALESCE(ship.ship_debit, 0) AS shipping_cleared,
               (COALESCE(pt.dep_credit, 0) - COALESCE(pt.ref_debit, 0)
                - COALESCE(ord.rev_debit, 0) - COALESCE(ship.ship_debit, 0)
               ) AS net_2100
        FROM orders o
        LEFT JOIN (
            SELECT pt2.order_id,
                   SUM(CASE WHEN jl2.credit > 0 THEN jl2.credit ELSE 0 END) AS dep_credit,
                   SUM(CASE WHEN jl2.debit > 0 THEN jl2.debit ELSE 0 END) AS ref_debit
            FROM payment_transactions pt2
            JOIN journal_entries je2
              ON je2.source_type = 'payment_transaction' AND je2.source_id = pt2.id
            JOIN journal_lines jl2 ON jl2.journal_entry_id = je2.id
            JOIN accounts a2 ON a2.id = jl2.account_id AND a2.code = ?
            WHERE (pt2.invalidated_at IS NULL OR pt2.invalidated_at = '')
            GROUP BY pt2.order_id
        ) pt ON pt.order_id = o.id
        LEFT JOIN (
            SELECT je3.source_id AS order_id,
                   SUM(CASE WHEN jl3.debit > 0 THEN jl3.debit ELSE 0 END) AS rev_debit
            FROM journal_entries je3
            JOIN journal_lines jl3 ON jl3.journal_entry_id = je3.id
            JOIN accounts a3 ON a3.id = jl3.account_id AND a3.code = ?
            WHERE je3.source_type = 'order'
              AND je3.description NOT LIKE 'Reversal:%'
            GROUP BY je3.source_id
        ) ord ON ord.order_id = o.id
        LEFT JOIN (
            SELECT je4.source_id AS order_id,
                   SUM(CASE WHEN jl4.debit > 0 THEN jl4.debit ELSE 0 END) AS ship_debit
            FROM journal_entries je4
            JOIN journal_lines jl4 ON jl4.journal_entry_id = je4.id
            JOIN accounts a4 ON a4.id = jl4.account_id AND a4.code = ?
            WHERE je4.source_type = 'order_shipping_hold'
            GROUP BY je4.source_id
        ) ship ON ship.order_id = o.id
        WHERE COALESCE(pt.dep_credit, 0) > 0
           OR COALESCE(ord.rev_debit, 0) > 0
    """
    params = [deposits_code, deposits_code, deposits_code]
    if order_id is not None:
        sql += " AND o.id = ?"
        params.append(order_id)
    sql += " ORDER BY o.id ASC"

    rows = conn.execute(sql, params).fetchall()

    result = []
    for r in rows:
        net = float(r["net_2100"])
        if abs(net) <= MISMATCH_TOLERANCE:
            continue
        status = r["status"]
        due_date = r["due_date"]
        if status not in ("delivered", "completed", "cancelled"):
            if not due_date:
                continue
            today = conn.execute(
                "SELECT strftime('%Y-%m-%d', 'now', 'localtime')"
            ).fetchone()[0]
            if due_date >= today:
                continue
        result.append(r)
    return result


def _process_deposit_balance_order(conn, order_id, *, dry_run):
    """Repair one order's deposit balance integrity (FR6).

    - Cancelled orders: reverse the payment transaction journal entries
      (the deposits were taken but never returned).
    - Delivered/completed/overdue orders: reconcile the revenue entry
      via :func:`_reconcile_order_revenue_entry`.

    Returns a result dict with keys: order_id, order_ref, status,
    deposits_in, revenue_cleared, shipping_cleared, net_2100, action.
    """
    deposits_code = CUSTOMER_DEPOSITS_CODE
    row = conn.execute(
        """
        SELECT o.id, o.order_ref, o.status, o.due_date,
               COALESCE((
                   SELECT SUM(jl.credit)
                   FROM payment_transactions pt
                   JOIN journal_entries je ON je.source_type = 'payment_transaction'
                     AND je.source_id = pt.id
                   JOIN journal_lines jl ON jl.journal_entry_id = je.id
                   JOIN accounts a ON a.id = jl.account_id AND a.code = ?
                   WHERE pt.order_id = o.id
                     AND (pt.invalidated_at IS NULL OR pt.invalidated_at = '')
                     AND jl.credit > 0
               ), 0) AS deposits_in,
               COALESCE((
                   SELECT SUM(jl.debit)
                   FROM journal_entries je
                   JOIN journal_lines jl ON jl.journal_entry_id = je.id
                   JOIN accounts a ON a.id = jl.account_id AND a.code = ?
                   WHERE je.source_type = 'order' AND je.source_id = o.id
                     AND je.description NOT LIKE 'Reversal:%'
                     AND jl.debit > 0
               ), 0) AS revenue_cleared,
               COALESCE((
                   SELECT SUM(jl.debit)
                   FROM journal_entries je
                   JOIN journal_lines jl ON jl.journal_entry_id = je.id
                   JOIN accounts a ON a.id = jl.account_id AND a.code = ?
                   WHERE je.source_type = 'order_shipping_hold'
                     AND je.source_id = o.id
                     AND jl.debit > 0
               ), 0) AS shipping_cleared
        FROM orders o
        WHERE o.id = ?
        """,
        (deposits_code, deposits_code, deposits_code, order_id),
    ).fetchone()
    if row is None:
        return {
            "order_id": order_id,
            "order_ref": f"#{order_id}",
            "status": "unknown",
            "deposits_in": 0.0,
            "revenue_cleared": 0.0,
            "shipping_cleared": 0.0,
            "net_2100": 0.0,
            "action": "not-applicable",
        }

    order_ref = row["order_ref"]
    status = row["status"]
    deposits_in = float(row["deposits_in"])
    revenue_cleared = float(row["revenue_cleared"])
    shipping_cleared = float(row["shipping_cleared"])
    net_2100 = deposits_in - revenue_cleared - shipping_cleared

    if status == "cancelled":
        if deposits_in <= 0:
            action = "not-applicable"
        elif dry_run:
            action = "will-repair"
        else:
            txn_ids = conn.execute(
                """
                SELECT pt.id
                FROM payment_transactions pt
                JOIN journal_entries je
                  ON je.source_type = 'payment_transaction' AND je.source_id = pt.id
                WHERE pt.order_id = ?
                  AND (pt.invalidated_at IS NULL OR pt.invalidated_at = '')
                """,
                (order_id,),
            ).fetchall()
            for t in txn_ids:
                entry_id_row = conn.execute(
                    "SELECT id FROM journal_entries "
                    "WHERE source_type = 'payment_transaction' AND source_id = ?",
                    (int(t["id"]),),
                ).fetchone()
                if entry_id_row:
                    eid = int(entry_id_row["id"])
                    if _is_locked(conn, eid):
                        _reverse_journal_entry(conn, eid)
                    else:
                        _delete_journal_entry_cascade(conn, eid)
            action = "repaired"
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "status": status,
            "deposits_in": deposits_in,
            "revenue_cleared": revenue_cleared,
            "shipping_cleared": shipping_cleared,
            "net_2100": net_2100,
            "action": action,
        }

    if dry_run:
        action = "will-repair"
    else:
        _reconcile_order_revenue_entry(conn, order_id, order_ref, respect_locks=True)
        action = "repaired"
    return {
        "order_id": order_id,
        "order_ref": order_ref,
        "status": status,
        "deposits_in": deposits_in,
        "revenue_cleared": revenue_cleared,
        "shipping_cleared": shipping_cleared,
        "net_2100": net_2100,
        "action": action,
    }


def _print_deposit_balance_report(results, *, dry_run):
    """Print the deposit balance repair report table and summary."""
    click.echo("Sửa số dư cọc khách hàng (2100)")
    click.echo("=" * 60)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Trạng thái':<14}{'Cọc vào':>14}{'Đã ghi nhận':>14}"
        f"{'VC giữ':>12}{'Còn lại':>14}{'Hành động':<14}"
    )
    click.echo("-" * 102)
    for r in results:
        action_label = _ACTION_LABELS.get(r["action"], r["action"])
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{r['status']:<14}"
            f"{_vn_amount(r['deposits_in']):>14}"
            f"{_vn_amount(r['revenue_cleared']):>14}"
            f"{_vn_amount(r['shipping_cleared']):>12}"
            f"{_vn_amount(r['net_2100']):>14}"
            f"{action_label:<14}"
        )
    click.echo("-" * 102)

    repaired = sum(1 for r in results if r["action"] == "repaired")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")
    not_applicable = sum(1 for r in results if r["action"] == "not-applicable")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair}")
    else:
        parts.append(f"đã sửa: {repaired}")
    if not_applicable:
        parts.append(f"không áp dụng: {not_applicable}")
    click.echo(f"Tổng: {len(results)} đơn  |  " + ", ".join(parts))


@click.command("repair-deposit-balance")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần sửa.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả đơn có số dư cọc bất thường.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_deposit_balance_cmd(order_id, repair_all, dry_run):
    """Sửa số dư cọc khách hàng (2100) bị lệch.

    Xử lý các vấn đề về tính toàn vẹn số dư cọc:
    - Đơn hàng đã hủy có cọc chưa hoàn trả → xoá/hoàn nhập bút toán cọc
    - Đơn hàng đã giao/hoàn thành có số dư 2100 âm hoặc dương
      bất thường → tạo lại bút toán doanh thu

    Lệnh idempotent: chạy lần hai sẽ không tìm thấy đơn hàng nào cần sửa.
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            if repair_all:
                orders = _orders_with_deposit_balance_issue(conn)
            else:
                orders = _orders_with_deposit_balance_issue(conn, order_id=order_id)

            results = []
            for o in orders:
                results.append(
                    _process_deposit_balance_order(
                        conn, int(o["id"]), dry_run=dry_run
                    )
                )
            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair deposit-balance CLI error")
        click.echo(
            "Lỗi khi sửa số dư cọc. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng nào cần sửa số dư cọc)")
        return

    _print_deposit_balance_report(results, dry_run=dry_run)


# ---------------------------------------------------------------------------
# ``baker repair-cancelled-orders`` — DG-236 Phase 3 cancelled order journal repair
# (FR9, NFR4, NFR5, AC5)
# ---------------------------------------------------------------------------


def _cancelled_orders_with_orphaned_entries(conn, order_id=None):
    """Return cancelled orders with non-zero 2100 balance, classified by category.

    Mirrors :func:`_check_deposit_balance_integrity` — calculates
    ``net_2100 = deposits_in - refunds_out - revenue_cleared - shipping_cleared``
    and returns only cancelled orders where ``abs(net_2100) > MISMATCH_TOLERANCE``.

    Each row is annotated with:
    - ``has_cash_issue``: ``deposits_in - refunds_out != 0`` (payment_transaction entries)
    - ``has_non_cash_issue``: ``revenue_cleared + shipping_cleared != 0`` (revenue/COGS/shipping)
    """
    deposits_code = CUSTOMER_DEPOSITS_CODE
    sql = """
        SELECT o.id, o.order_ref,
               COALESCE(pt.dep_credit, 0) AS deposits_in,
               COALESCE(pt.ref_debit, 0) AS refunds_out,
               COALESCE(ord.rev_debit, 0) AS revenue_cleared,
               COALESCE(ship.ship_debit, 0) AS shipping_cleared,
               (COALESCE(pt.dep_credit, 0) - COALESCE(pt.ref_debit, 0)
                - COALESCE(ord.rev_debit, 0) - COALESCE(ship.ship_debit, 0)
               ) AS net_2100
        FROM orders o
        LEFT JOIN (
            SELECT pt2.order_id,
                   SUM(CASE WHEN jl2.credit > 0 THEN jl2.credit ELSE 0 END) AS dep_credit,
                   SUM(CASE WHEN jl2.debit > 0 THEN jl2.debit ELSE 0 END) AS ref_debit
            FROM payment_transactions pt2
            JOIN journal_entries je2
              ON je2.source_type = 'payment_transaction' AND je2.source_id = pt2.id
            JOIN journal_lines jl2 ON jl2.journal_entry_id = je2.id
            JOIN accounts a2 ON a2.id = jl2.account_id AND a2.code = ?
            WHERE (pt2.invalidated_at IS NULL OR pt2.invalidated_at = '')
            GROUP BY pt2.order_id
        ) pt ON pt.order_id = o.id
        LEFT JOIN (
            SELECT je3.source_id AS order_id,
                   SUM(CASE WHEN jl3.debit > 0 THEN jl3.debit ELSE 0 END) AS rev_debit
            FROM journal_entries je3
            JOIN journal_lines jl3 ON jl3.journal_entry_id = je3.id
            JOIN accounts a3 ON a3.id = jl3.account_id AND a3.code = ?
            WHERE je3.source_type = 'order'
              AND je3.description NOT LIKE 'Reversal:%'
            GROUP BY je3.source_id
        ) ord ON ord.order_id = o.id
        LEFT JOIN (
            SELECT je4.source_id AS order_id,
                   SUM(CASE WHEN jl4.debit > 0 THEN jl4.debit ELSE 0 END) AS ship_debit
            FROM journal_entries je4
            JOIN journal_lines jl4 ON jl4.journal_entry_id = je4.id
            JOIN accounts a4 ON a4.id = jl4.account_id AND a4.code = ?
            WHERE je4.source_type = 'order_shipping_hold'
            GROUP BY je4.source_id
        ) ship ON ship.order_id = o.id
        WHERE o.status = 'cancelled'
    """
    params = [deposits_code, deposits_code, deposits_code]
    if order_id is not None:
        sql += " AND o.id = ?"
        params.append(order_id)
    sql += " ORDER BY o.id ASC"

    rows = conn.execute(sql, params).fetchall()

    result = []
    for r in rows:
        net = float(r["net_2100"])
        if abs(net) <= MISMATCH_TOLERANCE:
            continue
        deposits_in = float(r["deposits_in"])
        refunds_out = float(r["refunds_out"])
        revenue_cleared = float(r["revenue_cleared"])
        shipping_cleared = float(r["shipping_cleared"])
        has_cash = abs(deposits_in - refunds_out) > MISMATCH_TOLERANCE
        has_non_cash = abs(revenue_cleared + shipping_cleared) > MISMATCH_TOLERANCE
        r_dict = dict(r)
        r_dict["has_cash_issue"] = has_cash
        r_dict["has_non_cash_issue"] = has_non_cash
        result.append(r_dict)
    return result


def _process_cancelled_order(conn, order_id, order_ref, *, dry_run, has_non_cash_issue):
    """Auto-fix non-cash (revenue/COGS/shipping) entries for one cancelled order.

    Cash entries (payment_transaction deposits) are intentionally skipped —
    they represent real money that requires a human decision (refund vs.
    manual invalidation).
    """
    if dry_run:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "action": "will-repair",
        }
    if not has_non_cash_issue:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "action": "cash-only",
        }

    sync_result = run_journal_sync(
        _sync_cancelled_order_journal,
        conn,
        order_id,
        log_label=f"cancel-journal-{order_id}",
    )
    return {
        "order_id": order_id,
        "order_ref": order_ref,
        "action": "repaired" if sync_result == "ok" else "repaired-with-errors",
    }


def _print_cancelled_orders_report(results, *, dry_run):
    """Print the cancelled orders repair report, split by category."""
    auto_fixable = [r for r in results if r.get("has_non_cash_issue")]
    cash_only = [r for r in results if r.get("has_cash_issue") and not r.get("has_non_cash_issue")]
    mixed = [r for r in results if r.get("has_cash_issue") and r.get("has_non_cash_issue")]

    if auto_fixable or mixed:
        click.echo("Bút toán doanh thu / COGS / ship (tự động sửa)")
        click.echo("=" * 52)
        click.echo(f"{'Mã đơn':<20}{'Hành động':<16}")
        click.echo("-" * 36)
        auto_rows = []
        for cat_results in (mixed, auto_fixable):
            for r in cat_results:
                if r not in auto_rows:
                    auto_rows.append(r)
        for r in auto_rows:
            label = _ACTION_LABELS.get(r["action"], r["action"])
            click.echo(f"{r['order_ref'][:19]:<20}{label:<16}")
        click.echo("-" * 36)
        repaired = sum(1 for r in auto_rows if r["action"] in ("repaired", "repaired-with-errors"))
        will_repair = sum(1 for r in auto_rows if r["action"] == "will-repair")
        if dry_run:
            click.echo(f"Tổng: {len(auto_rows)} đơn  |  sẽ sửa: {will_repair}")
        else:
            click.echo(f"Tổng: {len(auto_rows)} đơn  |  đã sửa: {repaired}")
        click.echo("")

    if cash_only or mixed:
        click.echo("Bút toán thanh toán (cần xem xét — không tự động sửa)")
        click.echo("=" * 56)
        click.echo(f"{'Mã đơn':<20}{'Tiền cọc':>12}{'Hoàn lại':>12}")
        click.echo("-" * 44)
        cash_rows = []
        for cat_results in (mixed, cash_only):
            for r in cat_results:
                if r not in cash_rows:
                    cash_rows.append(r)
        for r in cash_rows:
            dep = float(r.get("deposits_in", 0))
            ref = float(r.get("refunds_out", 0))
            click.echo(f"{r['order_ref'][:19]:<20}{dep:>12,.0f}{ref:>12,.0f}")
        click.echo("-" * 44)
        total_dep = sum(float(r.get("deposits_in", 0)) for r in cash_rows)
        total_ref = sum(float(r.get("refunds_out", 0)) for r in cash_rows)
        click.echo(f"Tổng: {len(cash_rows)} đơn  |  cọc: {total_dep:,.0f}  |  hoàn: {total_ref:,.0f}")
        click.echo("")
        click.echo("Các đơn này cần hoàn tiền hoặc huỷ giao dịch thủ công trước.")
        click.echo("Sau đó chạy lại lệnh này để làm sạch bút toán còn lại.")


@click.command("repair-cancelled-orders")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng đã huỷ cần sửa.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả đơn đã huỷ có bút toán mồ côi.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_cancelled_orders_cmd(order_id, repair_all, dry_run):
    """Xoá/hoàn nhập bút toán doanh thu của đơn hàng đã huỷ.

    Tìm đơn hàng ở trạng thái ``cancelled`` có bút toán mồ côi và tự động
    đảo ngược (locked) hoặc xoá (unlocked) bút toán doanh thu / COGS /
    ship (source_type='order', 'order_cogs', 'order_shipping_release').

    Bút toán thanh toán (payment_transaction) bị bỏ qua — đây là tiền
    thật cần người dùng quyết định (hoàn tiền hoặc huỷ giao dịch thủ công).
    Sau khi xử lý các giao dịch tiền mặt, chạy lại lệnh này để làm sạch
    bút toán còn lại.
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            if repair_all:
                orders = _cancelled_orders_with_orphaned_entries(conn)
            else:
                orders = _cancelled_orders_with_orphaned_entries(conn, order_id=order_id)

            results = []
            for o in orders:
                r = _process_cancelled_order(
                    conn,
                    int(o["id"]),
                    o["order_ref"],
                    dry_run=dry_run,
                    has_non_cash_issue=o.get("has_non_cash_issue", False),
                )
                r["deposits_in"] = o.get("deposits_in", 0)
                r["refunds_out"] = o.get("refunds_out", 0)
                r["has_cash_issue"] = o.get("has_cash_issue", False)
                r["has_non_cash_issue"] = o.get("has_non_cash_issue", False)
                results.append(r)
            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair cancelled-orders CLI error")
        click.echo(
            "Lỗi khi sửa bút toán đơn đã huỷ. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng đã huỷ nào có bút toán mồ côi)")
        return

    _print_cancelled_orders_report(results, dry_run=dry_run)