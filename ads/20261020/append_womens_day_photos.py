#!/usr/bin/env python3
"""Append newly registered photos without rerunning AI or changing existing images.

Update PRODUCT_SOURCES and CATEGORIES first; then run this script. No ZIP.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

import create_womens_day_ads as renderer
from group_womens_day_photos import group_output

OUT = Path(__file__).resolve().parent / "processed-enhanced"


def main(model_path=None, refresh_groups=True):
    model_path = Path(model_path or "/tmp/womens-day-models/realesr-general-x4v3.onnx")
    model = None
    manifest_path = OUT / "manifest.json"
    entries = json.loads(manifest_path.read_text(encoding="utf-8"))
    existing = {entry["number"]: entry for entry in entries}
    expected = {product[0] for product in renderer.PRODUCTS}
    if not set(existing).issubset(expected) or len(existing) != len(entries):
        raise ValueError("The existing manifest has duplicate or unregistered photo numbers.")
    added = []
    for number, filename, box, title in renderer.PRODUCTS:
        if number in existing:
            entry = existing[number]
            digest = hashlib.sha256((renderer.ROOT / filename).read_bytes()).hexdigest()
            if entry["source"] != filename or entry["source_sha256"] != digest:
                raise ValueError(f"Source mapping changed for Mẫu {number}; refusing to overwrite it.")
            continue
        before = renderer.prepare_photo(filename, box)
        from enhance_womens_day_photos import STRENGTHS, session, upscale, MODEL_URL, MODEL_HASH
        strength = STRENGTHS.get(number)
        if strength is not None:
            if model is None:
                model = session(model_path)
            photo = upscale(before, model, strength)
        else:
            photo = before
        for folder in ("cleaned", "photos", "ads", "numbered"):
            (OUT / folder).mkdir(parents=True, exist_ok=True)
        photo.save(OUT / "cleaned" / f"mau-{number:02d}.png")
        photo.save(OUT / "photos" / f"mau-{number:02d}.jpg", quality=97, subsampling=0)
        renderer.render_ad(photo, number, title, OUT / "ads" / f"mau-{number:02d}.jpg")
        renderer.render_numbered(photo, number, title, OUT / "numbered" / f"mau-{number:02d}.jpg")
        entry = renderer.source_entry(number, filename, box, title, photo)
        entry.update({
            "pre_enhancement_size": list(before.size),
            "photo": f"photos/mau-{number:02d}.jpg",
            "enhancement": {
                "method": "neural 4× super-resolution" if strength is not None else "unchanged",
                "scale": 4 if strength is not None else 1, "neural_blend": strength,
                "model_url": MODEL_URL if strength is not None else None,
                "model_sha256": MODEL_HASH if strength is not None else None,
            },
        })
        entries.append(entry)
        added.append(number)
    entries.sort(key=lambda entry: entry["number"])
    manifest_path.write_text(json.dumps(entries, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    readme = OUT / "README.md"
    content = readme.read_text(encoding="utf-8")
    content = re.sub(r"(?m)^(- `(photos|ads|numbered)/`: )\d+ ",
                     lambda match: match[1]+str(len(entries))+" ", content)
    content = re.sub(r"overview of all \d+ regenerated ads",
                     f"overview of all {len(entries)} regenerated ads", content)
    newer = ', '.join(str(n) for n, *_ in renderer.PRODUCTS if n >= 16)
    addition = (
        "\n## Additional photos\n\n"
        f"Newer retained photo numbers: {newer}.\n"
        "New photos receive small natural color adjustments; selected low-resolution\n"
        "sources receive neural super-resolution. Existing retained photos are not rerendered by the append\n"
        "command. Permanently excluded photos and retired IDs are skipped.\n\n"
        "To add newly registered photos without rerunning AI, update the category\n"
        "numbers in `../cake_categories.py` and sources in `../create_womens_day_ads.py`, then run:\n\n"
        "```sh\n/tmp/womens-day-image-env/bin/python "
        "ads/20261020/append_womens_day_photos.py\n```\n"
    )
    if "\n## Additional photos\n" not in content:
        content = content.replace("\n## Cake types\n", addition+"\n## Cake types\n")
    readme.write_text(content, encoding="utf-8")
    if refresh_groups:
        group_output(OUT, rerender=False)
    print(f"Added photo numbers: {added or 'none (already up to date)'}. Total: {len(entries)}. No ZIP.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=None)
    args = parser.parse_args()
    main(args.model)
