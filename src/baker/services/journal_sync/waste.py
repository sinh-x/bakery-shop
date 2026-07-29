"""Waste/COGS-domain journal sync (DG-308 Phase 4.4, FR-ARCH-2).

Order COGS, gift COGS, waste COGS, negative-sale COGS, and restock inflow
journal entry logic, extracted from the original monolithic ``journal_sync.py``.
"""

from typing import Optional

from baker.db.schema import (
    COGS_CODE,
    INVENTORY_CODE,
    PROMO_EXPENSE_CODE,
    _account_id_by_code,
    _baseline_cost_for_product,
    _insert_journal_entry,
)
from baker.services.cost_resolver import resolve_product_cost
from baker.services.journal_sync._common import _resolve_delivered_timestamp
from baker.utils.time import now_utc


def _resolve_order_item_cost(
    conn,
    irow,
    *,
    populate_cost_at_sale: bool,
    force: bool,
) -> float:
    """Resolve the per-unit cost for one ``order_items`` row (DG-297 Phase 2).

    Snapshot-first (``cost_at_sale > 0`` and ``force`` is False → used as-is),
    otherwise resolved via :func:`resolve_product_cost` using the trưng bày
    assigned price as the baseline anchor when present (DG-296 Phase 2,
    FR5/NFR1), falling back to ``unit_price`` (DG-208 Phase 1, FR1/FR2) when no
    assigned price is stored. When ``populate_cost_at_sale`` is True the
    resolved value is also written back to ``order_items.cost_at_sale``
    (delivery-time snapshot behaviour). When False the row is left untouched
    — used by the COGS repair to compute the *expected* total without side
    effects before deciding whether to mutate.

    ``irow`` exposes ``item_id``, ``product_id``, ``quantity``, ``cost_at_sale``,
    ``unit_price`` and ``assigned_price`` columns (the latter may be ``NULL`` on
    databases that have not reached migration v84).
    """
    qty = int(irow["quantity"] or 0)
    if qty <= 0:
        return 0.0
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
        assigned_price = irow["assigned_price"]
        if assigned_price is not None:
            try:
                assigned_price = float(assigned_price)
            except (TypeError, ValueError):
                assigned_price = None
            if assigned_price <= 0:
                assigned_price = None
        if pid is None:
            # Unresolvable product_id (e.g. custom codes like BKS-DG-01
            # with no products row). Apply the 30% non-phụ-kiện baseline
            # directly to the effective anchor — mirrors the v45 backfill
            # fallback in _backfill_order_items_cost_at_sale so the live
            # delivery path no longer silently contributes 0 to COGS
            # (DG-208 review finding CQ-2). Unresolvable products are
            # never phụ kiện (phụ kiện is always a resolvable category).
            # Anchor precedence: assigned_price (trưng bày markup) →
            # selling_price (DG-208 Phase 1) — same as resolve_product_cost.
            if assigned_price is not None and assigned_price > 0:
                anchor = assigned_price
            elif selling_price is not None and selling_price > 0:
                anchor = selling_price
            else:
                anchor = 0.0
            if anchor > 0:
                cost_at_sale = _baseline_cost_for_product(
                    "", 0.0, price_override=anchor
                )
            else:
                cost_at_sale = 0.0
        else:
            cost_at_sale = resolve_product_cost(
                conn,
                pid,
                selling_price=selling_price,
                assigned_price=assigned_price,
            )
        if cost_at_sale > 0 and populate_cost_at_sale:
            conn.execute(
                "UPDATE order_items SET cost_at_sale = ? WHERE id = ?",
                (cost_at_sale, int(irow["item_id"])),
            )
    return cost_at_sale

