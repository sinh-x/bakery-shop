"""Append-only domain service for per-order inventory audit evidence.

The service owns the stable trigger/action/outcome/reason vocabulary and the
immutable snapshots written to migration v105's audit table. Callers supply an
open connection so stock effects and evidence can share one transaction; later
lifecycle instrumentation can roll work back to a savepoint before appending a
failed decision.
"""

from __future__ import annotations

import logging
import re
import sqlite3
import uuid
from dataclasses import dataclass, field, replace
from enum import Enum
from typing import Callable, Iterable

from baker.utils.time import normalize_timestamp, now_utc

logger = logging.getLogger("baker.server")

DEFAULT_QUERY_LIMIT = 100
MAX_QUERY_LIMIT = 500
MAX_DETAIL_LENGTH = 500


class AuditTrigger(str, Enum):
    """Server entry point that caused inventory evaluation."""

    ORDER_CREATION = "order_creation"
    STATUS_ACTION = "status_action"
    ORDER_EDIT = "order_edit"
    REVERSAL = "reversal"
    RE_EVALUATION = "re_evaluation"


class AuditAction(str, Enum):
    """Inventory-relevant action evaluated during an operation."""

    ORDER_CREATE = "order_create"
    STATUS_CHANGE = "status_change"
    ORDER_EDIT = "order_edit"
    INVENTORY_DEDUCT = "inventory_deduct"
    INVENTORY_RESTORE = "inventory_restore"
    INVENTORY_REVERSE = "inventory_reverse"
    INVENTORY_REEVALUATE = "inventory_reevaluate"


class AuditOutcome(str, Enum):
    """Stable result taxonomy for inventory decisions."""

    APPLIED = "applied"
    REVERSED = "reversed"
    SKIPPED = "skipped"
    NO_EFFECT = "no_effect"
    FAILED = "failed"


class AuditReason(str, Enum):
    """Allow-listed explanations for effects, skips, no-ops, and failures."""

    ELIGIBLE_DISPLAY_ITEM = "eligible_display_item"
    GIFT_ITEM = "gift_item"
    NON_DISPLAY_PRODUCT = "non_display_product"
    EXPLICIT_INVENTORY_OPT_IN = "explicit_inventory_opt_in"
    EXPLICIT_INVENTORY_OPT_OUT = "explicit_inventory_opt_out"
    MISSING_PRODUCT = "missing_product"
    SOURCE_DEFAULT_CONSUME = "source_default_consume"
    SOURCE_DEFAULT_SKIP = "source_default_skip"
    IDEMPOTENT_REPEAT = "idempotent_repeat"
    STATUS_NO_EFFECT = "status_no_effect"
    PRICE_CHIP_FALLBACK_TO_BASE = "price_chip_fallback_to_base"
    CANCEL_RESTORE = "cancel_restore"
    EDIT_REVERSAL = "edit_reversal"
    EDIT_RE_EVALUATION = "edit_re_evaluation"
    NEGATIVE_SALE = "negative_sale"
    FAILURE_INVALID_PRODUCT = "failure_invalid_product"
    FAILURE_INVALID_PRICE_CHIP = "failure_invalid_price_chip"
    FAILURE_INSUFFICIENT_STOCK = "failure_insufficient_stock"
    FAILURE_FIFO_MUTATION = "failure_fifo_mutation"
    FAILURE_NEGATIVE_BALANCE_MUTATION = "failure_negative_balance_mutation"
    FAILURE_RESTORE_MUTATION = "failure_restore_mutation"
    FAILURE_UNEXPECTED = "failure_unexpected"


FAILURE_REASONS = frozenset(
    reason for reason in AuditReason if reason.value.startswith("failure_")
)


@dataclass(frozen=True)
class AuditActor:
    """Trusted actor snapshot resolved by the API/auth boundary."""

    identifier: str
    username: str | None = None
    staff_id: int | None = None
    staff_name: str | None = None
    role: str | None = None


@dataclass(frozen=True)
class OperationContext:
    """Request-level identity shared by one or more audit entries."""

    operation_id: str
    order_id: int
    order_ref: str
    trigger: AuditTrigger
    action: AuditAction
    actor: AuditActor
    created_at: str
    status_before: str | None = None
    status_after: str | None = None


