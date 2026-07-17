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


# --- Urgency tier (DG-221) ---


def test_urgency_normal_when_terminal_status():
    from baker.models.order import compute_urgency
    assert compute_urgency("2026-07-10", "10:00", "delivered", None) == "normal"
    assert compute_urgency("2026-07-10", "10:00", "completed", None) == "normal"
    assert compute_urgency("2026-07-10", "10:00", "cancelled", None) == "normal"


def test_urgency_critical_when_past_due():
    from baker.models.order import compute_urgency
    assert compute_urgency("2020-01-01", "00:00", "new", None) == "critical"


def test_urgency_urgent_when_due_soon():
    from baker.models.order import compute_urgency
    from baker.config import TIMEZONE
    from datetime import datetime, timedelta
    soon_local = (datetime.now(TIMEZONE) + timedelta(hours=1))
    soon = soon_local.strftime("%Y-%m-%d")
    soon_time = soon_local.strftime("%H:%M")
    result = compute_urgency(soon, soon_time, "new", None)
    assert result == "urgent", f"Expected urgent for due in 1h, got {result}"


def test_urgency_urgent_when_new_and_unacknowledged():
    from baker.models.order import compute_urgency
    far_future = "2099-01-01"
    assert compute_urgency(far_future, "10:00", "new", None) == "urgent"


def test_urgency_urgent_when_due_today_and_active():
    from baker.models.order import compute_urgency
    from datetime import datetime, timezone
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    assert compute_urgency(today, "23:59", "new", None) == "urgent"
    assert compute_urgency(today, "23:59", "confirmed", None) == "urgent"


def test_urgency_new_unacknowledged_not_due_today():
    from baker.models.order import compute_urgency
    from datetime import datetime, timezone, timedelta
    yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")
    assert compute_urgency(yesterday, "10:00", "new", None) == "critical"


def test_urgency_acknowledged_new_not_urgent():
    from baker.models.order import compute_urgency
    from baker.utils.time import now_utc
    far_future = "2099-01-01"
    assert compute_urgency(far_future, "10:00", "new", now_utc()) == "normal"


def test_urgency_normal_no_match():
    from baker.models.order import compute_urgency
    from baker.utils.time import now_utc
    far_future = "2099-01-01"
    assert compute_urgency(far_future, "10:00", "confirmed", now_utc()) == "normal"


# --- Delivery critical threshold tests (DG-253 Phase 4) ---


def _soon_local_dt(minutes_from_now):
    """Return a timezone-aware local datetime `minutes_from_now` from now."""
    from baker.config import TIMEZONE
    from datetime import datetime, timedelta
    return datetime.now(TIMEZONE) + timedelta(minutes=minutes_from_now)


def _format_due(dt_local):
    return dt_local.strftime("%Y-%m-%d"), dt_local.strftime("%H:%M")


def test_delivery_critical_within_threshold():
    """AC1: delivery order due within default threshold (60 min) -> critical."""
    from baker.models.order import compute_urgency
    soon = _soon_local_dt(30)
    due_date, due_time = _format_due(soon)
    assert compute_urgency(due_date, due_time, "new", None, "delivery") == "critical"


def test_delivery_critical_past_due():
    """AC2: delivery order past due -> critical."""
    from baker.models.order import compute_urgency
    past = _soon_local_dt(-30)
    due_date, due_time = _format_due(past)
    assert compute_urgency(due_date, due_time, "new", None, "delivery") == "critical"


def test_pickup_not_critical_within_threshold():
    """AC3: pickup order due within threshold -> urgent (not critical)."""
    from baker.models.order import compute_urgency
    soon = _soon_local_dt(30)
    due_date, due_time = _format_due(soon)
    assert compute_urgency(due_date, due_time, "new", None, "pickup") == "urgent"


def test_terminal_status_normal():
    """AC4: terminal status order -> normal regardless of delivery type."""
    from baker.models.order import compute_urgency
    soon = _soon_local_dt(30)
    due_date, due_time = _format_due(soon)
    for status in ("delivered", "completed", "cancelled"):
        for dtype in ("delivery", "bus", "door", "pickup"):
            assert compute_urgency(due_date, due_time, status, None, dtype) == "normal"


def test_bus_door_critical_within_threshold():
    """AC6: bus/door orders within threshold -> critical."""
    from baker.models.order import compute_urgency
    soon = _soon_local_dt(30)
    due_date, due_time = _format_due(soon)
    assert compute_urgency(due_date, due_time, "new", None, "bus") == "critical"
    assert compute_urgency(due_date, due_time, "new", None, "door") == "critical"


