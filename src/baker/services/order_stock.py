"""Public stock service helpers used by order-related APIs."""

import json

from fastapi import HTTPException

from baker.services.inventory_fifo import (
    consume_fifo_items,
    create_lot_with_items,
    normalize_price_value,
    normalize_price_chip,
    resolve_price_bucket_chip_id,
    upsert_negative_balance,
)
from baker.services.order_inventory_audit import (
    AuditEntry,
    AuditEntryDraft,
    AuditOutcome,
    AuditReason,
    InventoryAuditFault,
    InventorySnapshot,
    ItemSnapshot,
    OperationContext,
    append_entry,
    snapshot_inventory,
)
from baker.logging import logger
from baker.models.event import Event
from baker.utils.time import now_utc


def _order_sale_was_deducted(conn, order_ref: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM stock_movements WHERE reference_id = ? AND movement_type = 'sale' LIMIT 1",
        (order_ref,),
    ).fetchone()
    return row is not None


def auto_decrement_stock(conn, order_id: int, order_ref: str) -> None:
    """Auto-decrement stock for trung bay products when order is delivered/completed.

    Idempotent: skips deduction if a sale movement already exists for this order."""
    if _order_sale_was_deducted(conn, order_ref):
        return

    order_items = conn.execute(
        """SELECT oi.id, oi.product_id, oi.product_name, oi.quantity,
                  oi.price_chip_id, oi.unit_price, oi.attributes, oi.is_gift, o.source
           FROM order_items oi
           JOIN orders o ON o.id = oi.order_id
           WHERE oi.order_id = ?
             AND oi.product_id != ''
             AND oi.is_gift = 0""",
        (order_id,),
    ).fetchall()

    for item in order_items:
        code_or_id = item["product_id"]
        product_row = conn.execute(
            "SELECT id FROM products WHERE product_code = ?",
            (code_or_id,),
        ).fetchone()
        if not product_row:
            try:
                product_row = conn.execute(
                    "SELECT id FROM products WHERE id = ?",
                    (int(code_or_id),),
                ).fetchone()
            except (ValueError, TypeError):
                continue
        if not product_row:
            continue

        product_id = product_row["id"]
        qty = item["quantity"]
        explicit_chip_id = item["price_chip_id"]
        if explicit_chip_id is not None:
            chip_id = normalize_price_chip(conn, product_id, explicit_chip_id)
        else:
            normalized_unit_price = normalize_price_value(item["unit_price"])
            try:
                chip_id = resolve_price_bucket_chip_id(
                    conn,
                    product_id,
                    normalized_unit_price,
                )
            except HTTPException:
                chip_id = None

        attr_row = conn.execute(
            """SELECT value FROM product_attribute_values
               WHERE product_id = ? AND attribute_type = 'trung_bay'""",
            (product_id,),
        ).fetchone()
        if not attr_row or attr_row["value"] != "true":
            logger.warning(
                "order_stock_skip_missing_trung_bay",
                extra={
                    "extra_data": {
                        "order_ref": order_ref,
                        "product_id": product_id,
                        "product_name": item["product_name"],
                        "trung_bay": attr_row["value"] if attr_row else None,
                    }
                },
            )
            continue

        attrs = {}
        if item["attributes"]:
            if isinstance(item["attributes"], str):
                try:
                    attrs = json.loads(item["attributes"])
                except json.JSONDecodeError:
                    attrs = {}
            elif isinstance(item["attributes"], dict):
                attrs = item["attributes"]

        has_use_inventory = "useInventory" in attrs
        use_inventory = attrs.get("useInventory")
        if isinstance(use_inventory, str):
            use_inventory_enabled = use_inventory.lower() == "true"
        else:
            use_inventory_enabled = bool(use_inventory)

        is_pos_order = item["source"] == "Tại tiệm - POS"
        is_reconciliation_order = item["source"] == "reconciliation"
        default_consume_sources = is_pos_order or is_reconciliation_order
        should_consume_fifo = use_inventory_enabled if has_use_inventory else default_consume_sources
        # POS and reconciliation sources allow negative stock: oversold qty
        # is tracked in negative_balance (DG-200 Phase 2, FR-3). Non-POS
        # sources keep the historical FIFO-blocks-at-zero behaviour (NFR-3).
        allow_negative = is_pos_order or is_reconciliation_order

        if not should_consume_fifo:
            logger.info(
                "order_stock_fifo_skipped",
                extra={
                    "extra_data": {
                        "order_ref": order_ref,
                        "product_id": product_id,
                        "product_name": item["product_name"],
                        "source": item["source"],
                        "has_use_inventory": has_use_inventory,
                        "use_inventory": use_inventory,
                        "default_consume_sources": default_consume_sources,
                    }
                },
            )

        failure_decision = _decision_for_row(conn, item) if should_consume_fifo else None
        failure_item = (
            failure_decision["item"] if failure_decision is not None else ItemSnapshot()
        )
        failure_before = (
            failure_decision["before"]
            if failure_decision is not None
            else InventorySnapshot()
        )

        movement_cursor = conn.execute(
            """INSERT INTO stock_movements
               (product_id, movement_type, quantity, reason, reference_id, price_chip_id, created_at)
               VALUES (?, 'sale', ?, ?, ?, ?, ?)""",
            (product_id, -qty, f"Order {order_ref}", order_ref, chip_id, now_utc()),
        )
        movement_id = movement_cursor.lastrowid
        deficit = 0
        if should_consume_fifo:
            try:
                deficit = consume_fifo_items(
                    conn, product_id, chip_id, qty, movement_id,
                    allow_negative=allow_negative,
                )
            except HTTPException as exc:
                reason = (
                    AuditReason.FAILURE_INSUFFICIENT_STOCK
                    if exc.status_code == 422
                    else AuditReason.FAILURE_FIFO_MUTATION
                )
                raise InventoryAuditFault(
                    reason=reason,
                    detail="inventory_fifo_rejected",
                    item=failure_item,
                    requested_delta=-qty,
                    before=failure_before,
                ) from exc
            except Exception as exc:
                raise InventoryAuditFault(
                    reason=AuditReason.FAILURE_FIFO_MUTATION,
                    detail="inventory_fifo_mutation_failed",
                    item=failure_item,
                    requested_delta=-qty,
                    before=failure_before,
                ) from exc

        if should_consume_fifo:
            lot_row = conn.execute(
                "SELECT lot_id FROM inventory_items WHERE consumed_by_movement_id = ? ORDER BY id ASC LIMIT 1",
                (movement_id,),
            ).fetchone()
            if lot_row:
                conn.execute(
                    "UPDATE stock_movements SET lot_id = ? WHERE id = ?",
                    (lot_row["lot_id"], movement_id),
                )

        # When a deficit remains, record a negative_sale movement and upsert
        # the negative_balance row. The 'sale' movement above captures the
        # full sold qty (FIFO-consumed portion); the 'negative_sale' movement
        # captures the oversold portion (AC-6).
        if deficit > 0:
            negative_movement_cursor = conn.execute(
                """INSERT INTO stock_movements
                   (product_id, movement_type, quantity, reason, reference_id, price_chip_id, created_at)
                   VALUES (?, 'negative_sale', ?, ?, ?, ?, ?)""",
                (product_id, -deficit, f"Order {order_ref} (negative)", order_ref, chip_id, now_utc()),
            )
            negative_movement_id = negative_movement_cursor.lastrowid
            try:
                upsert_negative_balance(conn, product_id, chip_id, deficit)
            except Exception as exc:
                raise InventoryAuditFault(
                    reason=AuditReason.FAILURE_NEGATIVE_BALANCE_MUTATION,
                    detail="negative_balance_mutation_failed",
                    item=failure_item,
                    requested_delta=-qty,
                    before=failure_before,
                ) from exc
            Event(
                summary=f"Ban am -{deficit} {item['product_name']}",
                type="inventory",
                data={
                    "product_id": product_id,
                    "product_name": item["product_name"],
                    "movement_type": "negative_sale",
                    "quantity": -deficit,
                    "reference_id": order_ref,
                    "price_chip_id": chip_id,
                    "movement_id": negative_movement_id,
                },
            ).save(conn)

            # DG-200 Phase 4, AC-8: COGS journal entry for the oversold
            # quantity. Mirrors the waste COGS sync pattern (DR COGS / CR
            # Inventory). Fire-and-forget: accounting failures never block
            # the primary sale operation (NFR1).
            #
            # Inline import (not module-level) is intentional: journal_sync
            # imports from baker.services.inventory_fifo (formerly under
            # baker.api), which would create a circular dependency if imported
            # at module load time here. Deferring the import to call-site
            # avoids the cycle while keeping the accounting coupling local to
            # the operation that needs it (DG-200 Phase 5.6-c1-fix, Mn-1).
            from baker.services.journal_sync import (
                _sync_negative_sale_cogs_journal,
                run_journal_sync,
            )

            run_journal_sync(
                _sync_negative_sale_cogs_journal,
                conn, product_id, negative_movement_id, deficit,
                log_label=(
                    f"negative sale cogs sync for movement {negative_movement_id}"
                ),
            )

        Event(
            summary=f"Ban hang -{qty} {item['product_name']}",
            type="inventory",
            data={
                "product_id": product_id,
                "product_name": item["product_name"],
                "movement_type": "sale",
                "quantity": -qty,
                "reference_id": order_ref,
                "price_chip_id": chip_id,
            },
        ).save(conn)


