from click.testing import CliRunner
from baker.cli import app


runner = CliRunner()


def test_staff_add():
    result = runner.invoke(app, ["staff", "add", "Ân", "--role", "baker", "--role", "cashier"])
    assert result.exit_code == 0
    assert "Added" in result.output
    assert "Ân" in result.output
    assert "tho-nuong" in result.output and "thu-ngan" in result.output


def test_staff_add_duplicate():
    runner.invoke(app, ["staff", "add", "Sinh"])
    result = runner.invoke(app, ["staff", "add", "Sinh"])
    assert "already exists" in result.output


def test_staff_list():
    runner.invoke(app, ["staff", "add", "Ân", "--role", "baker"])
    runner.invoke(app, ["staff", "add", "Sinh", "--role", "manager"])
    result = runner.invoke(app, ["staff", "list"])
    assert result.exit_code == 0
    assert "Ân" in result.output
    assert "Sinh" in result.output


def test_staff_report():
    runner.invoke(app, ["staff", "add", "Ân"])
    runner.invoke(app, ["log", "Làm bánh mì", "-t", "prod", "--by", "Ân"])
    runner.invoke(app, ["log", "Bán hàng", "-t", "sale", "--by", "Ân"])
    runner.invoke(app, ["log", "Kiểm kho", "--by", "Sinh"])

    result = runner.invoke(app, ["staff", "report", "Ân"])
    assert result.exit_code == 0
    assert "Làm bánh mì" in result.output
    assert "Bán hàng" in result.output
    assert "Kiểm kho" not in result.output


def test_log_with_by():
    result = runner.invoke(app, ["log", "Morning batch", "-t", "prod", "--by", "Ân"])
    assert result.exit_code == 0
    assert "by Ân" in result.output


def test_log_with_with():
    runner.invoke(app, ["staff", "add", "Ân"])
    runner.invoke(app, ["staff", "add", "Sinh"])
    result = runner.invoke(app, ["log", "Kiểm kho cùng nhau", "--by", "Sinh", "--with", "Ân"])
    assert result.exit_code == 0
    assert "by Sinh" in result.output

    # Ân should appear in report for this event
    result = runner.invoke(app, ["staff", "report", "Ân"])
    assert "Kiểm kho cùng nhau" in result.output


def test_query_by_person():
    runner.invoke(app, ["log", "Event by Ân", "--by", "Ân"])
    runner.invoke(app, ["log", "Event by Sinh", "--by", "Sinh"])

    result = runner.invoke(app, ["query", "events", "--by", "Ân"])
    assert result.exit_code == 0
    assert "Event by Ân" in result.output
    assert "Event by Sinh" not in result.output


def test_query_involving():
    runner.invoke(app, ["staff", "add", "Ân"])
    runner.invoke(app, ["log", "Team event", "--by", "Sinh", "--with", "Ân"])
    runner.invoke(app, ["log", "Solo event", "--by", "Sinh"])

    result = runner.invoke(app, ["query", "events", "--involving", "Ân"])
    assert result.exit_code == 0
    assert "Team event" in result.output
    assert "Solo event" not in result.output