def test_configurable_threshold_respected(monkeypatch):
    """AC5: with threshold=30, delivery order due in 45 min -> urgent (not critical).

    `compute_urgency` reads `DELIVERY_CRITICAL_THRESHOLD_MINUTES` from
    `baker.config` on each call via local import. We monkeypatch the module
    attribute so the smaller threshold is used for this test only.
    """
    from baker.models.order import compute_urgency
    import baker.config
    from datetime import datetime, timedelta
    from baker.config import TIMEZONE

    monkeypatch.setattr(baker.config, "DELIVERY_CRITICAL_THRESHOLD_MINUTES", 30)
    soon_local = datetime.now(TIMEZONE) + timedelta(minutes=45)
    due_date, due_time = _format_due(soon_local)
    assert compute_urgency(due_date, due_time, "new", None, "delivery") == "urgent"


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


# --- Completeness tier (DG-241 Phase 1) ---


def test_is_junk_phone_short():
    from baker.models.order import is_junk_phone
    assert is_junk_phone("000") is True
    assert is_junk_phone("000-00") is True
    assert is_junk_phone("") is True
    assert is_junk_phone("abc") is True


def test_is_junk_phone_all_same_digit():
    from baker.models.order import is_junk_phone
    assert is_junk_phone("0000000000") is True
    assert is_junk_phone("1111111111") is True


def test_is_junk_phone_sequential_ascending():
    from baker.models.order import is_junk_phone
    assert is_junk_phone("0123456789") is True


def test_is_junk_phone_sequential_descending():
    from baker.models.order import is_junk_phone
    assert is_junk_phone("9876543210") is True


def test_is_junk_phone_fewer_than_4_unique():
    from baker.models.order import is_junk_phone
    assert is_junk_phone("1112221112") is True


def test_is_junk_phone_valid():
    from baker.models.order import is_junk_phone
    assert is_junk_phone("0912345678") is False
    assert is_junk_phone("+84912345678") is False


def test_completeness_complete():
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="Nguyễn Văn A",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date="2026-07-15",
        due_time="10:00",
        delivery_type="pickup",
        customer_phone="0912345678",
        delivery_phone="0912345679",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert tier == "complete"
    assert missing == []


def test_completeness_missing_customer_name():
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date="2026-07-15",
        due_time="10:00",
        customer_phone="0912345678",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert tier == "incomplete"
    assert "customer_name" in missing


def test_completeness_walkin_khach_missing():
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="Khách",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date="2026-07-15",
        due_time="10:00",
        customer_phone="0912345678",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert tier == "incomplete"
    assert "customer_name" in missing


def test_completeness_missing_items():
    from baker.models.order import Order
    order = Order(
        customer_name="Nguyễn Văn A",
        items=[],
        total_price=0,
        due_date="2026-07-15",
        due_time="10:00",
        customer_phone="0912345678",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert tier == "incomplete"
    assert "items" in missing
    assert "total_price" in missing


def test_completeness_missing_dates():
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="Nguyễn Văn A",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date=None,
        due_time=None,
        customer_phone="0912345678",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert tier == "incomplete"
    assert "due_date" in missing
    assert "due_time" in missing


def test_completeness_delivery_address_required_for_delivery():
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="Nguyễn Văn A",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date="2026-07-15",
        due_time="10:00",
        delivery_type="delivery",
        delivery_address="",
        customer_phone="0912345678",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert tier == "incomplete"
    assert "delivery_address" in missing


def test_completeness_delivery_address_required_for_bus():
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="Nguyễn Văn A",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date="2026-07-15",
        due_time="10:00",
        delivery_type="bus",
        delivery_address="",
        customer_phone="0912345678",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert "delivery_address" in missing


def test_completeness_delivery_address_not_required_for_pickup():
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="Nguyễn Văn A",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date="2026-07-15",
        due_time="10:00",
        delivery_type="pickup",
        delivery_address="",
        customer_phone="0912345678",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert "delivery_address" not in missing


def test_completeness_junk_phone_flagged():
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="Nguyễn Văn A",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date="2026-07-15",
        due_time="10:00",
        customer_phone="0000000000",
        delivery_phone="0123456789",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert tier == "incomplete"
    assert "customer_phone" in missing
    assert "delivery_phone" in missing


def test_completeness_missing_source():
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="Nguyễn Văn A",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date="2026-07-15",
        due_time="10:00",
        customer_phone="0912345678",
        source="",
    )
    missing, tier = order.compute_completeness()
    assert "source" in missing


def test_completeness_delivery_phone_fallback_to_customer_phone():
    """F1: order with customer_phone set but delivery_phone empty
    should NOT flag delivery_phone as missing."""
    from baker.models.order import Order, OrderItem
    order = Order(
        customer_name="Nguyễn Văn A",
        items=[OrderItem(product="Bánh kem", qty=1, price=200000)],
        total_price=200000,
        due_date="2026-07-15",
        due_time="10:00",
        delivery_type="delivery",
        delivery_address="123 Main St",
        customer_phone="0912345678",
        delivery_phone="",
        source="Facebook",
    )
    missing, tier = order.compute_completeness()
    assert "delivery_phone" not in missing
    assert tier == "complete"
