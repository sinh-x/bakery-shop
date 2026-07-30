"""Repair command module: repair_bank_account_1200_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403

_LEGACY_BANK_PARENT_CODE = "1200"

def _tien_rut_return_entries_on_1200(conn, order_id=None):
    """Return ``tien_rut`` return entries (``source_type='order'``) whose
    credit-side asset line still references account 1200.

    Scope (FR3):
      - ``source_type = 'order'`` entries whose description starts with the
        ``Tien rut return:`` prefix (the tien rut return entry created at
        delivery by ``_reconcile_tien_rut_return_entry``).
      - The credit (asset) line of the entry references account 1200. After
        re-sync the entry credits 1290 (un-allocated bank) for orders whose
        original ``tien_rut`` payment had an empty ``payment_source`` and
        ``method='transfer'`` (the pre-Phase-4 default routing).
      - ``order_id`` optionally scopes to a single order.

    Returns a list of dicts ``{entry_id, order_id, order_ref, amount, locked}``.
    """
    sql = """
        SELECT je.id AS entry_id, je.source_id AS order_id,
               je.description AS description,
               je.locked_at AS locked_at,
               COALESCE((
                   SELECT jl.credit
                   FROM journal_lines jl
                   JOIN accounts a ON a.id = jl.account_id
                   WHERE jl.journal_entry_id = je.id AND a.code = ?
                     AND jl.credit > 0
                   ORDER BY jl.id LIMIT 1
               ), 0) AS amount
        FROM journal_entries je
        WHERE je.source_type = 'order'
          AND je.description LIKE ?
          AND je.description NOT LIKE 'Reversal:%'
          AND EXISTS (
              SELECT 1 FROM journal_lines jl
              JOIN accounts a ON a.id = jl.account_id
              WHERE jl.journal_entry_id = je.id
                AND a.code = ? AND jl.credit > 0
          )
    """
    params = [
        _LEGACY_BANK_PARENT_CODE,
        _TIEN_RUT_RETURN_PREFIX + "%",
        _LEGACY_BANK_PARENT_CODE,
    ]
    if order_id is not None:
        sql += " AND je.source_id = ?"
        params.append(order_id)
    sql += " ORDER BY je.id ASC"
    rows = conn.execute(sql, params).fetchall()
    result = []
    for r in rows:
        oid = int(r["order_id"]) if r["order_id"] is not None else None
        result.append({
            "entry_id": int(r["entry_id"]),
            "order_id": oid,
            "order_ref": _order_ref(conn, oid) if oid is not None else "-",
            "amount": float(r["amount"] or 0),
            "kind": "tien_rut_return",
            "locked": bool(r["locked_at"]),
        })
    return result

def _refund_entries_on_1200(conn, order_id=None):
    """Return refund payment-transaction journal entries whose credit-side
    asset line still references account 1200.

    Scope (FR4):
      - ``source_type = 'payment_transaction'`` entries whose
        ``payment_transactions.type = 'refund'`` (cash flowing back to the
        customer). The credit side is the asset account.
      - The credit (asset) line references account 1200. After re-sync the
        entry credits 1290 for refund transfers with no ``payment_source``.
      - ``order_id`` optionally scopes to a single order.

    Returns a list of dicts ``{entry_id, order_id, order_ref, txn_id, amount,
    locked}``.
    """
    from baker.models.payment_transaction import _invalidation_filter

    # SEC-3 (DG-308): _invalidation_filter returns a static whitelist string
    # ("AND invalidated_at IS NULL" or "") — never user input — but it was
    # f-string-injected into the SQL. Use a boolean flag + parameterized
    # placeholder instead so no string interpolation touches the SQL text.
    include_invalidation = _invalidation_filter(conn) != ""
    invalidation_clause = "AND invalidated_at IS NULL" if include_invalidation else ""
    sql = f"""
        SELECT je.id AS entry_id, je.source_id AS txn_id,
               pt.order_id AS order_id,
               je.locked_at AS locked_at,
               COALESCE((
                    SELECT jl.credit
                    FROM journal_lines jl
                    JOIN accounts a ON a.id = jl.account_id
                    WHERE jl.journal_entry_id = je.id AND a.code = ?
                      AND jl.credit > 0
                    ORDER BY jl.id LIMIT 1
                ), 0) AS amount
        FROM journal_entries je
        JOIN payment_transactions pt ON pt.id = je.source_id
        WHERE je.source_type = 'payment_transaction'
          AND je.description NOT LIKE 'Reversal:%'
          AND pt.type = 'refund'
          {invalidation_clause}
          AND EXISTS (
              SELECT 1 FROM journal_lines jl
              JOIN accounts a ON a.id = jl.account_id
              WHERE jl.journal_entry_id = je.id
                AND a.code = ? AND jl.credit > 0
          )
    """
    params = [_LEGACY_BANK_PARENT_CODE, _LEGACY_BANK_PARENT_CODE]
    if order_id is not None:
        sql += " AND pt.order_id = ?"
        params.append(order_id)
    sql += " ORDER BY je.id ASC"
    rows = conn.execute(sql, params).fetchall()
    result = []
    for r in rows:
        oid = int(r["order_id"]) if r["order_id"] is not None else None
        result.append({
            "entry_id": int(r["entry_id"]),
            "order_id": oid,
            "order_ref": _order_ref(conn, oid) if oid is not None else "-",
            "txn_id": int(r["txn_id"]),
            "amount": float(r["amount"] or 0),
            "kind": "refund",
            "locked": bool(r["locked_at"]),
        })
    return result

def _expense_entries_on_1200(conn):
    """Return expense journal entries (``source_type='expense'``) whose
    credit-side asset line still references account 1200 (FR1, DG-286 Phase 1).

    Scope:
      - ``source_type = 'expense'`` entries joined to ``events`` for the
        expense data (``payment_source``, ``amount_vnd``, ``category``).
      - The credit (asset) line references account 1200. After re-sync the
        entry credits the sub-account mapped by
        ``EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE`` (e.g. ``TK Ân VCB`` →
        ``1220``).
      - ``Reversal:%`` entries are excluded.
      - Entries with unparseable event data or a missing ``payment_source``
        are skipped (cannot resolve a target account).

    Returns a list of dicts ``{entry_id, event_id, summary, amount,
    payment_source, target_code, kind="expense", locked}``.
    """
    sql = """
        SELECT je.id AS entry_id, je.source_id AS event_id,
               je.description AS description,
               je.locked_at AS locked_at,
               e.summary AS event_summary,
               e.data AS event_data,
               COALESCE((
                   SELECT jl.credit
                   FROM journal_lines jl
                   JOIN accounts a ON a.id = jl.account_id
                   WHERE jl.journal_entry_id = je.id AND a.code = ?
                     AND jl.credit > 0
                   ORDER BY jl.id LIMIT 1
               ), 0) AS amount
        FROM journal_entries je
        JOIN events e ON e.id = je.source_id
        WHERE je.source_type = 'expense'
          AND je.description NOT LIKE 'Reversal:%'
          AND EXISTS (
              SELECT 1 FROM journal_lines jl
              JOIN accounts a ON a.id = jl.account_id
              WHERE jl.journal_entry_id = je.id
                AND a.code = ? AND jl.credit > 0
          )
    """
    params = [_LEGACY_BANK_PARENT_CODE, _LEGACY_BANK_PARENT_CODE]
    sql += " ORDER BY je.id ASC"
    rows = conn.execute(sql, params).fetchall()
    result = []
    for r in rows:
        try:
            data = json.loads(r["event_data"] or "{}")
        except (json.JSONDecodeError, TypeError):
            continue
        payment_source = data.get("payment_source")
        if not isinstance(payment_source, str) or not payment_source:
            continue
        target_code = EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE.get(payment_source)
        result.append({
            "entry_id": int(r["entry_id"]),
            "event_id": int(r["event_id"]),
            "summary": r["event_summary"] or r["description"],
            "amount": float(r["amount"] or 0),
            "payment_source": payment_source,
            "target_code": target_code,
            "kind": "expense",
            "locked": bool(r["locked_at"]),
        })
    return result

def _process_bank_account_1200_repair(conn, item, *, dry_run: bool) -> dict:
    """Re-point one credit-side entry from 1200 to the correct account (FR3/FR4).

    The credit (asset) line of the entry is re-pointed from account 1200 to
    the appropriate target account — a data-only account-id change that
    preserves double-entry integrity (both 1200 and the target are asset
    accounts under the same parent, so the entry still balances).

      - ``tien_rut`` return entries (``source_type='order'``): the credit
        line is the asset returned to the customer. Re-pointed directly to
        1290 because ``_reconcile_tien_rut_return_entry`` is tolerant of which
        asset account is credited (it sums across 1100/1200/1210/1220/1290)
        and would skip a rebuild for an entry already matching in total.
      - ``refund`` payment-transaction entries: re-synced via
        ``_sync_payment_journal`` which rebuilds via
        ``_build_payment_journal_lines`` — the single source of truth —
        so the credit side routes to 1290 for empty-source transfers.
      - ``expense`` entries (``source_type='expense'``): re-synced via
        ``_sync_expense_journal`` which rebuilds via
        ``_build_expense_journal_lines`` — the credit side routes to the
        sub-account mapped by ``EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE``
        (e.g. ``TK Ân VCB`` → ``1220``), so the target code varies by
        ``payment_source`` rather than always landing on 1290.

    Locked entries are reversed + recreated (no double-entry). Idempotent
    (FR5): once the credit line is on the correct account the entry drops
    out of the detection query so a second run is a no-op.
    """
    kind = item["kind"]
    order_ref = item.get("order_ref", "")
    amount = item["amount"]
    if dry_run:
        return {
            "entry_id": item["entry_id"],
            "order_ref": order_ref,
            "amount": amount,
            "from_code": _LEGACY_BANK_PARENT_CODE,
            "to_code": item.get("target_code", UNALLOCATED_BANK_CODE),
            "kind": kind,
            "action": "will-repair",
        }

    entry_id = item["entry_id"]
    target_acc_id = _account_id_by_code(conn, UNALLOCATED_BANK_CODE)
    legacy_acc_id = _account_id_by_code(conn, _LEGACY_BANK_PARENT_CODE)

    if kind == "tien_rut_return":
        if _is_locked(conn, entry_id):
            _reverse_journal_entry(conn, entry_id)
            order_id = item["order_id"]
            _reconcile_tien_rut_return_entry(
                conn,
                order_id=order_id,
                order_ref=order_ref,
                tien_rut_account_id=_account_id_by_code(conn, TIEN_RUT_HELD_CODE),
                tien_rut_held=_held_tien_rut_for_order(conn, order_id),
                order_transaction_date=_resolve_delivered_timestamp(
                    conn, order_id, order_ref
                ) or now_utc(),
                respect_locks=True,
            )
        else:
            # Direct re-point: update the credit (asset) line from 1200 to
            # 1290. The entry stays balanced (both are asset accounts).
            conn.execute(
                "UPDATE journal_lines SET account_id = ? "
                "WHERE journal_entry_id = ? AND account_id = ? AND credit > 0",
                (target_acc_id, entry_id, legacy_acc_id),
            )
    elif kind == "refund":
        txn_id = item["txn_id"]
        order_id = item["order_id"]
        txn_row = conn.execute(
            "SELECT amount, method FROM payment_transactions WHERE id = ?",
            (txn_id,),
        ).fetchone()
        _sync_payment_journal(
            conn,
            txn_id,
            float(txn_row["amount"] or 0),
            "refund",
            txn_row["method"] or "transfer",
            order_id=order_id,
        )
    elif kind == "expense":
        event_id = item["event_id"]
        row = conn.execute(
            "SELECT data, summary FROM events WHERE id = ?",
            (event_id,),
        ).fetchone()
        if row is None:
            raise ValueError(f"expense event {event_id} not found")
        data = json.loads(row["data"])
        summary = row["summary"]
        _sync_expense_journal(conn, event_id, data, summary)
    return {
        "entry_id": entry_id,
        "order_ref": order_ref,
        "amount": amount,
        "from_code": _LEGACY_BANK_PARENT_CODE,
        "to_code": item.get("target_code", UNALLOCATED_BANK_CODE),
        "kind": kind,
        "action": "repaired",
    }

def _print_bank_account_1200_report(results, *, dry_run):
    """Print the credit-side bank-account-1200 repair report."""
    click.echo("Chuyển bút toán Có TK ngân hàng cũ (1200) sang TK đúng")
    click.echo("=" * 74)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Số tiền':>16}{'Loại':<18}{'Hành động':<16}"
    )
    click.echo("-" * 70)
    for r in results:
        if r["kind"] == "tien_rut_return":
            kind_label = "Tiền rút trả"
        elif r["kind"] == "expense":
            kind_label = "Chi phí"
        else:
            kind_label = "Hoàn tiền"
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{_vn_amount(r['amount']):>16}"
            f"{kind_label:<18}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 70)

    repaired = sum(1 for r in results if r["action"] == "repaired")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair}")
    else:
        parts.append(f"đã sửa: {repaired}")
    click.echo(f"Tổng: {len(results)} bút toán  |  " + ", ".join(parts))

@click.command("repair-bank-account-1200")
@click.option("--order-id", "order_id", type=int, default=None,
              help="ID đơn hàng cần chuyển bút toán Có 1200 sang 1290.")
@click.option("--all", "repair_all", is_flag=True, default=False,
              help="Chuyển tất cả bút toán Có TK 1200 (tiền rút trả, hoàn tiền, chi phí) sang TK đúng.")
@click.option("--dry-run", is_flag=True, default=False,
              help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_bank_account_1200_cmd(order_id, repair_all, dry_run):
    """Chuyển bút toán Có TK ngân hàng cũ (1200) sang TK chưa phân bổ (1290).

    DG-285 Phase 2 — historical credit-side backfill (FR3, FR4, FR5, AC3, AC4):

      Tìm các bút toán nhật ký có dòng Có (tài sản) vẫn ở TK 1200 và chuyển
      sang TK 1290 (Un-allocated Bank) qua các hàm tái tạo duy nhất
      (``_reconcile_tien_rut_return_entry`` cho tiền rút trả,
      ``_sync_payment_journal`` cho hoàn tiền). Bên Nợ (2100/2400) giữ
      nguyên — không tạo double-entry.

      * Bút toán ``tien_rut`` trả (``source_type='order'``) — FR3: 2 bút toán
        lịch sử (1896, 1947).
      * Bút toán ``refund`` (``source_type='payment_transaction'``) — FR4:
        bút toán 4474 (10K, transfer, no source).
      * Bút toán ``expense`` (``source_type='expense'``) — DG-286: 7 bút toán
        lịch sử (16, 18, 4979, 4980, 4981, 4982, 4997) ghi Có TK 1200.
        Sửa qua ``_sync_expense_journal`` — tự động chuyển về TK con đúng
        (1220 cho TK Ân VCB, 1210 cho TK Phượng VCB, ...).
      * Lệnh idempotent (FR5): chạy lần hai sẽ không tìm thấy bút toán nào
        cần sửa.

    Scope: backend only. Chạy trên production database là bước UAT/ops dành
    cho Sinh.
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            items = _tien_rut_return_entries_on_1200(
                conn, order_id=order_id if not repair_all else None,
            ) + _refund_entries_on_1200(
                conn, order_id=order_id if not repair_all else None,
            ) + _expense_entries_on_1200(conn)
            results = [
                _process_bank_account_1200_repair(conn, it, dry_run=dry_run)
                for it in items
            ]
            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair bank-account-1200 CLI error")
        click.echo(
            "Lỗi khi chuyển bút toán TK ngân hàng. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo(
            "(không có bút toán nào cần chuyển)"
        )
        return

    _print_bank_account_1200_report(results, dry_run=dry_run)
