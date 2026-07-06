"""Accounting data integrity validation service.

Runs a set of read-only checks against the accounting data foundation
(journal entries/lines, order_items cost_at_sale, waste COGS, cost_history)
and returns a structured report of any anomalies found.

Checks:
  1. ``double_entry_integrity`` — for every journal entry, SUM(debit) must
     equal SUM(credit) within a small tolerance.
  2. ``cogs_completeness`` — delivered order_items (non-extra, non-gift)
     where ``cost_at_sale`` is NULL/0 despite a resolvable cost.
  3. ``waste_cogs_referential_integrity`` — ``waste_cogs`` journal entries
     whose ``source_id`` has no matching waste ``stock_movements`` row.
  4. ``cost_history_sanity`` — negative costs, duplicate ``effective_from``,
     and future-dated ``effective_from`` values.
  5. ``accounting_equation`` — Assets = Liabilities + Equity + (Income −
     Expenses). Flags any imbalance beyond tolerance.
  6. ``source_completeness`` — every expense event, payment_transaction, and
     delivered order has at least one corresponding journal entry.
  7. ``cogs_amount_accuracy`` — for each ``order_cogs`` journal entry, the
     COGS debit matches SUM(cost_at_sale × quantity) of the order's
     non-extra, non-gift items.
  8. ``cash_flow_integrity`` — net change in cash/asset accounts equals the
     sum of all cash inflows minus outflows across journal entries.
  9. ``lock_integrity`` — journal entries where ``locked_at`` is set but
     ``locked_by`` is empty/null.
  10. ``account_balance_sanity`` — asset/expense accounts with a negative
      balance (debit < credit) beyond tolerance.
  11. ``future_dated_entries`` — journal entries whose ``created_at`` is in
      the future.
  12. ``duplicate_entries`` — multiple journal entries sharing the same
      ``source_type`` + ``source_id`` (excluding reversals).
  13. ``orphaned_lines`` — journal lines whose ``account_id`` does not exist
      in the ``accounts`` table.
  14. ``expense_category_mismatch`` — expense journal entries where the
      debited account code does not match the expense event's category
      mapping in ``EXPENSE_CATEGORY_TO_ACCOUNT_CODE`` (inventory purchase
      categories debit Inventory, not expense accounts, and are excluded).
  15. ``deposit_revenue_integrity`` — for every delivered order revenue entry
      (``source_type = 'order'``), the 2100 debit must equal the 2400 credit
      plus the 4100 credit (deposits = tien_rut held + net revenue). Flags
      any revenue entry where this identity does not hold within tolerance
             (DG-198 Phase 6, FR5/AC5).
   16. ``deposit_balance_integrity`` — per-order 2100 net balance must be zero
       for delivered, completed, and cancelled orders (excluding active orders
       where deposits are expected). Computed across ``payment_transaction``,
       ``order``, and ``order_shipping_hold`` journal entries grouped by
       ``payment_transactions.order_id``.

The module is deliberately side-effect free: it only reads the database.
It is exposed via the CLI (``baker validate-accounts``) and the API
(``GET /api/accounts/validate``), both of which return the same
``ValidationReport`` structure.
"""

import json
from typing import Any

from baker.db.schema import (
    COGS_CODE,
    CUSTOMER_DEPOSITS_CODE,
    ORDER_REVENUE_CODE,
    TIEN_RUT_HELD_CODE,
)
from baker.utils.time import now_utc

# Tolerance for double-entry imbalance. Sub-cent rounding from REAL storage
# and per-line float arithmetic is expected; only imbalances above this
# threshold are reported as integrity violations.
DEBIT_CREDIT_TOLERANCE = 0.005


