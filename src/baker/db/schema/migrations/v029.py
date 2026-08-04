"""Migration v029: _migrate_v29_add_pin_support (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v29_add_pin_support(conn):
    """Add pin columns to knowledge_entries (idempotent via PRAGMA guard)."""
    existing = [r[1] for r in conn.execute("PRAGMA table_info(knowledge_entries)").fetchall()]
    if "pinned" not in existing:
        conn.execute("ALTER TABLE knowledge_entries ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0")
    if "pinned_at" not in existing:
        conn.execute("ALTER TABLE knowledge_entries ADD COLUMN pinned_at TEXT")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_knowledge_pinned ON knowledge_entries(pinned)")
