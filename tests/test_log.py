from click.testing import CliRunner
from baker.cli import app


runner = CliRunner()


def test_log_basic():
    result = runner.invoke(app, ["log", "Baked 50 croissants"])
    assert result.exit_code == 0
    assert "Logged" in result.output
    assert "note" in result.output


def test_log_with_type():
    result = runner.invoke(app, ["log", "Morning batch done", "-t", "prod"])
    assert result.exit_code == 0
    assert "production" in result.output


def test_log_with_tags():
    result = runner.invoke(app, ["log", "Customer called", "--tag", "customer", "--tag", "urgent"])
    assert result.exit_code == 0
    assert "Logged" in result.output


def test_log_with_data():
    result = runner.invoke(app, ["log", "Sold bread", "-t", "sale", "-d", "qty=5", "-d", "product=bread"])
    assert result.exit_code == 0
    assert "sale" in result.output


def test_query_events():
    runner.invoke(app, ["log", "Event 1", "-t", "sale"])
    runner.invoke(app, ["log", "Event 2", "-t", "production"])
    runner.invoke(app, ["log", "Event 3", "-t", "sale"])

    result = runner.invoke(app, ["query", "events", "--type", "sale"])
    assert result.exit_code == 0
    assert "Event 1" in result.output
    assert "Event 3" in result.output


def test_query_csv_export():
    runner.invoke(app, ["log", "Test sale", "-t", "sale"])
    result = runner.invoke(app, ["query", "events", "--format", "csv"])
    assert result.exit_code == 0
    assert "Test sale" in result.output
    assert "id,timestamp" in result.output


def test_organize_shows_untagged():
    runner.invoke(app, ["log", "Random observation"])
    result = runner.invoke(app, ["organize"])
    assert result.exit_code == 0


def test_tag_event():
    runner.invoke(app, ["log", "Something happened"])
    result = runner.invoke(app, ["tag", "1", "important,review"])
    assert result.exit_code == 0
    assert "Tagged" in result.output


def test_retype_event():
    runner.invoke(app, ["log", "Actually a sale"])
    result = runner.invoke(app, ["retype", "1", "sale"])
    assert result.exit_code == 0
    assert "Retyped" in result.output
    assert "sale" in result.output


def test_daily_dashboard():
    result = runner.invoke(app, ["daily"])
    assert result.exit_code == 0
    assert "Dashboard" in result.output
