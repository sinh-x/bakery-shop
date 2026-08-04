"""Shared helper functions used across migrations (extracted from schema.py)."""

import sqlite3
from typing import Optional
from baker.utils.time import now_utc
import unicodedata
from ._constants import *  # noqa: F401,F403 — helpers reference schema constants


def _normalize_accessory_name(name: str) -> str:
    return " ".join(name.strip().lower().split())

def _guard_add_column(conn, table: str, column: str, col_def: str):
    """Add a column only if it doesn't already exist (idempotent forward-only migration)."""
    if table not in ALLOWED_TABLES:
        raise ValueError(f"table {table!r} not in ALLOWED_TABLES")
    existing = [r[1] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()]
    if column not in existing:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {col_def}")

def _guard_drop_column(conn, table: str, column: str):
    """Drop a column only if it still exists (idempotent forward-only migration)."""
    if table not in ALLOWED_TABLES:
        raise ValueError(f"table {table!r} not in ALLOWED_TABLES")
    existing = [r[1] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()]
    if column in existing:
        conn.execute(f"ALTER TABLE {table} DROP COLUMN {column}")

def _seed_expense_categories(conn) -> None:
    """Seed the ``expense_categories`` table (idempotent via INSERT OR IGNORE).

    Parents are inserted first so their generated ids can be referenced by the
    subcategory rows. The unique index on (name, COALESCE(parent_id, -1))
    guarantees re-runs are no-ops on an already-seeded DB.
    """
    name_to_id: dict[str, int] = {}
    for name, account_code, parent_name in SEED_EXPENSE_CATEGORIES:
        parent_id = name_to_id.get(parent_name) if parent_name else None
        conn.execute(
            "INSERT OR IGNORE INTO expense_categories (name, account_code, parent_id) "
            "VALUES (?, ?, ?)",
            (name, account_code, parent_id),
        )
        row = conn.execute(
            "SELECT id FROM expense_categories "
            "WHERE name = ? AND COALESCE(parent_id, -1) = COALESCE(?, -1)",
            (name, parent_id),
        ).fetchone()
        if row is not None:
            name_to_id[name] = int(row[0])

def _seed_chart_of_accounts(conn) -> None:
    """Seed the chart of accounts (idempotent via INSERT OR IGNORE)."""
    code_to_id: dict[str, int] = {}
    for code, name, acc_type, parent_code in SEED_CHART_OF_ACCOUNTS:
        parent_id = code_to_id.get(parent_code) if parent_code else None
        cursor = conn.execute(
            "INSERT OR IGNORE INTO accounts (code, name, type, parent_id) "
            "VALUES (?, ?, ?, ?)",
            (code, name, acc_type, parent_id),
        )
        # NOTE: ``cursor.lastrowid`` is NOT a reliable "did we insert?" flag.
        # On an ignored INSERT OR IGNORE, sqlite3 returns the lastrowid of the
        # most recent successful INSERT on this connection (stale), not 0. So
        # always resolve the actual row id by code — this is correct whether
        # the row was just inserted or already existed (DG-245 Phase 2).
        row = conn.execute(
            "SELECT id FROM accounts WHERE code = ?", (code,)
        ).fetchone()
        code_to_id[code] = int(row[0])

def _ensure_staff_payable_sub_account(conn, staff_name: str) -> int:
    """Create (or return) a sub-account under Phải trả nhân viên for a staff member.

    Sub-account code is derived as 23XX where XX is a stable zero-padded index
    assigned by first-seen order. The code is unique within the chart of
    accounts and the parent is the 2300 parent account.
    """
    parent_row = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (STAFF_PAYABLES_CODE,)
    ).fetchone()
    if parent_row is None:
        raise RuntimeError(
            "Staff Payables parent account (2300) missing; seed COA first"
        )
    parent_id = int(parent_row[0])

    existing = conn.execute(
        "SELECT id FROM accounts WHERE parent_id = ? AND name = ?",
        (parent_id, staff_name),
    ).fetchone()
    if existing:
        return int(existing[0])

    count_row = conn.execute(
        "SELECT COUNT(*) FROM accounts WHERE parent_id = ?", (parent_id,)
    ).fetchone()
    next_idx = int(count_row[0]) + 1
    code = f"23{next_idx:02d}"
    cursor = conn.execute(
        "INSERT INTO accounts (code, name, type, parent_id) VALUES (?, ?, 'liability', ?)",
        (code, staff_name, parent_id),
    )
    return int(cursor.lastrowid)

