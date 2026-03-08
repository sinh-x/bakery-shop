import click

from baker.db.connection import get_db
from baker.db.schema import ensure_schema


@click.group()
@click.version_option(version="0.1.0", prog_name="baker")
def app():
    """Baker -- Bakery shop operations tracker.

    Capture first, organize later.
    """
    with get_db() as conn:
        ensure_schema(conn)


# Register commands
from baker.commands.log import log_cmd
from baker.commands.organize import organize_cmd, tag_cmd, retype_cmd
from baker.commands.order import order_cmd
from baker.commands.inventory import inv_cmd
from baker.commands.product import product_cmd
from baker.commands.query import query_cmd
from baker.commands.daily import daily_cmd
from baker.commands.staff import staff_cmd

app.add_command(log_cmd, "log")
app.add_command(organize_cmd, "organize")
app.add_command(tag_cmd, "tag")
app.add_command(retype_cmd, "retype")
app.add_command(order_cmd, "order")
app.add_command(inv_cmd, "inv")
app.add_command(product_cmd, "product")
app.add_command(query_cmd, "query")
app.add_command(daily_cmd, "daily")
app.add_command(staff_cmd, "staff")
