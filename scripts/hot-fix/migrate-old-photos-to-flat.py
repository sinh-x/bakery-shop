#!/usr/bin/env python3
"""Migrate old nested photos (data/photos/products/{id}.jpg) to flat hash storage.

- Hashes each file, applies EXIF rotation, saves to data/photos/{hash}.jpg
- Inserts into photos table
- Updates products.photo_id
- Removes old nested files + directory
"""

import hashlib
import io
import sqlite3
import sys
from pathlib import Path

from PIL import Image, ImageOps


DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data"
PHOTOS_DIR = DATA_DIR / "photos"
OLD_DIR = PHOTOS_DIR / "products"
DB_PATH = DATA_DIR / "baker.db"


def migrate():
    if not OLD_DIR.exists():
        print(f"No old photos dir: {OLD_DIR}")
        return

    old_files = list(OLD_DIR.glob("*.jpg")) + list(OLD_DIR.glob("*.png")) + list(OLD_DIR.glob("*.jpeg"))
    if not old_files:
        print("No old photo files found.")
        return

    print(f"Found {len(old_files)} old photo(s) to migrate\n")

    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    migrated = 0

    for old_file in sorted(old_files):
        product_id = old_file.stem  # e.g. "4" from "4.jpg"
        if not product_id.isdigit():
            print(f"  SKIP {old_file.name} — filename is not a product ID")
            continue

        product_id = int(product_id)

        # Check product exists
        row = conn.execute("SELECT id, name FROM products WHERE id = ?", (product_id,)).fetchone()
        if not row:
            print(f"  SKIP {old_file.name} — product {product_id} not found in DB")
            continue

        # Read, hash, apply EXIF rotation, save flat
        raw_data = old_file.read_bytes()
        img = Image.open(io.BytesIO(raw_data))
        img = ImageOps.exif_transpose(img)
        img = img.convert("RGB")
        if max(img.size) > 1200:
            img.thumbnail((1200, 1200), Image.LANCZOS)

        # Save to buffer to get final bytes for hashing
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=85)
        final_data = buf.getvalue()
        hash_hex = hashlib.sha256(final_data).hexdigest()

        dest = PHOTOS_DIR / f"{hash_hex}.jpg"
        if not dest.exists():
            dest.write_bytes(final_data)

        # Insert into photos table if not exists
        existing = conn.execute("SELECT id FROM photos WHERE hash = ?", (hash_hex,)).fetchone()
        if existing:
            photo_db_id = existing["id"]
        else:
            cur = conn.execute(
                "INSERT INTO photos (hash, original_name) VALUES (?, ?)",
                (hash_hex, old_file.name),
            )
            photo_db_id = cur.lastrowid

        # Update product
        conn.execute("UPDATE products SET photo_id = ? WHERE id = ?", (photo_db_id, product_id))
        conn.commit()

        print(f"  OK   {old_file.name} → {hash_hex[:12]}...jpg (product {product_id}: {row['name']})")
        migrated += 1

        # Remove old file
        old_file.unlink()

    # Remove old directory if empty
    if OLD_DIR.exists() and not list(OLD_DIR.iterdir()):
        OLD_DIR.rmdir()
        print(f"\n  Removed empty dir: {OLD_DIR.relative_to(DATA_DIR)}")

    conn.close()
    print(f"\nDone: {migrated} migrated, {len(old_files) - migrated} skipped")


if __name__ == "__main__":
    if "--dry-run" in sys.argv:
        print("DRY RUN — would migrate:")
        for f in sorted(OLD_DIR.glob("*")) if OLD_DIR.exists() else []:
            print(f"  {f.name}")
        sys.exit(0)

    migrate()