def reverse_order_stock_for_edit(conn, order_id: int, order_ref: str) -> None:
    """Reverse stock deductions for an order edit so the new items can be re-deducted.

    DG-342 Phase 4 (FR5, NFR2). Called by ``edit_order`` when the items list
    changes on a confirmed+ order. Unlike :func:`restore_stock_for_order`
    (which compensates by creating *new* lot items and is designed for
    cancellation), this reverses the original consumption in-place:

    1. Un-consume the FIFO inventory items consumed by each old ``sale``
       movement (status → ``available``, restore ``stock_lots.remaining_qty``,
       clear ``consumed_by_movement_id``).
    2. Reverse ``negative_sale`` movements: restore the ``negative_balance``
       deficit and reverse the matching ``negative_sale_cogs`` journal entry
       (fire-and-forget — journal failures are logged, not raised).
    3. Delete the old ``sale`` and ``negative_sale`` movements so
       :func:`auto_decrement_stock` (called next by the handler) can re-deduct
       for the new items without hitting its ``sale``-already-exists skip.

    Idempotent (NFR2): if no ``sale`` movement exists for the order, returns
    immediately — the caller's re-deduction is a no-op too. ``restore_sale``
    movements are intentionally left untouched: they only appear after a
    cancellation (terminal in the state machine), so a confirmed+ order
    being edited never carries them. All mutations run within the caller's
    ``get_db()`` transaction (NFR3).
    """
    sale_movements = conn.execute(
        """SELECT id, product_id, price_chip_id, quantity
           FROM stock_movements
           WHERE reference_id = ? AND movement_type = 'sale'""",
        (order_ref,),
    ).fetchall()
    if not sale_movements:
        return

    for movement in sale_movements:
        movement_id = movement["id"]
        consumed_items = conn.execute(
            "SELECT id, lot_id FROM inventory_items WHERE consumed_by_movement_id = ?",
            (movement_id,),
        ).fetchall()
        for item in consumed_items:
            conn.execute(
                "UPDATE inventory_items "
                "SET status = 'available', consumed_by_movement_id = NULL "
                "WHERE id = ?",
                (item["id"],),
            )
            conn.execute(
                "UPDATE stock_lots SET remaining_qty = remaining_qty + 1 WHERE id = ?",
                (item["lot_id"],),
            )

    negative_movements = conn.execute(
        """SELECT id, product_id, price_chip_id, quantity
           FROM stock_movements
           WHERE reference_id = ? AND movement_type = 'negative_sale'""",
        (order_ref,),
    ).fetchall()
    for movement in negative_movements:
        deficit = -int(movement["quantity"])
        if deficit > 0:
            conn.execute(
                "UPDATE negative_balance SET qty = qty - ?, updated_at = ? "
                "WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?",
                (deficit, now_utc(), movement["product_id"], movement["price_chip_id"]),
            )
            conn.execute(
                "DELETE FROM negative_balance WHERE product_id = ? "
                "AND price_chip_id IS NOT DISTINCT FROM ? AND qty <= 0",
                (movement["product_id"], movement["price_chip_id"]),
            )
        from baker.services.journal_sync._common import (
            _find_journal_entry,
            _reverse_journal_entry,
        )

        cogs_entry_id = _find_journal_entry(
            conn, "negative_sale_cogs", movement["id"]
        )
        if cogs_entry_id is not None:
            _reverse_journal_entry(conn, cogs_entry_id)

    conn.execute(
        "DELETE FROM stock_movements "
        "WHERE reference_id = ? AND movement_type IN ('sale', 'negative_sale')",
        (order_ref,),
    )