@dataclass(frozen=True)
class ItemSnapshot:
    """Immutable descriptive evidence for an evaluated order item/bucket."""

    order_item_id: int | None = None
    product_id: int | None = None
    product_code: str | None = None
    product_name: str | None = None
    is_gift: bool | None = None
    is_display: bool | None = None
    source: str | None = None
    requested_quantity: int | None = None
    price_chip_id: int | None = None
    price_chip_label: str | None = None
    use_inventory_present: bool | None = None
    use_inventory_value: bool | None = None
    resolved_bucket: str | None = None
    resolved_price_chip_id: int | None = None
    resolved_price_chip_label: str | None = None
    resolved_unit_price: int | None = None

    def __post_init__(self) -> None:
        if self.resolved_bucket not in (None, "base", "price_chip"):
            raise ValueError("resolved_bucket must be base, price_chip, or None")
        if self.use_inventory_value is not None and self.use_inventory_present is not True:
            raise ValueError("use_inventory_value requires use_inventory_present=True")


@dataclass(frozen=True)
class InventorySnapshot:
    """FIFO available, negative balance, and stock-overview net quantities."""

    fifo_available: int | None = None
    negative: int | None = None
    net: int | None = None

    def __post_init__(self) -> None:
        values = (self.fifo_available, self.negative, self.net)
        if all(value is None for value in values):
            return
        if any(value is None for value in values):
            raise ValueError("inventory snapshot values must be all null or all present")
        available = int(self.fifo_available)  # type: ignore[arg-type]
        negative = int(self.negative)  # type: ignore[arg-type]
        if available < 0 or negative < 0:
            raise ValueError("available and negative quantities cannot be below zero")
        if self.net != available - negative:
            raise ValueError("net must equal FIFO available minus negative balance")

    @classmethod
    def from_counts(cls, fifo_available: int, negative: int) -> "InventorySnapshot":
        available = int(fifo_available)
        negative_count = int(negative)
        return cls(
            fifo_available=available,
            negative=negative_count,
            net=available - negative_count,
        )


@dataclass(frozen=True)
class AuditEntryDraft:
    """One decision to append under an :class:`OperationContext`."""

    context: OperationContext
    outcome: AuditOutcome
    reason: AuditReason
    item: ItemSnapshot = field(default_factory=ItemSnapshot)
    requested_delta: int | None = None
    applied_delta: int | None = None
    before: InventorySnapshot = field(default_factory=InventorySnapshot)
    after: InventorySnapshot = field(default_factory=InventorySnapshot)
    stock_movement_id: int | None = None
    negative_movement_id: int | None = None
    related_entry_id: int | None = None
    detail: str | None = None


@dataclass(frozen=True)
class AuditEntry:
    """Persisted immutable audit entry."""

    id: int
    context: OperationContext
    outcome: AuditOutcome
    reason: AuditReason
    item: ItemSnapshot
    requested_delta: int | None
    applied_delta: int | None
    before: InventorySnapshot
    after: InventorySnapshot
    stock_movement_id: int | None
    negative_movement_id: int | None
    related_entry_id: int | None
    detail: str | None


class InventoryAuditFault(Exception):
    """Internal stock-stage failure carrying only safe audit evidence."""

    def __init__(
        self,
        *,
        reason: AuditReason,
        detail: str,
        context: OperationContext | None = None,
        item: ItemSnapshot | None = None,
        requested_delta: int | None = None,
        before: InventorySnapshot | None = None,
    ) -> None:
        super().__init__(detail)
        self.reason = reason
        self.detail = detail
        self.context = context
        self.item = item or ItemSnapshot()
        self.requested_delta = requested_delta
        self.before = before or InventorySnapshot()


# Remove all assignment-looking fragments instead of trying to maintain a
# fragile list of confidential field names. Reason codes retain diagnostics.
_KEY_VALUE_RE = re.compile(r"\b[\w-]{1,32}\s*[:=]\s*(?:\"[^\"]*\"|'[^']*'|\S+)")
_CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def sanitize_detail(detail: str | None) -> str | None:
    """Return bounded, single-line detail with stack bodies and values removed."""
    if detail is None:
        return None
    text = str(detail).split("Traceback (most recent call last):", 1)[0]
    text = " ".join(text.splitlines()).strip()
    text = _CONTROL_RE.sub("", text)
    text = _KEY_VALUE_RE.sub("[redacted]", text)
    if not text:
        return None
    return text[:MAX_DETAIL_LENGTH]