def _resolve_order_cogs_items(
    conn,
    order_id: int,
    *,
    gift_filter: str,
    populate_cost_at_sale: bool = True,
    force: bool = False,
) -> list[tuple[int, str, float, int, float]]:
    """Resolve the per-item cost rows for an order's COGS-eligible items.

    ``gift_filter`` selects the item set:

      - ``"sold"`` → ``is_gift = 0`` (main items + sold extras, FR1).
      - ``"gift"`` → ``is_gift = 1`` (gifted extras, FR3).

    Returns a list of ``(item_id, product_name, unit_cost, quantity,
    line_total)`` rows in the order returned by the query. ``unit_cost`` is
    resolved via :func:`_resolve_order_item_cost` (snapshot-first, with the
    ``populate_cost_at_sale`` / ``force`` flags forwarded). Items with a
    resolved cost <= 0 are omitted so callers only emit lines for items with
    a real cost (FR2/FR3).

    The ``assigned_price`` column is detected (added in migration v84) and
    falls back to ``NULL`` on older databases so the SELECT works at every
    migration stage (FR8 backward compatibility).
    """
    from baker.db.queries import _has_order_items_column
    has_assigned_price = _has_order_items_column(conn, "assigned_price")
    if gift_filter == "gift":
        gift_clause = "oi.is_gift = 1"
    else:
        gift_clause = "oi.is_gift = 0"
    items = conn.execute(
        "SELECT oi.id AS item_id, oi.product_id, oi.product_name, oi.quantity, "
        "oi.cost_at_sale, oi.unit_price"
        + (", oi.assigned_price " if has_assigned_price else ", NULL AS assigned_price ")
        + f"FROM order_items oi WHERE oi.order_id = ? AND {gift_clause}",
        (order_id,),
    ).fetchall()
    rows: list[tuple[int, str, float, int, float]] = []
    for irow in items:
        qty = int(irow["quantity"] or 0)
        if qty <= 0:
            continue
        unit_cost = _resolve_order_item_cost(
            conn,
            irow,
            populate_cost_at_sale=populate_cost_at_sale,
            force=force,
        )
        if unit_cost > 0:
            rows.append(
                (
                    int(irow["item_id"]),
                    str(irow["product_name"] or ""),
                    float(unit_cost),
                    qty,
                    float(unit_cost) * qty,
                )
            )
    return rows

def _compute_order_cogs_total(
    conn, order_id: int, *, populate_cost_at_sale: bool = True, force: bool = False
) -> float:
    """Compute the expected total COGS for an order (DG-208 Phase 5).

    Iterates the order's sold items (main items + sold extras with
    ``is_gift = 0``). For each item the per-unit cost is resolved via
    :func:`_resolve_order_item_cost` (snapshot-first, populating
    ``cost_at_sale`` for any zero-cost items using the current cost_history /
    baseline rule with ``unit_price``/``assigned_price`` as the anchor).

    DG-297 Phase 2 (FR1): the ``is_extra = 0`` filter was removed so sold
    extras (is_extra=1, is_gift=0) are now included alongside main items —
    phụ kiện baseline = 100% base_price (cost_at_sale snapshot preserved).
    Gifted items (is_gift=1) are excluded here; their cost is recorded by
    :func:`_sync_order_gift_cogs_entry` (FR3).

    Returns the summed ``cost * qty`` as a non-negative ``float``.
    """
    rows = _resolve_order_cogs_items(
        conn,
        order_id,
        gift_filter="sold",
        populate_cost_at_sale=populate_cost_at_sale,
        force=force,
    )
    return sum(line_total for _, _, _, _, line_total in rows)

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

    Computes the per-item cost rows via :func:`_resolve_order_cogs_items`
    (populating ``cost_at_sale`` for any zero-cost items using the current
    cost_history / baseline rule with ``unit_price``/``assigned_price`` as the
    anchor), then inserts a single ``order_cogs`` journal entry with one
    DR COGS 5900 / CR Inventory 1300 line pair per item (main + sold extras)
    with cost > 0 (DG-297 Phase 2, FR2 — per-item lines with item-identifying
    descriptions).

    When ``total_cogs_override`` is provided, the internal per-item
    :func:`_resolve_order_cogs_items` call is skipped and the per-item rows
    are read from the already-populated ``cost_at_sale`` snapshot (the caller
    MUST have populated ``cost_at_sale`` via a prior
    ``_compute_order_cogs_total(populate_cost_at_sale=True, ...)`` call —
    DG-208 review finding CQ-3, used by the COGS stale-entry repair path).
    The override still produces per-item lines: each item's snapshotted
    ``cost_at_sale`` is read to build the line pair, so the per-item structure
    is preserved across both code paths (NFR1 backward compatibility for
    existing entries — old aggregated entries are not retroactively changed,
    new entries use per-item lines).

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
        # The caller already populated cost_at_sale — read the snapshot to
        # build the per-item line pairs (FR2 per-item structure preserved on
        # the override path, used by the COGS repair).
        item_rows = _resolve_order_cogs_items(
            conn, order_id, gift_filter="sold", populate_cost_at_sale=False, force=False
        )
    else:
        item_rows = _resolve_order_cogs_items(
            conn, order_id, gift_filter="sold", populate_cost_at_sale=True, force=False
        )
        total_cogs = sum(line_total for _, _, _, _, line_total in item_rows)
    if total_cogs <= 0:
        return

    cogs_account_id = _account_id_by_code(conn, COGS_CODE)
    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    order_transaction_date = _resolve_delivered_timestamp(conn, order_id, order_ref) or now_utc()
    lines: list[tuple[int, float, float, str]] = []
    for _item_id, product_name, _unit_cost, _qty, line_total in item_rows:
        label = product_name or "Giá vốn hàng bán"
        lines.append((cogs_account_id, line_total, 0.0, f"Giá vốn: {label}"))
        lines.append((inventory_account_id, 0.0, line_total, f"Xuất kho: {label}"))
    _insert_journal_entry(
        conn,
        description=f"Order COGS: {order_ref}",
        source_type="order_cogs",
        source_id=order_id,
        lines=lines,
        transaction_date=order_transaction_date,
    )

