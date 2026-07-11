from click.testing import CliRunner
from baker.cli import app

from baker.db.connection import get_db
from baker.db.schema import ensure_schema


runner = CliRunner()


def test_order_create():
    result = runner.invoke(app, [
        "order", "new", "Mrs. Chen",
        "--item", "Birthday Cake x1 @45",
        "--due", "2026-03-10",
    ])
    assert result.exit_code == 0
    assert "Created" in result.output
    assert "Mrs. Chen" in result.output


def test_order_list():
    runner.invoke(app, ["order", "new", "TestBuyer", "--item", "Bread x2 @7"])
    result = runner.invoke(app, ["order", "list"])
    assert result.exit_code == 0
    assert "TestBuyer" in result.output


def test_order_show():
    runner.invoke(app, ["order", "new", "ShowTest", "--item", "Cake x1 @50"])
    result = runner.invoke(app, ["order", "show", "1"])
    assert result.exit_code == 0
    assert "ShowTest" in result.output


def test_order_status_transition():
    runner.invoke(app, ["order", "new", "Status Test", "--item", "Cake x1 @30"])
    # Get the order ref
    result = runner.invoke(app, ["order", "list"])
    assert result.exit_code == 0

    # Valid transition: new -> confirmed
    result = runner.invoke(app, ["order", "status", "1", "confirmed"])
    assert result.exit_code == 0
    assert "confirmed" in result.output

    # Valid: confirmed -> in_progress
    result = runner.invoke(app, ["order", "status", "1", "in_progress"])
    assert result.exit_code == 0

    # Valid: in_progress -> ready
    result = runner.invoke(app, ["order", "status", "1", "ready"])
    assert result.exit_code == 0


def test_order_forward_skip_transition():
    runner.invoke(app, ["order", "new", "Invalid Test", "--item", "Cake x1 @30"])
    # new -> ready is a forward skip — allowed (no strict transition enforcement)
    result = runner.invoke(app, ["order", "status", "1", "ready"])
    assert result.exit_code == 0
    assert "ready" in result.output


def test_order_cancel():
    runner.invoke(app, ["order", "new", "Cancel Test", "--item", "Cake x1 @30"])
    result = runner.invoke(app, ["order", "status", "1", "cancelled", "--reason", "Customer changed mind"])
    assert result.exit_code == 0
    assert "cancelled" in result.output


def test_order_edit():
    runner.invoke(app, ["order", "new", "Edit Test", "--item", "Cake x1 @30"])
    result = runner.invoke(app, ["order", "edit", "1", "--note", "Add extra frosting"])
    assert result.exit_code == 0
    assert "Updated" in result.output


def test_order_item_parsing():
    """Test various item spec formats."""
    from baker.models.order import OrderItem

    item = OrderItem.parse("Birthday Cake x1 @45")
    assert item.product == "Birthday Cake"
    assert item.qty == 1
    assert item.price == 45.0

    item = OrderItem.parse("Cupcakes x12 @2.50")
    assert item.product == "Cupcakes"
    assert item.qty == 12
    assert item.price == 2.50

    item = OrderItem.parse("Simple Bread")
    assert item.product == "Simple Bread"
    assert item.qty == 1
    assert item.price == 0.0


def test_order_from_row_delivery_phone_null_coerced_to_empty():
    """AC3: NULL delivery_phone in DB row must coerce to '' (not None)."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema
    from baker.models.order import Order

    with get_db() as conn:
        ensure_schema(conn)
        cursor = conn.execute(
            """INSERT INTO orders (order_ref, customer_name, customer_phone, items,
                                      total_price, status, delivery_phone)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            ("ORD-TEST-001", "NullPhone Test", "0123456789", "[]", 0, "new", None),
        )
        order_id = cursor.lastrowid
        conn.commit()

        row = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
        order = Order.from_row(row, conn=conn)
        assert order.delivery_phone == ""
        assert order.delivery_phone is not None