def _ensure_ap_vendor_sub_account(conn, vendor_name: str) -> int:
    """Create (or return) a per-vendor sub-account under Accounts Payable (2500).

    Mirrors :func:`_ensure_staff_payable_sub_account` but uses a MAX-based
    25XX code derivation instead of COUNT-based indexing. MAX-based avoids
    collision risk when sub-accounts are deleted and re-created: a COUNT-based
    counter would reuse the freed index and could clash with stale references,
    whereas MAX-based only ever moves forward (DG-245 Phase 3, FR2).

    The parent is the 2500 Accounts Payable account seeded by the v73
    migration (Phase 2). The sub-account name is the vendor's name, so the
    vendor → sub-account resolution is a single source of truth.
    """
    parent_row = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (ACCOUNTS_PAYABLE_CODE,)
    ).fetchone()
    if parent_row is None:
        raise RuntimeError(
            "Accounts Payable parent account (2500) missing; "
            "run v73 migration or seed COA first"
        )
    parent_id = int(parent_row[0])

    existing = conn.execute(
        "SELECT id FROM accounts WHERE parent_id = ? AND name = ?",
        (parent_id, vendor_name),
    ).fetchone()
    if existing:
        return int(existing[0])

    # MAX-based code derivation: scan existing vendor sub-account codes under
    # the 2500 parent and pick MAX+1. The GLOB patterns match both the legacy
    # 4-digit ``25[0-9][0-9]`` range (2501..2599, vendors 1-99) and the expanded
    # 5-digit ``25[0-9][0-9][0-9]`` range (25001..25999, vendors 100-999), so the
    # prior overflow at vendor #99 (2599 → 2600, escaping the 25xx namespace and
    # tripping the accounts.code UNIQUE constraint) is avoided without
    # disturbing existing 4-digit sub-accounts (CQ-2). Start at 2501 so the
    # first vendor sub-account does not collide with the parent 2500 code.
    max_row = conn.execute(
        "SELECT code FROM accounts "
        "WHERE parent_id = ? "
        "  AND (code GLOB '25[0-9][0-9]' OR code GLOB '25[0-9][0-9][0-9]') "
        "ORDER BY CAST(code AS INTEGER) DESC LIMIT 1",
        (parent_id,),
    ).fetchone()
    if max_row is None:
        next_num = 2501
    else:
        next_num = int(max_row[0]) + 1
    # Guard against the 4-digit overflow (CQ-2): when the max code is a 4-digit
    # 25xx value (2501..2599) and incrementing it would leave the 25-prefixed
    # namespace (2600+), roll to the 5-digit range so the new code stays under
    # the 2500 parent's 25xxx namespace (25001..25999). This preserves existing
    # 4-digit sub-accounts while accommodating up to 999 vendors total.
    if next_num >= 2600 and next_num < 25001:
        next_num = 25001
    code = f"{next_num}"
    try:
        cursor = conn.execute(
            "INSERT INTO accounts (code, name, type, parent_id) "
            "VALUES (?, ?, 'liability', ?)",
            (code, vendor_name, parent_id),
        )
        return int(cursor.lastrowid)
    except sqlite3.IntegrityError:
        # A concurrent insert may have created the same-name sub-account
        # between our existence check and the INSERT. Re-fetch rather than
        # swallow the error — silently losing the JE is the CQ-2 failure mode.
        existing = conn.execute(
            "SELECT id FROM accounts WHERE parent_id = ? AND name = ?",
            (parent_id, vendor_name),
        ).fetchone()
        if existing:
            return int(existing[0])
        raise

def _account_id_by_code(conn, code: str) -> int:
    row = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (code,)
    ).fetchone()
    if row is None:
        raise RuntimeError(f"Account code {code!r} not found")
    return int(row[0])

def _insert_journal_entry(
    conn,
    *,
    description: str,
    source_type: str,
    source_id,
    lines: list[tuple[int, float, float, str]],
    transaction_date: str | None = None,
    drawer_id: int | None = None,
) -> int:
    """Create a journal entry with its lines.

    `lines` is a list of (account_id, debit, credit, line_description).
    Double-entry integrity is enforced: total debit must equal total credit.

    `transaction_date` is the business event date the entry relates to (used
    by reports, API filtering, and journal locks). When ``None``, defaults to
    the current local time.
    The audit-only ``created_at`` column is set explicitly via
    ``now_utc()`` — the same pattern used by Event.save(), Order.save(),
    PaymentTransaction.save(), etc.

    `drawer_id` (DG-347 Phase 2, FR4): when provided, the new journal entry is
    linked to the given cash drawer via the ``cash_drawer_journal_entries``
    join table so per-drawer balance derivation (``expected_balance``) can
    filter 1101 journal lines by drawer. ``INSERT OR IGNORE`` makes the link
    idempotent.
    """
    total_debit = sum(d for _, d, _, _ in lines)
    total_credit = sum(c for _, _, c, _ in lines)
    if abs(total_debit - total_credit) > 0.005:
        raise RuntimeError(
            f"Double-entry violation: debit={total_debit} credit={total_credit} "
            f"for {source_type}:{source_id}"
        )

    if transaction_date is None:
        transaction_date = conn.execute(
            "SELECT strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'"
        ).fetchone()[0]

    # Transition guard: write transaction_date only when the column exists
    # (added by migration v50). Before v50 is applied, fall back to the legacy
    # INSERT that relies on the created_at DEFAULT. This keeps v44/v46/v47/v48/
    # v49 backfills (which run before v50 on fresh DBs) working unchanged.
    has_col = "transaction_date" in {
        r[1] for r in conn.execute("PRAGMA table_info(journal_entries)").fetchall()
    }
    now = now_utc()
    if has_col:
        cursor = conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, transaction_date, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (description, source_type, source_id, transaction_date, now),
        )
    else:
        cursor = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id, created_at) "
            "VALUES (?, ?, ?, ?)",
            (description, source_type, source_id, now),
        )
    entry_id = int(cursor.lastrowid)
    for account_id, debit, credit, line_desc in lines:
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, account_id, float(debit), float(credit), line_desc),
        )
    # DG-347 Phase 2 (FR4): link the journal entry to its cash drawer via the
    # join table so expected_balance() can filter 1101 lines per drawer.
    if drawer_id is not None:
        conn.execute(
            "INSERT OR IGNORE INTO cash_drawer_journal_entries "
            "(cash_drawer_id, journal_entry_id) VALUES (?, ?)",
            (int(drawer_id), entry_id),
        )
    return entry_id

