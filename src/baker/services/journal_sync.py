"""Journal auto-generation sync helpers.

These helpers create/update/delete double-entry journal entries for the
primary financial transactions (expenses, payments, order delivery, waste).
They are consumed by the events, payment_transactions, orders, reconciliations,
and stock routers so that every financial transaction automatically produces
a matching journal entry.

Accounting failures must never block the primary business operation: callers
wrap each ``_sync_*`` call in try/except with ``logger.exception``.
"""

import json
import logging
import traceback
from typing import Any, Callable, Optional

from baker.utils.time import now_utc

from baker.db.schema import (
    ACCOUNTS_PAYABLE_CODE,
    ACCOUNTS_RECEIVABLE_CODE,
    BUS_SHIPPING_HELD_CODE,
    COGS_CODE,
    CUSTOMER_DEPOSITS_CODE,
    EXPENSE_CATEGORY_TO_ACCOUNT_CODE,
    EXPENSE_DEBT_PAYMENT_METHOD,
    EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE,
    INVENTORY_CODE,
    INVENTORY_PURCHASE_CATEGORIES,
    ORDER_REVENUE_CODE,
    PAYMENT_METHOD_TO_ASSET_CODE,
    PAYMENT_OUTFLOW_TYPES,
    REVENUE_UPDATE_TOLERANCE,
    TIEN_RUT_HELD_CODE,
    TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE,
    UNALLOCATED_BANK_CODE,
    _account_id_by_code,
    _baseline_cost_for_product,
    _ensure_ap_vendor_sub_account,
    _ensure_staff_payable_sub_account,
    _insert_journal_entry,
)
from baker.models.journal_entry import JournalEntry, JournalLine
from baker.models.payment_transaction import PaymentTransaction
from baker.services.cost_resolver import resolve_product_cost

logger = logging.getLogger("baker.server")

STAFF_ADVANCE_PAYMENT_SOURCE = "Nhân viên ứng trước"

# Process-level counter of journal sync failures (review finding OPS-1).
# Incremented by :func:`run_journal_sync` whenever a sync callable raises.
# Exposed via the ``/api/health`` endpoint so operators can detect accumulated
# accounting gaps without tailing logs.
journal_sync_failures: int = 0


def sync_status_to_warning(status: str) -> str:
    return "ok" if status == "ok" else "journal_sync_failed"

# Auto-truncation limit for journal_sync_failure_log (NFR4, DG-226).
_JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS = 10000


def _log_journal_sync_failure(
    conn,
    source_type: str,
    source_id: int,
    error_message: str,
    stack_trace_str: str,
) -> None:
    """Record a journal sync failure in the audit log (NFR2: never throws)."""
    try:
        conn.execute(
            "INSERT INTO journal_sync_failure_log "
            "(source_type, source_id, error_message, stack_trace) "
            "VALUES (?, ?, ?, ?)",
            (source_type, source_id, error_message, stack_trace_str),
        )
        # NFR4: auto-truncate to last 10,000 rows, oldest-first.
        row_count = conn.execute(
            "SELECT COUNT(*) FROM journal_sync_failure_log"
        ).fetchone()[0]
        if row_count > _JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS:
            conn.execute(
                "DELETE FROM journal_sync_failure_log WHERE id NOT IN ("
                "SELECT id FROM journal_sync_failure_log ORDER BY id DESC "
                "LIMIT ?)",
                (_JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS,),
            )
    except Exception:
        pass  # NFR2: log write failure must not cascade into business operation failure


def run_journal_sync(
    sync_fn: Callable[..., None],
    *args: Any,
    log_label: str,
    source_type: Optional[str] = None,
    source_id: Optional[int] = None,
    **kwargs: Any,
) -> str:
    """Run a journal sync callable with non-blocking error handling + observability.

    Wraps the fire-and-forget pattern used by every API endpoint that triggers
    an accounting journal sync (NFR1: accounting failures must never block the
    primary business operation). On failure the exception is logged via
    ``logger.exception`` and the :data:`journal_sync_failures` counter is
    incremented, so the gap is observable through ``/api/health``.

    When ``source_type`` and ``source_id`` are both provided, the failure is
    also recorded in the ``journal_sync_failure_log`` audit table (DG-226) so
    the failure is traceable to a specific source.

    Returns ``"ok"`` when the sync succeeded, or ``"failed"`` when it raised.
    Callers may attach this to their API response (e.g. an
    ``accounting_sync`` field) so the Flutter client can surface a warning.
    """
    global journal_sync_failures
    try:
        sync_fn(*args, **kwargs)
    except Exception as exc:
        journal_sync_failures += 1
        logger.exception("%s failed", log_label)
        if source_type is not None and source_id is not None and args:
            conn = args[0]
            try:
                _log_journal_sync_failure(
                    conn,
                    source_type,
                    source_id,
                    str(exc),
                    traceback.format_exc(),
                )
            except Exception:
                pass  # NFR2: must never cascade into business operation failure
        return "failed"
    return "ok"

# Backwards-compatible alias kept so any external import of the legacy name
# continues to resolve to the centralized constant in ``baker.db.schema``.
_REVENUE_UPDATE_TOLERANCE = REVENUE_UPDATE_TOLERANCE


def _find_journal_entry(conn, source_type: str, source_id: int) -> Optional[int]:
    """Return the journal_entries.id for the given source, or None."""
    row = conn.execute(
        "SELECT id, locked_at FROM journal_entries "
        "WHERE source_type = ? AND source_id = ? ORDER BY id DESC LIMIT 1",
        (source_type, source_id),
    ).fetchone()
    if row is None:
        return None
    return int(row["id"])


def _is_locked(conn, entry_id: int) -> bool:
    row = conn.execute(
        "SELECT locked_at FROM journal_entries WHERE id = ?", (entry_id,)
    ).fetchone()
    return bool(row and row["locked_at"])


def _delete_journal_entry_cascade(conn, entry_id: int) -> None:
    """Delete a journal entry and its lines (CASCADE handled by DB, but be explicit)."""
    conn.execute("DELETE FROM journal_lines WHERE journal_entry_id = ?", (entry_id,))
    conn.execute("DELETE FROM journal_entries WHERE id = ?", (entry_id,))


def _reverse_journal_entry(conn, entry_id: int) -> Optional[int]:
    """Create a reversal entry that swaps debit/credit of the original entry.

    Returns the new reversal entry id, or None if the original has no lines.
    """
    orig = conn.execute(
        "SELECT description, source_type, source_id, transaction_date "
        "FROM journal_entries WHERE id = ?",
        (entry_id,),
    ).fetchone()
    if orig is None:
        return None
    lines = JournalLine.list_for_entry(conn, entry_id)
    if not lines:
        return None
    reversed_lines = [
        (line.account_id, float(line.credit), float(line.debit), line.description or "")
        for line in lines
    ]
    # FR12: the reversal preserves the original entry's transaction_date so
    # the correction relates to the same period as the entry being reversed.
    orig_transaction_date = orig["transaction_date"] if "transaction_date" in orig.keys() else None
    return _insert_journal_entry(
        conn,
        description=f"Reversal: {orig['description']}",
        source_type=orig["source_type"],
        source_id=orig["source_id"],
        lines=reversed_lines,
        transaction_date=orig_transaction_date,
    )


def _update_journal_entry_in_place(
    conn, entry_id: int, *, description: str, lines: list[tuple[int, float, float, str]]
) -> None:
    """Replace the lines of an unlocked journal entry with the given lines."""
    conn.execute("DELETE FROM journal_lines WHERE journal_entry_id = ?", (entry_id,))
    for account_id, debit, credit, line_desc in lines:
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, account_id, float(debit), float(credit), line_desc),
        )
    conn.execute(
        "UPDATE journal_entries SET description = ? WHERE id = ?",
        (description, entry_id),
    )


