"""Journal auto-generation sync helpers (DG-308 Phase 4.4, FR-ARCH-2).

This package splits the original monolithic ``journal_sync.py`` (1,999 lines)
into domain submodules while preserving the public import surface. All symbols
previously importable from ``baker.services.journal_sync`` remain available at
the package root via re-export, so existing callers (api/orders, api/events,
api/payment_transactions, api/stock, api/reconciliations, services/order_stock,
services/accounting_validation, db/schema, commands/repair) continue to work
unchanged.

Submodule layout:

- ``_common`` — non-blocking runner (``run_journal_sync``), failure counter/log,
  generic journal-entry CRUD helpers, delivered-timestamp resolver.
- ``expense`` — expense event + debt-settlement journal sync.
- ``payment`` — payment-transaction journal sync + held-shipping/tien-rut helpers.
- ``order`` — order revenue recognition, AR, tien-rut return, bus-shipping
  release, cancellation, completed/delivered orchestrators.
- ``waste`` — order COGS, gift COGS, waste COGS, negative-sale COGS, restock
  inflow.

Accounting failures must never block the primary business operation: callers
wrap each ``_sync_*`` call in try/except with ``logger.exception``.
"""

from baker.services.journal_sync import _common as _common_mod


def __getattr__(name):
    # PEP 562 module-level proxy. ``journal_sync_failures`` is a mutable
    # process-level counter owned by ``_common``; re-exporting it as a static
    # binding would freeze the value at import time and hide increments from
    # callers reading ``baker.services.journal_sync.journal_sync_failures``.
    # Proxy the lookup to the live ``_common`` attribute instead.
    if name == "journal_sync_failures":
        return _common_mod.journal_sync_failures
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


from baker.services.journal_sync._common import (
    STAFF_ADVANCE_PAYMENT_SOURCE,
    _JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS,
    _REVENUE_UPDATE_TOLERANCE,
    _delete_journal_entry_cascade,
    _find_journal_entry,
    _is_locked,
    _log_journal_sync_failure,
    _resolve_delivered_timestamp,
    _reverse_journal_entry,
    _update_journal_entry_in_place,
    run_journal_sync,
    sync_status_to_warning,
)
from baker.services.journal_sync.expense import (
    _build_debt_settlement_journal_lines,
    _build_expense_journal_lines,
    _is_expense_journallable,
    _resolve_expense_account_code,
    _sync_debt_settlement_journal,
    _sync_expense_journal,
)
from baker.services.journal_sync.payment import (
    _build_payment_journal_lines,
    _bus_shipping_allocation_for_order,
    _held_shipping_for_order,
    _held_tien_rut_for_order,
    _resolve_transaction_asset_code,
    _sync_payment_journal,
)
from baker.services.journal_sync.order import (
    _AR_ENTRY_PREFIX,
    _REVENUE_ENTRY_PREFIX,
    _TIEN_RUT_RETURN_PREFIX,
    _find_order_entry_by_prefix,
    _reconcile_order_revenue_entry,
    _reconcile_revenue_entry_lines,
    _reconcile_tien_rut_return_entry,
    _replace_order_entry,
    _resolve_shipping_release_asset_account,
    _resolve_tien_rut_return_asset_account,
    _sync_bus_shipping_release_entry,
    _sync_cancelled_order_journal,
    _sync_completed_order_journal,
    _sync_delivered_order_journal,
)
from baker.services.journal_sync.waste import (
    _compute_order_cogs_total,
    _order_cogs_entry,
    _resolve_order_cogs_items,
    _resolve_order_item_cost,
    _sync_negative_sale_cogs_journal,
    _sync_order_cogs_entry,
    _sync_order_gift_cogs_entry,
    _sync_restock_inflow_journal,
    _sync_waste_cogs_journal,
)

__all__ = [
    "STAFF_ADVANCE_PAYMENT_SOURCE",
    "journal_sync_failures",
    "run_journal_sync",
    "sync_status_to_warning",
    "_log_journal_sync_failure",
    "_find_journal_entry",
    "_is_locked",
    "_delete_journal_entry_cascade",
    "_reverse_journal_entry",
    "_update_journal_entry_in_place",
    "_resolve_delivered_timestamp",
    "_resolve_expense_account_code",
    "_is_expense_journallable",
    "_build_expense_journal_lines",
    "_sync_expense_journal",
    "_build_debt_settlement_journal_lines",
    "_sync_debt_settlement_journal",
    "_bus_shipping_allocation_for_order",
    "_held_shipping_for_order",
    "_held_tien_rut_for_order",
    "_resolve_transaction_asset_code",
    "_build_payment_journal_lines",
    "_sync_payment_journal",
    "_reconcile_order_revenue_entry",
    "_REVENUE_ENTRY_PREFIX",
    "_AR_ENTRY_PREFIX",
    "_TIEN_RUT_RETURN_PREFIX",
    "_find_order_entry_by_prefix",
    "_replace_order_entry",
    "_sync_cancelled_order_journal",
    "_reconcile_revenue_entry_lines",
    "_resolve_tien_rut_return_asset_account",
    "_reconcile_tien_rut_return_entry",
    "_sync_bus_shipping_release_entry",
    "_sync_completed_order_journal",
    "_sync_delivered_order_journal",
    "_resolve_order_item_cost",
    "_resolve_order_cogs_items",
    "_resolve_shipping_release_asset_account",
    "_compute_order_cogs_total",
    "_order_cogs_entry",
    "_sync_order_cogs_entry",
    "_sync_order_gift_cogs_entry",
    "_sync_waste_cogs_journal",
    "_sync_negative_sale_cogs_journal",
    "_sync_restock_inflow_journal",
]