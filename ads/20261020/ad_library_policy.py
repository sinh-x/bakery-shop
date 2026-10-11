"""Enforce the shared ads/library-exclusions.json registry before any rendering."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageOps

REGISTRY = Path(__file__).resolve().parent.parent / "library-exclusions.json"
COLLECTION = Path(__file__).resolve().parent.name
POLICY = json.loads(REGISTRY.read_text(encoding="utf-8"))
EXCLUDED_NUMBERS = frozenset(int(Path(name).stem) for name in
                             POLICY["collections"].get(COLLECTION, {}).get("excluded_index_files", []))
REVIEW = json.loads((Path(__file__).resolve().parent / "index-status.json").read_text(encoding="utf-8"))
STATUS_LABELS = {"approved": "Đã duyệt", "pending": "Chờ xác nhận"}


def is_approved(number: int) -> bool:
    return f"{number:02d}.jpg" in REVIEW["approved_index_files"] and number not in EXCLUDED_NUMBERS


def image_signature(image: Image.Image) -> str:
    rgb = image.convert("RGB")
    prefix = f"{rgb.width}x{rgb.height}:RGB:".encode()
    return hashlib.sha256(prefix+rgb.tobytes()).hexdigest()


def is_excluded(number: int, source: Path, crop=None, collection: str = COLLECTION) -> bool:
    reserved = {int(Path(name).stem) for name in
                POLICY["collections"].get(collection, {}).get("excluded_index_files", [])}
    if number in reserved:
        return True
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    for entry in POLICY["exclusions"]:
        if digest in entry["known_file_sha256"]:
            return True
        if digest == entry["source_sha256"]:
            # Removing one collage tile must NOT remove its other selections.
            if entry["crop_xyxy"] is None or tuple(crop or ()) == tuple(entry["crop_xyxy"]):
                return True
    # Detect a copied source with a new filename or metadata, or a lossless tile export.
    with Image.open(source) as image:
        photo = ImageOps.exif_transpose(image).convert("RGB")
        if crop:
            photo = photo.crop(crop)
        signature = image_signature(photo)
    return any(signature in entry["known_image_sha256"] for entry in POLICY["exclusions"])
