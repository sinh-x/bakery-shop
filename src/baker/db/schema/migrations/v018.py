"""Migration v018: _migrate_v18_seed_checklist (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v18_seed_checklist(conn):
    """Seed default opening and closing checklist items."""
    for name, period, sort_order in SEED_CHECKLIST_OPENING + SEED_CHECKLIST_CLOSING:
        conn.execute(
            "INSERT OR IGNORE INTO checklist_templates (name, period, sort_order) VALUES (?, ?, ?)",
            (name, period, sort_order),
        )