def test_order_from_row_delivery_phone_present_value_preserved():
    """AC3 complement: non-NULL delivery_phone must be preserved as-is."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema
    from baker.models.order import Order

    with get_db() as conn:
        ensure_schema(conn)
        cursor = conn.execute(
            """INSERT INTO orders (order_ref, customer_name, customer_phone, items,
                                      total_price, status, delivery_phone)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            ("ORD-TEST-002", "Phone Test", "0123456789", "[]", 0, "new", "0987654321"),
        )
        order_id = cursor.lastrowid
        conn.commit()

        row = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
        order = Order.from_row(row, conn=conn)
        assert order.delivery_phone == "0987654321"


def _account_id(conn, code: str) -> int:
    return int(
        conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0]
    )


def _create_test_order(conn):
    cursor = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, items, total_price, status, created_at) "
        "VALUES ('ACC-TEST-001', 'Accounting Test', '[]', 100, 'delivered', '2026-07-11T10:00:00Z')"
    )
    return cursor.lastrowid


def _make_entry(conn, description, source_type, source_id, lines, txn_date=None):
    from baker.models.journal_entry import JournalEntry

    return JournalEntry.create_with_lines(
        conn, description=description, source_type=source_type,
        source_id=source_id, lines=lines, transaction_date=txn_date,
    )


def _make_payment_txn(conn, order_id, amount=50):
    cursor = conn.execute(
        "INSERT INTO payment_transactions (order_id, amount, type, method, created_at) "
        "VALUES (?, ?, 'payment', 'cash', '2026-07-11T10:30:00Z')",
        (order_id, amount),
    )
    return cursor.lastrowid


def test_accounting_query_direct_source_types():
    """FR2: Journal entries queried across all order-linked source_types."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)

        aid = _account_id
        _make_entry(conn, "Revenue", "order", order_id, [(aid(conn, "4100"), 100, 0, ""), (aid(conn, "1100"), 0, 100, "")])
        _make_entry(conn, "COGS", "order_cogs", order_id, [(aid(conn, "5900"), 60, 0, ""), (aid(conn, "1100"), 0, 60, "")])
        _make_entry(conn, "Shipping hold", "order_shipping_hold", order_id, [(aid(conn, "1100"), 20, 0, ""), (aid(conn, "2200"), 0, 20, "")])
        _make_entry(conn, "Shipping release", "order_shipping_release", order_id, [(aid(conn, "2200"), 20, 0, ""), (aid(conn, "1100"), 0, 20, "")])

        from baker.models.journal_entry import JournalEntry

        results = JournalEntry.list_for_order(conn, order_id)

        assert len(results) == 4
        types_found = {r["source_type"] for r in results}
        assert types_found == {"order", "order_cogs", "order_shipping_hold", "order_shipping_release"}


def test_accounting_query_payment_transactions():
    """FR3+FR4: Payment transaction entries included via JOIN, invalidated excluded."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)

        txn_id = _make_payment_txn(conn, order_id)
        aid = _account_id
        _make_entry(conn, "Payment", "payment_transaction", txn_id, [(aid(conn, "1100"), 50, 0, ""), (aid(conn, "4100"), 0, 50, "")])

        from baker.models.journal_entry import JournalEntry

        results = JournalEntry.list_for_order(conn, order_id)
        payment_results = [r for r in results if r["source_type"] == "payment_transaction"]
        assert len(payment_results) == 1
        assert payment_results[0]["source_id"] == txn_id


