"""Repair command module: repair_debt_expenses_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


def _expense_journal_entry_id(conn, event_id: int):
    """Return the (non-reversal) journal entry id for an expense event, or None."""
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'expense' AND source_id = ? "
        "AND description NOT LIKE 'Reversal:%' "
        "ORDER BY id DESC LIMIT 1",
        (event_id,),
    ).fetchone()
    return int(row["id"]) if row else None

def _expense_credit_account(conn, entry_id: int):
    """Return ``(account_id, code, parent_id, name)`` for the credit line, or None."""
    row = conn.execute(
        """
        SELECT a.id AS account_id, a.code AS code,
               a.parent_id AS parent_id, a.name AS name
        FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE jl.journal_entry_id = ? AND jl.credit > 0
        ORDER BY jl.id LIMIT 1
        """,
        (entry_id,),
    ).fetchone()
    if row is None:
        return None
    return (
        int(row["account_id"]),
        row["code"],
        int(row["parent_id"]) if row["parent_id"] is not None else None,
        row["name"],
    )

def _expected_expense_credit(conn, data: dict, *, dry_run: bool = False):
    """Resolve the expected credit account id for an expense event.

    Mirrors the credit-account resolution in ``_build_expense_journal_lines``
    (single source of truth): debt → per-vendor 25xx sub-account under 2500,
    staff advance → per-staff 2300 sub-account, cash/transfer → mapped asset
    account. Returns ``(account_id, kind)`` where ``kind`` is one of
    ``'debt'``, ``'staff'``, ``'cash'``, or ``None`` when the expense data is
    incomplete/unsupported (by-design unjournalled).

    When ``dry_run`` is True the resolution is read-only: a missing per-vendor
    or per-staff sub-account is *not* created (CQ-4). In that case the function
    returns ``(None, kind)`` — the event is still flagged as a repair candidate
    (its JE is missing or stale), but no INSERT is issued against ``accounts``
    during detection. The mutating ``_ensure_*`` helpers are only called in
    apply mode (``dry_run=False``), where the subsequent ``conn.commit()`` is
    expected.
    """
    amount = data.get("amount_vnd")
    category = data.get("category")
    payment_source = data.get("payment_source")
    payment_method = data.get("payment_method", "")
    # Mirror the ``_build_expense_journal_lines`` skip predicate via the shared
    # ``_is_expense_journallable`` helper (CQ-5): events that produce no JE at
    # build time must not be flagged as missing/stale here, or repair would
    # re-flag the same unmapped-category event forever (non-idempotent) and
    # create phantom vendor sub-accounts during detection (CQ-3/CQ-4).
    if not _is_expense_journallable(data):
        return None, None

    is_debt = payment_method == EXPENSE_DEBT_PAYMENT_METHOD

    if is_debt:
        vendor_name = (data.get("vendor") or "").strip()
        if not vendor_name:
            return None, None
        if dry_run:
            # Read-only lookup: do not create the sub-account during detection.
            row = conn.execute(
                "SELECT a.id FROM accounts a "
                "JOIN accounts p ON p.id = a.parent_id "
                "WHERE p.code = ? AND a.name = ?",
                (ACCOUNTS_PAYABLE_CODE, vendor_name),
            ).fetchone()
            return (int(row[0]) if row else None), "debt"
        return _ensure_ap_vendor_sub_account(conn, vendor_name), "debt"
    if payment_source == STAFF_ADVANCE_PAYMENT_SOURCE:
        staff_name = (data.get("paid_by_name") or "").strip()
        if not staff_name:
            return None, None
        if dry_run:
            from baker.db.schema import STAFF_PAYABLES_CODE
            row = conn.execute(
                "SELECT a.id FROM accounts a "
                "JOIN accounts p ON p.id = a.parent_id "
                "WHERE p.code = ? AND a.name = ?",
                (STAFF_PAYABLES_CODE, staff_name),
            ).fetchone()
            return (int(row[0]) if row else None), "staff"
        from baker.db.schema import _ensure_staff_payable_sub_account
        return _ensure_staff_payable_sub_account(conn, staff_name), "staff"
    account_code = EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE.get(payment_source)
    if not account_code:
        return None, None
    return _account_id_by_code(conn, account_code), "cash"

def _expense_events_needing_debt_repair(conn, event_id=None, *, dry_run: bool = False):
    """Find debt/expense events whose journal entry is missing or stale.

    Mirrors the detection logic of ``_check_expense_payment_account_mismatch``
    (Phase 5) but scoped to actionable repairs:

      1. **Missing JE** (e.g. live event 6346): a debt expense with no
         ``source_type='expense'`` journal entry (sync failed pre-v73 because
         account 2500 did not exist).
      2. **Stale JE** (e.g. live event 6348): the credit-side account of the
         existing JE disagrees with the event's current
         ``payment_method``/``payment_source`` (cash JE left over from a
         cash→debt edit that re-synced to a now-creatable 25xx sub-account).

    Returns a list of dicts: ``{id, summary, data, action_kind}`` where
    ``action_kind`` is ``'create'`` or ``'fix'``. Reversal entries are
    excluded.

    When ``dry_run`` is True the per-vendor/per-staff sub-account resolution
    is read-only (CQ-4): a missing sub-account does not trigger an INSERT
    against ``accounts``. Such events are still reported as ``'create'``
    candidates (the JE is missing), but no vendor sub-account is persisted.
    """
    sql = """
        SELECT e.id, e.summary, e.data
        FROM events e
        WHERE e.type = 'expense'
          AND (e.deleted_at IS NULL OR e.deleted_at = '')
        ORDER BY e.id ASC
    """
    params = []
    if event_id is not None:
        sql = "SELECT e.id, e.summary, e.data FROM events e WHERE e.id = ?"
        params = [event_id]
    rows = conn.execute(sql, params).fetchall()

    result = []
    for r in rows:
        try:
            data = json.loads(r["data"] or "{}")
        except (ValueError, TypeError):
            continue
        if not isinstance(data, dict):
            continue

        expected_id, kind = _expected_expense_credit(conn, data, dry_run=dry_run)
        # kind is None → by-design unjournalled (unmapped category, missing
        # vendor/staff name, etc.); never a repair candidate.
        if kind is None:
            continue

        entry_id = _expense_journal_entry_id(conn, int(r["id"]))
        if entry_id is None:
            result.append({
                "id": int(r["id"]),
                "summary": r["summary"],
                "data": data,
                "action_kind": "create",
            })
            continue

        if _is_locked(conn, entry_id):
            continue

        credit_info = _expense_credit_account(conn, entry_id)
        if credit_info is None:
            continue
        actual_id = credit_info[0]
        if actual_id != expected_id:
            result.append({
                "id": int(r["id"]),
                "summary": r["summary"],
                "data": data,
                "action_kind": "fix",
            })
    return result

def _process_debt_expense_repair(conn, event, *, dry_run: bool) -> dict:
    """Repair one expense event's journal entry (create missing or fix stale).

    Calls :func:`_sync_expense_journal` which rebuilds the lines via
    :func:`_build_expense_journal_lines` (the single create/edit-path source
    of truth), so the repaired entry ends up identical to what a fresh
    create/edit would produce — DR 1300 for inventory categories / DR expense
    account otherwise, CR the per-vendor 25xx sub-account (debt) or mapped
    asset account (cash/staff).

    Idempotent: once the credit account matches the expected one, the event
    drops out of ``_expense_events_needing_debt_repair`` (NFR4).
    """
    event_id = event["id"]
    summary = event["summary"]
    data = event["data"]
    action_kind = event["action_kind"]
    amount = float(data.get("amount_vnd", 0) or 0)

    if dry_run:
        return {
            "event_id": event_id,
            "summary": summary,
            "amount": amount,
            "action": "will-create" if action_kind == "create" else "will-repair",
            "kind": action_kind,
        }

    entry_id = _expense_journal_entry_id(conn, event_id)
    if entry_id is not None and action_kind == "fix":
        _delete_journal_entry_cascade(conn, entry_id)
    _sync_expense_journal(conn, event_id, data, summary)
    return {
        "event_id": event_id,
        "summary": summary,
        "amount": amount,
        "action": "created" if action_kind == "create" else "repaired",
        "kind": action_kind,
    }

def _print_debt_expenses_report(results, *, dry_run):
    """Print the debt-expense repair report table and summary."""
    click.echo("Sửa bút toán chi phí nợ (debt expense journal repair)")
    click.echo("=" * 60)
    click.echo("")
    click.echo(
        f"{'Mã SK':<10}{'Tóm tắt':<28}{'Số tiền':>14}{'Hành động':<16}"
    )
    click.echo("-" * 68)
    for r in results:
        summary = (r["summary"] or "")[:27]
        click.echo(
            f"#{r['event_id']:<9}"
            f"{summary:<28}"
            f"{_vn_amount(r['amount']):>14}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 68)

    created = sum(1 for r in results if r["action"] == "created")
    repaired = sum(1 for r in results if r["action"] == "repaired")
    will_create = sum(1 for r in results if r["action"] == "will-create")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_create + will_repair}")
    else:
        parts.append(f"đã sửa: {created + repaired}")
    click.echo(f"Tổng: {len(results)} sự kiện  |  " + ", ".join(parts))

@click.command("repair-debt-expenses")
@click.option("--event-id", "event_id", type=int, default=None, help="ID sự kiện chi phí cần sửa bút toán.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả sự kiện chi phí nợ có bút toán thiếu/sai.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_debt_expenses_cmd(event_id, repair_all, dry_run):
    """Sửa bút toán chi phí nợ (debt expense) bị thiếu hoặc sai tài khoản có.

    Phát hiện hai loại lỗi trên sự kiện chi phí (type='expense'):

      1. **Thiếu bút toán** (vd. sự kiện 6346): chi phí nợ không có bút toán
         nhật ký (do thiếu tài khoản 2500 trước khi chạy migration v73).
         Lệnh sẽ tạo bút toán mới: Nợ 1300 (nhập kho) hoặc tài khoản chi phí,
         Có tài khoản con 25xx của nhà cung cấp dưới 2500.
      2. **Bút toán sai** (vd. sự kiện 6348): bút toán hiện có ghi Có sai tài
         khoản (vd. 1100 Cash thay vì 25xx sub-account). Lệnh sẽ xoá bút toán
         cũ và tạo lại đúng qua cùng đường tạo/sửa (single source of truth).

    Lệnh idempotent: chạy lần hai sẽ không tìm thấy sự kiện nào cần sửa
    (NFR4). Tự động chạy migration v73 (qua ``ensure_schema`` ở CLI startup)
    để đảm bảo tài khoản 2500 tồn tại trước khi sửa.
    """
    if event_id is None and not repair_all:
        click.echo("Cần chỉ định --event-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if event_id is not None and repair_all:
        click.echo("Không thể dùng --event-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            if repair_all:
                events = _expense_events_needing_debt_repair(conn, dry_run=dry_run)
            else:
                events = _expense_events_needing_debt_repair(
                    conn, event_id=event_id, dry_run=dry_run,
                )

            results = []
            for e in events:
                results.append(
                    _process_debt_expense_repair(conn, e, dry_run=dry_run)
                )
            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair debt-expenses CLI error")
        click.echo(
            "Lỗi khi sửa bút toán chi phí nợ. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có sự kiện chi phí nợ nào cần sửa bút toán)")
        return

    _print_debt_expenses_report(results, dry_run=dry_run)

