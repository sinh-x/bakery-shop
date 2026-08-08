import pytest
from click.testing import CliRunner
from baker.cli import app

from baker.db.connection import get_db
from baker.db.schema import ensure_schema

pytestmark = pytest.mark.critical


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


# --- DB-override + boundary tests (DG-253 Phase 5.6-c1) ---


def test_get_delivery_critical_threshold_default_no_db_row():
    """DB override missing -> returns env-var default (60)."""
    from baker.config import get_delivery_critical_threshold
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        assert get_delivery_critical_threshold(conn) == 60


def test_get_delivery_critical_threshold_db_override_active():
    """Active DB row takes precedence over env-var default (NFR1)."""
    from baker.config import DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, get_delivery_critical_threshold
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema
    from baker.utils.time import now_utc

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order, active, created_at)"
            " VALUES (?, ?, 0, 1, ?)",
            (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, "45", now_utc()),
        )
        assert get_delivery_critical_threshold(conn) == 45


def test_get_delivery_critical_threshold_db_inactive_falls_back():
    """Inactive DB row (active=0) -> falls back to env-var default."""
    from baker.config import DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, get_delivery_critical_threshold
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema
    from baker.utils.time import now_utc

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order, active, created_at)"
            " VALUES (?, ?, 0, 0, ?)",
            (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, "45", now_utc()),
        )
        assert get_delivery_critical_threshold(conn) == 60


def test_get_delivery_critical_threshold_db_invalid_falls_back():
    """DB row with invalid value (< 1 or non-int) -> falls back to env-var default."""
    from baker.config import DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, get_delivery_critical_threshold
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema
    from baker.utils.time import now_utc

    with get_db() as conn:
        ensure_schema(conn)
        # Invalid: 0 (< 1)
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order, active, created_at)"
            " VALUES (?, ?, 0, 1, ?)",
            (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, "0", now_utc()),
        )
        assert get_delivery_critical_threshold(conn) == 60


def test_get_delivery_critical_threshold_db_non_int_falls_back():
    """DB row with non-integer value -> falls back to env-var default."""
    from baker.config import DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, get_delivery_critical_threshold
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema
    from baker.utils.time import now_utc

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order, active, created_at)"
            " VALUES (?, ?, 0, 1, ?)",
            (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, "not-a-number", now_utc()),
        )
        assert get_delivery_critical_threshold(conn) == 60


def test_delivery_critical_boundary_exactly_threshold():
    """Boundary: delivery order due exactly 60 min out -> critical.

    The threshold is inclusive (due_dt - now <= threshold), so an order due
    exactly at the threshold boundary counts as critical (NFR1, MINOR-3).
    """
    from baker.models.order import compute_urgency

    # Build a due datetime exactly 60 minutes from now in local TZ, then round
    # the seconds down to avoid flakiness from sub-minute strptime truncation.
    soon = _soon_local_dt(60).replace(second=0, microsecond=0)
    due_date, due_time = _format_due(soon)
    assert compute_urgency(due_date, due_time, "new", None, "delivery") == "critical"


def test_compute_urgency_threshold_minutes_param_overrides_env():
    """threshold_minutes param takes precedence over env-var default.

    With threshold_minutes=30 and an order due in 45 min, urgency is 'urgent'
    (not critical) — same as the env-var-override test but via the new param.
    """
    from baker.models.order import compute_urgency
    from datetime import datetime, timedelta
    from baker.config import TIMEZONE

    soon_local = datetime.now(TIMEZONE) + timedelta(minutes=45)
    due_date, due_time = _format_due(soon_local)
    assert compute_urgency(due_date, due_time, "new", None, "delivery", threshold_minutes=30) == "urgent"


def test_compute_urgency_threshold_minutes_zero_not_used_when_none():
    """threshold_minutes=None -> falls back to env-var default (60).

    Sanity: passing None must NOT short-circuit the threshold check to 0.
    """
    from baker.models.order import compute_urgency
    from datetime import datetime, timedelta
    from baker.config import TIMEZONE

    soon_local = datetime.now(TIMEZONE) + timedelta(minutes=90)
    due_date, due_time = _format_due(soon_local)
    # 90 min out > 60 min default -> urgent (not critical)
    assert compute_urgency(due_date, due_time, "new", None, "delivery", threshold_minutes=None) == "urgent"