def _restore_reason(order_ref: str, sale_movement_id: int) -> str:
    return f"Restore order {order_ref} sale movement {sale_movement_id}"


def _sale_restore_plans(conn, order_ref: str) -> list[dict]:
    """Return movement-aware outstanding FIFO/negative restore components."""
    effects = conn.execute(
        """SELECT id, product_id, price_chip_id, movement_type, quantity
           FROM stock_movements
           WHERE reference_id = ? AND movement_type IN ('sale', 'negative_sale')
           ORDER BY id""",
        (order_ref,),
    ).fetchall()
    sales = []
    last_sale_by_bucket: dict[tuple[int, int | None], int] = {}
    negative_by_sale: dict[int, list] = {}
    for movement in effects:
        bucket = (movement["product_id"], movement["price_chip_id"])
        if movement["movement_type"] == "sale":
            sales.append(movement)
            last_sale_by_bucket[bucket] = movement["id"]
        else:
            sale_id = last_sale_by_bucket.get(bucket)
            if sale_id is not None:
                negative_by_sale.setdefault(sale_id, []).append(movement)

    restored_by_bucket: dict[tuple[int, int | None], int] = {}
    restore_rows = conn.execute(
        """SELECT product_id, price_chip_id, quantity
           FROM stock_movements
           WHERE reference_id = ? AND movement_type = 'restore_sale'
           ORDER BY id""",
        (order_ref,),
    ).fetchall()
    for movement in restore_rows:
        bucket = (movement["product_id"], movement["price_chip_id"])
        restored_by_bucket[bucket] = restored_by_bucket.get(bucket, 0) + max(
            0, int(movement["quantity"])
        )

    plans = []
    for sale in sales:
        bucket = (sale["product_id"], sale["price_chip_id"])
        fifo_qty = int(
            conn.execute(
                "SELECT COUNT(*) AS qty FROM inventory_items "
                "WHERE consumed_by_movement_id = ?",
                (sale["id"],),
            ).fetchone()["qty"]
        )
        negative_movements = negative_by_sale.get(sale["id"], [])
        negative_qty = sum(-int(row["quantity"]) for row in negative_movements)
        already_restored = min(
            fifo_qty + negative_qty, restored_by_bucket.get(bucket, 0)
        )
        restored_by_bucket[bucket] = max(
            0, restored_by_bucket.get(bucket, 0) - already_restored
        )
        restored_fifo = min(fifo_qty, already_restored)
        restored_negative = min(
            negative_qty, already_restored - restored_fifo
        )
        plans.append(
            {
                "movement": sale,
                "fifo_qty": fifo_qty - restored_fifo,
                "negative_qty": negative_qty - restored_negative,
                "negative_movement_id": (
                    negative_movements[0]["id"] if negative_movements else None
                ),
            }
        )
    return plans


