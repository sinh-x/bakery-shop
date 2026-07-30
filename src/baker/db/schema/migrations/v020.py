"""Migration v020: _migrate_v20_seed_shipping_and_extras (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v20_seed_shipping_and_extras(conn):
    """Seed shipping fee presets and extra item presets into app_config."""
    for config_key, config_value, sort_order in SEED_SHIPPING_AND_EXTRAS:
        conn.execute(
            "INSERT OR IGNORE INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            (config_key, config_value, sort_order),
        )
