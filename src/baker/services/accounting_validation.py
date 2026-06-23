"""Accounting data integrity validation service.

Runs a set of read-only checks against the accounting data foundation
(journal entries/lines, order_items cost_at_sale, waste COGS, cost_history)
and returns a structured report of any anomalies found.

Checks (FR6 / AC6):
  1. ``double_entry_integrity`` — for every journal entry, SUM(debit) must
    equal SUM(credit) within a small tolerance. Entries whose absolute
    difference exceeds the tolerance are flagged.
  2. ``cogs_completeness`` — delivered order_items (non-extra, non-gift)
    where ``cost_at_sale`` is NULL or 0 even though the product has a
    resolvable cost (cost_history record or non-zero baseline). Flags rows
    that should have a cost but do not.
  3. ``waste_cogs_referential_integrity`` — ``waste_cogs`` journal entries
    whose ``source_id`` does not match a ``stock_movements`` row with
    ``movement_type = 'waste'``. Flags orphaned/incorrect references.
  4. ``cost_history_sanity`` — negative costs, duplicate
    ``effective_from`` dates for the same product, and future-dated
    ``effective_from`` values.

The module is deliberately side-effect free: it only reads the database.
It is exposed via the CLI (``baker validate-accounts``) and the API
(``GET /api/accounts/validate``), both of which return the same
``ValidationReport`` structure.
"""

from typing import Any

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
                     AND ch.effective_from
                       <= strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')
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
        WHERE effective_from > strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')
        ORDER BY id
        """,
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


CHECKS = (
    _check_double_entry_integrity,
    _check_cogs_completeness,
    _check_waste_cogs_referential_integrity,
    _check_cost_history_sanity,
)


def run_validation(conn) -> dict[str, Any]:
    """Run all accounting validation checks and return a structured report.

    The report has the shape::

        {
          "summary": {"total_checks": 4, "passed": N, "failed": M,
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