def restore_stock_for_order(conn, order_id: int, order_ref: str) -> None:
    """Reverse each outstanding sale effect exactly once on cancellation."""
    plans = _sale_restore_plans(conn, order_ref)
    item_rows = load_order_inventory_rows(conn, order_id)
    captured_by_movement = {
        movement["id"]: (item, before)
        for movement, item, before in _capture_movement_snapshots(
            conn,
            [plan["movement"] for plan in plans],
            item_rows,
        )
    }
    for plan in plans:
        movement = plan["movement"]
        fifo_qty = plan["fifo_qty"]
        negative_qty = plan["negative_qty"]
        qty = fifo_qty + negative_qty
        if qty <= 0:
            continue
        chip_id = movement["price_chip_id"]
        product_id = movement["product_id"]

        conn.execute(
            """INSERT INTO stock_movements
               (product_id, movement_type, quantity, reason, reference_id,
                price_chip_id, created_at)
               VALUES (?, 'restore_sale', ?, ?, ?, ?, ?)""",
            (
                product_id,
                qty,
                _restore_reason(order_ref, movement["id"]),
                order_ref,
                chip_id,
                now_utc(),
            ),
        )
        try:
            if fifo_qty > 0:
                create_lot_with_items(conn, product_id, chip_id, fifo_qty)
            if negative_qty > 0:
                conn.execute(
                    """UPDATE negative_balance
                       SET qty = qty - ?, updated_at = ?
                       WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?""",
                    (negative_qty, now_utc(), product_id, chip_id),
                )
                conn.execute(
                    """DELETE FROM negative_balance
                       WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?
                         AND qty <= 0""",
                    (product_id, chip_id),
                )
        except Exception as exc:
            item, before = captured_by_movement.get(
                movement["id"], (ItemSnapshot(), InventorySnapshot())
            )
            raise InventoryAuditFault(
                reason=AuditReason.FAILURE_RESTORE_MUTATION,
                detail="inventory_restore_mutation_failed",
                item=item,
                requested_delta=qty,
                before=before,
                stock_movement_id=movement["id"],
                negative_movement_id=(
                    plan["negative_movement_id"] if negative_qty > 0 else None
                ),
            ) from exc

        Event(
            summary=f"Hoan hang +{qty} (order {order_ref})",
            type="inventory",
            data={
                "product_id": product_id,
                "movement_type": "restore_sale",
                "quantity": qty,
                "reference_id": order_ref,
                "price_chip_id": chip_id,
            },
        ).save(conn)


