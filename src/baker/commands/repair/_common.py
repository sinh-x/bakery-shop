"""Shared constants, imports, and helpers for the repair command package."""

import json
import logging
import click
from baker.db.connection import get_db
from baker.db.schema import (
    ACCOUNTS_PAYABLE_CODE,
    ACCOUNTS_RECEIVABLE_CODE,
    BUS_SHIPPING_HELD_CODE,
    CUSTOMER_DEPOSITS_CODE,
    EXPENSE_CATEGORY_TO_ACCOUNT_CODE,
    EXPENSE_DEBT_PAYMENT_METHOD,
    EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE,
    INVENTORY_PURCHASE_CATEGORIES,
    PAYMENT_METHOD_TO_ASSET_CODE,
    REVENUE_UPDATE_TOLERANCE,
    TIEN_RUT_HELD_CODE,
    TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE,
    UNALLOCATED_BANK_CODE,
    _account_id_by_code,
    _ensure_ap_vendor_sub_account,
    _insert_journal_entry,
)
from baker.formatters import format_vnd_amount
from baker.utils.time import now_utc
from baker.models.cash_drawer import CashDrawer
from baker.models.payment_transaction import PaymentTransaction
from baker.services.journal_sync import (
    STAFF_ADVANCE_PAYMENT_SOURCE,
    _AR_ENTRY_PREFIX,
    _TIEN_RUT_RETURN_PREFIX,
    _compute_order_cogs_total,
    _delete_journal_entry_cascade,
    _find_journal_entry,
    _find_order_entry_by_prefix,
    _held_shipping_for_order,
    _held_tien_rut_for_order,
    _is_expense_journallable,
    _is_locked,
    _order_cogs_entry,
    _reconcile_order_revenue_entry,
    _reconcile_tien_rut_return_entry,
    _replace_order_entry,
    _resolve_delivered_timestamp,
    _resolve_shipping_release_asset_account,
    _reverse_journal_entry,
    _sync_cancelled_order_journal,
    _sync_delivered_order_journal,
    _sync_expense_journal,
    _sync_order_cogs_entry,
    _sync_payment_journal,
    run_journal_sync,
)

logger = logging.getLogger(__name__)

DELIVERED_STATUSES = ("delivered", "completed")

MISMATCH_TOLERANCE = REVENUE_UPDATE_TOLERANCE

# Owner's Cash (sub-account of 1100) — used by the shipping-release repair
# when no open drawer covers the order's delivery timestamp (FR4). Mirrors the
# 1102 routing used elsewhere in the codebase (api/cash_drawer.py).
OWNER_CASH_CODE = "1102"

# Shipping-release repair action labels (Vietnamese) — extends _ACTION_LABELS
# with the backfill vocabulary used by _print_shipping_release_report.
SHIPPING_RELEASE_ACTION_LABELS = {
    "backfilled": "đã tạo",
    "will-backfill": "sẽ tạo",
}

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


__all__ = [
    'ACCOUNTS_PAYABLE_CODE',
    'ACCOUNTS_RECEIVABLE_CODE',
    'BUS_SHIPPING_HELD_CODE',
    'CashDrawer',
    'CUSTOMER_DEPOSITS_CODE',
    'DELIVERED_STATUSES',
    'EXPENSE_CATEGORY_TO_ACCOUNT_CODE',
    'EXPENSE_DEBT_PAYMENT_METHOD',
    'EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE',
    'INVENTORY_PURCHASE_CATEGORIES',
    'MISMATCH_TOLERANCE',
    'OWNER_CASH_CODE',
    'PAYMENT_METHOD_TO_ASSET_CODE',
    'PaymentTransaction',
    'REVENUE_UPDATE_TOLERANCE',
    'SHIPPING_RELEASE_ACTION_LABELS',
    'STAFF_ADVANCE_PAYMENT_SOURCE',
    'TIEN_RUT_HELD_CODE',
    'TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE',
    'UNALLOCATED_BANK_CODE',
    '_ACTION_LABELS',
    '_AR_ENTRY_PREFIX',
    '_TIEN_RUT_RETURN_PREFIX',
    '_account_id_by_code',
    '_compute_order_cogs_total',
    '_delete_journal_entry_cascade',
    '_ensure_ap_vendor_sub_account',
    '_find_journal_entry',
    '_find_order_entry_by_prefix',
    '_held_shipping_for_order',
    '_held_tien_rut_for_order',
    '_insert_journal_entry',
    '_is_expense_journallable',
    '_is_locked',
    '_order_cogs_entry',
    '_order_ref',
    '_order_revenue_2100_debit',
    '_reconcile_order_revenue_entry',
    '_reconcile_tien_rut_return_entry',
    '_replace_order_entry',
    '_resolve_delivered_timestamp',
    '_resolve_shipping_release_asset_account',
    '_reverse_journal_entry',
    '_sync_cancelled_order_journal',
    '_sync_delivered_order_journal',
    '_sync_expense_journal',
    '_sync_order_cogs_entry',
    '_sync_payment_journal',
    '_vn_amount',
    'click',
    'format_vnd_amount',
    'get_db',
    'json',
    'logger',
    'logging',
    'now_utc',
    'run_journal_sync',
]
