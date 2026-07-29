"""Migration v005: _migrate_v5_update_categories (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v5_update_categories(conn):
    """Update product categories from old slugs to new slugs (safety for existing v4 DBs)."""
    for old_cat, new_slug in _OLD_CATEGORY_TO_SLUG.items():
        conn.execute(
            "UPDATE products SET category = ? WHERE category = ?",
            (new_slug, old_cat),
        )