def load_order_inventory_rows(conn, order_id: int) -> list:
    """Capture saved item rows before an edit replaces their operational state."""
    return conn.execute(
        """SELECT oi.*, o.source
           FROM order_items oi JOIN orders o ON o.id = oi.order_id
           WHERE oi.order_id = ? ORDER BY oi.position, oi.id""",
        (order_id,),
    ).fetchall()


def _attributes(row) -> tuple[dict, bool, bool]:
    attrs = {}
    raw = row["attributes"]
    if raw:
        if isinstance(raw, str):
            try:
                attrs = json.loads(raw)
            except json.JSONDecodeError:
                attrs = {}
        elif isinstance(raw, dict):
            attrs = raw
    present = "useInventory" in attrs
    value = attrs.get("useInventory")
    enabled = value.lower() == "true" if isinstance(value, str) else bool(value)
    return attrs, present, enabled


def _product_for_saved_item(conn, code_or_id):
    if code_or_id in (None, ""):
        return None
    row = conn.execute(
        "SELECT id, product_code, name FROM products WHERE product_code = ?",
        (str(code_or_id),),
    ).fetchone()
    if row is not None:
        return row
    try:
        return conn.execute(
            "SELECT id, product_code, name FROM products WHERE id = ?",
            (int(code_or_id),),
        ).fetchone()
    except (TypeError, ValueError):
        return None


def _decision_for_row(conn, row) -> dict:
    """Resolve the same display/source/chip decision used by stock mutation."""
    _, use_present, use_enabled = _attributes(row)
    base_item = ItemSnapshot(
        order_item_id=row["id"],
        product_code=str(row["product_id"] or "") or None,
        product_name=row["product_name"],
        is_gift=bool(row["is_gift"]),
        source=row["source"],
        requested_quantity=int(row["quantity"]),
        price_chip_id=row["price_chip_id"],
        use_inventory_present=use_present,
        use_inventory_value=use_enabled if use_present else None,
    )
    product = _product_for_saved_item(conn, row["product_id"])
    if product is None:
        reason = AuditReason.GIFT_ITEM if row["is_gift"] else AuditReason.MISSING_PRODUCT
        return {"item": base_item, "reason": reason}
    product_id = int(product["id"])
    selected_chip_id = row["price_chip_id"]
    selected_chip = None
    if selected_chip_id is not None:
        selected_chip = conn.execute(
            "SELECT label, price FROM product_price_chips "
            "WHERE id = ? AND product_id = ?",
            (selected_chip_id, product_id),
        ).fetchone()
    is_display = conn.execute(
        """SELECT 1 FROM product_attribute_values
           WHERE product_id = ? AND attribute_type = 'trung_bay' AND value = 'true'""",
        (product_id,),
    ).fetchone() is not None
    item = ItemSnapshot(
        **{
            **base_item.__dict__,
            "product_id": product_id,
            "product_code": product["product_code"],
            "price_chip_label": selected_chip["label"] if selected_chip else None,
            "is_display": is_display,
        }
    )
    fallback = False
    try:
        if selected_chip_id is not None:
            chip_id = normalize_price_chip(conn, product_id, selected_chip_id)
        else:
            try:
                chip_id = resolve_price_bucket_chip_id(
                    conn, product_id, normalize_price_value(row["unit_price"])
                )
            except HTTPException:
                chip_id = None
                fallback = True
    except HTTPException as exc:
        if row["is_gift"]:
            return {"item": item, "reason": AuditReason.GIFT_ITEM}
        raise InventoryAuditFault(
            reason=AuditReason.FAILURE_INVALID_PRICE_CHIP,
            detail="invalid_price_chip",
            item=item,
            requested_delta=-int(row["quantity"]),
        ) from exc

    resolved_chip = None
    if chip_id is not None:
        resolved_chip = conn.execute(
            "SELECT label, price FROM product_price_chips WHERE id = ?",
            (chip_id,),
        ).fetchone()
    item = ItemSnapshot(
        **{
            **item.__dict__,
            "resolved_bucket": "price_chip" if chip_id is not None else "base",
            "resolved_price_chip_id": chip_id,
            "resolved_price_chip_label": (
                resolved_chip["label"] if resolved_chip else None
            ),
            "resolved_unit_price": (
                normalize_price_value(resolved_chip["price"])
                if resolved_chip
                else normalize_price_value(row["unit_price"])
            ),
        }
    )
    if row["is_gift"]:
        return {"item": item, "reason": AuditReason.GIFT_ITEM}

    before = snapshot_inventory(conn, product_id, chip_id)
    if not is_display:
        reason = AuditReason.NON_DISPLAY_PRODUCT
        should_consume = False
    elif use_present and not use_enabled:
        reason = AuditReason.EXPLICIT_INVENTORY_OPT_OUT
        should_consume = False
    elif use_present:
        reason = AuditReason.EXPLICIT_INVENTORY_OPT_IN
        should_consume = True
    elif row["source"] in ("Tại tiệm - POS", "reconciliation"):
        reason = AuditReason.SOURCE_DEFAULT_CONSUME
        should_consume = True
    else:
        reason = AuditReason.SOURCE_DEFAULT_SKIP
        should_consume = False
    if fallback and is_display and should_consume:
        reason = AuditReason.PRICE_CHIP_FALLBACK_TO_BASE
    return {
        "item": item,
        "reason": reason,
        "before": before,
        "product_id": product_id,
        "chip_id": chip_id,
        "quantity": int(row["quantity"]),
        "should_consume": should_consume,
        "fallback": fallback,
    }