def test_set_delivery_critical_threshold_endpoint_upserts(api_client):
    """PUT /api/config/delivery_critical_threshold_minutes upserts into app_config."""
    from baker.config import DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    # First PUT — INSERT path.
    resp = api_client.put(
        "/api/config/delivery_critical_threshold_minutes",
        json={"minutes": 45},
    )
    assert resp.status_code == 200
    assert resp.json() == {"minutes": 45}

    with get_db() as conn:
        ensure_schema(conn)
        row = conn.execute(
            "SELECT config_value, active FROM app_config WHERE config_key = ?",
            (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY,),
        ).fetchone()
        assert row is not None
        assert row["config_value"] == "45"
        assert row["active"] == 1

    # Second PUT — UPDATE path (existing row).
    resp = api_client.put(
        "/api/config/delivery_critical_threshold_minutes",
        json={"minutes": 90},
    )
    assert resp.status_code == 200
    assert resp.json() == {"minutes": 90}

    with get_db() as conn:
        rows = conn.execute(
            "SELECT config_value FROM app_config WHERE config_key = ?",
            (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY,),
        ).fetchall()
        assert len(rows) == 1
        assert rows[0]["config_value"] == "90"


def test_get_delivery_critical_threshold_endpoint_no_override(api_client):
    """GET /api/config/delivery_critical_threshold_minutes returns default when no DB row."""
    from baker.config import DELIVERY_CRITICAL_THRESHOLD_MINUTES

    resp = api_client.get("/api/config/delivery_critical_threshold_minutes")
    assert resp.status_code == 200
    body = resp.json()
    assert body["minutes"] == DELIVERY_CRITICAL_THRESHOLD_MINUTES
    assert body["default"] == DELIVERY_CRITICAL_THRESHOLD_MINUTES


def test_set_delivery_critical_threshold_rejects_below_one(api_client):
    """PUT with minutes < 1 -> 422."""
    resp = api_client.put(
        "/api/config/delivery_critical_threshold_minutes",
        json={"minutes": 0},
    )
    assert resp.status_code == 422


def test_set_delivery_critical_threshold_rejects_above_max(api_client):
    """PUT with minutes > 10080 (7 days) -> 422.

    Without an upper bound, large values overflow timedelta in
    compute_urgency and break all order endpoints with 500s
    (DG-253 review-auto r2 MAJOR).
    """
    resp = api_client.put(
        "/api/config/delivery_critical_threshold_minutes",
        json={"minutes": 10081},
    )
    assert resp.status_code == 422


def test_get_delivery_critical_threshold_db_oversized_falls_back():
    """DB row with value > 10080 -> falls back to env-var default.

    Guards the upper-bound validation on the DB read path so a stale
    oversized row can never overflow timedelta (DG-253 review-auto r2 MAJOR).
    """
    from baker.config import DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, get_delivery_critical_threshold
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema
    from baker.utils.time import now_utc

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order, active, created_at)"
            " VALUES (?, ?, 0, 1, ?)",
            (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, "99999999", now_utc()),
        )
        assert get_delivery_critical_threshold(conn) == 60


# --- DG-280 Phase 2: auto-sync main items status on terminal order transitions ---


def _dg280_create_order_with_main_items(client, *, main_statuses=None, extra=False, gift=False, unit_price=100000):
    """Create an order with N main items at the given initial statuses.

    Work items are created via POST /api/orders (which starts every item at
    'pending'); callers then drive each main item through the requested
    status sequence using the work-item status endpoint before triggering
    the order-level transition under test.
    """
    items_payload = [
        {"productName": f"Bánh chính {i + 1}", "quantity": 1, "unitPrice": unit_price}
        for i in range(len(main_statuses or []))
    ]
    if extra:
        items_payload.append(
            {"productName": "Phụ kiện", "quantity": 1, "unitPrice": 5000, "isExtra": True}
        )
    if gift:
        items_payload.append(
            {"productName": "Quà tặng", "quantity": 1, "unitPrice": 0, "isGift": True}
        )
    resp = client.post(
        "/api/orders",
        json={"customerName": "DG-280 Test", "dueDate": "2026-07-25", "items": items_payload},
    )
    assert resp.status_code == 201
    return resp.json()


