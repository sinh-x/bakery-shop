"""Migration v031: _migrate_v31_enum_attributes (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v31_enum_attributes(conn):
    """Seed nhan_banh enum attribute and its 5 options for banh_kem category."""
    conn.execute(
        """INSERT OR IGNORE INTO product_attributes
           (attribute_type, label_vi, value_type, applicable_categories,
            default_value, sort_order, active)
           VALUES ('nhan_banh', 'Nhân bánh', 'enum', '["banh_kem"]', '', 10, 1)""",
    )
    row = conn.execute(
        "SELECT id FROM product_attributes WHERE attribute_type = 'nhan_banh'"
    ).fetchone()
    if row is None:
        return
    attribute_id = row[0]

    for value_vi, sort_order in SEED_NHAN_BANH_OPTIONS:
        existing = conn.execute(
            "SELECT id FROM product_attribute_options "
            "WHERE attribute_id = ? AND value_vi = ?",
            (attribute_id, value_vi),
        ).fetchone()
        if existing is None:
            conn.execute(
                """INSERT INTO product_attribute_options
                   (attribute_id, value_vi, sort_order, active)
                   VALUES (?, ?, ?, 1)""",
                (attribute_id, value_vi, sort_order),
            )

    default_row = conn.execute(
        "SELECT id FROM product_attribute_options "
        "WHERE attribute_id = ? AND value_vi = 'Sầu riêng'",
        (attribute_id,),
    ).fetchone()
    if default_row is not None:
        conn.execute(
            "UPDATE product_attributes SET default_value = ? WHERE id = ?",
            (str(default_row[0]), attribute_id),
        )