def audited_auto_decrement_stock(
    conn,
    order_id: int,
    order_ref: str,
    context: OperationContext,
    *,
    effect_reason: AuditReason | None = None,
    related_entry_ids: dict[int, int] | None = None,
) -> list[AuditEntry]:
    """Apply the legacy deduction and append one decision per saved item."""
    decisions = [_decision_for_row(conn, row) for row in load_order_inventory_rows(conn, order_id)]
    already_deducted = _order_sale_was_deducted(conn, order_ref)
    max_movement = conn.execute(
        "SELECT COALESCE(MAX(id), 0) AS id FROM stock_movements"
    ).fetchone()["id"]
    try:
        auto_decrement_stock(conn, order_id, order_ref)
    except InventoryAuditFault as exc:
        decision = next(
            (
                candidate
                for candidate in decisions
                if exc.item.order_item_id is not None
                and candidate["item"].order_item_id == exc.item.order_item_id
            ),
            None,
        )
        if decision is None and decisions and exc.item == ItemSnapshot():
            decision = next(
                (item for item in decisions if item.get("should_consume")),
                decisions[0],
            )
        if decision is not None:
            raise InventoryAuditFault(
                reason=exc.reason,
                detail=exc.detail,
                context=context,
                item=(decision["item"] if exc.item == ItemSnapshot() else exc.item),
                requested_delta=exc.requested_delta,
                before=decision.get("before", InventorySnapshot()),
                stock_movement_id=exc.stock_movement_id,
                negative_movement_id=exc.negative_movement_id,
            ) from exc
        raise

    new_movements = conn.execute(
        """SELECT id, product_id, price_chip_id, movement_type, quantity
           FROM stock_movements WHERE id > ? AND reference_id = ? ORDER BY id""",
        (max_movement, order_ref),
    ).fetchall()
    entries = []
    movement_pool = list(new_movements)
    running_snapshots: dict[tuple[int, int | None], InventorySnapshot] = {}
    for decision in decisions:
        item = decision["item"]
        bucket_key = (decision.get("product_id"), decision.get("chip_id"))
        before = running_snapshots.get(
            bucket_key, decision.get("before", InventorySnapshot())
        )
        if already_deducted:
            after = before
            outcome = AuditOutcome.NO_EFFECT
            reason = AuditReason.IDEMPOTENT_REPEAT
            stock_movement_id = None
            negative_movement_id = None
            applied_delta = 0
        elif "product_id" not in decision or not item.is_display:
            after = before
            outcome = AuditOutcome.SKIPPED
            reason = decision["reason"]
            stock_movement_id = None
            negative_movement_id = None
            applied_delta = 0
        else:
            sale = next(
                (
                    m for m in movement_pool
                    if m["product_id"] == decision["product_id"]
                    and m["price_chip_id"] == decision["chip_id"]
                    and m["movement_type"] == "sale"
                ),
                None,
            )
            if sale is not None:
                movement_pool.remove(sale)
            negative = next(
                (
                    m for m in movement_pool
                    if m["product_id"] == decision["product_id"]
                    and m["price_chip_id"] == decision["chip_id"]
                    and m["movement_type"] == "negative_sale"
                ),
                None,
            )
            if negative is not None:
                movement_pool.remove(negative)
            if decision["should_consume"]:
                consumed = min(decision["quantity"], before.fifo_available or 0)
                deficit = decision["quantity"] - consumed
                after = InventorySnapshot.from_counts(
                    (before.fifo_available or 0) - consumed,
                    (before.negative or 0) + deficit,
                )
            else:
                after = before
            running_snapshots[bucket_key] = after
            stock_movement_id = sale["id"] if sale else None
            negative_movement_id = negative["id"] if negative else None
            if decision["should_consume"]:
                outcome = AuditOutcome.APPLIED
                reason = decision["reason"]
                if negative is not None and not decision["fallback"]:
                    reason = AuditReason.NEGATIVE_SALE
                elif effect_reason is not None and not decision["fallback"]:
                    reason = effect_reason
                applied_delta = after.net - before.net
            else:
                outcome = AuditOutcome.SKIPPED
                reason = decision["reason"]
                applied_delta = 0
        entry = append_entry(
            conn,
            AuditEntryDraft(
                context=context,
                outcome=outcome,
                reason=reason,
                item=item,
                requested_delta=-int(item.requested_quantity or 0),
                applied_delta=applied_delta,
                before=before,
                after=after,
                stock_movement_id=stock_movement_id,
                negative_movement_id=negative_movement_id,
                related_entry_id=(related_entry_ids or {}).get(item.order_item_id),
            ),
        )
        entries.append(entry)
    if not decisions:
        entries.append(
            append_entry(
                conn,
                AuditEntryDraft(
                    context=context,
                    outcome=AuditOutcome.NO_EFFECT,
                    reason=AuditReason.IDEMPOTENT_REPEAT,
                ),
            )
        )
    return entries