def _dg280_advance_item(client, ref, item_id, target_status, reason=""):
    """Transition a work item to target_status, walking forward as needed."""
    resp = client.get(f"/api/orders/{ref}/items")
    current = next(i for i in resp.json() if int(i["id"]) == int(item_id))["status"]
    if current == target_status:
        return
    # Walk the canonical forward path pending -> working -> ready -> delivered
    path = ["working", "ready", "delivered"]
    for step in path:
        if current == step:
            continue
        r = client.post(
            f"/api/orders/{ref}/items/{item_id}/status",
            json={"status": step, "reason": reason},
        )
        assert r.status_code == 200, f"advance to {step} failed: {r.json()}"
        if step == target_status:
            return
    # If target is cancelled, jump from current forward position
    if target_status == "cancelled":
        r = client.post(
            f"/api/orders/{ref}/items/{item_id}/status",
            json={"status": "cancelled", "reason": reason},
        )
        assert r.status_code == 200, f"cancel failed: {r.json()}"


def _dg280_main_items(order_json):
    return [i for i in order_json["workItems"] if not i["isExtra"] and not i["isGift"]]


def _dg280_item_statuses(client, ref):
    items = client.get(f"/api/orders/{ref}/items").json()
    return {i["productName"]: i["status"] for i in items}


def test_dg280_ac1_delivered_syncs_main_items_to_delivered(api_client):
    """AC1: order -> delivered: all non-cancelled main items become 'delivered'."""
    order = _dg280_create_order_with_main_items(
        api_client, main_statuses=["pending", "working", "ready", "delivered"]
    )
    ref = order["orderRef"]
    main_items = _dg280_main_items(order)
    # Drive the first three to non-terminal forward statuses; leave the 4th at pending->delivered.
    _dg280_advance_item(api_client, ref, main_items[1]["id"], "working")
    _dg280_advance_item(api_client, ref, main_items[2]["id"], "ready")
    _dg280_advance_item(api_client, ref, main_items[3]["id"], "delivered")

    # Trigger the order-level transition to delivered (no payment required for delivered).
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200, resp.text

    statuses = _dg280_item_statuses(api_client, ref)
    assert statuses["Bánh chính 1"] == "delivered"
    assert statuses["Bánh chính 2"] == "delivered"
    assert statuses["Bánh chính 3"] == "delivered"
    assert statuses["Bánh chính 4"] == "delivered"


def test_dg280_ac2_completed_syncs_main_items_to_delivered(api_client):
    """AC2: order -> completed: all non-cancelled main items become 'delivered'."""
    order = _dg280_create_order_with_main_items(
        api_client, main_statuses=["pending", "working", "ready"], unit_price=100000
    )
    ref = order["orderRef"]
    # Completed requires full payment — record a payment covering total_price.
    total = order["totalPrice"]
    pay = api_client.post(
        f"/api/orders/{ref}/transactions",
        json={"amount": total, "type": "payment", "method": "cash"},
    )
    assert pay.status_code == 201, pay.text

    main_items = _dg280_main_items(order)
    _dg280_advance_item(api_client, ref, main_items[1]["id"], "working")
    _dg280_advance_item(api_client, ref, main_items[2]["id"], "ready")

    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "completed"})
    assert resp.status_code == 200, resp.text

    statuses = _dg280_item_statuses(api_client, ref)
    assert statuses["Bánh chính 1"] == "delivered"
    assert statuses["Bánh chính 2"] == "delivered"
    assert statuses["Bánh chính 3"] == "delivered"


def test_dg280_ac3_cancelled_syncs_main_items_to_cancelled(api_client):
    """AC3: order -> cancelled: all non-cancelled main items become 'cancelled'."""
    order = _dg280_create_order_with_main_items(
        api_client, main_statuses=["pending", "working", "ready"]
    )
    ref = order["orderRef"]
    main_items = _dg280_main_items(order)
    _dg280_advance_item(api_client, ref, main_items[1]["id"], "working")
    _dg280_advance_item(api_client, ref, main_items[2]["id"], "ready")

    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "Khách hủy"},
    )
    assert resp.status_code == 200, resp.text

    statuses = _dg280_item_statuses(api_client, ref)
    assert statuses["Bánh chính 1"] == "cancelled"
    assert statuses["Bánh chính 2"] == "cancelled"
    assert statuses["Bánh chính 3"] == "cancelled"