def test_accounting_query_excludes_invalidated_payments():
    """FR4: Invalidated (soft-deleted) payment transactions excluded."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)

        valid_txn = _make_payment_txn(conn, order_id, 30)
        aid = _account_id
        _make_entry(conn, "Valid payment", "payment_transaction", valid_txn,
                    [(aid(conn, "1100"), 30, 0, ""), (aid(conn, "4100"), 0, 30, "")])

        invalid_txn = _make_payment_txn(conn, order_id, 20)
        conn.execute(
            "UPDATE payment_transactions SET invalidated_at = '2026-07-11T12:00:00Z' WHERE id = ?",
            (invalid_txn,),
        )
        _make_entry(conn, "Invalidated payment", "payment_transaction", invalid_txn,
                    [(aid(conn, "1100"), 20, 0, ""), (aid(conn, "4100"), 0, 20, "")])

        from baker.models.journal_entry import JournalEntry

        results = JournalEntry.list_for_order(conn, order_id)
        payment_results = [r for r in results if r["source_type"] == "payment_transaction"]
        assert len(payment_results) == 1
        assert payment_results[0]["source_id"] == valid_txn


def test_accounting_query_empty():
    """FR7 edge: No journal entries returns empty list."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)

        from baker.models.journal_entry import JournalEntry

        results = JournalEntry.list_for_order(conn, order_id)
        assert results == []


def test_accounting_query_line_account_info():
    """FR5: Each line includes account code, name, debit, credit, description."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)

        aid = _account_id
        _make_entry(conn, "Revenue", "order", order_id,
                    [(aid(conn, "4100"), 100, 0, "Sales revenue"), (aid(conn, "1100"), 0, 100, "Cash received")])

        from baker.models.journal_entry import JournalEntry

        results = JournalEntry.list_for_order(conn, order_id)
        assert len(results) == 1
        lines = results[0]["lines"]
        assert len(lines) == 2

        debit_line = next(l for l in lines if l["debit"] > 0)
        assert debit_line["account_code"] == "4100"
        assert debit_line["account_name"] == "Doanh thu bán hàng (Order Revenue)"
        assert debit_line["debit"] == 100
        assert debit_line["credit"] == 0
        assert debit_line["description"] == "Sales revenue"

        credit_line = next(l for l in lines if l["credit"] > 0)
        assert credit_line["account_code"] == "1100"
        assert credit_line["account_name"] == "Tiền mặt (Cash on Hand)"
        assert credit_line["credit"] == 100


def test_cli_accounting_flag_activates_display():
    """AC1/FR1: --accounting flag triggers accounting display after order detail."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)
        aid = _account_id
        _make_entry(conn, "Revenue", "order", order_id, [(aid(conn, "4100"), 100, 0, ""), (aid(conn, "1100"), 0, 100, "")])

    result = runner.invoke(app, ["order", "show", "ACC-TEST-001", "--accounting"])
    assert result.exit_code == 0
    assert "Accounting Test" in result.output
    assert "Tóm tắt theo tài khoản" in result.output
    assert "Bút toán" in result.output


def test_cli_accounting_all_source_types():
    """AC2, AC3, AC4 / FR2, FR3: All order-linked source types appear."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)

        aid = _account_id
        _make_entry(conn, "Revenue", "order", order_id, [(aid(conn, "4100"), 100, 0, ""), (aid(conn, "1100"), 0, 100, "")])
        _make_entry(conn, "COGS", "order_cogs", order_id, [(aid(conn, "5900"), 60, 0, ""), (aid(conn, "1100"), 0, 60, "")])
        _make_entry(conn, "Shipping hold", "order_shipping_hold", order_id, [(aid(conn, "1100"), 20, 0, ""), (aid(conn, "2200"), 0, 20, "")])
        _make_entry(conn, "Shipping release", "order_shipping_release", order_id, [(aid(conn, "2200"), 20, 0, ""), (aid(conn, "1100"), 0, 20, "")])
        txn_id = _make_payment_txn(conn, order_id, 50)
        _make_entry(conn, "Payment", "payment_transaction", txn_id, [(aid(conn, "1100"), 50, 0, ""), (aid(conn, "4100"), 0, 50, "")])

    result = runner.invoke(app, ["order", "show", "ACC-TEST-001", "--accounting"])
    assert result.exit_code == 0
    assert "Doanh thu" in result.output
    assert "Giá vốn" in result.output
    assert "Ship" in result.output
    assert "Thanh toán" in result.output


def test_cli_accounting_excludes_invalidated_payments():
    """FR4: Invalidated payment transactions excluded from CLI output."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)

        valid_txn = _make_payment_txn(conn, order_id, 30)
        aid = _account_id
        _make_entry(conn, "Valid payment", "payment_transaction", valid_txn,
                    [(aid(conn, "1100"), 30, 0, ""), (aid(conn, "4100"), 0, 30, "")])

        invalid_txn = _make_payment_txn(conn, order_id, 20)
        conn.execute(
            "UPDATE payment_transactions SET invalidated_at = '2026-07-11T12:00:00Z' WHERE id = ?",
            (invalid_txn,),
        )
        _make_entry(conn, "Invalidated payment", "payment_transaction", invalid_txn,
                    [(aid(conn, "1100"), 20, 0, ""), (aid(conn, "4100"), 0, 20, "")])

    result = runner.invoke(app, ["order", "show", "ACC-TEST-001", "--accounting"])
    assert result.exit_code == 0
    assert "Valid payment" in result.output
    assert "Invalidated payment" not in result.output