def _backfill_expense_journal_entries(conn) -> None:
    """Backfill journal entries for all non-deleted expense events.

    DG-302 Phase 6 (FR4/AC4): when ``events.data.subcategory`` maps to an
    account code, the debit hits that subcategory account (e.g. 5110 for
    Trứng) and the inventory-purchase path is bypassed. Without a mappable
    subcategory, the legacy behavior applies: parent categories in
    ``INVENTORY_PURCHASE_CATEGORIES`` debit Inventory (1300).
    """
    import json

    rows = conn.execute(
        "SELECT id, summary, data, timestamp FROM events "
        "WHERE type = 'expense' "
        "  AND (deleted_at IS NULL OR deleted_at = '')"
    ).fetchall()

    for row in rows:
        event_id = int(row["id"])
        # Skip if a journal entry already exists for this source (idempotent).
        existing = conn.execute(
            "SELECT 1 FROM journal_entries "
            "WHERE source_type = 'expense' AND source_id = ?",
            (event_id,),
        ).fetchone()
        if existing:
            continue

        event_timestamp = row["timestamp"] or ""

        try:
            data = json.loads(row["data"]) if row["data"] else {}
        except (json.JSONDecodeError, TypeError):
            continue

        amount = data.get("amount_vnd")
        category = data.get("category")
        payment_source = data.get("payment_source")
        if not isinstance(amount, (int, float)) or amount <= 0:
            continue
        if not isinstance(category, str) or not category:
            continue
        if not isinstance(payment_source, str) or not payment_source:
            continue

        # Phase 6: prefer subcategory account code; fall back to category.
        subcategory = data.get("subcategory")
        has_subcategory_code = (
            isinstance(subcategory, str)
            and bool(subcategory)
            and bool(EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(subcategory))
        )
        if has_subcategory_code:
            expense_code = EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(subcategory)
        else:
            expense_code = EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(category)
        if not expense_code:
            continue

        if payment_source == "Nhân viên ứng trước":
            staff_name = (data.get("paid_by_name") or "").strip()
            if not staff_name:
                continue
            payment_account_id = _ensure_staff_payable_sub_account(conn, staff_name)
        else:
            account_code = EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE.get(payment_source)
            if not account_code:
                continue
            payment_account_id = _account_id_by_code(conn, account_code)

        # Phase 6: a mappable subcategory debits its own account and bypasses
        # the inventory-purchase path (FR4/AC4). Otherwise, parent
        # inventory-purchase categories still debit Inventory (1300) (FR6).
        if not has_subcategory_code and category in INVENTORY_PURCHASE_CATEGORIES:
            inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
            _insert_journal_entry(
                conn,
                description=f"Expense: {row['summary']}",
                source_type="expense",
                source_id=event_id,
                transaction_date=event_timestamp,
                lines=[
                    (inventory_account_id, float(amount), 0.0, "Nhập kho nguyên vật liệu"),
                    (payment_account_id, 0.0, float(amount), "Thanh toán"),
                ],
            )
        else:
            expense_account_id = _account_id_by_code(conn, expense_code)
            _insert_journal_entry(
                conn,
                description=f"Expense: {row['summary']}",
                source_type="expense",
                source_id=event_id,
                transaction_date=event_timestamp,
                lines=[
                    (expense_account_id, float(amount), 0.0, "Chi phí"),
                    (payment_account_id, 0.0, float(amount), "Thanh toán"),
                ],
            )

