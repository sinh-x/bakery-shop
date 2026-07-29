"""Migration v024: _migrate_v24_rut_tien_toggle (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v24_rut_tien_toggle(conn):
    """Seed rut_tien attribute type and enable it for all existing banh_kem products."""
    conn.execute(
        """INSERT OR IGNORE INTO product_attributes
           (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
           VALUES ('rut_tien', 'Rút tiền', 'boolean', '[]', 'false', 0)""",
    )
    # Enable rut_tien for all existing banh_kem products
    conn.execute(
        """INSERT OR IGNORE INTO product_attribute_values (product_id, attribute_type, value)
           SELECT id, 'rut_tien', 'true' FROM products WHERE category = 'banh_kem'""",
    )
