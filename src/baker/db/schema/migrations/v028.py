"""Migration v028: _migrate_v28_cascade_and_reseed (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v28_cascade_and_reseed(conn):
    """Rebuild catalog_photo_tags with ON DELETE CASCADE and re-seed catalog_tag vocabulary."""
    # Rebuild junction table with ON DELETE CASCADE (SQLite recreate-and-copy)
    conn.executescript(
        """
        CREATE TABLE catalog_photo_tags_new (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            photo_id    INTEGER NOT NULL REFERENCES product_catalog_photos(id) ON DELETE CASCADE,
            tag_key     TEXT NOT NULL,
            created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
        );
        INSERT INTO catalog_photo_tags_new (id, photo_id, tag_key, created_at)
            SELECT id, photo_id, tag_key, created_at FROM catalog_photo_tags;
        DROP TABLE catalog_photo_tags;
        ALTER TABLE catalog_photo_tags_new RENAME TO catalog_photo_tags;
        CREATE INDEX idx_catalog_photo_tags_photo ON catalog_photo_tags(photo_id);
        CREATE INDEX idx_catalog_photo_tags_tag ON catalog_photo_tags(tag_key);
        CREATE UNIQUE INDEX idx_catalog_photo_tags_unique ON catalog_photo_tags(photo_id, tag_key);
        """
    )
    # Clear v27 seed (typos + wrong vocabulary) and re-seed approved F1 vocabulary
    conn.execute("DELETE FROM app_config WHERE config_key = 'catalog_tag'")
    for config_key, config_value, sort_order in SEED_CATALOG_TAGS:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            (config_key, config_value, sort_order),
        )
    # Drop any photo-tag rows referencing keys that no longer exist in vocabulary
    valid_keys = [v.split(":")[1] for _, v, _ in SEED_CATALOG_TAGS]
    placeholders = ",".join("?" * len(valid_keys))
    conn.execute(
        f"DELETE FROM catalog_photo_tags WHERE tag_key NOT IN ({placeholders})",
        valid_keys,
    )
