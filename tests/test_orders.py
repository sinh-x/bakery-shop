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