def _sync_order_gift_cogs_entry(
    conn,
    order_id: int,
    order_ref: str,
) -> None:
    """Create the ``order_gift_cogs`` journal entry for a delivered order if absent.

    DG-297 Phase 2 (FR3). For each gifted item (``is_gift = 1``) with cost > 0
    a per-item DR Promotional Expense 5910 / CR Inventory 1300 line pair is
    emitted with an item-identifying description, recording the promotional
    cost of the giveaway (gifts consume inventory but have no sale movement,
    so the cost is journaled independently — see §11 risk register).

    ``cost_at_sale`` is populated at delivery time via
    :func:`_resolve_order_cogs_items` (same snapshot-first behaviour as main
    items, FR4) so the gift cost snapshot is preserved alongside the sold
    items.

    Idempotent: skips when an ``order_gift_cogs`` entry already exists for
    the order (NFR2 — re-running delivery sync does not create duplicates).
    When there are no gifted items (or all resolve to zero cost) no entry is
    created, leaving the idempotency check ready for a later delivery sync
    that might add gifts.
    """
    existing = conn.execute(
        "SELECT 1 FROM journal_entries WHERE source_type = 'order_gift_cogs' "
        "AND source_id = ?",
        (order_id,),
    ).fetchone()
    if existing:
        return

    item_rows = _resolve_order_cogs_items(
        conn, order_id, gift_filter="gift", populate_cost_at_sale=True, force=False
    )
    total_gift_cogs = sum(line_total for _, _, _, _, line_total in item_rows)
    if total_gift_cogs <= 0:
        return

    promo_account_id = _account_id_by_code(conn, PROMO_EXPENSE_CODE)
    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    order_transaction_date = _resolve_delivered_timestamp(conn, order_id, order_ref) or now_utc()
    lines: list[tuple[int, float, float, str]] = []
    for _item_id, product_name, _unit_cost, _qty, line_total in item_rows:
        label = product_name or "Khuyến mãi"
        lines.append((promo_account_id, line_total, 0.0, f"Chi phí khuyến mãi: {label}"))
        lines.append((inventory_account_id, 0.0, line_total, f"Xuất kho khuyến mãi: {label}"))
    _insert_journal_entry(
        conn,
        description=f"Order gift COGS: {order_ref}",
        source_type="order_gift_cogs",
        source_id=order_id,
        lines=lines,
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
