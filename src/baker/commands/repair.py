"""``baker repair-order-revenue`` CLI command (DG-190 Phase 4.2).

Repairs stale order-revenue journal entries whose 2100 (Customer Deposits)
debit no longer matches the order's current net deposits
(deposits − outflows (refund only); ``PaymentTransaction.total_paid_net``).
``tien_rut`` is a deposit inflow (DG-198 reversal), not an outflow, so it is
not subtracted from the deposit balance.

The repair deletes the existing ``source_type = 'order'`` journal entry and
re-runs :func:`_sync_delivered_order_journal` to recreate it with the current
net deposit amounts. The command is idempotent: entries already within 0.005 of
the net deposits are skipped.

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

Only delivered/completed orders are considered. Orders without a revenue entry
(or with an accounts-receivable entry that has no 2100 debit) are reported as
"không áp dụng" (not applicable).

All user-facing labels are in Vietnamese (VN label policy). Exit code is 0 on
success and 1 on error; errors are written to stderr only — following the
existing ``validate-accounts`` pattern.
"""

import logging

import click

from baker.db.connection import get_db
from baker.db.schema import (
    CUSTOMER_DEPOSITS_CODE,
    REVENUE_UPDATE_TOLERANCE,
    TIEN_RUT_HELD_CODE,
)
from baker.formatters import format_vnd_amount
from baker.models.payment_transaction import PaymentTransaction
from baker.services.journal_sync import (
    _compute_order_cogs_total,
    _delete_journal_entry_cascade,
    _is_locked,
    _order_cogs_entry,
    _reconcile_order_revenue_entry,
    _sync_delivered_order_journal,
    _sync_order_cogs_entry,
    _sync_payment_journal,
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
    action (one of 'repaired', 'skipped', 'not-applicable', 'locked', 'will-repair').
    """
    order_ref = _order_ref(conn, order_id)
    entry_id, old_debit = _order_revenue_2100_debit(conn, order_id)
    net = PaymentTransaction.total_paid_net(conn, order_id)

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