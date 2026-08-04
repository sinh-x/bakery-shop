"""Migration v038: _migrate_v38_accessory_products (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v38_accessory_products(conn):
    """Create product-backed accessories from app_config.order_extra values."""
    table_rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()
    existing_tables = {row["name"] for row in table_rows}
    required_tables = {
        "categories",
        "products",
        "app_config",
        "product_attribute_values",
    }
    if not required_tables.issubset(existing_tables):
        return

    category_slug = "phu_kien"
    category_name = "Phụ kiện"
    category_prefix = "PKI"

    category_row = conn.execute(
        "SELECT id FROM categories WHERE slug = ?",
        (category_slug,),
    ).fetchone()
    if category_row is None:
        max_position = conn.execute(
            "SELECT COALESCE(MAX(position), -1) FROM categories WHERE active = 1"
        ).fetchone()[0]
        conn.execute(
            "INSERT INTO categories (slug, name, code_prefix, icon, position, active) VALUES (?, ?, ?, '', ?, 1)",
            (category_slug, category_name, category_prefix, int(max_position) + 1),
        )

    extras_rows = conn.execute(
        "SELECT config_value FROM app_config WHERE config_key = 'order_extra' ORDER BY sort_order, id"
    ).fetchall()
    if not extras_rows:
        return

    products = conn.execute(
        "SELECT id, name, base_price FROM products WHERE category = ?",
        (category_slug,),
    ).fetchall()
    existing_by_norm_name: dict[str, dict] = {
        _normalize_accessory_name(row["name"]): row for row in products if (row["name"] or "").strip()
    }

    next_code_idx_row = conn.execute(
        "SELECT COALESCE(MAX(CAST(SUBSTR(product_code, 5) AS INTEGER)), 0) AS max_idx "
        "FROM products WHERE product_code GLOB 'PKI-[0-9][0-9]'"
    ).fetchone()
    next_code_index = int(next_code_idx_row["max_idx"] or 0) + 1

    for extra_row in extras_rows:
        raw = (extra_row["config_value"] or "").strip()
        if not raw or "|" not in raw:
            continue

        name_part, price_part = raw.split("|", 1)
        accessory_name = name_part.strip()
        normalized_name = _normalize_accessory_name(accessory_name)
        if not normalized_name:
            continue

        try:
            base_price = float(price_part.strip())
        except (TypeError, ValueError):
            continue

        existing = existing_by_norm_name.get(normalized_name)
        if existing is not None:
            product_id = int(existing["id"])
            conn.execute(
                "UPDATE products SET active = 1, category = ? WHERE id = ?",
                (category_slug, product_id),
            )
            conn.execute(
                "UPDATE products SET base_price = ? WHERE id = ? AND ROUND(base_price) != ROUND(?)",
                (base_price, product_id, base_price),
            )
            conn.execute(
                "UPDATE products SET product_code = ? WHERE id = ? AND (product_code = '' OR product_code IS NULL)",
                (f"{category_prefix}-{next_code_index:02d}", product_id),
            )
            next_code_index += 1
        else:
            product_code = f"{category_prefix}-{next_code_index:02d}"
            next_code_index += 1
            cursor = conn.execute(
                """INSERT INTO products (name, category, base_price, cost, recipe_notes, active, product_code)
                   VALUES (?, ?, ?, 0, '', 1, ?)""",
                (accessory_name, category_slug, base_price, product_code),
            )
            product_id = int(cursor.lastrowid)
            existing_by_norm_name[normalized_name] = {
                "id": product_id,
                "name": accessory_name,
                "base_price": base_price,
            }

        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, 'trung_bay', 'true')
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (product_id,),
        )
        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, 'tang_kem', 'true')
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (product_id,),
        )
