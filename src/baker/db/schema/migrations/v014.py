"""Migration v014: _migrate_v14_seed_order_sources (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v14_seed_order_sources(conn):
    """Seed order source config values into app_config."""
    for config_key, config_value, sort_order in SEED_ORDER_SOURCES:
        conn.execute(
            "INSERT OR IGNORE INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            (config_key, config_value, sort_order),
        )
