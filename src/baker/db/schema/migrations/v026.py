"""Migration v026: _migrate_v26_trung_bay_and_stock (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v26_trung_bay_and_stock(conn):
    """Seed trung_bay and tang_kem attribute types; enable tang_kem for existing banh_kem products."""
    conn.execute(
        """INSERT OR IGNORE INTO product_attributes
           (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
           VALUES ('trung_bay', 'Trưng bày', 'boolean', '[]', 'false', 0)""",
    )
    conn.execute(
        """INSERT OR IGNORE INTO product_attributes
           (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
           VALUES ('tang_kem', 'Tặng kèm', 'boolean', '[]', 'false', 0)""",
    )
    # Auto-enable tang_kem for all existing banh_kem products (backwards compatibility)
    conn.execute(
        """INSERT OR IGNORE INTO product_attribute_values (product_id, attribute_type, value)
           SELECT id, 'tang_kem', 'true' FROM products WHERE category = 'banh_kem'""",
    )