def _backfill_payment_transaction_journal_entries(conn) -> None:
    """Backfill journal entries for all payment_transactions."""
    rows = conn.execute(
        "SELECT id, order_id, amount, type, method, created_at "
        "FROM payment_transactions"
    ).fetchall()

    for row in rows:
        pt_id = int(row["id"])
        existing = conn.execute(
            "SELECT 1 FROM journal_entries "
            "WHERE source_type = 'payment_transaction' AND source_id = ?",
            (pt_id,),
        ).fetchone()
        if existing:
            continue

        amount = float(row["amount"] or 0)
        if amount <= 0:
            continue

        method = row["method"] or "cash"
        asset_code = PAYMENT_METHOD_TO_ASSET_CODE.get(method, "1100")
        asset_account_id = _account_id_by_code(conn, asset_code)
        deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
        tien_rut_account_id = _account_id_by_code(conn, TIEN_RUT_HELD_CODE)

        ptype = row["type"] or "deposit"
        transaction_date = row["created_at"] or ""
        if ptype in PAYMENT_OUTFLOW_TYPES:
            # Cash flows back to customer: debit Customer Deposits, credit Asset.
            _insert_journal_entry(
                conn,
                description=f"Payment: {ptype} {amount}",
                source_type="payment_transaction",
                source_id=pt_id,
                transaction_date=transaction_date,
                lines=[
                    (deposits_account_id, amount, 0.0, "Hoàn tiền khách"),
                    (asset_account_id, 0.0, amount, "Trả lại tiền"),
                ],
            )
        elif ptype in PAYMENT_TIEN_RUT_TYPES:
            # Tien rut deposit inflow (DG-198 reversal): customer gives cash to
            # the shop for safekeeping. DR Asset, CR 2400 (Tien Rut Held). 2400
            # is cleared at delivery via a separate return entry.
            _insert_journal_entry(
                conn,
                description=f"Payment: tien_rut {amount}",
                source_type="payment_transaction",
                source_id=pt_id,
                transaction_date=transaction_date,
                lines=[
                    (asset_account_id, amount, 0.0, "Tiền khách gửi giữ hộ"),
                    (tien_rut_account_id, 0.0, amount, "Tiền rút tạm giữ"),
                ],
            )
        else:
            # Customer pays in: debit Asset, credit Customer Deposits.
            _insert_journal_entry(
                conn,
                description=f"Payment: {ptype} {amount}",
                source_type="payment_transaction",
                source_id=pt_id,
                transaction_date=transaction_date,
                lines=[
                    (asset_account_id, amount, 0.0, "Tiền khách đặt/cọc"),
                    (deposits_account_id, 0.0, amount, "Tiền khách đặt cọc"),
                ],
            )

def _backfill_delivered_order_journal_entries(conn) -> None:
    """Backfill revenue conversion + COGS entries for delivered and completed orders.

    Revenue entries are reconciled against current net deposits
    (deposits − tien_rut refunds): stale entries are deleted and recreated so
    the 2100 debit matches the actual deposit balance being converted to
    revenue. Orders with net deposits <= 0 get no revenue entry. This keeps the
    backfill consistent with :func:`_sync_delivered_order_journal`.

    Delegates revenue reconciliation to
    :func:`_reconcile_order_revenue_entry` so that locked entries are reversed
    (never deleted) — the same path used by live sync (review findings M-1, Mn-2).
    """
    from baker.models.payment_transaction import PaymentTransaction
    from baker.services.journal_sync import _reconcile_order_revenue_entry

    orders = conn.execute(
        "SELECT id, order_ref, total_price, due_date, created_at "
        "FROM orders WHERE status IN ('delivered', 'completed')"
    ).fetchall()

    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    cogs_account_id = _account_id_by_code(conn, COGS_CODE)

    for orow in orders:
        order_id = int(orow["id"])
        order_ref = orow["order_ref"]
        # Phase 3: use now_utc() as the authoritative transaction timestamp
        # for backfilled delivered-order journal entries.
        transaction_date = now_utc()

        # Revenue reconciliation — shared with live sync (handles lock checks
        # and idempotent creation via _reconcile_order_revenue_entry).
        _reconcile_order_revenue_entry(
            conn,
            order_id,
            order_ref,
            total_price=float(orow["total_price"] or 0),
        )

        # COGS: for each order_item with product.cost > 0, debit COGS, credit Inventory.
        # Group into one COGS entry per order for performance and clarity.
        existing_cogs = conn.execute(
            "SELECT 1 FROM journal_entries "
            "WHERE source_type = 'order_cogs' AND source_id = ?",
            (order_id,),
        ).fetchone()
        if existing_cogs:
            continue

        items = conn.execute(
            "SELECT oi.product_name, oi.quantity, p.cost "
            "FROM order_items oi "
            "LEFT JOIN products p ON CAST(oi.product_id AS INTEGER) = p.id "
            "WHERE oi.order_id = ? AND oi.is_extra = 0 AND oi.is_gift = 0",
            (order_id,),
        ).fetchall()

        total_cogs = 0.0
        for irow in items:
            cost = float(irow["cost"] or 0)
            qty = int(irow["quantity"] or 0)
            if cost > 0 and qty > 0:
                total_cogs += cost * qty

        if total_cogs > 0:
            _insert_journal_entry(
                conn,
                description=f"Order COGS: {order_ref}",
                source_type="order_cogs",
                source_id=order_id,
                transaction_date=transaction_date,
                lines=[
                    (cogs_account_id, total_cogs, 0.0, "Giá vốn hàng bán"),
                    (inventory_account_id, 0.0, total_cogs, "Xuất kho"),
                ],
            )

