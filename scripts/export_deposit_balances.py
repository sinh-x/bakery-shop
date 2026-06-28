#!/usr/bin/env python3
"""Export ONLY orders with non-zero deposit balance (outstanding 2100)."""
import sqlite3, csv
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "baker.db"
OUT_PATH = Path(__file__).resolve().parent.parent / "deposit_balance_orders.csv"


def main():
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute(
        """
        SELECT o.id, o.order_ref, o.public_order_code, o.customer_name,
               o.created_at, o.due_date, o.status, o.total_price, o.delivery_type,
               COALESCE(pt.dep_credit, 0) AS deposits_in,
               COALESCE(pt.ref_debit, 0)  AS refunds_out,
               COALESCE(ord.rev_debit, 0) AS revenue_cleared,
               COALESCE(ship.ship_debit, 0) AS shipping_cleared,
               (
                   COALESCE(pt.dep_credit, 0)
                   - COALESCE(pt.ref_debit, 0)
                   - COALESCE(ord.rev_debit, 0)
                   - COALESCE(ship.ship_debit, 0)
               ) AS net_2100,
               COALESCE(pt.tien_rut_dep, 0)  AS tien_rut_dep,
               COALESCE(tien.tien_rut_ret, 0) AS tien_rut_ret
        FROM orders o
        LEFT JOIN (
            SELECT pt.order_id,
                   SUM(CASE WHEN a.code = '2100' AND jl.credit > 0
                       THEN jl.credit ELSE 0 END) AS dep_credit,
                   SUM(CASE WHEN a.code = '2100' AND jl.debit > 0
                       THEN jl.debit ELSE 0 END)  AS ref_debit,
                   SUM(CASE WHEN a.code = '2400' AND jl.credit > 0
                       THEN jl.credit ELSE 0 END) AS tien_rut_dep
            FROM payment_transactions pt
            JOIN journal_entries je
                ON je.source_type = 'payment_transaction' AND je.source_id = pt.id
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id
            WHERE pt.invalidated_at IS NULL AND a.code IN ('2100', '2400')
            GROUP BY pt.order_id
        ) pt ON pt.order_id = o.id
        LEFT JOIN (
            SELECT je.source_id AS order_id,
                   SUM(CASE WHEN a.code = '2100' AND jl.debit > 0
                       THEN jl.debit ELSE 0 END) AS rev_debit
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id AND a.code = '2100'
            WHERE je.source_type = 'order'
              AND je.description NOT LIKE 'Reversal:%%'
            GROUP BY je.source_id
        ) ord ON ord.order_id = o.id
        LEFT JOIN (
            SELECT je.source_id AS order_id,
                   SUM(CASE WHEN a.code = '2100' AND jl.debit > 0
                       THEN jl.debit ELSE 0 END) AS ship_debit
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id AND a.code = '2100'
            WHERE je.source_type = 'order_shipping_hold'
            GROUP BY je.source_id
        ) ship ON ship.order_id = o.id
        LEFT JOIN (
            SELECT je.source_id AS order_id,
                   SUM(CASE WHEN a.code = '2400' AND jl.debit > 0
                       THEN jl.debit ELSE 0 END) AS tien_rut_ret
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id AND a.code = '2400'
            WHERE je.source_type = 'order'
              AND je.description LIKE 'Tien rut return:%%'
            GROUP BY je.source_id
        ) tien ON tien.order_id = o.id
        WHERE COALESCE(pt.dep_credit, 0) > 0
           OR COALESCE(ord.rev_debit, 0) > 0
        ORDER BY
            ABS(
                COALESCE(pt.dep_credit, 0) - COALESCE(pt.ref_debit, 0)
                - COALESCE(ord.rev_debit, 0) - COALESCE(ship.ship_debit, 0)
            ) DESC
        """
    )
    rows = cur.fetchall()
    # Filter to only non-zero balances
    rows = [r for r in rows if abs(r["net_2100"] or 0) > 0.005]

    with open(OUT_PATH, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "Order#", "Order Number", "Code", "Customer",
                "Created", "Due Date", "Status", "Delivery",
                "Total Price",
                "Deposits In", "Refunds Out",
                "Revenue Cleared", "Shipping Cleared",
                "Net 2100", "Issue",
                "Tien Rut Dep", "Tien Rut Ret",
            ]
        )
        for r in rows:
            net = round(r["net_2100"] or 0, 0)
            status = r["status"]
            issue = ""
            if status == "cancelled":
                issue = "DEPOSITS_NOT_REFUNDED"
            elif status in ("delivered", "completed"):
                issue = "OUTSTANDING"
            else:
                issue = "ACTIVE"
            tien_net = round(
                (r["tien_rut_dep"] or 0) - (r["tien_rut_ret"] or 0), 0
            )
            if abs(tien_net) > 0.005:
                issue += "+TIEN_RUT"

            w.writerow(
                [
                    r["id"],
                    r["order_ref"] or f"#{r['id']}",
                    r["public_order_code"] or f"#{r['id']}",
                    r["customer_name"] or "",
                    r["created_at"] or "",
                    r["due_date"] or "",
                    r["status"],
                    r["delivery_type"] or "",
                    r["total_price"] or 0,
                    r["deposits_in"] or 0,
                    r["refunds_out"] or 0,
                    r["revenue_cleared"] or 0,
                    r["shipping_cleared"] or 0,
                    net,
                    issue,
                    r["tien_rut_dep"] or 0,
                    r["tien_rut_ret"] or 0,
                ]
            )

    conn.close()
    print(f"Saved {len(rows)} orders with non-zero deposit balance to {OUT_PATH}")


if __name__ == "__main__":
    main()
