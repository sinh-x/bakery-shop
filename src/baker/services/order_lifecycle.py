"""Order lifecycle service — status transition side-effect orchestration.

Extracted from ``api/orders.py`` (DG-308 Phase 5, FR-ARCH-3) so the order
status machine, item cascade, and accounting/stock sync orchestration are
reusable outside the FastAPI layer (e.g. by repair commands and tests).

This module is intentionally *thin orchestration*: it owns the sequencing of
side effects that must run together when an order transitions between
statuses. The HTTP handler in ``api/orders.py`` keeps the request/response
validation and rejection-path concerns; the pure business logic lives here.

Conventions:
- Every public function takes a ``conn`` (``sqlite3.Connection``) plus the
  primitive values it needs (``order_id``, ``order_ref``, statuses). It never
  raises ``HTTPException`` — validation/rejection is the handler's job. The
  journal-sync layer records failures rather than raising, so accounting
  errors never block an operational transition (NFR1).
- Functions return the ``accounting_sync_warning`` (or ``None``) produced by
  any journal sync they triggered, so the handler can attach it to the
  response without re-querying journal state.

Ordering note: pre-update side effects (stock decrement on ``confirmed``,
stock restore + cancellation journal sync on ``cancelled``) run *before*
``Order.update_status`` in the handler; post-update side effects
(delivered/completed journal sync, item cascade, extras sync) run *after*.
This split is preserved by exposing two entry points — see
``apply_pre_update_side_effects`` and ``apply_post_update_side_effects``.
"""

import logging

from baker.services.journal_sync import run_journal_sync, sync_status_to_warning
from baker.services.order_inventory_audit import (
    AuditAction,
    AuditEntryDraft,
    AuditOutcome,
    AuditReason,
    OperationContext,
    append_entry,
    execute_inventory_audit_savepoint,
    operation_context_for,
)

logger = logging.getLogger("baker.server")


def cascade_main_items_to_status(conn, order_id: int, target_status: str) -> None:
    """Auto-cascade a status transition to the order's main line items.

    Main items are non-extra, non-gift ``order_items`` rows. The cascade
    rules (DG-280 Phase 1, FR2):

    - ``confirmed``  → pending main items become ``confirmed``.
    - ``delivered`` / ``completed`` → non-cancelled, non-delivered main items
      become ``delivered`` (``WorkItemStatus`` has no ``completed`` value).
    - ``cancelled``  → non-cancelled main items become ``cancelled``.

    Already-cancelled items are never resurrected (AC5); items already at the
    target status are skipped to avoid redundant writes (AC4).
    """
    if target_status == "confirmed":
        conn.execute(
            "UPDATE order_items SET status = 'confirmed' "
            "WHERE order_id = ? AND is_extra = 0 AND is_gift = 0 "
            "AND status = 'pending'",
            (order_id,),
        )
    elif target_status in ("delivered", "completed"):
        conn.execute(
            "UPDATE order_items SET status = 'delivered' "
            "WHERE order_id = ? AND is_extra = 0 AND is_gift = 0 "
            "AND status != 'cancelled' AND status != 'delivered'",
            (order_id,),
        )
    elif target_status == "cancelled":
        conn.execute(
            "UPDATE order_items SET status = 'cancelled' "
            "WHERE order_id = ? AND is_extra = 0 AND is_gift = 0 "
            "AND status != 'cancelled'",
            (order_id,),
        )