def _backfill_journal_transaction_date(conn) -> None:
    """Re-backfill ``transaction_date`` on existing ``journal_entries`` from
    their source record dates.

    Source-type → source-date mapping (FR10/FR11):

    - ``expense`` → ``events.timestamp`` (via ``source_id`` = event id)
    - ``payment_transaction`` → ``payment_transactions.created_at``
    - ``order`` → ``orders.due_date`` (fallback ``orders.created_at``)
    - ``order_cogs`` → ``orders.due_date`` (fallback ``orders.created_at``)
    - ``waste_cogs`` → ``stock_movements.created_at`` (via ``source_id``)
    - ``owner_capital``, ``owner_draw``, ``staff_reimburse`` → existing
      ``created_at`` (no source record exists; INSERT time is the business date)
    - ``reversal`` → existing ``created_at`` (reversals are corrected in
      Phase 3 via ``_reverse_journal_entry`` copying the original entry's date)
    - ``order_shipping_hold`` / ``order_shipping_release`` → ``orders.due_date``
      (fallback ``orders.created_at``); these originated at order delivery time

    Idempotent (AC10): entries whose ``transaction_date`` is already non-empty
    are skipped, so re-running on a backfilled DB is a no-op.
    """
    conn.execute(
        """
        UPDATE journal_entries
        SET transaction_date = (
            SELECT e.timestamp
            FROM events e
            WHERE e.id = journal_entries.source_id
        )
        WHERE source_type = 'expense'
          AND (transaction_date IS NULL OR transaction_date = '')
        """
    )
    conn.execute(
        """
        UPDATE journal_entries
        SET transaction_date = (
            SELECT pt.created_at
            FROM payment_transactions pt
            WHERE pt.id = journal_entries.source_id
        )
        WHERE source_type = 'payment_transaction'
          AND (transaction_date IS NULL OR transaction_date = '')
        """
    )
    now = now_utc()
    for source_type in ("order", "order_cogs", "order_shipping_hold",
                        "order_shipping_release"):
        conn.execute(
            """
            UPDATE journal_entries
            SET transaction_date = ?
            WHERE source_type = ?
              AND (transaction_date IS NULL OR transaction_date = '')
            """,
            (now, source_type,),
        )
    conn.execute(
        """
        UPDATE journal_entries
        SET transaction_date = (
            SELECT sm.created_at
            FROM stock_movements sm
            WHERE sm.id = journal_entries.source_id
        )
        WHERE source_type = 'waste_cogs'
          AND (transaction_date IS NULL OR transaction_date = '')
        """
    )
    # Manual / reversal source types have no source record — use the existing
    # created_at as the business date (FR6/FR12).
    conn.execute(
        """
        UPDATE journal_entries
        SET transaction_date = created_at
        WHERE source_type IN (
            'owner_capital', 'owner_draw', 'staff_reimburse', 'reversal'
        )
          AND (transaction_date IS NULL OR transaction_date = '')
        """
    )

def _baseline_cost_for_product(
    category: str, base_price: float, *, price_override: Optional[float] = None
) -> float:
    """Baseline cost: 30% of the anchor price for non-phụ-kiện, 100% for phụ kiện.

    The anchor is ``price_override`` when provided (the actual selling price),
    otherwise ``base_price``. Phụ kiện always uses ``base_price`` regardless of
    ``price_override`` — the 100% rule is intentional and unchanged (Non-Goal:
    do not change how phụ kiện COGS works). The 30% non-phụ-kiện rule shifts to
    the selling price when available so COGS reflects the actual sale value
    rather than the catalog base price (DG-208 Phase 1, FR1).
    """
    if category == PHU_KIEN_CATEGORY:
        return float(base_price)
    anchor = float(price_override) if price_override is not None else float(base_price)
    return round(anchor * 0.30, 2)

def _backfill_order_items_cost_at_sale(conn) -> None:
    """Populate cost_at_sale on existing delivered order_items using the
    baseline rule (30% non-phụ-kiện / 100% phụ-kiện).

    The anchor is the actual selling price (``unit_price``) when available,
    falling back to ``base_price`` otherwise (DG-208 Phase 2, FR2/NFR2). For
    items whose product cannot be resolved (e.g. custom-product codes like
    ``BKS-DG-01`` that have no matching ``products`` row), the 30% non-phụ-kiện
    baseline is applied to ``unit_price`` — phụ kiện is a real product category
    that is always resolvable, so unresolvable items are never phụ kiện.

    Idempotent: only updates order_items whose cost_at_sale is 0. Cost_history
    is not consulted at backfill time because historical cost records do not
    exist before this migration; the baseline rule is the documented estimate.

    DG-297 Phase 1: the ``is_extra = 0`` filter was removed so sold extras
    (is_extra=1, is_gift=0) receive the baseline cost backfill (phụ kiện =
    100% base_price). Gifted items (is_gift=1) are still excluded — their
    cost is handled by the order_gift_cogs journal entry at delivery time.
    """
    rows = conn.execute(
        """
        SELECT oi.id AS item_id, oi.unit_price,
               p.category, p.base_price
        FROM order_items oi
        JOIN orders o ON o.id = oi.order_id
        LEFT JOIN products p ON CAST(oi.product_id AS INTEGER) = p.id
        WHERE o.status IN ('delivered', 'completed')
          AND oi.is_gift = 0
          AND (oi.cost_at_sale IS NULL OR oi.cost_at_sale = 0)
        """
    ).fetchall()
    for row in rows:
        category = row["category"] if row["category"] is not None else ""
        unit_price = float(row["unit_price"] or 0)
        base_price = float(row["base_price"] or 0)
        # Anchor on the actual selling price (unit_price) when available, else
        # base_price. Unresolvable products (no products row, e.g. custom
        # codes like BKS-DG-01) are never phụ kiện — phụ kiện is always a real
        # resolvable category — so they correctly fall through the 30% non-
        # phụ-kiện branch (DG-208 Phase 2, fixes Order #1091 missing COGS).
        anchor = unit_price if unit_price > 0 else base_price
        cost = _baseline_cost_for_product(category, base_price, price_override=anchor)
        if cost > 0:
            conn.execute(
                "UPDATE order_items SET cost_at_sale = ? WHERE id = ?",
                (cost, int(row["item_id"])),
            )

