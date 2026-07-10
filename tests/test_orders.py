from click.testing import CliRunner
from baker.cli import app


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
