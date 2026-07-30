"""Migration v023: _migrate_v23_product_attributes (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v23_product_attributes(conn):
    """Seed cash_amount and cash_fee attribute types for banh_kem category."""
    for attr_type, label_vi, value_type, applicable_cats, default_val, sort_order in SEED_PRODUCT_ATTRIBUTES:
        conn.execute(
            """INSERT OR IGNORE INTO product_attributes
               (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (attr_type, label_vi, value_type, applicable_cats, default_val, sort_order),
        )