def create_operation_context(
    *,
    order_id: int,
    order_ref: str,
    trigger: AuditTrigger,
    action: AuditAction,
    actor: AuditActor,
    status_before: str | None = None,
    status_after: str | None = None,
    operation_id: str | None = None,
    created_at: str | None = None,
) -> OperationContext:
    """Create server-owned operation identity and canonical UTC timestamp."""
    resolved_operation_id = (
        str(uuid.uuid4()) if operation_id is None else str(uuid.UUID(operation_id))
    )
    return OperationContext(
        operation_id=resolved_operation_id,
        order_id=int(order_id),
        order_ref=order_ref,
        trigger=trigger,
        action=action,
        actor=actor,
        created_at=_canonical_utc(created_at or now_utc()),
        status_before=status_before,
        status_after=status_after,
    )


def operation_context_for(
    context: OperationContext,
    *,
    trigger: AuditTrigger | None = None,
    action: AuditAction | None = None,
) -> OperationContext:
    """Derive an entry-stage context while retaining request correlation."""
    return replace(
        context,
        trigger=trigger or context.trigger,
        action=action or context.action,
    )


def execute_inventory_audit_savepoint(
    conn,
    *,
    context: OperationContext,
    operation: Callable[[], object],
    failure_reason: AuditReason,
    failure_detail: str,
) -> bool:
    """Atomically run stock effects and success audit, then persist safe failure.

    A caught stock or audit fault rolls the complete group back before its
    failed entry is appended. If SQLite itself is unavailable, evidence cannot
    be written safely and the failure remains log-only, preserving the existing
    non-blocking order transition behavior.
    """
    savepoint = f"order_inventory_audit_{uuid.uuid4().hex}"
    try:
        conn.execute(f"SAVEPOINT {savepoint}")
        operation()
        conn.execute(f"RELEASE SAVEPOINT {savepoint}")
        return True
    except Exception as exc:
        try:
            conn.execute(f"ROLLBACK TO SAVEPOINT {savepoint}")
            conn.execute(f"RELEASE SAVEPOINT {savepoint}")
        except sqlite3.Error:
            logger.exception("order inventory audit savepoint rollback unavailable")
            return False

        fault = exc if isinstance(exc, InventoryAuditFault) else None
        draft = AuditEntryDraft(
            context=fault.context if fault and fault.context else context,
            outcome=AuditOutcome.FAILED,
            reason=fault.reason if fault else failure_reason,
            item=fault.item if fault else ItemSnapshot(),
            requested_delta=fault.requested_delta if fault else None,
            applied_delta=0,
            before=fault.before if fault else InventorySnapshot(),
            after=fault.before if fault else InventorySnapshot(),
            detail=fault.detail if fault else failure_detail,
        )
        try:
            append_entry(conn, draft)
        except sqlite3.Error:
            logger.exception("order inventory audit failure evidence unavailable")
        except Exception:
            logger.exception("order inventory audit failure evidence rejected")
        logger.exception("audited order inventory operation failed")
        return False


def snapshot_inventory(
    conn,
    product_id: int,
    price_chip_id: int | None,
) -> InventorySnapshot:
    """Read one bucket using stock-overview ``available - negative`` semantics."""
    available_row = conn.execute(
        """SELECT COUNT(ii.id) AS qty
           FROM stock_lots sl
           LEFT JOIN inventory_items ii
             ON ii.lot_id = sl.id AND ii.status = 'available'
           WHERE sl.product_id = ?
             AND sl.price_chip_id IS NOT DISTINCT FROM ?""",
        (product_id, price_chip_id),
    ).fetchone()
    negative_row = conn.execute(
        """SELECT qty FROM negative_balance
           WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?""",
        (product_id, price_chip_id),
    ).fetchone()
    available = int(available_row["qty"] or 0) if available_row else 0
    negative = int(negative_row["qty"] or 0) if negative_row else 0
    return InventorySnapshot.from_counts(available, negative)


