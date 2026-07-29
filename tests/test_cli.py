"""Dedicated tests for baker.cli (FR-PY-6).

Covers the CLI app group: --version, --help, and that all expected commands
are registered. Uses Click's CliRunner in isolated mode (no DB side effects).
"""

from click.testing import CliRunner

from baker.cli import app


def _invoke(*args):
    runner = CliRunner()
    result = runner.invoke(app, list(args), catch_exceptions=False)
    return result


def test_cli_version():
    result = _invoke("--version")
    assert result.exit_code == 0
    assert "baker" in result.output.lower()


def test_cli_help():
    result = _invoke("--help")
    assert result.exit_code == 0
    assert "Baker" in result.output
    # The help text lists registered commands.
    assert "log" in result.output
    assert "order" in result.output


def test_cli_registers_expected_commands():
    result = _invoke("--help")
    assert result.exit_code == 0
    expected = [
        "log",
        "organize",
        "tag",
        "retype",
        "order",
        "inv",
        "product",
        "category",
        "query",
        "daily",
        "staff",
        "serve",
        "db",
        "server-log",
        "user",
        "session",
        "validate-accounts",
        "report",
        "pipeline",
        "repair-order-revenue",
        "repair-tien-rut-gap",
        "check-revenue-gaps",
        "repair-payment-journal",
        "repair-ar-entries",
        "repair-future-dates",
        "repair-inventory",
        "repair-deposit-balance",
        "repair-cancelled-orders",
        "repair-debt-expenses",
        "repair-unallocated-transfers",
        "repair-delivered-dates",
        "repair-bank-account",
    ]
    for cmd in expected:
        assert cmd in result.output, f"Command '{cmd}' not in CLI help output"


def test_cli_config_option_in_help():
    result = _invoke("--help")
    assert result.exit_code == 0
    assert "--config" in result.output


def test_cli_subcommand_help_works():
    # Each registered command should respond to --help without error.
    for cmd in ["log", "order", "product", "report"]:
        result = _invoke(cmd, "--help")
        assert result.exit_code == 0, f"'{cmd} --help' failed: {result.output}"