def _strip_diacritics(text: str) -> str:
    """Remove Vietnamese diacritics for case-insensitive search.

    Converts 'Nguyễn Văn Đức' → 'nguyen van duc' so searching for
    'duc' or 'Đức' or 'đức' all match.
    """
    nfkd = unicodedata.normalize('NFKD', text)
    ascii_form = ''.join(ch for ch in nfkd if not unicodedata.combining(ch))
    return ascii_form.lower().replace('đ', 'd').replace('Đ', 'd')

def _normalize_phone(phone: str) -> str:
    """Normalize a phone number for grouping/deduplication.

    Strips whitespace, dots, and dashes. All phones are already in 84-prefix
    format (no leading "+"), so no prefix normalization is applied here. The
    normalized form is used only for grouping; the original phone is preserved
    in the customer record (FR2).

    >>> _normalize_phone("84 912 345 678")
    '84912345678'
    >>> _normalize_phone("84-912-345-678")
    '84912345678'
    >>> _normalize_phone("84.912.345.678")
    '84912345678'
    >>> _normalize_phone("84912345678")
    '84912345678'
    >>> _normalize_phone("")
    ''
    """
    if not phone:
        return ""
    return phone.replace(" ", "").replace(".", "").replace("-", "")

def _pick_most_common_name(names: list[str]) -> str:
    """Pick the most frequent customer name from a list of name variants.

    Comparison is case-insensitive and trims whitespace (FR3). On a tie, the
    name that sorts first alphabetically (case-insensitive) wins. The returned
    name preserves the original casing/whitespace of the first occurrence of
    the winning normalized form.

    >>> _pick_most_common_name(["Nguyen Van A"])
    'Nguyen Van A'
    >>> _pick_most_common_name(["Nguyen Van A", "Nguyen Van A", "Bob"])
    'Nguyen Van A'
    >>> _pick_most_common_name(["Nguyen Van A", "nguyen van a", "Bob"])
    'Nguyen Van A'
    >>> _pick_most_common_name(["  Nguyen Van A  ", "nguyen van a", "Bob"])
    'Nguyen Van A'
    >>> _pick_most_common_name(["Bob", "Alice"])  # tie -> Alice (alphabetical)
    'Alice'
    >>> _pick_most_common_name([])
    ''
    """
    if not names:
        return ""

    # Group original names by their normalized (lowercased, stripped) form,
    # preserving the first-seen original form within each group (stripped of
    # surrounding whitespace so the returned name is clean per FR3).
    groups: dict[str, list[str]] = {}
    counts: dict[str, int] = {}
    for name in names:
        key = (name or "").strip().lower()
        if key not in groups:
            groups[key] = []
        groups[key].append(name)
        counts[key] = counts.get(key, 0) + 1

    # Highest count wins; ties broken by alphabetical order of the key.
    best_key = min(counts, key=lambda k: (-counts[k], k))
    first = groups[best_key][0]
    return (first or "").strip()

def _order_year(created_at: str) -> Optional[int]:
    """Extract the calendar year from an orders.created_at timestamp.

    created_at is stored as ISO-8601 UTC ('YYYY-MM-DDTHH:MM:SS...Z'). Returns
    ``None`` when the value is empty or malformed.
    """
    if not created_at:
        return None
    # The year is the first 4 chars of the ISO timestamp; validate it is numeric.
    year_str = created_at[:4]
    if len(year_str) != 4 or not year_str.isdigit():
        return None
    return int(year_str)

def _recompute_customer_year_summary(conn, customer_id, year) -> None:
    """Recompute one (customer_id, year) row from scratch.

    Counts orders and sums total_price for the given customer and year. The
    row is deleted then re-inserted so it always reflects the current state of
    ``orders``. Safe to call inside an existing order transaction (NFR2: a
    single UPSERT within the same transaction adds negligible latency).
    """
    if customer_id is None or year is None:
        return
    conn.execute(
        "DELETE FROM customer_year_summary WHERE customer_id = ? AND year = ?",
        (customer_id, year),
    )
    row = conn.execute(
        "SELECT COUNT(*) AS c, COALESCE(SUM(total_price), 0) AS v "
        "FROM orders WHERE customer_id = ? "
        "  AND CAST(strftime('%Y', created_at) AS INTEGER) = ?",
        (customer_id, int(year)),
    ).fetchone()
    order_count = int(row["c"] or 0)
    total_volume = float(row["v"] or 0)
    conn.execute(
        "INSERT INTO customer_year_summary (customer_id, year, order_count, total_volume) "
        "VALUES (?, ?, ?, ?)",
        (int(customer_id), int(year), order_count, total_volume),
    )