def append_entry(conn, draft: AuditEntryDraft) -> AuditEntry:
    """Append one entry inside the caller's current transaction."""
    _validate_outcome_reason(draft.outcome, draft.reason)
    columns = (
        "operation_id", "order_id", "order_ref", "trigger", "action",
        "status_before", "status_after", "actor_identifier", "actor_username",
        "actor_staff_id", "actor_staff_name", "actor_role", "created_at",
        "outcome", "reason_code", "detail", "order_item_id", "product_id",
        "product_code", "product_name", "is_gift", "is_display", "source",
        "requested_quantity", "price_chip_id", "price_chip_label",
        "use_inventory_present", "use_inventory_value", "resolved_bucket",
        "resolved_price_chip_id", "resolved_price_chip_label",
        "resolved_unit_price", "requested_delta", "applied_delta",
        "before_fifo_available", "before_negative", "before_net",
        "after_fifo_available", "after_negative", "after_net",
        "stock_movement_id", "negative_movement_id", "related_entry_id",
    )
    item = draft.item
    actor = draft.context.actor
    values = (
        draft.context.operation_id, draft.context.order_id, draft.context.order_ref,
        draft.context.trigger.value, draft.context.action.value,
        draft.context.status_before, draft.context.status_after, actor.identifier,
        actor.username, actor.staff_id, actor.staff_name, actor.role,
        _canonical_utc(draft.context.created_at), draft.outcome.value,
        draft.reason.value, sanitize_detail(draft.detail), item.order_item_id,
        item.product_id, item.product_code, item.product_name, _db_bool(item.is_gift),
        _db_bool(item.is_display), item.source, item.requested_quantity,
        item.price_chip_id, item.price_chip_label, _db_bool(item.use_inventory_present),
        _db_bool(item.use_inventory_value), item.resolved_bucket,
        item.resolved_price_chip_id, item.resolved_price_chip_label,
        item.resolved_unit_price, draft.requested_delta, draft.applied_delta,
        draft.before.fifo_available, draft.before.negative, draft.before.net,
        draft.after.fifo_available, draft.after.negative, draft.after.net,
        draft.stock_movement_id, draft.negative_movement_id, draft.related_entry_id,
    )
    placeholders = ", ".join("?" for _ in columns)
    cursor = conn.execute(
        f"INSERT INTO order_inventory_audit_entries ({', '.join(columns)}) "
        f"VALUES ({placeholders})",
        values,
    )
    return _get_entry(conn, int(cursor.lastrowid))


def append_entries(conn, drafts: Iterable[AuditEntryDraft]) -> list[AuditEntry]:
    """Append a request's entries, requiring one operation and one order."""
    pending = list(drafts)
    if not pending:
        return []
    first = pending[0].context
    for draft in pending[1:]:
        context = draft.context
        if (
            context.operation_id != first.operation_id
            or context.order_id != first.order_id
            or context.order_ref != first.order_ref
        ):
            raise ValueError("all entries must share one operation and order")
    return [append_entry(conn, draft) for draft in pending]


def query_order_entries(
    conn,
    *,
    order_id: int | None = None,
    order_ref: str | None = None,
    limit: int = DEFAULT_QUERY_LIMIT,
    offset: int = 0,
) -> list[AuditEntry]:
    """Return one order's entries by ``created_at DESC, id DESC``."""
    where_sql, params = _order_filter(order_id=order_id, order_ref=order_ref)
    _validate_page(limit, offset)
    rows = conn.execute(
        "SELECT * FROM order_inventory_audit_entries "
        f"WHERE {where_sql} ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?",
        (*params, limit, offset),
    ).fetchall()
    return [_row_to_entry(row) for row in rows]


def count_order_entries(
    conn,
    *,
    order_id: int | None = None,
    order_ref: str | None = None,
) -> int:
    """Count immutable entries for one order without loading snapshots."""
    where_sql, params = _order_filter(order_id=order_id, order_ref=order_ref)
    row = conn.execute(
        f"SELECT COUNT(*) AS total FROM order_inventory_audit_entries WHERE {where_sql}",
        params,
    ).fetchone()
    return int(row["total"] if row else 0)