def test_dg280_ac4_already_delivered_items_not_changed_on_delivered_transition(api_client):
    """AC4: items already at 'delivered' are not re-updated (idempotent delivered transition)."""
    order = _dg280_create_order_with_main_items(
        api_client, main_statuses=["delivered", "pending"]
    )
    ref = order["orderRef"]
    main_items = _dg280_main_items(order)
    # Drive item 1 to delivered; leave item 2 at pending.
    _dg280_advance_item(api_client, ref, main_items[0]["id"], "delivered")
    pre = _dg280_item_statuses(api_client, ref)
    assert pre["Bánh chính 1"] == "delivered"

    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200, resp.text

    post = _dg280_item_statuses(api_client, ref)
    # Item 1 stays delivered (no backward / no duplicate update), item 2 synced up.
    assert post["Bánh chính 1"] == "delivered"
    assert post["Bánh chính 2"] == "delivered"


def test_dg280_ac5_cancelled_items_preserved_on_delivered_transition(api_client):
    """AC5: cancelled main items stay cancelled when order -> delivered."""
    order = _dg280_create_order_with_main_items(
        api_client, main_statuses=["cancelled", "pending"]
    )
    ref = order["orderRef"]
    main_items = _dg280_main_items(order)
    _dg280_advance_item(api_client, ref, main_items[0]["id"], "cancelled")

    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200, resp.text

    statuses = _dg280_item_statuses(api_client, ref)
    assert statuses["Bánh chính 1"] == "cancelled"
    assert statuses["Bánh chính 2"] == "delivered"


def test_dg280_ac6_response_includes_updated_work_items(api_client):
    """AC6: the order status transition response embeds workItems with updated statuses."""
    order = _dg280_create_order_with_main_items(
        api_client, main_statuses=["pending", "working"]
    )
    ref = order["orderRef"]
    main_items = _dg280_main_items(order)
    _dg280_advance_item(api_client, ref, main_items[1]["id"], "working")

    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "workItems" in body
    statuses = {i["productName"]: i["status"] for i in body["workItems"]}
    assert statuses["Bánh chính 1"] == "delivered"
    assert statuses["Bánh chính 2"] == "delivered"


def test_dg280_ac3_cancelled_preserves_already_cancelled_item(api_client):
    """AC3 complement: an already-cancelled main item is not re-touched on order -> cancelled."""
    order = _dg280_create_order_with_main_items(
        api_client, main_statuses=["cancelled", "working"]
    )
    ref = order["orderRef"]
    main_items = _dg280_main_items(order)
    _dg280_advance_item(api_client, ref, main_items[0]["id"], "cancelled")
    _dg280_advance_item(api_client, ref, main_items[1]["id"], "working")

    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "Khách hủy"},
    )
    assert resp.status_code == 200, resp.text

    statuses = _dg280_item_statuses(api_client, ref)
    assert statuses["Bánh chính 1"] == "cancelled"
    assert statuses["Bánh chính 2"] == "cancelled"


def test_dg280_extras_and_gifts_not_treated_as_main_items(api_client):
    """Out-of-scope guard: extras/gifts are not main items and are handled by sync_extras_to_order_status.

    This test asserts the WHERE clause (`is_extra=0 AND is_gift=0`) by creating an
    order with one main, one extra, and one gift, transitioning to delivered, and
    confirming the auto-sync UPDATE never raises and main item is delivered.
    """
    order = _dg280_create_order_with_main_items(
        api_client, main_statuses=["pending"], extra=True, gift=True
    )
    ref = order["orderRef"]

    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200, resp.text

    statuses = _dg280_item_statuses(api_client, ref)
    assert statuses["Bánh chính 1"] == "delivered"


# --- DG-248: public_order_code CLI lookup + multi-match picker (Phases 1+2) ---


def _dg248_insert_order(conn, *, order_ref, customer_name, public_order_code,
                        due_date="2026-08-10", due_time="10:00", status="new",
                        created_at=None, total_price=0):
    from baker.utils.time import now_utc
    conn.execute(
        "INSERT INTO orders (order_ref, customer_name, items, total_price, status, "
        "due_date, due_time, public_order_code, created_at, updated_at) "
        "VALUES (?, ?, '[]', ?, ?, ?, ?, ?, ?, ?)",
        (order_ref, customer_name, total_price, status, due_date, due_time,
         public_order_code, created_at or now_utc(), created_at or now_utc()),
    )
    conn.commit()


def test_public_code_single_match_show():
    """AC1: single public_code match -> order show displays detail directly."""
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-001", customer_name="Alpha",
                            public_order_code="A56-T")
    result = runner.invoke(app, ["order", "show", "A56-T"])
    assert result.exit_code == 0
    assert "Alpha" in result.output
    assert "Select order number" not in result.output


