"""Migration v008: _migrate_v8_photos (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v8_photos(conn):
    """Hash existing photos, populate photos table, update FKs, copy files to flat dir."""
    import hashlib
    import shutil
    import baker.config

    flat_dir = baker.config.DATA_DIR / "photos"
    flat_dir.mkdir(parents=True, exist_ok=True)

    def _ensure_photo(src_path, original_name):
        if not src_path.exists():
            return None
        data = src_path.read_bytes()
        hash_hex = hashlib.sha256(data).hexdigest()
        dest = flat_dir / f"{hash_hex}.jpg"
        if not dest.exists():
            shutil.copy2(src_path, dest)
        row = conn.execute("SELECT id FROM photos WHERE hash = ?", (hash_hex,)).fetchone()
        if row:
            return row[0]
        cursor = conn.execute(
            "INSERT INTO photos (hash, original_name) VALUES (?, ?)",
            (hash_hex, original_name),
        )
        return cursor.lastrowid

    # Migrate product main photos
    rows = conn.execute(
        "SELECT id, photo_path FROM products WHERE photo_path != '' AND photo_path IS NOT NULL"
    ).fetchall()
    for row in rows:
        photo_id = _ensure_photo(
            baker.config.DATA_DIR / row["photo_path"], row["photo_path"]
        )
        if photo_id:
            conn.execute(
                "UPDATE products SET photo_id = ? WHERE id = ?", (photo_id, row["id"])
            )

    # Migrate catalog photos
    rows = conn.execute(
        "SELECT id, file_path FROM product_catalog_photos"
        " WHERE file_path != '' AND file_path IS NOT NULL"
    ).fetchall()
    for row in rows:
        photo_id = _ensure_photo(
            baker.config.DATA_DIR / row["file_path"], row["file_path"]
        )
        if photo_id:
            conn.execute(
                "UPDATE product_catalog_photos SET photo_id = ? WHERE id = ?",
                (photo_id, row["id"]),
            )