def _snapshot_for_movement(
    conn, movement, item_rows: list, *, bucket_occurrence: int = 0
) -> ItemSnapshot:
    product = conn.execute(
        "SELECT id, product_code, name FROM products WHERE id = ?",
        (movement["product_id"],),
    ).fetchone()
    matched = None
    matched_snapshot = None
    match_index = 0
    for row in item_rows:
        decision = _decision_for_row(conn, row)
        if (
            decision.get("product_id") == movement["product_id"]
            and decision.get("chip_id") == movement["price_chip_id"]
        ):
            if match_index == bucket_occurrence:
                matched = row
                matched_snapshot = decision["item"]
                break
            match_index += 1
    chip = None
    if movement["price_chip_id"] is not None:
        chip = conn.execute(
            "SELECT label, price FROM product_price_chips WHERE id = ?",
            (movement["price_chip_id"],),
        ).fetchone()
    if matched_snapshot is not None:
        return matched_snapshot
    return ItemSnapshot(
        product_id=movement["product_id"],
        product_code=product["product_code"] if product else None,
        product_name=product["name"] if product else None,
        is_display=True,
        requested_quantity=-int(movement["quantity"]),
        price_chip_id=movement["price_chip_id"],
        price_chip_label=chip["label"] if chip else None,
        resolved_bucket="price_chip" if movement["price_chip_id"] is not None else "base",
        resolved_price_chip_id=movement["price_chip_id"],
        resolved_price_chip_label=chip["label"] if chip else None,
        resolved_unit_price=normalize_price_value(chip["price"]) if chip else None,
    )


def _capture_movement_snapshots(conn, movements: list, item_rows: list) -> list:
    bucket_counts: dict[tuple[int, int | None], int] = {}
    captured = []
    for movement in movements:
        bucket = (movement["product_id"], movement["price_chip_id"])
        occurrence = bucket_counts.get(bucket, 0)
        bucket_counts[bucket] = occurrence + 1
        captured.append(
            (
                movement,
                _snapshot_for_movement(
                    conn, movement, item_rows, bucket_occurrence=occurrence
                ),
                snapshot_inventory(
                    conn, movement["product_id"], movement["price_chip_id"]
                ),
            )
        )
    return captured