def apply_pre_update_side_effects(
    conn,
    order_id: int,
    order_ref: str,
    to_status: str,
    audit_context: OperationContext | None = None,
) -> str | None:
    """Run side effects that must precede ``Order.update_status``.

    Currently this covers:
    - ``confirmed``  → stock auto-decrement for trưng bày products
      (idempotent via ``order_stock.auto_decrement_stock``).
    - ``cancelled``  → stock restoration + cancellation journal sync.

    Returns the ``accounting_sync_warning`` (or ``None``) from any journal
    sync that ran.
    """
    accounting_sync_warning: str | None = None

    if to_status == "confirmed":
        from baker.services.order_stock import (
            audited_auto_decrement_stock,
            auto_decrement_stock,
        )

        if audit_context is None:
            try:
                auto_decrement_stock(conn, order_id, order_ref)
            except Exception:
                logger.exception(
                    "auto_decrement_stock failed for order %s (%s)",
                    order_id, order_ref,
                )
        else:
            deduct_context = operation_context_for(
                audit_context, action=AuditAction.INVENTORY_DEDUCT
            )
            execute_inventory_audit_savepoint(
                conn,
                context=deduct_context,
                operation=lambda: audited_auto_decrement_stock(
                    conn, order_id, order_ref, deduct_context
                ),
                failure_reason=AuditReason.FAILURE_FIFO_MUTATION,
                failure_detail="inventory_deduction_failed",
            )

    if to_status == "cancelled":
        from baker.services.order_stock import (
            audited_restore_stock_for_order,
            restore_stock_for_order,
        )
        from baker.services.journal_sync import _sync_cancelled_order_journal

        if audit_context is None:
            try:
                restore_stock_for_order(conn, order_id, order_ref)
            except Exception:
                logger.exception(
                    "restore_stock_for_order failed for order %s (%s)",
                    order_id, order_ref,
                )
        else:
            restore_context = operation_context_for(
                audit_context, action=AuditAction.INVENTORY_RESTORE
            )
            execute_inventory_audit_savepoint(
                conn,
                context=restore_context,
                operation=lambda: audited_restore_stock_for_order(
                    conn, order_id, order_ref, restore_context
                ),
                failure_reason=AuditReason.FAILURE_RESTORE_MUTATION,
                failure_detail="inventory_restore_failed",
            )
        sync_status = run_journal_sync(
            _sync_cancelled_order_journal,
            conn, order_id,
            log_label=f"cancelled order journal sync for order {order_id}",
            source_type="order",
            source_id=order_id,
        )
        accounting_sync_warning = sync_status_to_warning(sync_status)

    if audit_context is not None and to_status not in ("confirmed", "cancelled"):
        append_entry(
            conn,
            AuditEntryDraft(
                context=operation_context_for(
                    audit_context, action=AuditAction.STATUS_CHANGE
                ),
                outcome=AuditOutcome.NO_EFFECT,
                reason=(
                    AuditReason.IDEMPOTENT_REPEAT
                    if audit_context.status_before == to_status
                    else AuditReason.STATUS_NO_EFFECT
                ),
                applied_delta=0,
            ),
        )

    return accounting_sync_warning


def apply_post_update_side_effects(
    conn,
    order_id: int,
    order_ref: str,
    from_status: str,
    to_status: str,
    prior_warning: str | None = None,
) -> str | None:
    """Run side effects that must follow ``Order.update_status``.

    Orchestrates, in order:

    1. Delivered-order journal sync (revenue + COGS) when transitioning *to*
       ``delivered`` from a non-delivered status.
    2. Completion journal sync (deposit reconciliation + AR clear) when
       transitioning *to* ``completed`` from a non-completed status.
    3. Main-item status cascade (``cascade_main_items_to_status``).
    4. Extras/gifts auto-sync to match the new order status (via
       ``work_items.sync_extras_to_order_status``).

    The journal-sync layer records failures rather than raising (NFR1); the
    warning string from any sync is returned (preferring a post-update sync
    warning over a prior one when both exist) so the caller can surface it.

    Args:
        conn: SQLite connection (from ``get_db()``).
        order_id: Numeric order id.
        order_ref: Human-readable order reference (for stock movements).
        from_status: The order's status before the transition.
        to_status: The target status being applied.
        prior_warning: Optional warning carried from
            ``apply_pre_update_side_effects`` (e.g. cancellation sync).

    Returns:
        An ``accounting_sync_warning`` string (or ``None`` when no journal
        sync ran or all syncs succeeded).
    """
    accounting_sync_warning = prior_warning

    if to_status == "delivered" and from_status != "delivered":
        from baker.services.journal_sync import _sync_delivered_order_journal

        sync_status = run_journal_sync(
            _sync_delivered_order_journal,
            conn, order_id, order_ref,
            log_label=f"delivered order journal sync for order {order_id}",
            source_type="order",
            source_id=order_id,
        )
        accounting_sync_warning = sync_status_to_warning(sync_status)

    if to_status == "completed" and from_status != "completed":
        from baker.services.journal_sync import _sync_completed_order_journal

        sync_status = run_journal_sync(
            _sync_completed_order_journal,
            conn, order_id, order_ref,
            log_label=f"completed order journal sync for order {order_id}",
            source_type="order",
            source_id=order_id,
        )
        accounting_sync_warning = sync_status_to_warning(sync_status)

    cascade_main_items_to_status(conn, order_id, to_status)

    from baker.api.work_items import sync_extras_to_order_status

    sync_extras_to_order_status(conn, order_id, to_status)

    return accounting_sync_warning