def _is_expense_journallable(data: dict) -> bool:
    """Return True iff an expense event should produce a journal entry.

    Encodes the build-time skip predicate shared by three call sites that must
    agree on which expense events are by-design journalled:

      - ``_build_expense_journal_lines`` (journal_sync) — the create path.
      - ``_source_sum_expense`` (accounting_validation) — the source-ledger
        SUM must exclude events that produce no JE, or it reports a phantom
        delta (CQ-3).
      - ``_expected_expense_credit`` (repair) — detection must not flag
        unjournalled events as missing/stale, or repair becomes
        non-idempotent and creates phantom vendor sub-accounts (CQ-3/CQ-4).

    An event is journallable iff it has a positive numeric ``amount_vnd``, a
    non-empty ``category`` mapped by ``EXPENSE_CATEGORY_TO_ACCOUNT_CODE``, a
    resolvable payment configuration (``payment_method`` debt, or a
    ``payment_source`` in the asset map), and — for debt / staff-advance
    events — a non-empty ``vendor`` / ``paid_by_name`` respectively.

    This predicate performs no I/O and mutates nothing; callers retain the
    branch-specific resolution (sub-account creation, account-id lookup) after
    it returns True (CQ-5).
    """
    amount = data.get("amount_vnd")
    category = data.get("category")
    payment_source = data.get("payment_source")
    payment_method = data.get("payment_method", "")
    if not isinstance(amount, (int, float)) or amount <= 0:
        return False
    if not isinstance(category, str) or not category:
        return False
    if not EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(category):
        return False
    is_debt = payment_method == EXPENSE_DEBT_PAYMENT_METHOD
    if not is_debt and (not isinstance(payment_source, str) or not payment_source):
        return False
    if is_debt:
        if not (data.get("vendor") or "").strip():
            return False
    elif payment_source == STAFF_ADVANCE_PAYMENT_SOURCE:
        if not (data.get("paid_by_name") or "").strip():
            return False
    else:
        if payment_source not in EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE:
            return False
    return True


def _build_expense_journal_lines(
    conn, data: dict[str, Any], summary: str
) -> Optional[tuple[str, list[tuple[int, float, float, str]]]]:
    """Build (description, lines) for an expense event's journal entry.

    Returns None when the expense data is incomplete/unsupported (silently skip).
    """
    amount = data.get("amount_vnd")
    category = data.get("category")
    payment_source = data.get("payment_source")
    payment_method = data.get("payment_method", "")
    if not _is_expense_journallable(data):
        return None

    is_debt = payment_method == EXPENSE_DEBT_PAYMENT_METHOD
    expense_code = EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(category)

    if is_debt:
        # FR3 (DG-245 Phase 3): debt expenses credit a per-vendor sub-account
        # under Accounts Payable (2500) — not the 2500 parent. The vendor
        # field is the creditor identifier (FR2) and resolves to a single
        # sub-account via _ensure_ap_vendor_sub_account (MAX-based 25xx code).
        vendor_name = (data.get("vendor") or "").strip()
        if not vendor_name:
            return None
        payment_account_id = _ensure_ap_vendor_sub_account(conn, vendor_name)
    elif payment_source == STAFF_ADVANCE_PAYMENT_SOURCE:
        staff_name = (data.get("paid_by_name") or "").strip()
        if not staff_name:
            return None
        payment_account_id = _ensure_staff_payable_sub_account(conn, staff_name)
    else:
        account_code = EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE.get(payment_source)
        if not account_code:
            return None
        payment_account_id = _account_id_by_code(conn, account_code)

    amount_f = float(amount)
    description = f"Expense: {summary}"

    if category in INVENTORY_PURCHASE_CATEGORIES:
        inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
        lines = [
            (inventory_account_id, amount_f, 0.0, "Nhập kho nguyên vật liệu"),
            (payment_account_id, 0.0, amount_f, "Thanh toán"),
        ]
    else:
        expense_account_id = _account_id_by_code(conn, expense_code)
        lines = [
            (expense_account_id, amount_f, 0.0, "Chi phí"),
            (payment_account_id, 0.0, amount_f, "Thanh toán"),
        ]
    return description, lines