def audited_reverse_order_stock_for_edit(
    conn,
    order_id: int,
    order_ref: str,
    context: OperationContext,
    *,
    item_rows: list | None = None,
    reverse_operation=None,
) -> list[AuditEntry]:
    """Reverse old effects and retain immutable old-item evidence."""
    rows = item_rows if item_rows is not None else load_order_inventory_rows(conn, order_id)
    movements = conn.execute(
        """SELECT id, product_id, price_chip_id, quantity FROM stock_movements
           WHERE reference_id = ? AND movement_type = 'sale' ORDER BY id""",
        (order_ref,),
    ).fetchall()
    captured = _capture_movement_snapshots(conn, movements, rows)
    try:
        mutation = reverse_operation or reverse_order_stock_for_edit
        mutation(conn, order_id, order_ref)
    except Exception as exc:
        if isinstance(exc, InventoryAuditFault):
            raise
        movement, item, before = captured[0] if captured else (None, ItemSnapshot(), InventorySnapshot())
        raise InventoryAuditFault(
            reason=AuditReason.FAILURE_FIFO_MUTATION,
            detail="edit_reversal_mutation_failed",
            context=context,
            item=item,
            requested_delta=(-int(movement["quantity"]) if movement else None),
            before=before,
        ) from exc
    entries = []
    for movement, item, before in captured:
        after = snapshot_inventory(conn, movement["product_id"], movement["price_chip_id"])
        entries.append(
            append_entry(
                conn,
                AuditEntryDraft(
                    context=context,
                    outcome=AuditOutcome.REVERSED,
                    reason=AuditReason.EDIT_REVERSAL,
                    item=item,
                    requested_delta=-int(movement["quantity"]),
                    applied_delta=after.net - before.net,
                    before=before,
                    after=after,
                    stock_movement_id=movement["id"],
                ),
            )
        )
    if not captured:
        entries.append(
            append_entry(
                conn,
                AuditEntryDraft(
                    context=context,
                    outcome=AuditOutcome.NO_EFFECT,
                    reason=AuditReason.IDEMPOTENT_REPEAT,
                ),
            )
        )
    return entries


def audited_restore_stock_for_order(
    conn,
    order_id: int,
    order_ref: str,
    context: OperationContext,
) -> list[AuditEntry]:
    """Restore cancellation stock and append exact before/after evidence."""
    rows = load_order_inventory_rows(conn, order_id)
    movements = conn.execute(
        """SELECT id, product_id, price_chip_id, quantity FROM stock_movements
           WHERE reference_id = ? AND movement_type = 'sale' ORDER BY id""",
        (order_ref,),
    ).fetchall()
    captured = _capture_movement_snapshots(conn, movements, rows)
    plans = {
        plan["movement"]["id"]: plan
        for plan in _sale_restore_plans(conn, order_ref)
    }
    max_movement = conn.execute(
        "SELECT COALESCE(MAX(id), 0) AS id FROM stock_movements"
    ).fetchone()["id"]
    try:
        restore_stock_for_order(conn, order_id, order_ref)
    except InventoryAuditFault as exc:
        raise InventoryAuditFault(
            reason=exc.reason,
            detail=exc.detail,
            context=exc.context or context,
            item=exc.item,
            requested_delta=exc.requested_delta,
            before=exc.before,
            stock_movement_id=exc.stock_movement_id,
            negative_movement_id=exc.negative_movement_id,
        ) from exc
    new_restores = conn.execute(
        """SELECT id, reason FROM stock_movements
           WHERE id > ? AND reference_id = ? AND movement_type = 'restore_sale'
           ORDER BY id""",
        (max_movement, order_ref),
    ).fetchall()
    restores_by_reason = {row["reason"]: row for row in new_restores}
    running_snapshots: dict[tuple[int, int | None], InventorySnapshot] = {}
    entries = []
    for movement, item, captured_before in captured:
        bucket = (movement["product_id"], movement["price_chip_id"])
        before = running_snapshots.get(bucket, captured_before)
        plan = plans[movement["id"]]
        restore = restores_by_reason.get(
            _restore_reason(order_ref, movement["id"])
        )
        changed = restore is not None
        if changed:
            after = InventorySnapshot.from_counts(
                (before.fifo_available or 0) + plan["fifo_qty"],
                (before.negative or 0) - plan["negative_qty"],
            )
        else:
            after = before
        running_snapshots[bucket] = after
        entries.append(
            append_entry(
                conn,
                AuditEntryDraft(
                    context=context,
                    outcome=AuditOutcome.REVERSED if changed else AuditOutcome.NO_EFFECT,
                    reason=(AuditReason.CANCEL_RESTORE if changed else AuditReason.IDEMPOTENT_REPEAT),
                    item=item,
                    requested_delta=-int(movement["quantity"]),
                    applied_delta=after.net - before.net,
                    before=before,
                    after=after,
                    stock_movement_id=restore["id"] if restore else None,
                    negative_movement_id=(
                        plan["negative_movement_id"] if changed else None
                    ),
                ),
            )
        )
    if not captured:
        entries.append(
            append_entry(
                conn,
                AuditEntryDraft(
                    context=context,
                    outcome=AuditOutcome.NO_EFFECT,
                    reason=AuditReason.IDEMPOTENT_REPEAT,
                ),
            )
        )
    return entries
