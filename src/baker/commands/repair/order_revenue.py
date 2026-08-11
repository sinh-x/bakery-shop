"""Repair command module: repair_order_revenue_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


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
        # Revenue entry is correct, but check for and clean up any orphaned
        # AR entry (DG-269: stale AR entries from prior delivery sync when
        # the order was unpaid but is now fully paid and processed).
        if not dry_run:
            stale_ar_id = _find_order_entry_by_prefix(conn, order_id, _AR_ENTRY_PREFIX)
            if stale_ar_id is not None:
                _replace_order_entry(conn, stale_ar_id, respect_locks=False)
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

def _bus_orders_with_shipping_held(conn):
    """Return ids of all delivered/completed bus orders with shipping_fee > 0.

    Used by the shipping-release repair ``--all`` scan (FR2/FR8). Only bus
    orders are considered — pickup/door orders never hold shipping in 2200.
    Ordered by id ASC for deterministic output.
    """
    rows = conn.execute(
        f"""
        SELECT DISTINCT o.id AS order_id
        FROM orders o
        WHERE o.status IN ({",".join("?" * len(DELIVERED_STATUSES))})
          AND (o.delivery_type IS NULL OR o.delivery_type = 'bus')
          AND COALESCE(o.shipping_fee, 0) > 0
        ORDER BY o.id ASC
        """,
        list(DELIVERED_STATUSES),
    ).fetchall()
    return [int(r["order_id"]) for r in rows]

def _process_shipping_release_order(conn, order_id: int, *, dry_run: bool) -> dict:
    """Evaluate and optionally repair one order's shipping release entry.

    Mirrors :func:`_process_order` / :func:`_process_cogs_order` (per-order
    repair with dry-run). Returns a result dict with keys: order_id,
    order_ref, held_amount, release_amount, asset_code, action.

    DG-366 Phase 4 — aligned with the new release logic in
    :func:`_sync_bus_shipping_release_entry` (Phase 1): the release amount is
    always the full ``shipping_fee`` (the previous ``min(shipping_fee,
    held_in_2200)`` gate is removed) so the repair backfills missing entries
    even when no payment has credited 2200. The actual write is delegated to
    :func:`_sync_bus_shipping_release_entry` via the shared
    :func:`run_journal_sync` wrapper (with ``source_type`` / ``source_id``),
    mirroring the delivery/completion paths (FR6, NFR1) so failures are
    observable via the ``journal_sync_failures`` counter and recorded in
    ``journal_sync_failure_log``.

    Actions:
      - ``not-applicable``: non-bus order or ``shipping_fee <= 0``.
      - ``skipped``: an existing ``order_shipping_release`` entry matches the
        expected release amount within tolerance (idempotent, FR7).
      - ``locked``: an existing entry is locked and stale (FR7 — do not modify).
      - ``will-backfill``: dry-run preview of a missing entry (FR6).
      - ``will-repair``: dry-run preview of a stale unlocked entry.
      - ``backfilled``: missing entry created (CR is drawer-aware, FR3/FR4).
      - ``repaired``: stale unlocked entry deleted and recreated.
      - ``failed``: the delegated sync raised — reported, not raised to the
        CLI caller (NFR1: repair never blocks on a single order).
    """
    order_ref = _order_ref(conn, order_id)
    order_row = conn.execute(
        "SELECT delivery_type, shipping_fee FROM orders WHERE id = ?", (order_id,)
    ).fetchone()
    if order_row is None:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "held_amount": 0.0,
            "release_amount": 0.0,
            "asset_code": "",
            "action": "not-applicable",
        }
    delivery_type = order_row["delivery_type"] or "pickup"
    shipping_fee = float(order_row["shipping_fee"] or 0)
    if delivery_type != "bus" or shipping_fee <= 0:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "held_amount": 0.0,
            "release_amount": 0.0,
            "asset_code": "",
            "action": "not-applicable",
        }

    held_in_2200 = _held_shipping_for_order(conn, order_id)
    release_amount = shipping_fee

    asset_code, drawer_id = _resolve_shipping_release_asset_account(
        conn, order_id, order_ref
    )

    existing_id = _find_journal_entry(conn, "order_shipping_release", order_id)
    if existing_id is not None:
        row = conn.execute(
            """
            SELECT COALESCE(SUM(jl.debit), 0) AS debit_2200
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND a.code = ?
            """,
            (existing_id, BUS_SHIPPING_HELD_CODE),
        ).fetchone()
        current_debit = float(row["debit_2200"]) if row else 0.0
        if abs(current_debit - release_amount) <= MISMATCH_TOLERANCE:
            return {
                "order_id": order_id,
                "order_ref": order_ref,
                "held_amount": held_in_2200,
                "release_amount": release_amount,
                "asset_code": asset_code,
                "action": "skipped",
            }
        if _is_locked(conn, existing_id):
            return {
                "order_id": order_id,
                "order_ref": order_ref,
                "held_amount": held_in_2200,
                "release_amount": release_amount,
                "asset_code": asset_code,
                "action": "locked",
            }
        if dry_run:
            return {
                "order_id": order_id,
                "order_ref": order_ref,
                "held_amount": held_in_2200,
                "release_amount": release_amount,
                "asset_code": asset_code,
                "action": "will-repair",
            }
    else:
        if dry_run:
            return {
                "order_id": order_id,
                "order_ref": order_ref,
                "held_amount": held_in_2200,
                "release_amount": release_amount,
                "asset_code": asset_code,
                "action": "will-backfill",
            }

    # Delegate the write to the shared sync function (Phase 1 logic: always
    # release the full shipping_fee) via the fire-and-forget runner with
    # source_type/source_id, mirroring the delivery/completion paths (FR6,
    # NFR1). The runner handles locked-stale reversal and unlocked-stale
    # delete-and-recreate inside :func:`_sync_bus_shipping_release_entry`.
    sync_status = run_journal_sync(
        _sync_bus_shipping_release_entry,
        conn, order_id, order_ref,
        log_label=f"shipping release repair for order {order_id} ({order_ref})",
        source_type="order_shipping_release",
        source_id=order_id,
    )
    action = "repaired" if existing_id is not None else "backfilled"
    if sync_status != "ok":
        action = "failed"
    return {
        "order_id": order_id,
        "order_ref": order_ref,
        "held_amount": held_in_2200,
        "release_amount": release_amount,
        "asset_code": asset_code,
        "action": action,
    }

def _run_shipping_release_repair(conn, *, order_id, repair_all, dry_run):
    """Drive the shipping-release repair for a single order or all bus orders.

    Mirrors :func:`_run_cogs_repair`. When ``repair_all`` is True, scans every
    delivered/completed bus order with ``shipping_fee > 0`` (FR2/FR8). Each
    scanned order is reported with its action so the second idempotent run
    reports every order as ``skipped`` (AC6).
    """
    if repair_all:
        order_ids = _bus_orders_with_shipping_held(conn)
    else:
        order_ids = [order_id]
    return [
        _process_shipping_release_order(conn, oid, dry_run=dry_run)
        for oid in order_ids
    ]

def _print_shipping_release_report(results, *, dry_run):
    """Print the shipping-release repair report table and summary."""
    click.echo("Sửa bút toán ship bus (shipping release)")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Giữ 2200':>16}{'Trả ship':>16}{'TK đối ứng':<14}{'Hành động':<16}"
    )
    click.echo("-" * 82)
    labels = {**_ACTION_LABELS, **SHIPPING_RELEASE_ACTION_LABELS}
    for r in results:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{_vn_amount(r['held_amount']):>16}"
            f"{_vn_amount(r['release_amount']):>16}"
            f"{r['asset_code']:<14}"
            f"{labels.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 82)

    backfilled = sum(1 for r in results if r["action"] == "backfilled")
    repaired = sum(1 for r in results if r["action"] == "repaired")
    will_backfill = sum(1 for r in results if r["action"] == "will-backfill")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")
    skipped = sum(1 for r in results if r["action"] == "skipped")
    not_applicable = sum(1 for r in results if r["action"] == "not-applicable")
    locked = sum(1 for r in results if r["action"] == "locked")
    failed = sum(1 for r in results if r["action"] == "failed")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair + will_backfill}")
    else:
        parts.append(f"đã sửa: {repaired + backfilled}")
    parts.append(f"bỏ qua: {skipped}")
    parts.append(f"không áp dụng: {not_applicable}")
    if locked:
        parts.append(f"khoá: {locked}")
    if failed:
        parts.append(f"lỗi: {failed}")
    click.echo(f"Tổng: {len(results)} đơn  |  " + ", ".join(parts))

@click.command("repair-order-revenue")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần sửa.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả đơn đã giao có bút toán lệch.")
@click.option("--cogs", "repair_cogs", is_flag=True, default=False, help="Sửa/bổ sung bút toán giá vốn (COGS) thay vì doanh thu.")
@click.option("--shipping-release", "repair_shipping_release", is_flag=True, default=False, help="Sửa/bổ sung bút toán trả ship bus (2200 → 1101/1102) thay vì doanh thu.")
@click.option("--force", "force_cogs", is_flag=True, default=False, help="Tính lại toàn bộ cost_at_sale (không chỉ dòng = 0). Chỉ dùng với --cogs.")
@click.option("--since", "since_date", type=str, default=None, help="Chỉ xử lý đơn có ngày giao từ DATE trở đi (YYYY-MM-DD). Chỉ dùng với --all.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_order_revenue_cmd(order_id, repair_all, repair_cogs, repair_shipping_release, force_cogs, since_date, dry_run):
    """Sửa bút toán doanh thu đơn hàng bị lệch (nợ 2100 ≠ cọc thực tế).

    Với ``--cogs``, sửa/bổ sung bút toán giá vốn (COGS) cho đơn đã giao:
    bỏ qua đơn đã có bút toán COGS khớp với chi phí dự kiến (idempotent).

    Với ``--cogs --force``, tính lại toàn bộ cost_at_sale cho tất cả mặt hàng
    (kể cả những dòng đã có cost_at_sale > 0) dùng công thức unit_price × 30%.

    Với ``--shipping-release``, sửa/bổ sung bút toán trả ship bus
    (2200 → 1101/1102) cho đơn bus đã giao. Tài khoản đối ứng phụ thuộc
    drawer đang mở: 1101 nếu giao trong phiên drawer hiện tại, 1102 nếu
    không có drawer mở hoặc giao trước phiên đó.
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
    if repair_shipping_release and repair_cogs:
        click.echo("Không thể dùng --shipping-release và --cogs cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            if repair_cogs:
                results = _run_cogs_repair(
                    conn, order_id=order_id, repair_all=repair_all, dry_run=dry_run, force=force_cogs
                )
            elif repair_shipping_release:
                results = _run_shipping_release_repair(
                    conn, order_id=order_id, repair_all=repair_all, dry_run=dry_run
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

    if repair_shipping_release:
        _print_shipping_release_report(results, dry_run=dry_run)
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