def _repair_null_customer_links(conn) -> dict:
    """Link all ``customer_id IS NULL`` orders (DG-227 Phase 2 / DG-252 Phase 4).

    Shared repair body used by both the v66 migration (DG-227) and the v74
    backfill migration (DG-252 Phase 4). Idempotent: scans orders
    WHERE customer_id IS NULL, groups by phone/name, creates new customers
    for unmatched identities, and links orders. Three categories:
      (1) phone-having orders — resolve/match/create
      (2) name-only orders — match via search_name or create
      (3) walk-in (no phone, no name) — link to "Khách lẻ"

    Recomputes customer_year_summary for every affected customer after linking.
    Logs a summary with counts per resolution method and returns the same
    counts as a dict so callers (e.g. DG-252 backfill tests / ``baker db``
    pre/post report) can assert on them without scraping log lines.

    Returns a dict with keys: ``null_before``, ``null_after``, ``phone_match``,
    ``name_match``, ``new_customer``, ``walk_in``, ``linked``.
    """
    import logging
    from baker.models.customer import Customer

    logger = logging.getLogger("baker.db")

    total_null_before = conn.execute(
        "SELECT COUNT(*) FROM orders WHERE customer_id IS NULL"
    ).fetchone()[0]

    if total_null_before == 0:
        logger.info("Không có đơn hàng nào thiếu customer_id — bỏ qua.")
        return {
            "null_before": 0,
            "null_after": 0,
            "phone_match": 0,
            "name_match": 0,
            "new_customer": 0,
            "walk_in": 0,
            "linked": 0,
        }

    # -- Build lookup tables ------------------------------------------------
    # Existing customer phones (from customer_phones and legacy customers.phone).
    existing_phones: dict[str, int] = {}
    for crow in conn.execute(
        "SELECT customer_id, phone FROM customer_phones"
    ).fetchall():
        nphone = _normalize_phone(crow["phone"] or "")
        if nphone and nphone not in existing_phones:
            existing_phones[nphone] = crow["customer_id"]
    for crow in conn.execute(
        "SELECT id, phone FROM customers WHERE phone IS NOT NULL AND phone != ''"
    ).fetchall():
        nphone = _normalize_phone(crow["phone"] or "")
        if nphone and nphone not in existing_phones:
            existing_phones[nphone] = crow["id"]

    # Existing customers by search_name (for name-only matching).
    existing_names: dict[str, int] = {}
    for crow in conn.execute(
        "SELECT id, search_name FROM customers WHERE search_name IS NOT NULL AND search_name != ''"
    ).fetchall():
        key = crow["search_name"].strip().lower()
        if key and key not in existing_names:
            existing_names[key] = crow["id"]

    # Find "Khách lẻ" customer for walk-in orders (FR5).
    khach_le = conn.execute(
        "SELECT id FROM customers WHERE LOWER(name) = 'khách lẻ' ORDER BY id ASC LIMIT 1"
    ).fetchone()
    khach_le_id = khach_le["id"] if khach_le else None

    # -- Counters -----------------------------------------------------------
    phone_match = 0
    name_match = 0
    new_customer = 0
    walk_in = 0
    affected_customers: set[int] = set()

    def _link_and_track(oid: int, cust_id: int) -> None:
        conn.execute(
            "UPDATE orders SET customer_id = ? WHERE id = ? AND customer_id IS NULL",
            (cust_id, oid),
        )
        affected_customers.add(cust_id)

    # -- (1) Phone-having orders -------------------------------------------
    phone_rows = conn.execute(
        """
        SELECT id, customer_phone, customer_name
        FROM orders
        WHERE customer_id IS NULL
          AND customer_phone IS NOT NULL
          AND customer_phone != ''
        ORDER BY created_at ASC, id ASC
        """
    ).fetchall()

    # Group by normalized phone.
    phone_groups: dict[str, list[dict]] = {}
    for orow in phone_rows:
        nphone = _normalize_phone(orow["customer_phone"])
        if not nphone:
            continue
        phone_groups.setdefault(nphone, []).append({
            "id": orow["id"],
            "name": orow["customer_name"] or "",
        })

    for nphone, orders in phone_groups.items():
        if nphone in existing_phones:
            cust_id = existing_phones[nphone]
            for o in orders:
                _link_and_track(o["id"], cust_id)
                phone_match += 1
        else:
            # Create a new customer — use the most common name for the group.
            names = [o["name"] for o in orders if o["name"]]
            resolved_name = _pick_most_common_name(names) if names else "Khách"
            # DG-252 r3 [MAJOR]: materialize a `customer_phones` row so the
            # auto-created customer is visible to `/duplicates` and survives
            # a later merge (mirrors the runtime fix at orders.py:
            # _resolve_or_create_customer_id). Without this row the phone
            # only lives in the legacy `customers.phone` column, which the
            # dedup finder and merge copy loop never consult.
            cust = Customer(
                name=resolved_name,
                phone=nphone,
                phones=[{"phone": nphone, "isPrimary": True}],
            )
            cust_id = cust.save(conn)
            existing_phones[nphone] = cust_id
            search_name = _strip_diacritics(resolved_name)
            if search_name and search_name not in existing_names:
                existing_names[search_name] = cust_id
            for o in orders:
                _link_and_track(o["id"], cust_id)
                new_customer += 1

    # -- (2) Name-only orders (no phone, has name) -------------------------
    name_rows = conn.execute(
        """
        SELECT id, customer_name
        FROM orders
        WHERE customer_id IS NULL
          AND (customer_phone IS NULL OR customer_phone = '')
          AND customer_name IS NOT NULL
          AND customer_name != ''
        ORDER BY created_at ASC, id ASC
        """
    ).fetchall()

    # Group by diacritic-stripped name.
    name_groups: dict[str, list[dict]] = {}
    for orow in name_rows:
        key = _strip_diacritics(orow["customer_name"] or "")
        if not key:
            continue
        name_groups.setdefault(key, []).append({
            "id": orow["id"],
            "name": orow["customer_name"],
        })

    for key, orders in name_groups.items():
        if key in existing_names:
            cust_id = existing_names[key]
            for o in orders:
                _link_and_track(o["id"], cust_id)
                name_match += 1
        else:
            resolved_name = _pick_most_common_name([o["name"] for o in orders])
            cust = Customer(name=resolved_name, phone="")
            cust_id = cust.save(conn)
            existing_names[key] = cust_id
            for o in orders:
                _link_and_track(o["id"], cust_id)
                new_customer += 1

    # -- (3) Walk-in orders (no phone, no name) — FR5 ---------------------
    walk_in_rows = conn.execute(
        """
        SELECT id FROM orders
        WHERE customer_id IS NULL
          AND (customer_phone IS NULL OR customer_phone = '')
          AND (customer_name IS NULL OR customer_name = '')
        """
    ).fetchall()
    if walk_in_rows:
        # DG-252 Phase 4 (FR9/AC5): create the shared "Khách lẻ" record if it
        # does not yet exist so identity-less orders always get linked (v66
        # only linked when the row pre-existed; v74 guarantees 100% linkage).
        if khach_le_id is None:
            khach_le = Customer(name="Khách lẻ", phone="")
            khach_le_id = khach_le.save(conn)
        for row in walk_in_rows:
            _link_and_track(row["id"], khach_le_id)
            walk_in += 1

    # -- Recompute customer_year_summary for affected customers — FR6 ------
    for cust_id in affected_customers:
        year_rows = conn.execute(
            "SELECT DISTINCT CAST(strftime('%Y', created_at) AS INTEGER) AS yr "
            "FROM orders WHERE customer_id = ? AND created_at IS NOT NULL",
            (cust_id,),
        ).fetchall()
        for yr_row in year_rows:
            if yr_row["yr"]:
                _recompute_customer_year_summary(conn, cust_id, yr_row["yr"])

    # -- Log summary — FR3 --------------------------------------------------
    total_linked = phone_match + name_match + new_customer + walk_in
    total_null_after = conn.execute(
        "SELECT COUNT(*) FROM orders WHERE customer_id IS NULL"
    ).fetchone()[0]

    logger.info(
        "Đã sửa %d đơn hàng: %d khớp số điện thoại, %d khớp tên, "
        "%d tạo mới, %d khách lẻ. Còn lại NULL: %d.",
        total_linked, phone_match, name_match, new_customer, walk_in, total_null_after,
    )
    return {
        "null_before": total_null_before,
        "null_after": total_null_after,
        "phone_match": phone_match,
        "name_match": name_match,
        "new_customer": new_customer,
        "walk_in": walk_in,
        "linked": total_linked,
    }

