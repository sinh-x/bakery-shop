"""Migration v006: _migrate_v6_seed_variants (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v6_seed_variants(conn):
    """Seed cake size×type variants and su kem set products."""
    for name, cat, price, cost, notes, code in SEED_CAKE_VARIANTS + SEED_SU_KEM_SETS:
        conn.execute(
            "INSERT OR IGNORE INTO products "
            "(name, category, base_price, cost, recipe_notes, product_code) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (name, cat, price, cost, notes, code),
        )