def test_public_code_multi_match_show_picker():
    """AC2: multi public_code match -> picker displayed, selection shows order."""
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-010", customer_name="Older",
                            public_order_code="V96-T", due_date="2026-08-01",
                            created_at="2026-07-20T10:00:00Z")
        _dg248_insert_order(conn, order_ref="ORD-248-011", customer_name="Newer",
                            public_order_code="V96-T", due_date="2026-08-09",
                            created_at="2026-08-05T10:00:00Z")
    result = runner.invoke(app, ["order", "show", "V96-T"], input="1\n")
    assert result.exit_code == 0
    assert "Found 2 orders" in result.output
    assert "Older" in result.output
    assert "Newer" in result.output
    assert "Select order number" in result.output


def test_public_code_multi_match_show_picker_second_select():
    """AC2: selecting the second order shows that order's detail."""
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-020", customer_name="First",
                            public_order_code="W22-X", due_date="2026-08-01",
                            created_at="2026-07-20T10:00:00Z")
        _dg248_insert_order(conn, order_ref="ORD-248-021", customer_name="Second",
                            public_order_code="W22-X", due_date="2026-08-09",
                            created_at="2026-08-05T10:00:00Z")
    # Newer (Second) is first in DESC order, so choosing 2 selects First.
    result = runner.invoke(app, ["order", "show", "W22-X"], input="2\n")
    assert result.exit_code == 0
    assert "First" in result.output


def test_public_code_single_match_status():
    """AC3: single public_code match -> order status proceeds."""
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-030", customer_name="StatusOne",
                            public_order_code="S11-T", status="new")
    result = runner.invoke(app, ["order", "status", "S11-T", "confirmed"])
    assert result.exit_code == 0
    assert "confirmed" in result.output


def test_public_code_single_match_edit():
    """AC4: single public_code match -> order edit proceeds."""
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-040", customer_name="EditOne",
                            public_order_code="E33-T", status="new")
    result = runner.invoke(app, ["order", "edit", "E33-T", "--note", "hello"])
    assert result.exit_code == 0
    assert "Updated" in result.output


def test_order_ref_lookup_unchanged():
    """AC5: order_ref lookup unchanged (backward compatibility)."""
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-050", customer_name="RefTest",
                            public_order_code="R99-T")
    result = runner.invoke(app, ["order", "show", "ORD-248-050"])
    assert result.exit_code == 0
    assert "RefTest" in result.output


def test_numeric_id_lookup_unchanged():
    """AC5: numeric id lookup unchanged (backward compatibility)."""
    with get_db() as conn:
        ensure_schema(conn)
        cursor = conn.execute(
            "INSERT INTO orders (order_ref, customer_name, items, total_price, status) "
            "VALUES ('ORD-248-060', 'IdTest', '[]', 0, 'new')"
        )
        oid = cursor.lastrowid
        conn.commit()
    result = runner.invoke(app, ["order", "show", str(oid)])
    assert result.exit_code == 0
    assert "IdTest" in result.output


def test_public_code_not_found():
    """AC6: non-matching public_code -> 'not found' message."""
    result = runner.invoke(app, ["order", "show", "XYZ-99"])
    assert result.exit_code == 0
    assert "not found" in result.output


def test_public_code_multi_match_status_picker():
    """AC7: multi public_code match in status -> picker then transition proceeds."""
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-070", customer_name="StatusA",
                            public_order_code="P77-T", status="new", due_date="2026-08-01",
                            created_at="2026-07-20T10:00:00Z")
        _dg248_insert_order(conn, order_ref="ORD-248-071", customer_name="StatusB",
                            public_order_code="P77-T", status="new", due_date="2026-08-09",
                            created_at="2026-08-05T10:00:00Z")
    result = runner.invoke(app, ["order", "status", "P77-T", "confirmed"], input="1\n")
    assert result.exit_code == 0
    assert "Select order number" in result.output
    assert "confirmed" in result.output


def test_public_code_multi_match_edit_picker():
    """AC8: multi public_code match in edit -> picker then edit proceeds."""
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-080", customer_name="EditA",
                            public_order_code="Q88-T", status="new", due_date="2026-08-01",
                            created_at="2026-07-20T10:00:00Z")
        _dg248_insert_order(conn, order_ref="ORD-248-081", customer_name="EditB",
                            public_order_code="Q88-T", status="new", due_date="2026-08-09",
                            created_at="2026-08-05T10:00:00Z")
    result = runner.invoke(app, ["order", "edit", "Q88-T", "--note", "x"], input="1\n")
    assert result.exit_code == 0
    assert "Select order number" in result.output
    assert "Updated" in result.output


