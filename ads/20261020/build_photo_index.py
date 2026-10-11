#!/usr/bin/env python3
"""Raw originals -> numbered index previews, before approval and final ads."""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageOps

import create_womens_day_ads as renderer
from ad_library_policy import EXCLUDED_NUMBERS, STATUS_LABELS, is_approved
from cake_categories import CATEGORIES

ROOT = Path(__file__).resolve().parent
INDEX = ROOT / "index"


def build_index():
    INDEX.mkdir(parents=True, exist_ok=True)
    allowed = {f"{number:02d}.jpg" for number, *_ in renderer.REGISTERED_PRODUCTS}
    for path in INDEX.glob("*.jpg"):
        if path.stem.isdigit() and path.name not in allowed:
            path.unlink()
    with Image.open(renderer.RAW / renderer.COLLAGE) as source:
        collage = renderer.clean_collage(source.convert("RGB"))
    entries = []
    photos = {}
    for number, filename, box, title in renderer.REGISTERED_PRODUCTS:
        photo = renderer.prepare_photo(filename, box, collage)
        name = f"{number:02d}.jpg"
        status = "approved" if is_approved(number) else "pending"
        renderer.render_numbered(photo, number, title, INDEX / name)
        entries.append({"index_file": name, "number": number, "cake_type": title,
                        "status": status, "source": filename, "crop_xyxy": box})
        photos[number] = photo
    order = {category["label"]: category["order"] for category in CATEGORIES}
    entries.sort(key=lambda entry: (order.get(entry["cake_type"], 999), entry["number"]))
    (INDEX / "manifest.json").write_text(json.dumps(entries, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    pending = [entry["index_file"] for entry in entries if entry["status"] == "pending"]
    confirmation = ("Awaiting confirmation: " + ", ".join(pending) + ".") if pending else "All listed files are confirmed for the final list."
    lines = ["# Photo index — confirm using filenames", "",
             "Workflow: **raw → index → your confirmation → final ads**.", "",
             confirmation, "Pending uploads never reach final ads. Originals stay in `../raw/`.",
             "Files below follow the user-confirmed cake-type order.", "",
             "| Index file | Cake type | Status |", "| --- | --- | --- |"]
    for entry in entries:
        lines.append(f"| {entry['index_file']} | {entry['cake_type']} | {STATUS_LABELS[entry['status']]} |")
    lines += ["", "Excluded index filenames (never reused): "
              + ", ".join(f"{n:02d}.jpg" for n in sorted(EXCLUDED_NUMBERS)) + ".", "",
              "Use index filenames to request removals, replacements, or type corrections.",
              "07.jpg was permanently retired after the latest quality review.", ""]
    (INDEX / "INDEX.md").write_text("\n".join(lines), encoding="utf-8")
    # Flat visual review sheet mirrors numeric filenames, independent of type grouping.
    c = renderer.Canvas(1800, 190+math.ceil(len(entries)/5)*340+42)
    c.text((60, 42), "Danh mục bánh • Theo loại", 54, family="serif")
    approved = sum(entry["status"] == "approved" for entry in entries)
    c.text((64, 128), f"{len(entries)} ảnh • Đã duyệt: {approved} • Chờ xác nhận: {len(entries)-approved}",
           28, renderer.MUTED)
    for i, entry in enumerate(entries):
        x, y = 64+(i%5)*344, 190+(i//5)*340
        c.rounded((x,y,x+320,y+238),12,"#F1E9E2","#DECABC",1)
        photo = ImageOps.contain(photos[entry["number"]], (312*renderer.SCALE,230*renderer.SCALE),
                                 Image.Resampling.LANCZOS)
        c.image.paste(photo,(x*renderer.SCALE+(320*renderer.SCALE-photo.width)//2,
                            y*renderer.SCALE+(238*renderer.SCALE-photo.height)//2))
        c.text((x,y+252),entry["index_file"],25)
        c.text((x+320,y+255),STATUS_LABELS[entry["status"]],19,renderer.MUTED,anchor="rt")
        c.text((x,y+288),entry["cake_type"],20)
    c.save(INDEX / "catalog.jpg")
    print(f"Created {len(entries)} index previews in {INDEX}; pending files are not final ads.")
    return entries


if __name__ == "__main__":
    build_index()
