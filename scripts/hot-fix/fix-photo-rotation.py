#!/usr/bin/env python3
"""Fix rotated photos in data/photos/ — only re-processes files with EXIF orientation != 1."""

import sys
from pathlib import Path

from PIL import Image, ImageOps


def needs_rotation(img: Image.Image) -> bool:
    """Check if image has EXIF orientation that requires transposing."""
    try:
        exif = img.getexif()
        # EXIF tag 274 = Orientation
        orientation = exif.get(274, 1)
        return orientation != 1
    except Exception:
        return False


def fix_photos(photos_dir: Path, dry_run: bool = False) -> None:
    fixed = 0
    skipped = 0

    for jpg in sorted(photos_dir.rglob("*.jpg")):
        try:
            img = Image.open(jpg)
        except Exception as e:
            print(f"  SKIP {jpg.name} — cannot open: {e}")
            skipped += 1
            continue

        if not needs_rotation(img):
            print(f"  OK   {jpg.relative_to(photos_dir)} — no rotation needed")
            skipped += 1
            continue

        orientation = img.getexif().get(274, 1)
        if dry_run:
            print(f"  FIX  {jpg.relative_to(photos_dir)} — orientation={orientation} (dry run)")
            fixed += 1
            continue

        rotated = ImageOps.exif_transpose(img)
        rotated = rotated.convert("RGB")
        rotated.save(str(jpg), "JPEG", quality=85)
        print(f"  FIX  {jpg.relative_to(photos_dir)} — orientation={orientation} → corrected")
        fixed += 1

    print(f"\nDone: {fixed} fixed, {skipped} skipped")


if __name__ == "__main__":
    data_dir = Path(__file__).resolve().parent.parent / "data" / "photos"
    if not data_dir.exists():
        print(f"Photos dir not found: {data_dir}")
        sys.exit(1)

    dry_run = "--dry-run" in sys.argv
    if dry_run:
        print(f"DRY RUN — scanning {data_dir}\n")
    else:
        print(f"Fixing rotated photos in {data_dir}\n")

    fix_photos(data_dir, dry_run=dry_run)
