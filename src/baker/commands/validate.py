"""``baker validate-accounts`` CLI command.

Runs the accounting data integrity validation checks (see
``baker.services.accounting_validation``) and prints a human-readable
report to stdout. Exit code is 0 when all checks pass and 1 when any
check fails — suitable for cron/CI usage.
"""

import click

from baker.db.connection import get_db
from baker.services.accounting_validation import run_validation


@click.command("validate-accounts")
def validate_accounts_cmd():
    """Run accounting data integrity checks and print a report."""
    with get_db() as conn:
        report = run_validation(conn)

    summary = report["summary"]
    click.echo("Accounting validation report")
    click.echo("=" * 40)
    click.echo(
        f"Overall: {summary['overall_status']} "
        f"({summary['passed']}/{summary['total_checks']} checks passed, "
        f"{summary['total_issues']} issues)"
    )
    click.echo("")

    for check in report["checks"]:
        status_label = "PASS" if check["status"] == "pass" else "FAIL"
        click.echo(
            f"[{status_label}] {check['check']} — {check['issue_count']} issue(s)"
        )
        for detail in check["details"]:
            click.echo(f"    {detail}")

    if summary["overall_status"] != "pass":
        raise SystemExit(1)