"""Migration v027: _migrate_v27_seed_catalog_tags (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v27_seed_catalog_tags(conn):
    """Seed 20 catalog tag entries into app_config."""
    for config_key, config_value, sort_order in SEED_CATALOG_TAGS:
        conn.execute(
            "INSERT OR IGNORE INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            (config_key, config_value, sort_order),
        )