def _canonical_utc(value: str) -> str:
    normalized = normalize_timestamp(value, empty_error="created_at is required")
    if normalized is None:
        raise ValueError("created_at is required")
    return normalized


def _validate_outcome_reason(outcome: AuditOutcome, reason: AuditReason) -> None:
    is_failure_reason = reason in FAILURE_REASONS
    if outcome is AuditOutcome.FAILED and not is_failure_reason:
        raise ValueError("failed outcomes require an allow-listed failure reason")
    if outcome is not AuditOutcome.FAILED and is_failure_reason:
        raise ValueError("failure reasons require outcome=failed")


def _db_bool(value: bool | None) -> int | None:
    return None if value is None else int(value)


def _validate_page(limit: int, offset: int) -> None:
    if limit < 1 or limit > MAX_QUERY_LIMIT:
        raise ValueError(f"limit must be between 1 and {MAX_QUERY_LIMIT}")
    if offset < 0:
        raise ValueError("offset cannot be negative")


def _order_filter(
    *,
    order_id: int | None,
    order_ref: str | None,
) -> tuple[str, tuple]:
    if order_id is None and order_ref is None:
        raise ValueError("order_id or order_ref is required")
    if order_id is not None and order_ref is not None:
        return "order_id = ? AND order_ref = ?", (order_id, order_ref)
    if order_id is not None:
        return "order_id = ?", (order_id,)
    return "order_ref = ?", (order_ref,)


def _get_entry(conn, entry_id: int) -> AuditEntry:
    row = conn.execute(
        "SELECT * FROM order_inventory_audit_entries WHERE id = ?",
        (entry_id,),
    ).fetchone()
    if row is None:
        raise RuntimeError("newly appended audit entry was not found")
    return _row_to_entry(row)


def _row_to_entry(row) -> AuditEntry:
    context = OperationContext(
        operation_id=row["operation_id"],
        order_id=int(row["order_id"]),
        order_ref=row["order_ref"],
        trigger=AuditTrigger(row["trigger"]),
        action=AuditAction(row["action"]),
        actor=AuditActor(
            identifier=row["actor_identifier"],
            username=row["actor_username"],
            staff_id=row["actor_staff_id"],
            staff_name=row["actor_staff_name"],
            role=row["actor_role"],
        ),
        created_at=row["created_at"],
        status_before=row["status_before"],
        status_after=row["status_after"],
    )
    item = ItemSnapshot(
        order_item_id=row["order_item_id"],
        product_id=row["product_id"],
        product_code=row["product_code"],
        product_name=row["product_name"],
        is_gift=_from_db_bool(row["is_gift"]),
        is_display=_from_db_bool(row["is_display"]),
        source=row["source"],
        requested_quantity=row["requested_quantity"],
        price_chip_id=row["price_chip_id"],
        price_chip_label=row["price_chip_label"],
        use_inventory_present=_from_db_bool(row["use_inventory_present"]),
        use_inventory_value=_from_db_bool(row["use_inventory_value"]),
        resolved_bucket=row["resolved_bucket"],
        resolved_price_chip_id=row["resolved_price_chip_id"],
        resolved_price_chip_label=row["resolved_price_chip_label"],
        resolved_unit_price=row["resolved_unit_price"],
    )
    return AuditEntry(
        id=int(row["id"]),
        context=context,
        outcome=AuditOutcome(row["outcome"]),
        reason=AuditReason(row["reason_code"]),
        item=item,
        requested_delta=row["requested_delta"],
        applied_delta=row["applied_delta"],
        before=InventorySnapshot(
            row["before_fifo_available"], row["before_negative"], row["before_net"]
        ),
        after=InventorySnapshot(
            row["after_fifo_available"], row["after_negative"], row["after_net"]
        ),
        stock_movement_id=row["stock_movement_id"],
        negative_movement_id=row["negative_movement_id"],
        related_entry_id=row["related_entry_id"],
        detail=row["detail"],
    )


def _from_db_bool(value: int | None) -> bool | None:
    return None if value is None else bool(value)