def test_cli_accounting_line_details():
    """AC5/FR5: Lines display account code, VN name, debit, credit, description."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)
        aid = _account_id
        _make_entry(conn, "Revenue", "order", order_id,
                    [(aid(conn, "4100"), 100, 0, "Sales revenue"), (aid(conn, "1100"), 0, 100, "Cash received")])

    result = runner.invoke(app, ["order", "show", "ACC-TEST-001", "--accounting"])
    assert result.exit_code == 0
    assert "4100" in result.output
    assert "TK" in result.output
    assert "Tên tài khoản" in result.output
    assert "Diễn giải" in result.output
    assert "Sales revenue" in result.output
    assert "Cash received" in result.output


def test_cli_accounting_summary_section():
    """FR6: Summary shows totals per account across all entries."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)
        aid = _account_id
        _make_entry(conn, "Revenue", "order", order_id, [(aid(conn, "4100"), 100, 0, ""), (aid(conn, "1100"), 0, 100, "")])
        _make_entry(conn, "COGS", "order_cogs", order_id, [(aid(conn, "5900"), 60, 0, ""), (aid(conn, "1100"), 0, 60, "")])

    result = runner.invoke(app, ["order", "show", "ACC-TEST-001", "--accounting"])
    assert result.exit_code == 0
    assert "Tóm tắt theo tài khoản" in result.output
    assert "4100" in result.output
    assert "5900" in result.output
    assert "1100" in result.output
    assert "Tổng" in result.output


def test_cli_accounting_empty_no_entries():
    """AC6/FR7: Empty order shows 'Không có bút toán kế toán cho đơn hàng này'."""
    with get_db() as conn:
        ensure_schema(conn)
        _create_test_order(conn)

    result = runner.invoke(app, ["order", "show", "ACC-TEST-001", "--accounting"])
    assert result.exit_code == 0
    assert "Accounting Test" in result.output
    assert "Không có bút toán kế toán cho đơn hàng này" in result.output


def test_cli_accounting_backward_compatible():
    """AC7/FR8: Without --accounting, output unchanged (no accounting display)."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)
        aid = _account_id
        _make_entry(conn, "Revenue", "order", order_id, [(aid(conn, "4100"), 100, 0, ""), (aid(conn, "1100"), 0, 100, "")])

    result = runner.invoke(app, ["order", "show", "ACC-TEST-001"])
    assert result.exit_code == 0
    assert "Accounting Test" in result.output
    assert "Kế toán" not in result.output
    assert "Bút toán" not in result.output


def test_cli_accounting_read_only():
    """NFR1: --accounting does not modify the database (no new rows)."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _create_test_order(conn)
        aid = _account_id
        _make_entry(conn, "Revenue", "order", order_id, [(aid(conn, "4100"), 100, 0, ""), (aid(conn, "1100"), 0, 100, "")])
        before_count = conn.execute("SELECT COUNT(*) FROM journal_entries").fetchone()[0]

    runner.invoke(app, ["order", "show", "ACC-TEST-001", "--accounting"])

    with get_db() as conn:
        after_count = conn.execute("SELECT COUNT(*) FROM journal_entries").fetchone()[0]
    assert before_count == after_count