def ensure_schema(conn):
    """Apply any pending migrations."""
    cursor = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
    )
    if not cursor.fetchone():
        current_version = 0
    else:
        cursor = conn.execute("SELECT MAX(version) FROM schema_version")
        row = cursor.fetchone()
        current_version = row[0] if row[0] is not None else 0

    for version in sorted(MIGRATIONS.keys()):
        if version > current_version:
            conn.executescript(MIGRATIONS[version]["sql"])

            # Seed data if present
            seed = MIGRATIONS[version].get("seed")
            if seed:
                for name, category, base_price, cost, recipe_notes in seed:
                    conn.execute(
                        "INSERT OR IGNORE INTO products "
                        "(name, category, base_price, cost, recipe_notes) "
                        "VALUES (?, ?, ?, ?, ?)",
                        (name, category, base_price, cost, recipe_notes),
                    )

            # Run callable if present (for complex migrations)
            callable_fn = MIGRATIONS[version].get("callable")
            if callable_fn:
                callable_fn(conn)

            conn.execute(
                "INSERT INTO schema_version (version, description) VALUES (?, ?)",
                (version, MIGRATIONS[version]["description"]),
            )
    conn.commit()


__all__ = [
    '_normalize_accessory_name',
    '_guard_add_column',
    '_guard_drop_column',
    '_seed_expense_categories',
    '_seed_chart_of_accounts',
    '_ensure_staff_payable_sub_account',
    '_ensure_ap_vendor_sub_account',
    '_account_id_by_code',
    '_insert_journal_entry',
    '_backfill_expense_journal_entries',
    '_backfill_payment_transaction_journal_entries',
    '_backfill_delivered_order_journal_entries',
    '_backfill_journal_transaction_date',
    '_baseline_cost_for_product',
    '_backfill_order_items_cost_at_sale',
    '_strip_diacritics',
    '_normalize_phone',
    '_pick_most_common_name',
    '_order_year',
    '_recompute_customer_year_summary',
    '_repair_null_customer_links',
    'ensure_schema',
]