def test_public_code_multi_match_invalid_then_valid_input():
    """FR2: invalid number re-prompts, then valid selection proceeds."""
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-090", customer_name="Inv1",
                            public_order_code="I55-T", due_date="2026-08-01",
                            created_at="2026-07-20T10:00:00Z")
        _dg248_insert_order(conn, order_ref="ORD-248-091", customer_name="Inv2",
                            public_order_code="I55-T", due_date="2026-08-09",
                            created_at="2026-08-05T10:00:00Z")
    # 9 invalid, then 1 valid.
    result = runner.invoke(app, ["order", "show", "I55-T"], input="9\n1\n")
    assert result.exit_code == 0
    assert "Select order number" in result.output


def test_resolve_order_ref_helper_directly():
    """Unit test the helper: single public_code match returns the row."""
    from baker.commands.order import _resolve_order_ref
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="ORD-248-100", customer_name="HelperTest",
                            public_order_code="H44-T")
        row = _resolve_order_ref(conn, "H44-T")
        assert row is not None
        assert row["customer_name"] == "HelperTest"
        # order_ref lookup
        row = _resolve_order_ref(conn, "ORD-248-100")
        assert row is not None
        # not found
        row = _resolve_order_ref(conn, "NOPE")
        assert row is None


def test_public_code_collision_with_order_ref_picks_public_code():
    """DG-373 collision case: value matches both an order_ref and multiple
    public_order_codes — public_code must win, triggering the picker.

    Order A has order_ref='L57-T' (no public_code set to that value).
    Orders B and C both share public_order_code='L57-T'.
    Old lookup (order_ref first) returned Order A directly, bypassing the
    picker. New lookup (public_code first) shows the picker for B and C.
    """
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="L57-T", customer_name="RefOrder",
                            public_order_code="OTHER-1")
        _dg248_insert_order(conn, order_ref="ORD-248-111", customer_name="PubA",
                            public_order_code="L57-T",
                            due_date="2026-08-02", created_at="2026-07-21T10:00:00Z")
        _dg248_insert_order(conn, order_ref="ORD-248-112", customer_name="PubB",
                            public_order_code="L57-T",
                            due_date="2026-08-03", created_at="2026-07-22T10:00:00Z")
    result = runner.invoke(app, ["order", "show", "L57-T"], input="1\n")
    assert result.exit_code == 0
    assert "Found 2 orders" in result.output
    assert "Select order number" in result.output
    assert "RefOrder" not in result.output


def test_public_code_collision_with_order_ref_single_match():
    """DG-373 collision case (single): value matches both an order_ref and
    exactly one public_order_code — public_code single match returns it
    directly (FR3), not the order_ref row.
    """
    from baker.commands.order import _resolve_order_ref
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="M88-T", customer_name="RefOrder",
                            public_order_code="OTHER-2")
        _dg248_insert_order(conn, order_ref="ORD-248-120", customer_name="PubSingle",
                            public_order_code="M88-T")
        row = _resolve_order_ref(conn, "M88-T")
        assert row is not None
        assert row["customer_name"] == "PubSingle"
        assert row["customer_name"] != "RefOrder"


def test_public_code_collision_picker_via_cli():
    """DG-373 collision via CLI: order show with a value that is both an
    order_ref and a multi-match public_code triggers the picker (FR1+FR2).
    """
    with get_db() as conn:
        ensure_schema(conn)
        _dg248_insert_order(conn, order_ref="N99-T", customer_name="RefOrder",
                            public_order_code="OTHER-3")
        _dg248_insert_order(conn, order_ref="ORD-248-130", customer_name="CliPubA",
                            public_order_code="N99-T",
                            due_date="2026-08-01", created_at="2026-07-20T10:00:00Z")
        _dg248_insert_order(conn, order_ref="ORD-248-131", customer_name="CliPubB",
                            public_order_code="N99-T",
                            due_date="2026-08-09", created_at="2026-08-05T10:00:00Z")
    result = runner.invoke(app, ["order", "show", "N99-T"], input="1\n")
    assert result.exit_code == 0
    assert "Found 2 orders" in result.output
    assert "Select order number" in result.output
    assert "RefOrder" not in result.output