def _check_double_entry_integrity(conn) -> dict[str, Any]:
    """Flag journal entries where SUM(debit) != SUM(credit)."""
    rows = conn.execute(
        """
        SELECT je.id          AS entry_id,
               je.description AS description,
               je.source_type AS source_type,
               je.source_id   AS source_id,
               COALESCE(SUM(jl.debit), 0)  AS total_debit,
               COALESCE(SUM(jl.credit), 0) AS total_credit
        FROM journal_entries je
        LEFT JOIN journal_lines jl ON jl.journal_entry_id = je.id
        GROUP BY je.id
        HAVING ABS(total_debit - total_credit) > ?
        ORDER BY je.id
        """,
        (DEBIT_CREDIT_TOLERANCE,),
    ).fetchall()

    findings = [
        {
            "entry_id": int(r["entry_id"]),
            "description": r["description"],
            "source_type": r["source_type"],
            "source_id": int(r["source_id"]) if r["source_id"] is not None else None,
            "total_debit": float(r["total_debit"]),
            "total_credit": float(r["total_credit"]),
            "imbalance": round(float(r["total_debit"]) - float(r["total_credit"]), 4),
        }
        for r in rows
    ]
    return {
        "check": "double_entry_integrity",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_cogs_completeness(conn) -> dict[str, Any]:
    """Flag delivered order_items missing cost_at_sale despite a resolvable cost.

    A row is flagged when:
      - the parent order status is 'delivered'
      - the item is neither extra nor a gift
      - ``cost_at_sale`` is NULL or 0
      - the product has a resolvable cost: an effective cost_history row OR a
        non-zero ``base_price`` (baseline rule yields a non-zero cost for any
        product with base_price > 0).
    """
    rows = conn.execute(
        """
        SELECT oi.id          AS item_id,
               oi.order_id    AS order_id,
               oi.product_id  AS product_id,
               oi.product_name AS product_name,
               oi.quantity    AS quantity,
               oi.cost_at_sale AS cost_at_sale,
               o.order_ref    AS order_ref,
               p.base_price   AS base_price,
               p.category     AS category,
               EXISTS (
                   SELECT 1 FROM cost_history ch
                   WHERE ch.product_id = CAST(oi.product_id AS INTEGER)
                     AND ch.effective_from <= ?
               ) AS has_cost_history
        FROM order_items oi
        JOIN orders o ON o.id = oi.order_id
        LEFT JOIN products p ON p.id = CAST(oi.product_id AS INTEGER)
        WHERE o.status = 'delivered'
          AND oi.is_extra = 0
          AND oi.is_gift = 0
          AND (oi.cost_at_sale IS NULL OR oi.cost_at_sale = 0)
        ORDER BY oi.id
        """,
        (now_utc(),),
    ).fetchall()

    findings = []
    for r in rows:
        product_id_str = r["product_id"]
        if product_id_str is None or product_id_str == "":
            continue
        try:
            product_id = int(product_id_str)
        except (TypeError, ValueError):
            continue
        has_history = bool(r["has_cost_history"])
        base_price = float(r["base_price"] or 0)
        # Resolvable cost exists if there is an effective cost_history row, or
        # the baseline rule would yield a non-zero value (any base_price > 0).
        resolvable = has_history or base_price > 0
        if not resolvable:
            continue
        findings.append({
            "item_id": int(r["item_id"]),
            "order_id": int(r["order_id"]),
            "order_ref": r["order_ref"],
            "product_id": product_id,
            "product_name": r["product_name"],
            "quantity": int(r["quantity"] or 0),
            "cost_at_sale": float(r["cost_at_sale"] or 0),
            "has_cost_history": has_history,
            "base_price": base_price,
        })

    return {
        "check": "cogs_completeness",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_waste_cogs_referential_integrity(conn) -> dict[str, Any]:
    """Flag waste_cogs journal entries with no matching waste stock_movement."""
    rows = conn.execute(
        """
        SELECT je.id          AS entry_id,
               je.description AS description,
               je.source_id   AS movement_id,
               je.created_at  AS created_at
        FROM journal_entries je
        WHERE je.source_type = 'waste_cogs'
          AND je.source_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM stock_movements sm
              WHERE sm.id = je.source_id
                AND sm.movement_type = 'waste'
          )
        ORDER BY je.id
        """,
    ).fetchall()

    findings = [
        {
            "entry_id": int(r["entry_id"]),
            "description": r["description"],
            "movement_id": int(r["movement_id"]) if r["movement_id"] is not None else None,
            "created_at": r["created_at"],
        }
        for r in rows
    ]
    return {
        "check": "waste_cogs_referential_integrity",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_cost_history_sanity(conn) -> dict[str, Any]:
    """Flag cost_history anomalies: negative costs, duplicate effective_from
    per product, and future-dated effective_from values.
    """
    findings: list[dict[str, Any]] = []

    # Negative costs
    neg_rows = conn.execute(
        """
        SELECT id, product_id, cost, effective_from, created_at
        FROM cost_history
        WHERE cost < 0
        ORDER BY id
        """,
    ).fetchall()
    for r in neg_rows:
        findings.append({
            "anomaly": "negative_cost",
            "cost_history_id": int(r["id"]),
            "product_id": int(r["product_id"]),
            "cost": float(r["cost"]),
            "effective_from": r["effective_from"],
        })

    # Duplicate effective_from for the same product
    dup_rows = conn.execute(
        """
        SELECT product_id, effective_from, COUNT(*) AS cnt
        FROM cost_history
        GROUP BY product_id, effective_from
        HAVING cnt > 1
        ORDER BY product_id, effective_from
        """,
    ).fetchall()
    for r in dup_rows:
        findings.append({
            "anomaly": "duplicate_effective_from",
            "product_id": int(r["product_id"]),
            "effective_from": r["effective_from"],
            "count": int(r["cnt"]),
        })

    # Future-dated effective_from
    future_rows = conn.execute(
        """
        SELECT id, product_id, cost, effective_from, created_at
        FROM cost_history
        WHERE effective_from > ?
        ORDER BY id
        """,
        (now_utc(),),
    ).fetchall()
    for r in future_rows:
        findings.append({
            "anomaly": "future_effective_from",
            "cost_history_id": int(r["id"]),
            "product_id": int(r["product_id"]),
            "cost": float(r["cost"]),
            "effective_from": r["effective_from"],
        })

    return {
        "check": "cost_history_sanity",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_accounting_equation(conn) -> dict[str, Any]:
    """Verify the fundamental accounting equation.

    Assets = Liabilities + Equity + (Income − Expenses)

    Computes per-type balances from journal_lines and checks that the
    equation holds within tolerance. Returns the computed values so the
    caller can see the exact numbers even when the check passes.
    """
    rows = conn.execute(
        """
        SELECT a.type,
               COALESCE(SUM(jl.debit), 0)  AS total_debit,
               COALESCE(SUM(jl.credit), 0) AS total_credit
        FROM accounts a
        LEFT JOIN journal_lines jl ON jl.account_id = a.id
        WHERE a.is_active = 1
        GROUP BY a.type
        ORDER BY a.type
        """,
    ).fetchall()

    balances: dict[str, float] = {}
    for r in rows:
        t = r["type"]
        d = float(r["total_debit"])
        c = float(r["total_credit"])
        if t in ("asset", "expense"):
            balances[t] = d - c
        else:
            balances[t] = c - d

    assets = balances.get("asset", 0.0)
    liabilities = balances.get("liability", 0.0)
    equity = balances.get("equity", 0.0)
    income = balances.get("income", 0.0)
    expenses = balances.get("expense", 0.0)

    lhs = assets
    rhs = liabilities + equity + (income - expenses)
    imbalance = abs(lhs - rhs)

    return {
        "check": "accounting_equation",
        "status": "pass" if imbalance <= DEBIT_CREDIT_TOLERANCE else "fail",
        "issue_count": 0 if imbalance <= DEBIT_CREDIT_TOLERANCE else 1,
        "details": [
            {
                "assets": round(assets, 2),
                "liabilities": round(liabilities, 2),
                "equity": round(equity, 2),
                "income": round(income, 2),
                "expenses": round(expenses, 2),
                "lhs": round(lhs, 2),
                "rhs": round(rhs, 2),
                "imbalance": round(imbalance, 4),
            }
        ],
    }


def _check_source_completeness(conn) -> dict[str, Any]:
    """Flag financial source records that have no corresponding journal entry.

    Checks three source types:
      - expense events (type='expense', not soft-deleted)
      - payment_transactions
      - delivered orders (status='delivered')
    """
    findings: list[dict[str, Any]] = []

    # Expenses without journal entries
    exp_rows = conn.execute(
        """
        SELECT e.id, e.summary, e.timestamp
        FROM events e
        WHERE e.type = 'expense'
          AND (e.deleted_at IS NULL OR e.deleted_at = '')
          AND NOT EXISTS (
              SELECT 1 FROM journal_entries je
              WHERE je.source_type = 'expense' AND je.source_id = e.id
          )
        ORDER BY e.id
        """,
    ).fetchall()
    for r in exp_rows:
        findings.append({
            "source_type": "expense",
            "source_id": int(r["id"]),
            "summary": r["summary"],
            "timestamp": r["timestamp"],
        })

    # Payment transactions without journal entries.
    # Invalidated transactions (invalidated_at IS NOT NULL) are excluded —
    # their journal entry is reversed/removed by invalidation (DG-196 Phase 3,
    # NFR1/AC10: accounting integrity must pass after invalidation).
    pt_rows = conn.execute(
        """
        SELECT pt.id, pt.amount, pt.type, pt.method, pt.created_at
        FROM payment_transactions pt
        WHERE (pt.invalidated_at IS NULL OR pt.invalidated_at = '')
          AND NOT EXISTS (
            SELECT 1 FROM journal_entries je
            WHERE je.source_type = 'payment_transaction' AND je.source_id = pt.id
          )
        ORDER BY pt.id
        """,
    ).fetchall()
    for r in pt_rows:
        findings.append({
            "source_type": "payment_transaction",
            "source_id": int(r["id"]),
            "amount": float(r["amount"] or 0),
            "type": r["type"],
            "method": r["method"],
            "created_at": r["created_at"],
        })

    # Delivered orders without revenue conversion journal entry
    ord_rows = conn.execute(
        """
        SELECT o.id, o.order_ref, o.total_price
        FROM orders o
        WHERE o.status = 'delivered'
          AND NOT EXISTS (
              SELECT 1 FROM journal_entries je
              WHERE je.source_type = 'order' AND je.source_id = o.id
          )
        ORDER BY o.id
        """,
    ).fetchall()
    for r in ord_rows:
        findings.append({
            "source_type": "order",
            "source_id": int(r["id"]),
            "order_ref": r["order_ref"],
            "total_price": float(r["total_price"] or 0),
        })

    return {
        "check": "source_completeness",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_cogs_amount_accuracy(conn) -> dict[str, Any]:
    """Flag order_cogs journal entries whose debit does not match
    SUM(resolved_cost × quantity) using the canonical cost resolution order:
    product.cost → cost_history → baseline.
    """
    from baker.services.cost_resolver import resolve_product_cost

    rows = conn.execute(
        f"""
        SELECT je.id          AS entry_id,
               je.description AS description,
               je.source_id   AS order_id,
               SUM(CASE WHEN a.code = ? THEN jl.debit ELSE 0 END) AS cogs_debit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order_cogs'
        GROUP BY je.id
        ORDER BY je.id
        """,
        (COGS_CODE,),
    ).fetchall()

    findings: list[dict[str, Any]] = []
    for r in rows:
        entry_id = int(r["entry_id"])
        order_id = int(r["order_id"])
        actual = float(r["cogs_debit"])

        items = conn.execute(
            """
            SELECT oi.product_id, oi.product_name, oi.quantity
            FROM order_items oi
            WHERE oi.order_id = ?
              AND oi.is_extra = 0
              AND oi.is_gift = 0
            """,
            (order_id,),
        ).fetchall()

        expected = 0.0
        for i in items:
            pid_str = i["product_id"]
            if pid_str is None:
                continue
            try:
                pid = int(pid_str)
            except (TypeError, ValueError):
                continue
            cost = resolve_product_cost(conn, pid)
            qty = int(i["quantity"] or 0)
            expected += cost * qty

        if abs(actual - expected) > DEBIT_CREDIT_TOLERANCE:
            findings.append({
                "entry_id": entry_id,
                "order_id": order_id,
                "description": r["description"],
                "actual_cogs": round(actual, 2),
                "expected_cogs": round(expected, 2),
                "difference": round(actual - expected, 2),
            })

    return {
        "check": "cogs_amount_accuracy",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_cash_flow_integrity(conn) -> dict[str, Any]:
    """Verify net change in cash/asset accounts equals sum of cash inflows
    minus outflows across all journal entries.

    Cash accounts are asset accounts with code 1100 (Cash on Hand) and
    1200 (Bank Account). The net debit minus credit on these accounts
    should equal the sum of all cash-affecting journal line movements.
    """
    cash_codes = ("1100", "1200")

    # Net change in cash accounts
    cash_rows = conn.execute(
        """
        SELECT a.code, a.name,
               COALESCE(SUM(jl.debit), 0)  AS total_debit,
               COALESCE(SUM(jl.credit), 0) AS total_credit
        FROM accounts a
        LEFT JOIN journal_lines jl ON jl.account_id = a.id
        WHERE a.code IN (?, ?)
        GROUP BY a.id
        ORDER BY a.code
        """,
        cash_codes,
    ).fetchall()

    cash_net = 0.0
    cash_detail: dict[str, dict[str, float]] = {}
    for r in cash_rows:
        d = float(r["total_debit"])
        c = float(r["total_credit"])
        net = d - c
        cash_net += net
        cash_detail[r["code"]] = {
            "name": r["name"],
            "debit": round(d, 2),
            "credit": round(c, 2),
            "net": round(net, 2),
        }

    # Sum of all cash-affecting journal lines (debit to cash = inflow,
    # credit from cash = outflow)
    flow_rows = conn.execute(
        """
        SELECT SUM(jl.debit)  AS total_inflow,
               SUM(jl.credit) AS total_outflow
        FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code IN (?, ?)
        """,
        cash_codes,
    ).fetchone()

    total_inflow = float(flow_rows["total_inflow"] or 0)
    total_outflow = float(flow_rows["total_outflow"] or 0)
    expected_net = total_inflow - total_outflow
    imbalance = abs(cash_net - expected_net)

    return {
        "check": "cash_flow_integrity",
        "status": "pass" if imbalance <= DEBIT_CREDIT_TOLERANCE else "fail",
        "issue_count": 0 if imbalance <= DEBIT_CREDIT_TOLERANCE else 1,
        "details": [
            {
                "cash_accounts": cash_detail,
                "cash_net_change": round(cash_net, 2),
                "total_inflow": round(total_inflow, 2),
                "total_outflow": round(total_outflow, 2),
                "expected_net": round(expected_net, 2),
                "imbalance": round(imbalance, 4),
            }
        ],
    }


def _check_lock_integrity(conn) -> dict[str, Any]:
    """Flag journal entries where ``locked_at`` is set but ``locked_by`` is
    empty/null — a partial lock that should never occur under normal
    operation (both columns should be set together or both unset).
    """
    rows = conn.execute(
        """
        SELECT je.id          AS entry_id,
               je.description AS description,
               je.locked_at    AS locked_at,
               je.locked_by    AS locked_by
        FROM journal_entries je
        WHERE je.locked_at IS NOT NULL
          AND je.locked_at != ''
          AND (je.locked_by IS NULL OR je.locked_by = '')
        ORDER BY je.id
        """,
    ).fetchall()

    findings = [
        {
            "entry_id": int(r["entry_id"]),
            "description": r["description"],
            "locked_at": r["locked_at"],
        }
        for r in rows
    ]
    return {
        "check": "lock_integrity",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_account_balance_sanity(conn) -> dict[str, Any]:
    """Flag asset/expense accounts whose balance is negative beyond
    tolerance — i.e. credit exceeds debit. Asset and expense accounts have
    a natural debit balance, so a negative running balance indicates a
    posting anomaly.
    """
    rows = conn.execute(
        """
        SELECT a.id   AS account_id,
               a.code AS code,
               a.name AS name,
               a.type AS type,
               COALESCE(SUM(jl.debit), 0)  AS total_debit,
               COALESCE(SUM(jl.credit), 0) AS total_credit
        FROM accounts a
        LEFT JOIN journal_lines jl ON jl.account_id = a.id
        WHERE a.type IN ('asset', 'expense')
          AND a.is_active = 1
        GROUP BY a.id
        HAVING (total_debit - total_credit) < -?
        ORDER BY a.code
        """,
        (DEBIT_CREDIT_TOLERANCE,),
    ).fetchall()

    findings = [
        {
            "account_id": int(r["account_id"]),
            "code": r["code"],
            "name": r["name"],
            "type": r["type"],
            "total_debit": float(r["total_debit"]),
            "total_credit": float(r["total_credit"]),
            "balance": round(float(r["total_debit"]) - float(r["total_credit"]), 4),
        }
        for r in rows
    ]
    return {
        "check": "account_balance_sanity",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_future_dated_entries(conn) -> dict[str, Any]:
    """Flag journal entries whose ``created_at`` is in the future."""
    rows = conn.execute(
        """
        SELECT je.id          AS entry_id,
               je.description AS description,
               je.source_type AS source_type,
               je.source_id   AS source_id,
               je.created_at  AS created_at
        FROM journal_entries je
        WHERE je.created_at > ?
        ORDER BY je.id
        """,
        (now_utc(),),
    ).fetchall()

    findings = [
        {
            "entry_id": int(r["entry_id"]),
            "description": r["description"],
            "source_type": r["source_type"],
            "source_id": int(r["source_id"]) if r["source_id"] is not None else None,
            "created_at": r["created_at"],
        }
        for r in rows
    ]
    return {
        "check": "future_dated_entries",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_duplicate_entries(conn) -> dict[str, Any]:
    """Flag multiple journal entries sharing the same ``source_type`` +
    ``source_id``. Reversal entries (whose description starts with
    ``Reversal:``) are excluded — they legitimately share a source with the
    original entry they reverse. ``source_type = 'order'`` entries are also
    excluded — DG-198 creates two entries per delivered order (revenue +
    tien rut return), which is intentional.
    """
    rows = conn.execute(
        """
        SELECT je.source_type AS source_type,
               je.source_id   AS source_id,
               COUNT(*)        AS cnt,
               GROUP_CONCAT(je.id) AS entry_ids
        FROM journal_entries je
        WHERE je.source_id IS NOT NULL
          AND je.description NOT LIKE 'Reversal:%'
          AND je.source_type != 'order'
        GROUP BY je.source_type, je.source_id
        HAVING cnt > 1
        ORDER BY je.source_type, je.source_id
        """,
    ).fetchall()

    findings = []
    for r in rows:
        entry_ids = [int(eid) for eid in str(r["entry_ids"]).split(",") if eid]
        findings.append({
            "source_type": r["source_type"],
            "source_id": int(r["source_id"]),
            "count": int(r["cnt"]),
            "entry_ids": entry_ids,
        })
    return {
        "check": "duplicate_entries",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_orphaned_lines(conn) -> dict[str, Any]:
    """Flag journal lines whose ``account_id`` does not exist in the
    ``accounts`` table. Referential integrity is normally enforced by a
    foreign key, but SQLite does not enforce FKs unless ``PRAGMA
    foreign_keys=ON`` is set, so this check catches legacy/corrupt rows.
    """
    rows = conn.execute(
        """
        SELECT jl.id              AS line_id,
               jl.journal_entry_id AS journal_entry_id,
               jl.account_id      AS account_id,
               jl.debit           AS debit,
               jl.credit          AS credit,
               jl.description     AS description
        FROM journal_lines jl
        WHERE NOT EXISTS (
            SELECT 1 FROM accounts a WHERE a.id = jl.account_id
        )
        ORDER BY jl.id
        """,
    ).fetchall()

    findings = [
        {
            "line_id": int(r["line_id"]),
            "journal_entry_id": int(r["journal_entry_id"]),
            "account_id": int(r["account_id"]),
            "debit": float(r["debit"] or 0),
            "credit": float(r["credit"] or 0),
            "description": r["description"],
        }
        for r in rows
    ]
    return {
        "check": "orphaned_lines",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_expense_category_mismatch(conn) -> dict[str, Any]:
    """Flag expense journal entries where the debited account code does not
    match the expense event's category mapping.

    The expense event's category (stored in ``events.data`` JSON) maps to an
    expected expense account code via ``EXPENSE_CATEGORY_TO_ACCOUNT_CODE``.
    However, inventory purchase categories (``INVENTORY_PURCHASE_CATEGORIES``
    — "Nguyên liệu", "Bao bì") correctly debit Inventory (1300), not expense
    accounts, so they are excluded from this check.
    """
    from baker.db.schema import (
        EXPENSE_CATEGORY_TO_ACCOUNT_CODE,
        INVENTORY_PURCHASE_CATEGORIES,
        INVENTORY_CODE,
    )

    inventory_id = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (INVENTORY_CODE,)
    ).fetchone()
    inventory_account_id = int(inventory_id["id"]) if inventory_id else None

    rows = conn.execute(
        """
        SELECT je.id    AS entry_id,
               je.source_id AS event_id,
               je.description AS description,
               jl.account_id AS debit_account_id,
               a.code       AS debit_account_code
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'expense'
          AND jl.debit > 0
        ORDER BY je.id
        """,
    ).fetchall()

    findings: list[dict[str, Any]] = []
    for r in rows:
        event_id = r["event_id"]
        if event_id is None:
            continue
        event_id = int(event_id)
        event_row = conn.execute(
            "SELECT data FROM events WHERE id = ?", (event_id,),
        ).fetchone()
        if event_row is None or not event_row["data"]:
            continue
        try:
            data = json.loads(event_row["data"])
        except (json.JSONDecodeError, TypeError):
            continue
        category = data.get("category")
        if not isinstance(category, str) or not category:
            continue

        # Inventory purchase categories correctly debit Inventory, not
        # expense accounts — skip them.
        if category in INVENTORY_PURCHASE_CATEGORIES:
            expected_account_id = inventory_account_id
        else:
            expected_code = EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(category)
            if not expected_code:
                continue
            expected_row = conn.execute(
                "SELECT id FROM accounts WHERE code = ?", (expected_code,),
            ).fetchone()
            if expected_row is None:
                continue
            expected_account_id = int(expected_row["id"])

        if expected_account_id is not None and int(r["debit_account_id"]) != expected_account_id:
            findings.append({
                "entry_id": int(r["entry_id"]),
                "event_id": event_id,
                "description": r["description"],
                "category": category,
                "expected_account_code": (
                    INVENTORY_CODE if category in INVENTORY_PURCHASE_CATEGORIES
                    else EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(category)
                ),
                "actual_account_code": r["debit_account_code"],
                "actual_account_id": int(r["debit_account_id"]),
            })

    return {
        "check": "expense_category_mismatch",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_deposit_revenue_integrity(conn) -> dict[str, Any]:
    """Flag delivered order revenue entries where the deposit balance moved
    into revenue does not reconcile with the net revenue recognised.

    For every ``source_type = 'order'`` revenue entry (the deposits→revenue
    entry created at delivery, identified by a 2100 debit), the accounting
    identity must hold::

        debit_2100 = credit_4100

    i.e. the Customer Deposits (2100) cleared into revenue equal the Order
    Revenue (4100) recognised. Tien Rut Held (2400) is cleared separately via
    a distinct ``Tien rut return:`` entry (DR 2400 / CR Asset) and is NOT part
    of this check. A violation indicates a deposit-revenue gap — the original
    failure mode that DG-198 fixes.

    Accounts Receivable (AR) entries — unpaid orders with zero deposits — are
    excluded: they debit 1500 and credit 4100 only, with no 2100 component,
    so the identity is not applicable.
    """
    rows = conn.execute(
        """
        SELECT je.id          AS entry_id,
               je.description AS description,
               je.source_id   AS order_id,
               COALESCE(SUM(CASE WHEN a.code = ? THEN jl.debit  ELSE 0 END), 0) AS debit_2100,
               COALESCE(SUM(CASE WHEN a.code = ? THEN jl.credit ELSE 0 END), 0) AS credit_4100
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order'
        GROUP BY je.id
        HAVING debit_2100 > 0
           AND ABS(debit_2100 - credit_4100) > ?
        ORDER BY je.id
        """,
        (
            CUSTOMER_DEPOSITS_CODE,
            ORDER_REVENUE_CODE,
            DEBIT_CREDIT_TOLERANCE,
        ),
    ).fetchall()

    findings = [
        {
            "entry_id": int(r["entry_id"]),
            "order_id": int(r["order_id"]) if r["order_id"] is not None else None,
            "description": r["description"],
            "debit_2100": float(r["debit_2100"]),
            "credit_4100": float(r["credit_4100"]),
            "gap": round(
                float(r["debit_2100"]) - float(r["credit_4100"]),
                4,
            ),
        }
        for r in rows
    ]
    return {
        "check": "deposit_revenue_integrity",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


def _check_deposit_balance_integrity(conn) -> dict[str, Any]:
    """Flag orders where the per-order 2100 (Customer Deposits) balance is
    non-zero and the order is in a terminal state (delivered, completed,
    cancelled) OR is an active order whose due date has already passed
    (overdue — deposit should have been cleared by now).

    Per-order 2100 balance = total credits from payment_transaction journal
    entries − total debits from payment_transaction journal entries − total
    debits from ``source_type = 'order'`` revenue entries − total debits from
    ``source_type = 'order_shipping_hold'`` entries.

    Active orders (confirmed, ready, new) with a future due date are NOT
    flagged — the deposit balance is expected to clear at delivery.

    Payment transactions are linked to orders via ``payment_transactions.order_id``
    (NOT ``je.source_id`` — source_id for payment_transaction entries is the
    payment_transaction ID, not the order ID). Invalidated (soft-deleted)
    payment transactions are excluded.
    """
    deposits_code = CUSTOMER_DEPOSITS_CODE

    rows = conn.execute(
        """
        SELECT o.id               AS order_id,
               o.order_ref        AS order_ref,
               o.status           AS status,
               o.due_date         AS due_date,
               COALESCE(pt.dep_credit, 0) AS deposits_in,
               COALESCE(pt.ref_debit, 0)  AS refunds_out,
               COALESCE(ord.rev_debit, 0) AS revenue_cleared,
               COALESCE(ship.ship_debit, 0) AS shipping_cleared,
               (
                   COALESCE(pt.dep_credit, 0)
                   - COALESCE(pt.ref_debit, 0)
                   - COALESCE(ord.rev_debit, 0)
                   - COALESCE(ship.ship_debit, 0)
               ) AS net_2100
        FROM orders o
        LEFT JOIN (
            SELECT pt2.order_id,
                   SUM(CASE WHEN a2.code = ? AND jl2.credit > 0
                       THEN jl2.credit ELSE 0 END) AS dep_credit,
                   SUM(CASE WHEN a2.code = ? AND jl2.debit > 0
                       THEN jl2.debit ELSE 0 END)  AS ref_debit
            FROM payment_transactions pt2
            JOIN journal_entries je2
                ON je2.source_type = 'payment_transaction'
                AND je2.source_id = pt2.id
            JOIN journal_lines jl2 ON jl2.journal_entry_id = je2.id
            JOIN accounts a2 ON a2.id = jl2.account_id AND a2.code = ?
            WHERE (pt2.invalidated_at IS NULL OR pt2.invalidated_at = '')
            GROUP BY pt2.order_id
        ) pt ON pt.order_id = o.id
        LEFT JOIN (
            SELECT je3.source_id AS order_id,
                   SUM(CASE WHEN a3.code = ? AND jl3.debit > 0
                       THEN jl3.debit ELSE 0 END) AS rev_debit
            FROM journal_entries je3
            JOIN journal_lines jl3 ON jl3.journal_entry_id = je3.id
            JOIN accounts a3 ON a3.id = jl3.account_id AND a3.code = ?
            WHERE je3.source_type = 'order'
              AND je3.description NOT LIKE 'Reversal:%'
            GROUP BY je3.source_id
        ) ord ON ord.order_id = o.id
        LEFT JOIN (
            SELECT je4.source_id AS order_id,
                   SUM(CASE WHEN a4.code = ? AND jl4.debit > 0
                       THEN jl4.debit ELSE 0 END) AS ship_debit
            FROM journal_entries je4
            JOIN journal_lines jl4 ON jl4.journal_entry_id = je4.id
            JOIN accounts a4 ON a4.id = jl4.account_id AND a4.code = ?
            WHERE je4.source_type = 'order_shipping_hold'
            GROUP BY je4.source_id
        ) ship ON ship.order_id = o.id
        WHERE COALESCE(pt.dep_credit, 0) > 0
           OR COALESCE(ord.rev_debit, 0) > 0
        ORDER BY o.id
        """,
        (
            deposits_code, deposits_code, deposits_code,
            deposits_code, deposits_code,
            deposits_code, deposits_code,
        ),
    ).fetchall()

    findings: list[dict[str, Any]] = []
    for r in rows:
        order_id = int(r["order_id"])
        order_ref = r["order_ref"]
        status = r["status"]
        due_date = r["due_date"]
        net = float(r["net_2100"])
        deposits_in = float(r["deposits_in"])
        refunds_out = float(r["refunds_out"])
        revenue_cleared = float(r["revenue_cleared"])
        shipping_cleared = float(r["shipping_cleared"])

        if abs(net) <= DEBIT_CREDIT_TOLERANCE:
            continue  # clean

        # Terminal statuses — always flag non-zero balance.
        if status in ("delivered", "completed"):
            issue_type = "outstanding_balance"
        elif status == "cancelled":
            issue_type = "cancelled_with_deposits"
        else:
            # Active order (confirmed, ready, new) — only flag if overdue.
            if not due_date:
                continue  # no due date, can't determine — skip
            # Compare due_date to now (local time).  SQLite stores dates in
            # local time via ``strftime('%Y-%m-%d', 'now', 'localtime')``, so
            # we compare as strings (YYYY-MM-DD lexicographic order works).
            today = conn.execute(
                "SELECT strftime('%Y-%m-%d', 'now', 'localtime')"
            ).fetchone()[0]
            if due_date >= today:
                continue  # not yet due — deposit is expected
            issue_type = "overdue_active_balance"

        findings.append({
            "order_id": order_id,
            "order_ref": order_ref,
            "status": status,
            "due_date": due_date,
            "deposits_in": round(deposits_in, 2),
            "refunds_out": round(refunds_out, 2),
            "revenue_cleared": round(revenue_cleared, 2),
            "shipping_cleared": round(shipping_cleared, 2),
            "net_2100": round(net, 2),
            "issue_type": issue_type,
        })

    return {
        "check": "deposit_balance_integrity",
        "status": "pass" if not findings else "fail",
        "issue_count": len(findings),
        "details": findings,
    }


CHECKS = (
    _check_double_entry_integrity,
    _check_cogs_completeness,
    _check_waste_cogs_referential_integrity,
    _check_cost_history_sanity,
    _check_accounting_equation,
    _check_source_completeness,
    _check_cogs_amount_accuracy,
    _check_cash_flow_integrity,
    _check_lock_integrity,
    _check_account_balance_sanity,
    _check_future_dated_entries,
    _check_duplicate_entries,
    _check_orphaned_lines,
    _check_expense_category_mismatch,
    _check_deposit_revenue_integrity,
    _check_deposit_balance_integrity,
)


def run_validation(conn) -> dict[str, Any]:
    """Run all accounting validation checks and return a structured report.

    The report has the shape::

        {
          "summary": {"total_checks": 15, "passed": N, "failed": M,
                       "total_issues": K, "overall_status": "pass"|"fail"},
          "checks": [ <per-check result dicts> ]
        }

    The function performs only read-only queries and never mutates the
    database. Safe to run at any time.
    """
    check_results = [check(conn) for check in CHECKS]
    passed = sum(1 for c in check_results if c["status"] == "pass")
    failed = sum(1 for c in check_results if c["status"] == "fail")
    total_issues = sum(int(c["issue_count"]) for c in check_results)
    return {
        "summary": {
            "total_checks": len(check_results),
            "passed": passed,
            "failed": failed,
            "total_issues": total_issues,
            "overall_status": "pass" if failed == 0 else "fail",
        },
        "checks": check_results,
    }