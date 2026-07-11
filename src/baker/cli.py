import click

import baker.config
from baker.db.connection import get_db
from baker.db.schema import ensure_schema


@click.group()
@click.version_option(version=baker.config.VERSION, prog_name="baker")
@click.option(
    "--config", "config_file",
    default=None,
    metavar="FILE",
    help=f"Config file (default: {baker.config.DEFAULT_CONFIG_PATH})",
)
def app(config_file):
    """Baker -- Bakery shop operations tracker.

    Capture first, organize later.
    """
    if config_file:
        baker.config.reload(config_file)
    with get_db() as conn:
        ensure_schema(conn)


# Register commands
from baker.commands.log import log_cmd
from baker.commands.organize import organize_cmd, tag_cmd, retype_cmd
from baker.commands.order import order_cmd
from baker.commands.inventory import inv_cmd
from baker.commands.product import product_cmd
from baker.commands.category import category_cmd
from baker.commands.query import query_cmd
from baker.commands.daily import daily_cmd
from baker.commands.staff import staff_cmd
from baker.commands.serve import serve_cmd
from baker.commands.db import db_cmd
from baker.commands.server_log import server_log_cmd
from baker.commands.validate import validate_accounts_cmd
from baker.commands.report import report_cmd
from baker.commands.pipeline import pipeline_cmd
from baker.commands.repair import repair_order_revenue_cmd, repair_tien_rut_gap_cmd, check_revenue_gaps_cmd, repair_payment_journal_cmd, repair_ar_entries_cmd, repair_future_dates_cmd, repair_inventory_cmd, repair_deposit_balance_cmd, repair_cancelled_orders_cmd

app.add_command(log_cmd, "log")
app.add_command(organize_cmd, "organize")
app.add_command(tag_cmd, "tag")
app.add_command(retype_cmd, "retype")
app.add_command(order_cmd, "order")
app.add_command(inv_cmd, "inv")
app.add_command(product_cmd, "product")
app.add_command(category_cmd, "category")
app.add_command(query_cmd, "query")
app.add_command(daily_cmd, "daily")
app.add_command(staff_cmd, "staff")
app.add_command(serve_cmd, "serve")
app.add_command(db_cmd)
app.add_command(server_log_cmd, "server-log")
app.add_command(validate_accounts_cmd, "validate-accounts")
app.add_command(report_cmd, "report")
app.add_command(pipeline_cmd, "pipeline")
app.add_command(repair_order_revenue_cmd, "repair-order-revenue")
app.add_command(repair_tien_rut_gap_cmd, "repair-tien-rut-gap")
app.add_command(check_revenue_gaps_cmd, "check-revenue-gaps")
app.add_command(repair_payment_journal_cmd, "repair-payment-journal")
app.add_command(repair_ar_entries_cmd, "repair-ar-entries")
app.add_command(repair_future_dates_cmd, "repair-future-dates")
app.add_command(repair_inventory_cmd, "repair-inventory")
app.add_command(repair_deposit_balance_cmd, "repair-deposit-balance")
app.add_command(repair_cancelled_orders_cmd, "repair-cancelled-orders")
