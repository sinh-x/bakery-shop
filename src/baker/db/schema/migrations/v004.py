"""Migration v004: _migrate_v4_assign_codes (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v4_assign_codes(conn):
    """Seed categories and assign product codes to existing products."""
    # Seed categories
    for slug, name, code_prefix in SEED_CATEGORIES:
        conn.execute(
            "INSERT OR IGNORE INTO categories (slug, name, code_prefix) "
            "VALUES (?, ?, ?)",
            (slug, name, code_prefix),
        )

    # Build prefix lookup: old category -> code_prefix
    slug_to_prefix = {slug: prefix for slug, _, prefix in SEED_CATEGORIES}
    prefix_counters = {}

    # Fetch all products ordered by id to assign codes deterministically
    rows = conn.execute(
        "SELECT id, category FROM products ORDER BY id"
    ).fetchall()

    for row in rows:
        product_id = row[0]
        old_cat = row[1]
        slug = _OLD_CATEGORY_TO_SLUG.get(old_cat, "khac")
        prefix = slug_to_prefix[slug]

        count = prefix_counters.get(prefix, 0) + 1
        prefix_counters[prefix] = count
        code = f"{prefix}-{count:02d}"

        conn.execute(
            "UPDATE products SET product_code = ? WHERE id = ?",
            (code, product_id),
        )

    # Update category values from old slugs to new slugs
    for old_cat, new_slug in _OLD_CATEGORY_TO_SLUG.items():
        conn.execute(
            "UPDATE products SET category = ? WHERE category = ?",
            (new_slug, old_cat),
        )

    # Add unique index after all codes are assigned
    conn.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_products_code "
        "ON products(product_code) WHERE product_code != ''"
    )