def _sync_expense_journal(
    conn,
    event_id: int,
    data: dict[str, Any],
    summary: str,
    *,
    deleted: bool = False,
) -> None:
    """Create/update/delete the journal entry for an expense event.

    Wrap in try/except by the caller — accounting must never break expense CRUD.
    """
    existing_id = _find_journal_entry(conn, "expense", event_id)

    if deleted:
        if existing_id is None:
            return
        if _is_locked(conn, existing_id):
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)
        return

    built = _build_expense_journal_lines(conn, data, summary)
    if built is None:
        # Cannot build new lines; if an existing entry exists and is unlocked,
        # it is now stale — delete it in place.
        if existing_id is not None and not _is_locked(conn, existing_id):
            _delete_journal_entry_cascade(conn, existing_id)
        return
    description, lines = built

    # FR4: the expense event's `timestamp` is the business event date.
    event_row = conn.execute(
        "SELECT timestamp FROM events WHERE id = ?", (event_id,)
    ).fetchone()
    transaction_date = event_row["timestamp"] if event_row else None

    if existing_id is None:
        _insert_journal_entry(
            conn,
            description=description,
            source_type="expense",
            source_id=event_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    elif _is_locked(conn, existing_id):
        # Locked: reverse the original, then create a new correct entry.
        _reverse_journal_entry(conn, existing_id)
        _insert_journal_entry(
            conn,
            description=description,
            source_type="expense",
            source_id=event_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    else:
        _update_journal_entry_in_place(
            conn, existing_id, description=description, lines=lines
        )


def _build_debt_settlement_journal_lines(
    conn, event_summary: str, amount: float, payment_source: str,
    vendor_name: str = "",
) -> Optional[tuple[str, list[tuple[int, float, float, str]]]]:
    """Build (description, lines) for a debt settlement journal entry (FR4/FR5).

    Settlement journals DR the vendor's per-vendor 25xx sub-account under
    Accounts Payable (2500) and CR the asset account chosen by
    ``payment_source`` (FR4). FR5 (DG-245 Phase 4): the debit must hit the
    *same* per-vendor sub-account that the originating debt expense credited,
    so a full settlement nets that sub-account to zero. The sub-account is
    resolved via the single-source-of-truth ``_ensure_ap_vendor_sub_account``
    helper (Phase 3).

    When ``vendor_name`` is empty, fall back to the 2500 parent account
    (preserves backwards compatibility for any legacy settlements that lack a
    vendor). When ``payment_source`` is the staff advance source, the credit
    would go to a per-staff sub-account under 2300 — but settlements do not
    currently carry ``paid_by_name``, so the staff advance path is unsupported
    and the function returns None.
    """
    if amount <= 0:
        return None
    if vendor_name and vendor_name.strip():
        ap_account_id = _ensure_ap_vendor_sub_account(conn, vendor_name.strip())
    else:
        ap_account_id = _account_id_by_code(conn, ACCOUNTS_PAYABLE_CODE)
    account_code = EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE.get(payment_source)
    if not account_code:
        return None
    asset_account_id = _account_id_by_code(conn, account_code)
    amount_f = float(amount)
    description = f"Debt settlement: {event_summary}"
    lines = [
        (ap_account_id, amount_f, 0.0, "Trả nợ nhà cung cấp"),
        (asset_account_id, 0.0, amount_f, "Thanh toán nợ"),
    ]
    return description, lines


def _sync_debt_settlement_journal(
    conn,
    settlement_id: int,
    event_id: int,
    event_summary: str,
    amount: float,
    payment_source: str,
    *,
    deleted: bool = False,
) -> None:
    """Create/update/delete the journal entry for a debt settlement.

    Each settlement has its own journal entry keyed by
    ``source_type='expense_settlement'`` and ``source_id=settlement_id`` so
    multiple partial settlements can coexist on the same expense event. On
    delete, unlocked entries are removed and locked entries are reversed.

    FR5 (DG-245 Phase 4): the vendor is resolved from the originating expense
    event's ``data`` JSON (``event.data["vendor"]``) and passed to
    :func:`_build_debt_settlement_journal_lines` so the settlement debits the
    same per-vendor 25xx sub-account the expense credited. A full settlement
    nets that sub-account to zero.
    """
    existing_id = _find_journal_entry(conn, "expense_settlement", settlement_id)

    if deleted:
        if existing_id is None:
            return
        if _is_locked(conn, existing_id):
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)
        return

    # FR5: resolve the vendor from the originating expense event so the
    # settlement debits the same per-vendor 25xx sub-account.
    vendor_name = ""
    event_row = conn.execute(
        "SELECT data, timestamp FROM events WHERE id = ?", (event_id,)
    ).fetchone()
    transaction_date = None
    if event_row:
        transaction_date = event_row["timestamp"] if "timestamp" in event_row.keys() else None
        try:
            event_data = json.loads(event_row["data"]) if event_row["data"] else {}
        except (ValueError, TypeError):
            event_data = {}
        vendor_name = (event_data.get("vendor") or "").strip() if isinstance(event_data, dict) else ""

    built = _build_debt_settlement_journal_lines(
        conn, event_summary, amount, payment_source, vendor_name=vendor_name
    )
    if built is None:
        if existing_id is not None and not _is_locked(conn, existing_id):
            _delete_journal_entry_cascade(conn, existing_id)
        return
    description, lines = built

    # The settlement's business date is the event's timestamp (the debt was
    # incurred on the event date; settlement records the cash outflow).
    # `transaction_date` is already resolved from `event_row` above.
    if event_row is None:
        transaction_date = None

    if existing_id is None:
        _insert_journal_entry(
            conn,
            description=description,
            source_type="expense_settlement",
            source_id=settlement_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    elif _is_locked(conn, existing_id):
        _reverse_journal_entry(conn, existing_id)
        _insert_journal_entry(
            conn,
            description=description,
            source_type="expense_settlement",
            source_id=settlement_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    else:
        _update_journal_entry_in_place(
            conn, existing_id, description=description, lines=lines
        )


def _bus_shipping_allocation_for_order(
    conn, order_id: int
) -> tuple[str, float]:
    """Return ``(delivery_type, shipping_fee)`` for the order, or ``("pickup", 0)``.

    Reads the orders table directly so callers do not need to pass the values.
    """
    row = conn.execute(
        "SELECT delivery_type, shipping_fee FROM orders WHERE id = ?",
        (order_id,),
    ).fetchone()
    if row is None:
        return "pickup", 0.0
    return (row["delivery_type"] or "pickup"), float(row["shipping_fee"] or 0)


def _held_shipping_for_order(
    conn, order_id: int, *, exclude_txn_id: Optional[int] = None
) -> float:
    """Return the net shipping already held in 2200 for the order.

    Sums 2200 credits (held) minus 2200 debits (released) across all journal
    entries that credit 2200 for this order's shipping. Two source types can
    place shipping into 2200:

    - ``payment_transaction`` entries (Phase 2 payment-time split): the
      shipping portion of a deposit payment credits 2200.
    - ``order_shipping_hold`` entries (Phase 5 backfill): the one-time
      migration moves the shipping portion from 2100 to 2200 for delivered
      bus orders that pre-date the payment split.

    When ``exclude_txn_id`` is given, that transaction's journal entry is
    excluded from the sum — used on the update path so the current
    transaction's stale entry does not skew the allocation. The exclude
    clause only applies to ``payment_transaction`` entries (where
    ``source_id`` is a transaction id); ``order_shipping_hold`` entries are
    never excluded because their ``source_id`` is the order id.
    """
    exclude_clause = ""
    tx_params: list = [order_id]
    if exclude_txn_id is not None:
        exclude_clause = " AND je.source_id != ?"
        tx_params.append(exclude_txn_id)
    # Params: payment_transactions.order_id, [exclude_txn_id], hold source_id,
    # then the account code (shared by both branches via a.code = ?).
    row = conn.execute(
        f"""
        SELECT COALESCE(SUM(jl.credit - jl.debit), 0) AS net_held
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = ?
          AND (
                ( je.source_type = 'payment_transaction'
                    AND je.source_id IN (
                        SELECT id FROM payment_transactions WHERE order_id = ?
                    )
                    {exclude_clause}
                )
             OR
                ( je.source_type = 'order_shipping_hold'
                    AND je.source_id = ?
                )
              )
        """,
        [BUS_SHIPPING_HELD_CODE] + tx_params + [order_id],
    ).fetchone()
    return float(row["net_held"] or 0)


def _held_tien_rut_for_order(
    conn, order_id: int, *, exclude_txn_id: Optional[int] = None
) -> float:
    """Return the net tien_rut currently held in account 2400 for the order.

    Sums 2400 credits (held at payment time — DR Asset / CR 2400) minus 2400
    debits (returned to the customer at delivery, or reversed by
    invalidation/reversal) across the order's ``payment_transaction`` and
    ``order`` journal entries. Used by :func:`_reconcile_order_revenue_entry`
    to determine how much 2400 to return to the customer at delivery (FR3,
    DG-198 reversal).

    ``exclude_txn_id`` excludes that transaction's journal entry from the sum —
    used on the update path so the current transaction's stale entry does not
    skew the total.
    """
    exclude_clause = ""
    params: list = [order_id]
    if exclude_txn_id is not None:
        exclude_clause = " AND je.source_id != ?"
        params.append(exclude_txn_id)
    row = conn.execute(
        f"""
        SELECT COALESCE(SUM(jl.credit - jl.debit), 0) AS net_held
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = ?
          AND je.source_type = 'payment_transaction'
          AND je.source_id IN (
              SELECT id FROM payment_transactions WHERE order_id = ?
          )
          {exclude_clause}
        """,
        [TIEN_RUT_HELD_CODE] + params,
    ).fetchone()
    return float(row["net_held"] or 0)


def _resolve_transaction_asset_code(
    method: str,
    payment_source: str,
) -> str:
    """Resolve the asset account code for a payment_transaction journal line.

    DG-244 Phase 4 routing rules (FR4/FR5/FR8):

      * ``payment_source`` in ``TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE``
        → that bank sub-account (1210 Phượng VCB / 1220 Ân VCB). The
        ``method`` is ignored — when an account is explicitly selected, the
        journal entry references that bank account regardless of method.
      * ``payment_source`` empty/None/unrecognized AND ``method == 'transfer'``
        → ``UNALLOCATED_BANK_CODE`` (1290). This replaces the old
        ``PAYMENT_METHOD_TO_ASSET_CODE['transfer']`` (1200) default so
        unallocated transfer deposits land in a distinct account. Phase 5
        historical backfill will move existing 1200 transfer entries to 1290.
      * ``payment_source`` empty/None/unrecognized AND method is ``cash``/``card``
        → ``PAYMENT_METHOD_TO_ASSET_CODE[method]`` (1100). Non-transfer
        methods keep their existing behavior (FR5 only mandates the
        un-allocated fallback for transfer-type payments routed to a bank).

    Unknown ``payment_source`` values (not in the map) are treated as
    un-allocated rather than rejected, so a stale label never breaks
    journal sync — the entry still balances and is reassignable via Edit
    Payment.
    """
    ps = (payment_source or "").strip()
    if ps and ps in TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE:
        return TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE[ps]
    method_norm = method or "cash"
    if method_norm == "transfer":
        return UNALLOCATED_BANK_CODE
    return PAYMENT_METHOD_TO_ASSET_CODE.get(method_norm, "1100")


def _build_payment_journal_lines(
    conn,
    amount: float,
    ptype: str,
    method: str,
    *,
    order_id: Optional[int] = None,
    delivery_type: str = "pickup",
    shipping_fee: float = 0.0,
    exclude_txn_id: Optional[int] = None,
    payment_source: str = "",
) -> tuple[str, list[tuple[int, float, float, str]]]:
    """Build (description, lines) for a payment_transaction's journal entry.

    Bus orders (``delivery_type == 'bus'``) with ``shipping_fee > 0`` split the
    inflow credit between Customer Deposits (2100) and Bus Shipping Held (2200).
    The shipping portion is allocated to 2200 only up to the order's
    ``shipping_fee`` across all payments (first payments cover shipping; later
    payments go entirely to 2100). ``exclude_txn_id`` is used on the update
    path so the current transaction's stale entry does not skew the allocation.

    Outflow transactions (``refund``) are NOT split — the 2200 release at
    refund time is deferred to Phase 3 (revenue exclusion + shipping release).
    ``refund`` debits 2100 (Customer Deposits) and credits the asset account —
    the reverse of a normal deposit. The held shipping balance in 2200 is
    preserved until the delivery release entry handles it.

    ``tien_rut`` is a deposit inflow (DG-198 reversal): the customer gives cash
    to the shop for safekeeping. It journals DR Asset / CR 2400 (Tien Rut Held)
    — NOT split into 2200 because tien_rut is not a product deposit. At
    delivery 2400 is returned to the customer via a separate ``order`` journal
    entry (see :func:`_reconcile_order_revenue_entry`).

    Non-bus orders and bus orders with no shipping_fee behave exactly as before.

    DG-244 Phase 4: ``payment_source`` routes the asset (debit) side to a
    distinct bank sub-account when set, or to the un-allocated bank account
    (1290) when empty on a transfer. See :func:`_resolve_transaction_asset_code`.
    """
    asset_code = _resolve_transaction_asset_code(method, payment_source)
    asset_account_id = _account_id_by_code(conn, asset_code)
    deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
    tien_rut_account_id = _account_id_by_code(conn, TIEN_RUT_HELD_CODE)
    amount_f = float(amount)
    ptype = ptype or "deposit"

    # Tien rut deposit inflow (DG-198 reversal): DR Asset, CR 2400. Not split
    # into 2200 — tien_rut is cash held for the customer, not a product deposit.
    if ptype == "tien_rut":
        lines = [
            (asset_account_id, amount_f, 0.0, "Tiền khách gửi giữ hộ"),
            (tien_rut_account_id, 0.0, amount_f, "Tiền rút tạm giữ"),
        ]
        description = f"Payment: tien_rut {amount_f}"
        return description, lines

    # Determine the shipping portion to allocate to 2200 for this inflow payment.
    shipping_portion = 0.0
    is_bus = delivery_type == "bus"
    if is_bus and shipping_fee > 0 and order_id is not None:
        already_held = _held_shipping_for_order(
            conn, order_id, exclude_txn_id=exclude_txn_id
        )
        remaining_shipping = max(0.0, shipping_fee - already_held)
        shipping_portion = min(amount_f, remaining_shipping)

    if ptype in PAYMENT_OUTFLOW_TYPES:
        # Refund: cash flows back to customer. Phase 2 does NOT split outflows —
        # the 2200 release is deferred to Phase 3 (delivery shipping release).
        # refund debits 2100 (Customer Deposits) and credits the asset account.
        lines = [
            (deposits_account_id, amount_f, 0.0, "Hoàn tiền khách"),
            (asset_account_id, 0.0, amount_f, "Trả lại tiền"),
        ]
        description = f"Payment: {ptype} {amount_f}"
        return description, lines

    # Inflow: customer pays in. Debit Asset, credit Customer Deposits (+ 2200
    # for the bus shipping portion).
    if shipping_portion > 0:
        bus_shipping_account_id = _account_id_by_code(conn, BUS_SHIPPING_HELD_CODE)
        deposit_portion = amount_f - shipping_portion
        lines = [
            (asset_account_id, amount_f, 0.0, "Tiền khách đặt/cọc"),
            (deposits_account_id, 0.0, deposit_portion, "Tiền khách đặt cọc"),
            (bus_shipping_account_id, 0.0, shipping_portion, "Tiền ship bus giữ hộ"),
        ]
        description = f"Payment: {ptype} {amount_f} (bus shipping split)"
        return description, lines
    # Default inflow (no shipping split)
    lines = [
        (asset_account_id, amount_f, 0.0, "Tiền khách đặt/cọc"),
        (deposits_account_id, 0.0, amount_f, "Tiền khách đặt cọc"),
    ]
    description = f"Payment: {ptype} {amount_f}"
    return description, lines


def _sync_payment_journal(
    conn,
    txn_id: int,
    amount: float,
    ptype: str,
    method: str,
    *,
    order_id: Optional[int] = None,
    delivery_type: str = "pickup",
    shipping_fee: float = 0.0,
    deleted: bool = False,
    payment_source: str = "",
) -> None:
    """Create/update/delete the journal entry for a payment_transaction.

    When ``order_id`` is provided, the order's ``delivery_type`` and
    ``shipping_fee`` are read from the orders table unless explicitly
    overridden by the ``delivery_type`` / ``shipping_fee`` keyword arguments.
    Bus orders with shipping split the credit between 2100 and 2200 (see
    :func:`_build_payment_journal_lines`).

    DG-244 Phase 4: ``payment_source`` is forwarded to
    :func:`_build_payment_journal_lines` so the asset (debit) side routes to
    the selected bank sub-account (1210/1220) or the un-allocated fallback
    (1290) on transfers with no source. On the ``deleted=True`` path the
    existing entry is reversed/deleted directly (no asset re-resolution), so
    ``payment_source`` is informational there.
    """
    # Resolve order context from the orders table when only order_id is given.
    if order_id is not None and (not delivery_type or delivery_type == "pickup") and shipping_fee == 0.0:
        d_type, s_fee = _bus_shipping_allocation_for_order(conn, order_id)
        delivery_type = d_type
        shipping_fee = s_fee

    existing_id = _find_journal_entry(conn, "payment_transaction", txn_id)

    if deleted:
        if existing_id is None:
            return
        if _is_locked(conn, existing_id):
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)
        return

    if not isinstance(amount, (int, float)) or float(amount) <= 0:
        if existing_id is not None and not _is_locked(conn, existing_id):
            _delete_journal_entry_cascade(conn, existing_id)
        return

    # FR4: the payment transaction's `created_at` is the business event date.
    # DG-244 Phase 4: also read the persisted payment_source so callers that
    # don't thread payment_source (e.g. orders.py shipping-fee re-sync) still
    # route to the correct bank sub-account. The column is optional on legacy
    # schemas (added by v76); fall back to '' when absent so historical
    # migration callables don't raise.
    has_payment_source_col = bool(conn.execute(
        "SELECT 1 FROM pragma_table_info('payment_transactions') "
        "WHERE name = 'payment_source'"
    ).fetchone())
    if has_payment_source_col:
        txn_row = conn.execute(
            "SELECT created_at, payment_source FROM payment_transactions WHERE id = ?",
            (txn_id,),
        ).fetchone()
    else:
        txn_row = conn.execute(
            "SELECT created_at, '' AS payment_source FROM payment_transactions WHERE id = ?",
            (txn_id,),
        ).fetchone()
    transaction_date = txn_row["created_at"] if txn_row else None
    # If the caller did not pass payment_source, fall back to the persisted
    # value (e.g. orders.py shipping-fee re-sync path reads rows directly
    # without threading payment_source through). When the caller DOES pass
    # a non-empty value, that wins — it reflects the latest update payload.
    persisted_source = (
        txn_row["payment_source"] if txn_row and "payment_source" in txn_row.keys() else ""
    ) or ""
    effective_source = payment_source if payment_source else persisted_source

    description, lines = _build_payment_journal_lines(
        conn,
        amount,
        ptype,
        method,
        order_id=order_id,
        delivery_type=delivery_type,
        shipping_fee=shipping_fee,
        exclude_txn_id=txn_id if existing_id is not None else None,
        payment_source=effective_source,
    )

    if existing_id is None:
        _insert_journal_entry(
            conn,
            description=description,
            source_type="payment_transaction",
            source_id=txn_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    elif _is_locked(conn, existing_id):
        _reverse_journal_entry(conn, existing_id)
        _insert_journal_entry(
            conn,
            description=description,
            source_type="payment_transaction",
            source_id=txn_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    else:
        _update_journal_entry_in_place(
            conn, existing_id, description=description, lines=lines
        )


def _reconcile_order_revenue_entry(
    conn,
    order_id: int,
    order_ref: str,
    *,
    total_price: Optional[float] = None,
    respect_locks: bool = True,
) -> None:
    """Reconcile the ``source_type = 'order'`` journal entries for a delivered order.

    Single source of truth for revenue recognition — shared by the live sync
    (:func:`_sync_delivered_order_journal`) and the migration backfill
    (:func:`baker.db.schema._backfill_delivered_order_journal_entries`).

    Revenue rules (DG-198 reversal, FR3):
      - Paid orders (any deposits): create a **revenue entry** that debits
        Customer Deposits (2100) for the full deposit balance still held and
        credits Order Revenue (4100) for that same amount. Deposits only —
        tien_rut is NOT netted against deposits. ``deposit_balance =
        deposits_in − refund_total − shipping_held``.
      - Unpaid orders (zero deposits, zero outflows): debit Accounts Receivable
        (1500), credit Order Revenue (4100) for ``total_price`` (customer debt).
      - Negative or zero deposit balance with zero deposits (nothing held):
        no revenue entry is created (nothing to recognise).

    Tien rut return (DG-198 reversal, FR3): separately, when tien_rut is held
    in 2400 for the order, create a **tien rut return entry** that debits
    Tien Rut Held (2400) for the full held amount and credits the asset
    account (the same asset account as the original tien_rut payment method,
    defaulting to 1100 when the method cannot be determined). This returns the
    held cash to the customer at delivery. The two entries are separate so
    deposits→revenue and tien_rut→return are independent transactions.

    Bus shipping exclusion: when the order's ``delivery_type == 'bus'`` and
    ``shipping_fee > 0``, the recognised revenue is reduced by the shipping
    fee, since bus shipping is held separately in account 2200 and must never
    flow into revenue account 4100.

    Update handling: each entry (revenue, tien rut return) is looked up by its
    description prefix and compared against the expected amounts. When they
    differ by more than ``REVENUE_UPDATE_TOLERANCE`` the stale entry is removed
    and a corrected one is created.

    Lock handling (``respect_locks``):
      - ``True`` (default): locked stale entries are *reversed* rather than
        deleted, then a corrected entry is created below. Used by live sync.
      - ``False``: locked entries are deleted unconditionally. Intended for
        migration-only callers that pre-date lock semantics.

    The AR account is seeded idempotently via the chart-of-accounts seed; this
    helper resolves its id directly (review finding Mn-4).
    """
    revenue_account_id = _account_id_by_code(conn, ORDER_REVENUE_CODE)
    deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
    ar_account_id = _account_id_by_code(conn, ACCOUNTS_RECEIVABLE_CODE)
    tien_rut_account_id = _account_id_by_code(conn, TIEN_RUT_HELD_CODE)

    order_row = conn.execute(
        "SELECT delivery_type, shipping_fee, total_price, due_date, created_at FROM orders WHERE id = ?",
        (order_id,),
    ).fetchone()

    # Deposit balance still held in 2100 at delivery. Inflows (deposit /
    # payment / full_payment) credit 2100, refunds debit 2100. tien_rut is a
    # deposit inflow but journals to 2400 (not 2100), so it must be SUBTRACTED
    # from deposits_in so the 2100 debit clears exactly the 2100 balance
    # (deposits only — tien_rut is returned separately). For bus orders the
    # shipping portion is split into 2200 at payment time, so it is also
    # subtracted here.
    deposits_in = float(PaymentTransaction.total_paid_excl_outflows(conn, order_id))
    tien_rut_total = float(PaymentTransaction.total_tien_rut(conn, order_id))
    refund_total = float(PaymentTransaction.total_outflows(conn, order_id))
    shipping_held = 0.0
    if order_row is not None:
        delivery_type = order_row["delivery_type"] or "pickup"
        shipping_fee = float(order_row["shipping_fee"] or 0)
        if delivery_type == "bus" and shipping_fee > 0:
            shipping_held = shipping_fee
    deposit_balance = max(0.0, deposits_in - tien_rut_total - refund_total - shipping_held)

    # Net revenue (4100 credit) = deposit balance. Deposits only — tien_rut is
    # returned separately and does not reduce revenue.
    revenue_amount = deposit_balance

    # Tien rut held in 2400 (credits at payment time minus debits at return).
    tien_rut_held = _held_tien_rut_for_order(conn, order_id)

    order_transaction_date = now_utc()

    # --- Revenue entry (deposits → 4100) -----------------------------------
    _reconcile_revenue_entry_lines(
        conn,
        order_id=order_id,
        order_ref=order_ref,
        revenue_account_id=revenue_account_id,
        deposits_account_id=deposits_account_id,
        ar_account_id=ar_account_id,
        deposit_balance=deposit_balance,
        revenue_amount=revenue_amount,
        total_price=total_price,
        order_row=order_row,
        order_transaction_date=order_transaction_date,
        respect_locks=respect_locks,
        deposits_in=deposits_in,
        tien_rut_total=tien_rut_total,
    )

    # --- Tien rut return entry (2400 → Asset) ------------------------------
    _reconcile_tien_rut_return_entry(
        conn,
        order_id=order_id,
        order_ref=order_ref,
        tien_rut_account_id=tien_rut_account_id,
        tien_rut_held=tien_rut_held,
        order_transaction_date=order_transaction_date,
        respect_locks=respect_locks,
    )


# Description prefixes used to identify the two order journal entries.
_REVENUE_ENTRY_PREFIX = "Order revenue:"
_AR_ENTRY_PREFIX = "Order revenue (AR):"
_TIEN_RUT_RETURN_PREFIX = "Tien rut return:"


def _find_order_entry_by_prefix(conn, order_id: int, prefix: str) -> Optional[int]:
    """Return the id of the ``source_type='order'`` entry whose description
    starts with ``prefix``, or None."""
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'order' AND source_id = ? AND description LIKE ? "
        "ORDER BY id DESC LIMIT 1",
        (order_id, prefix + "%"),
    ).fetchone()
    return int(row["id"]) if row else None


def _replace_order_entry(
    conn,
    existing_id: int,
    *,
    respect_locks: bool,
) -> None:
    """Reverse (locked) or delete (unlocked) a stale order journal entry."""
    if respect_locks and _is_locked(conn, existing_id):
        _reverse_journal_entry(conn, existing_id)
    else:
        _delete_journal_entry_cascade(conn, existing_id)


def _sync_cancelled_order_journal(conn, order_id: int) -> None:
    """Reverse (locked) or delete (unlocked) accounting entries for a cancelled order.

    Handles revenue, COGS, and shipping release entries — internal accounting
    entries that can be auto-reversed on cancellation. Payment transaction
    entries are deliberately excluded: they represent real cash that requires
    a human decision (refund vs. manual invalidation).
    """
    entry_id = _find_order_entry_by_prefix(conn, order_id, _REVENUE_ENTRY_PREFIX)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

    entry_id = _find_order_entry_by_prefix(conn, order_id, _AR_ENTRY_PREFIX)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

    entry_id = _find_order_entry_by_prefix(conn, order_id, _TIEN_RUT_RETURN_PREFIX)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

    entry_id = _find_journal_entry(conn, 'order_cogs', order_id)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

    entry_id = _find_journal_entry(conn, 'order_shipping_release', order_id)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)


def _reconcile_revenue_entry_lines(
    conn,
    *,
    order_id: int,
    order_ref: str,
    revenue_account_id: int,
    deposits_account_id: int,
    ar_account_id: int,
    deposit_balance: float,
    revenue_amount: float,
    total_price: Optional[float],
    order_row,
    order_transaction_date,
    respect_locks: bool,
    deposits_in: float,
    tien_rut_total: float,
) -> None:
    """Create/update the deposits→revenue (or AR) ``source_type='order'`` entry.

    Looked up by the ``Order revenue:`` / ``Order revenue (AR):`` description
    prefix so it is distinguishable from the tien rut return entry (which
    shares the same source_type/source_id).
    """
    is_ar = deposit_balance <= 0 and (deposits_in - tien_rut_total) <= 0
    prefix = _AR_ENTRY_PREFIX if is_ar else _REVENUE_ENTRY_PREFIX
    existing_id = _find_order_entry_by_prefix(conn, order_id, prefix)

    if is_ar:
        # Truly unpaid (no deposits and no refunds): record the order total
        # as accounts receivable (customer debt). Bus shipping exclusion does
        # not apply here because there were no deposits to hold shipping in
        # 2200; the full order total remains a receivable. When total_price
        # is unknown the order row is read from the orders table to remain
        # backwards compatible with callers that omit it.
        if total_price is None:
            total_price = float(order_row["total_price"] or 0) if order_row else 0.0
        if total_price <= 0:
            return  # nothing to recognise
        expected_debit = float(total_price)
        expected_credit_4100 = float(total_price)
        if existing_id is not None:
            row = conn.execute(
                """
                SELECT
                  COALESCE(SUM(CASE WHEN a.code = ? THEN jl.debit ELSE 0 END), 0) AS debit_1500,
                  COALESCE(SUM(CASE WHEN a.code = ? THEN jl.credit ELSE 0 END), 0) AS credit_4100
                FROM journal_lines jl
                JOIN accounts a ON a.id = jl.account_id
                WHERE jl.journal_entry_id = ?
                """,
                (ACCOUNTS_RECEIVABLE_CODE, ORDER_REVENUE_CODE, existing_id),
            ).fetchone()
            mismatch = abs(float(row["debit_1500"]) - expected_debit) + abs(
                float(row["credit_4100"]) - expected_credit_4100
            )
            if mismatch <= REVENUE_UPDATE_TOLERANCE:
                return
            _replace_order_entry(conn, existing_id, respect_locks=respect_locks)
        _insert_journal_entry(
            conn,
            description=f"Order revenue (AR): {order_ref}",
            source_type="order",
            source_id=order_id,
            lines=[
                (ar_account_id, expected_debit, 0.0, "Phải thu khách hàng"),
                (revenue_account_id, 0.0, expected_credit_4100, "Doanh thu bán hàng"),
            ],
            transaction_date=order_transaction_date,
        )
        return

    # Paid: clear the full 2100 deposit balance to revenue (DR 2100, CR 4100).
    # Deposits only — tien_rut is returned separately. Lines with a zero amount
    # are omitted so double-entry integrity holds (DG-198 reversal, FR3).
    if deposit_balance <= 0:
        # deposit_balance <= 0 but deposits existed (nothing held, e.g. fully
        # refunded) → no revenue to recognise; remove any stale revenue entry.
        if existing_id is not None:
            _replace_order_entry(conn, existing_id, respect_locks=respect_locks)
        return

    if existing_id is not None:
        row = conn.execute(
            """
            SELECT
              COALESCE(SUM(CASE WHEN a.code = ? THEN jl.debit ELSE 0 END), 0) AS debit_2100,
              COALESCE(SUM(CASE WHEN a.code = ? THEN jl.credit ELSE 0 END), 0) AS credit_4100
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ?
            """,
            (CUSTOMER_DEPOSITS_CODE, ORDER_REVENUE_CODE, existing_id),
        ).fetchone()
        mismatch = abs(float(row["debit_2100"]) - deposit_balance) + abs(
            float(row["credit_4100"]) - revenue_amount
        )
        if mismatch <= REVENUE_UPDATE_TOLERANCE:
            return
        _replace_order_entry(conn, existing_id, respect_locks=respect_locks)

    lines: list[tuple[int, float, float, str]] = [
        (deposits_account_id, deposit_balance, 0.0, "Chuyển cọc sang doanh thu"),
    ]
    if revenue_amount > 0:
        lines.append(
            (revenue_account_id, 0.0, revenue_amount, "Doanh thu bán hàng")
        )
    _insert_journal_entry(
        conn,
        description=f"Order revenue: {order_ref}",
        source_type="order",
        source_id=order_id,
        lines=lines,
        transaction_date=order_transaction_date,
    )


def _resolve_tien_rut_return_asset_account(conn, order_id: int) -> int:
    """Resolve the asset account to credit for the tien rut return entry.

    Uses the same asset account as the original tien_rut payment method. When
    the order has multiple tien_rut transactions with different methods, the
    first one's method is used. Defaults to 1100 (Cash on Hand) when no
    tien_rut payment exists or the method is unknown.

    DG-244 Phase 4: when the first tien_rut transaction carries a
    ``payment_source``, the return credits the same bank sub-account the
    original deposit debited (so the held balance and its return net to zero
    on the same account).

    The ``payment_source`` column is optional on legacy schemas (added by
    migration v76). When absent we fall back to the pre-Phase-4 method-based
    resolution so historical migration callables (v44 backfill) still work on
    pre-v76 databases.
    """
    from baker.models.payment_transaction import _invalidation_filter

    invalidation = _invalidation_filter(conn)
    # Detect the payment_source column once; v44 backfill runs before v76 has
    # added it, so a bare SELECT pt.payment_source would raise OperationalError.
    has_payment_source_col = bool(conn.execute(
        "SELECT 1 FROM pragma_table_info('payment_transactions') "
        "WHERE name = 'payment_source'"
    ).fetchone())
    source_expr = "pt.payment_source" if has_payment_source_col else "''"
    row = conn.execute(
        f"""
        SELECT pt.method AS method, {source_expr} AS payment_source
        FROM payment_transactions pt
        WHERE pt.order_id = ? AND pt.type = 'tien_rut'
          {invalidation}
        ORDER BY pt.id ASC LIMIT 1
        """,
        (order_id,),
    ).fetchone()
    method = row["method"] if row else "cash"
    payment_source = (row["payment_source"] if row else "") or ""
    asset_code = _resolve_transaction_asset_code(method, payment_source)
    return _account_id_by_code(conn, asset_code)


def _reconcile_tien_rut_return_entry(
    conn,
    *,
    order_id: int,
    order_ref: str,
    tien_rut_account_id: int,
    tien_rut_held: float,
    order_transaction_date,
    respect_locks: bool,
) -> None:
    """Create/update the tien rut return ``source_type='order'`` entry.

    At delivery the full tien_rut held in 2400 is returned to the customer:
    DR 2400 (Tien Rut Held), CR Asset (cash returned). Looked up by the
    ``Tien rut return:`` description prefix so it is distinguishable from the
    revenue entry (which shares the same source_type/source_id).

    When ``tien_rut_held <= 0`` any existing return entry is removed (the
    holding has already been cleared or was reversed).
    """
    existing_id = _find_order_entry_by_prefix(conn, order_id, _TIEN_RUT_RETURN_PREFIX)

    if tien_rut_held <= 0:
        if existing_id is not None:
            _replace_order_entry(conn, existing_id, respect_locks=respect_locks)
        return

    asset_account_id = _resolve_tien_rut_return_asset_account(conn, order_id)

    if existing_id is not None:
        row = conn.execute(
            """
            SELECT
              COALESCE(SUM(CASE WHEN a.code = ? THEN jl.debit ELSE 0 END), 0) AS debit_2400,
              COALESCE(SUM(CASE WHEN a.code IN ('1100','1200','1210','1220','1290') THEN jl.credit ELSE 0 END), 0) AS credit_asset
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ?
            """,
            (TIEN_RUT_HELD_CODE, existing_id),
        ).fetchone()
        mismatch = abs(float(row["debit_2400"]) - tien_rut_held) + abs(
            float(row["credit_asset"]) - tien_rut_held
        )
        if mismatch <= REVENUE_UPDATE_TOLERANCE:
            return
        _replace_order_entry(conn, existing_id, respect_locks=respect_locks)

    _insert_journal_entry(
        conn,
        description=f"Tien rut return: {order_ref}",
        source_type="order",
        source_id=order_id,
        lines=[
            (tien_rut_account_id, tien_rut_held, 0.0, "Trả tiền rút cho khách"),
            (asset_account_id, 0.0, tien_rut_held, "Tiền rút đã trả"),
        ],
        transaction_date=order_transaction_date,
    )


def _sync_bus_shipping_release_entry(
    conn, order_id: int, order_ref: str
) -> None:
    """Create the shipping release entry for a delivered bus order (FR4).

    Bus orders hold the shipping fee in account 2200 at payment time (see
    :func:`_build_payment_journal_lines`). At delivery the held shipping is
    released to the cash asset account (1100): debit 2200, credit 1100.

    Behaviour:
      - Non-bus orders or ``shipping_fee <= 0``: no-op.
      - The release amount is ``min(shipping_fee, held_in_2200)`` so the
        entry never releases more than was actually held.
      - Idempotent: when an existing ``order_shipping_release`` entry matches
        the expected release amount (within tolerance), it is left untouched.
      - Lock semantics (FR6): a locked stale entry is *reversed* then a
        corrected entry is created; an unlocked stale entry is *deleted* and
        recreated.
    """
    order_row = conn.execute(
        "SELECT delivery_type, shipping_fee, due_date, created_at FROM orders WHERE id = ?",
        (order_id,),
    ).fetchone()
    if order_row is None:
        return
    delivery_type = order_row["delivery_type"] or "pickup"
    shipping_fee = float(order_row["shipping_fee"] or 0)
    if delivery_type != "bus" or shipping_fee <= 0:
        return

    held_in_2200 = _held_shipping_for_order(conn, order_id)
    release_amount = min(shipping_fee, held_in_2200)
    if release_amount <= 0:
        return

    bus_shipping_account_id = _account_id_by_code(conn, BUS_SHIPPING_HELD_CODE)
    asset_code = PAYMENT_METHOD_TO_ASSET_CODE.get("cash", "1100")
    asset_account_id = _account_id_by_code(conn, asset_code)
    description = f"Shipping release: {order_ref}"
    order_transaction_date = now_utc()

    existing_id = _find_journal_entry(
        conn, "order_shipping_release", order_id
    )
    if existing_id is not None:
        # Compare the existing entry's 2200 debit against release_amount.
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
        if abs(current_debit - release_amount) <= REVENUE_UPDATE_TOLERANCE:
            # Already in sync — idempotent no-op.
            return
        if _is_locked(conn, existing_id):
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)

    _insert_journal_entry(
        conn,
        description=description,
        source_type="order_shipping_release",
        source_id=order_id,
        lines=[
            (bus_shipping_account_id, release_amount, 0.0, "Thanh toán ship bus"),
            (asset_account_id, 0.0, release_amount, "Tiền ship bus đã trả"),
        ],
        transaction_date=order_transaction_date,
    )


def _sync_delivered_order_journal(conn, order_id: int, order_ref: str) -> None:
    """Create/update revenue conversion + COGS journal entries for a delivered/completed order.

    Revenue recognition is delegated to :func:`_reconcile_order_revenue_entry`
    (see its docstring for the paid/unpaid/refund-drained rules). This wrapper
    then handles COGS.

    COGS: one entry per order summing cost_at_sale*qty for items with a
    resolved cost > 0. cost_at_sale is populated at delivery time from
    cost_history (via resolve_product_cost), applying the documented baseline
    fallback when no historical cost is in effect.
    """
    _reconcile_order_revenue_entry(conn, order_id, order_ref, respect_locks=True)

    # Release the held bus shipping (2200 → 1100) at delivery (FR4). Wrapped in
    # the shared non-blocking wrapper so accounting failures never block the
    # primary business operation (NFR1) and are observable via the
    # ``journal_sync_failures`` counter (review finding OPS-1).
    run_journal_sync(
        _sync_bus_shipping_release_entry,
        conn, order_id, order_ref,
        log_label=f"bus shipping release sync for order {order_id} ({order_ref})",
    )

    _sync_order_cogs_entry(conn, order_id, order_ref)


def _compute_order_cogs_total(
    conn, order_id: int, *, populate_cost_at_sale: bool = True, force: bool = False
) -> float:
    """Compute the expected total COGS for an order (DG-208 Phase 5).

    Iterates the order's non-extra/non-gift items. For each item:

    - When ``cost_at_sale > 0`` and ``force`` is False the snapshotted value is
      used as-is (historical cost is preserved — review finding from the
      requirements risk register: "Backfill only touches orders where COGS is
      missing or cost_at_sale = 0; existing non-zero cost_at_sale is
      preserved").
    - When ``cost_at_sale == 0`` or ``force`` is True the cost is resolved via
      :func:`resolve_product_cost` using ``unit_price`` as the baseline anchor
      (DG-208 Phase 1, FR1/FR2). When ``populate_cost_at_sale`` is True the
      resolved value is also written back to ``order_items.cost_at_sale``
      (delivery-time snapshot behaviour). When False the row is left untouched
      — used by the COGS repair to compute the *expected* total without side
      effects before deciding whether to mutate.

    Returns the summed ``cost * qty`` as a non-negative ``float``.
    """
    items = conn.execute(
        "SELECT oi.id AS item_id, oi.product_id, oi.quantity, oi.cost_at_sale, "
        "oi.unit_price "
        "FROM order_items oi "
        "WHERE oi.order_id = ? AND oi.is_extra = 0 AND oi.is_gift = 0",
        (order_id,),
    ).fetchall()
    total_cogs = 0.0
    for irow in items:
        qty = int(irow["quantity"] or 0)
        if qty <= 0:
            continue
        cost_at_sale = float(irow["cost_at_sale"] or 0)
        if cost_at_sale == 0 or force:
            product_id = irow["product_id"]
            pid: int | None = None
            if product_id is not None:
                try:
                    pid = int(product_id)
                except (TypeError, ValueError):
                    pid = None
            selling_price = float(irow["unit_price"] or 0) or None
            if pid is None:
                # Unresolvable product_id (e.g. custom codes like BKS-DG-01
                # with no products row). Apply the 30% non-phụ-kiện baseline
                # directly to unit_price — mirrors the v45 backfill fallback
                # in _backfill_order_items_cost_at_sale so the live delivery
                # path no longer silently contributes 0 to COGS
                # (DG-208 review finding CQ-2). Unresolvable products are
                # never phụ kiện (phụ kiện is always a resolvable category).
                anchor = selling_price if (selling_price and selling_price > 0) else 0.0
                if anchor > 0:
                    cost_at_sale = _baseline_cost_for_product(
                        "", 0.0, price_override=anchor
                    )
                else:
                    cost_at_sale = 0.0
            else:
                cost_at_sale = resolve_product_cost(conn, pid, selling_price=selling_price)
            if cost_at_sale > 0 and populate_cost_at_sale:
                conn.execute(
                    "UPDATE order_items SET cost_at_sale = ? WHERE id = ?",
                    (cost_at_sale, int(irow["item_id"])),
                )
        if cost_at_sale > 0:
            total_cogs += cost_at_sale * qty
    return total_cogs


def _order_cogs_entry(conn, order_id: int) -> tuple:
    """Return ``(entry_id, cogs_debit_total)`` for the order's order_cogs entry.

    Looks up the ``source_type = 'order_cogs'`` entry and sums the debit on the
    COGS (5900) account. Returns ``(None, 0.0)`` when the order has no
    order_cogs entry or the entry has no COGS debit line.
    """
    row = conn.execute(
        """
        SELECT je.id AS entry_id, COALESCE(SUM(jl.debit), 0) AS cogs_debit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order_cogs' AND je.source_id = ? AND a.code = ?
        GROUP BY je.id
        """,
        (order_id, COGS_CODE),
    ).fetchone()
    if row is None:
        return None, 0.0
    return int(row["entry_id"]), float(row["cogs_debit"])


def _sync_order_cogs_entry(
    conn,
    order_id: int,
    order_ref: str,
    *,
    total_cogs_override: Optional[float] = None,
) -> None:
    """Create the ``order_cogs`` journal entry for a delivered order if absent.

    Computes the total COGS via :func:`_compute_order_cogs_total` (populating
    ``cost_at_sale`` for any zero-cost items using the current cost_history /
    baseline rule with ``unit_price`` as the anchor), then inserts a single
    ``order_cogs`` journal entry (DR COGS 5900 / CR Inventory 1300).

    When ``total_cogs_override`` is provided, the internal
    :func:`_compute_order_cogs_total` call is skipped and the supplied total
    is used directly. The caller MUST ensure the override was computed with
    ``populate_cost_at_sale=True`` (so ``cost_at_sale`` rows are already
    written) — this avoids a redundant re-scan of ``order_items``
    (DG-208 review finding CQ-3, used by the COGS stale-entry repair path).

    Idempotent: skips when an ``order_cogs`` entry already exists for the
    order. The COGS entry is created once per order with the accumulated
    total from all items (inserting inside the per-item loop previously
    produced duplicate entries with partial totals — review finding C-1).
    """
    existing_cogs = conn.execute(
        "SELECT 1 FROM journal_entries WHERE source_type = 'order_cogs' AND source_id = ?",
        (order_id,),
    ).fetchone()
    if existing_cogs:
        return

    if total_cogs_override is not None:
        total_cogs = float(total_cogs_override)
    else:
        total_cogs = _compute_order_cogs_total(conn, order_id, populate_cost_at_sale=True)
    if total_cogs <= 0:
        return

    cogs_account_id = _account_id_by_code(conn, COGS_CODE)
    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    order_transaction_date = now_utc()
    _insert_journal_entry(
        conn,
        description=f"Order COGS: {order_ref}",
        source_type="order_cogs",
        source_id=order_id,
        lines=[
            (cogs_account_id, total_cogs, 0.0, "Giá vốn hàng bán"),
            (inventory_account_id, 0.0, total_cogs, "Xuất kho"),
        ],
        transaction_date=order_transaction_date,
    )


def _sync_waste_cogs_journal(
    conn, product_id: int, movement_id: int, quantity: int
) -> None:
    """Create a COGS journal entry for wasted stock (source_type ``waste_cogs``).

    Debits COGS (5900) and credits Inventory (1300) for the cost of the wasted
    quantity. Cost is resolved via :func:`resolve_product_cost` (cost_history →
    baseline fallback). When the resolved cost is zero, no entry is created
    (consistent with sale COGS behaviour for zero-cost items).

    Idempotent: skips when a ``waste_cogs`` entry already exists for the given
    stock movement.
    """
    if quantity <= 0:
        return

    existing = conn.execute(
        "SELECT 1 FROM journal_entries WHERE source_type = 'waste_cogs' AND source_id = ?",
        (movement_id,),
    ).fetchone()
    if existing:
        return

    unit_cost = resolve_product_cost(conn, product_id)
    total = unit_cost * quantity
    if total <= 0:
        return

    # FR5: waste COGS uses the stock movement's `created_at` as the business
    # event date (queried via source_id = movement_id).
    movement_row = conn.execute(
        "SELECT created_at FROM stock_movements WHERE id = ?", (movement_id,)
    ).fetchone()
    transaction_date = movement_row["created_at"] if movement_row else None

    cogs_account_id = _account_id_by_code(conn, COGS_CODE)
    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    _insert_journal_entry(
        conn,
        description=f"Waste COGS: movement #{movement_id} product {product_id}",
        source_type="waste_cogs",
        source_id=movement_id,
        lines=[
            (cogs_account_id, float(total), 0.0, "Giá vốn hàng hao hụt"),
            (inventory_account_id, 0.0, float(total), "Xuất kho hao hụt"),
        ],
        transaction_date=transaction_date,
    )


def _sync_negative_sale_cogs_journal(
    conn, product_id: int, movement_id: int, quantity: int
) -> None:
    """Create a COGS journal entry for a negative (oversold) sale.

    DG-200 Phase 4, AC-8. Mirrors :func:`_sync_waste_cogs_journal`: debits
    COGS (5900) and credits Inventory (1300) for the cost of the oversold
    quantity. Cost is resolved via :func:`resolve_product_cost`
    (cost_history → baseline fallback). When the resolved cost is zero, no
    entry is created (consistent with sale/waste COGS behaviour for
    zero-cost items).

    Idempotent: skips when a ``negative_sale_cogs`` entry already exists for
    the given stock movement. The stock movement's ``created_at`` is used as
    the business event date (FR4-style).
    """
    if quantity <= 0:
        return

    existing = conn.execute(
        "SELECT 1 FROM journal_entries WHERE source_type = 'negative_sale_cogs' "
        "AND source_id = ?",
        (movement_id,),
    ).fetchone()
    if existing:
        return

    unit_cost = resolve_product_cost(conn, product_id)
    total = unit_cost * quantity
    if total <= 0:
        return

    movement_row = conn.execute(
        "SELECT created_at FROM stock_movements WHERE id = ?", (movement_id,)
    ).fetchone()
    transaction_date = movement_row["created_at"] if movement_row else None

    cogs_account_id = _account_id_by_code(conn, COGS_CODE)
    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    _insert_journal_entry(
        conn,
        description=f"Negative sale COGS: movement #{movement_id} product {product_id}",
        source_type="negative_sale_cogs",
        source_id=movement_id,
        lines=[
            (cogs_account_id, float(total), 0.0, "Giá vốn bán âm"),
            (inventory_account_id, 0.0, float(total), "Xuất kho bán âm"),
        ],
        transaction_date=transaction_date,
    )


def _sync_restock_inflow_journal(
    conn, product_id: int, movement_id: int, quantity: int
) -> None:
    """Create an Inventory debit journal entry for a reconciliation surplus inflow.

    DG-200 Phase 4, AC-9. The mirror of :func:`_sync_waste_cogs_journal` /
    :func:`_sync_negative_sale_cogs_journal`: debits Inventory (1300) and
    credits COGS (5900) for the cost of the restocked quantity. Cost is
    resolved via :func:`resolve_product_cost` (cost_history → baseline
    fallback). When the resolved cost is zero, no entry is created
    (consistent with the other COGS flows).

    Idempotent: skips when a ``restock_inflow`` entry already exists for the
    given stock movement. The stock movement's ``created_at`` is used as the
    business event date.
    """
    if quantity <= 0:
        return

    existing = conn.execute(
        "SELECT 1 FROM journal_entries WHERE source_type = 'restock_inflow' "
        "AND source_id = ?",
        (movement_id,),
    ).fetchone()
    if existing:
        return

    unit_cost = resolve_product_cost(conn, product_id)
    total = unit_cost * quantity
    if total <= 0:
        return

    movement_row = conn.execute(
        "SELECT created_at FROM stock_movements WHERE id = ?", (movement_id,)
    ).fetchone()
    transaction_date = movement_row["created_at"] if movement_row else None

    cogs_account_id = _account_id_by_code(conn, COGS_CODE)
    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    _insert_journal_entry(
        conn,
        description=f"Restock inflow: movement #{movement_id} product {product_id}",
        source_type="restock_inflow",
        source_id=movement_id,
        lines=[
            (inventory_account_id, float(total), 0.0, "Nhập kho thừa kiểm kê"),
            (cogs_account_id, 0.0, float(total), "Hoàn giá vốn nhập lại"),
        ],
        transaction_date=transaction_date,
    )
