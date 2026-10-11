#!/usr/bin/env python3
"""Export the confirmed shortened cake subset with numeric-only photo labels."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

import create_catalog_video as design
import create_womens_day_ads as art

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "shorten-processed-images"
SELECTED_NUMBERS = (2, 3, 4, 5, 9, 12, 21, 26, 30, 31)
COPY = {"instruction": "Nhắn tin kèm số ảnh để đặt bánh"}


def subset_sources():
    categories, photos, sources = design.approved_sources()
    wanted = set(SELECTED_NUMBERS)
    if not wanted <= set(photos):
        raise ValueError(f"Selected indexes are missing, pending, or excluded: {sorted(wanted-set(photos))}")
    selected_categories = []
    for category in categories:
        numbers = [n for n in category["numbers"] if n in wanted]
        if numbers:
            selected_categories.append({**category, "numbers": numbers})
    return (selected_categories, {n: photos[n] for n in SELECTED_NUMBERS},
            [s for s in sources if s["number"] in wanted])


def background(height):
    c = art.Canvas(1080, height)
    c.ellipse((-340, height-450, 590, height+420), "#F6E5DF")
    c.ellipse((815, -190, 1310, 360), "#FAEBE3")
    art.floral_corner(c, 1102, 308, -1)
    art.floral_corner(c, -135, height-130)
    return c


def header(c, label):
    design.brand_stamp(c)
    design.centered(c, 155, art.COPY["date"], 23, "sans", art.MUTED)
    design.centered(c, 207, label, 44)
    design.centered(c, 282, art.COPY["headline_1"]+" "+art.COPY["headline_2"], 25, "italic")
    c.line([(110, 326), (970, 326)], "#D4B69D", 1)


def save(c, path, height):
    image = c.image.resize((1080, height), Image.Resampling.LANCZOS)
    image.save(path, quality=97, subsampling=0)
    return {"file": str(path.relative_to(OUT)), "width": 1080, "height": height,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def render_ad(photo, number, category, destination):
    c = background(1350)
    header(c, category["label"])
    design.place(c, photo, number, 540, 790, 960, 860, 0, label_prefix="", index_style="circle")
    design.centered(c, 1270, COPY["instruction"], 29, "sans")
    return save(c, destination, 1350)


def collage_layouts(count):
    if count == 1:
        return [(540, 1050, 900, 1170, -0.8)]
    rows = {2: (1, 1), 3: (1, 2), 4: (2, 2), 5: (2, 3), 6: (3, 3),
            7: (2, 3, 2), 8: (2, 3, 3), 9: (3, 3, 3)}.get(count)
    if rows is None:
        raise ValueError("Split categories larger than nine photos into additional collage pages.")
    centers = {1: (540,), 2: (290, 790), 3: (210, 540, 870)}
    widths = {1: 900, 2: 455, 3: 300}
    angles = {1: (-0.8,), 2: (-1.0, 1.0), 3: (-0.7, 0, 0.7)}
    ys, height = ((595, 1055, 1515), 435) if len(rows) == 3 else ((700, 1400), 650)
    return [(x, y, widths[size], height, angle) for size, y in zip(rows, ys, strict=True)
            for x, angle in zip(centers[size], angles[size], strict=True)]


def render_collage(category, photos, destination):
    c = background(1920)
    header(c, category["label"])
    numbers = category["numbers"]
    for number, layout in zip(numbers, collage_layouts(len(numbers)), strict=True):
        design.place(c, photos[number], number, *layout, label_prefix="", index_style="circle")
    design.centered(c, 1814, COPY["instruction"], 29, "sans")
    return save(c, destination, 1920)


def main():
    categories, photos, sources = subset_sources()
    for folder in (OUT / "ads", OUT / "collages"):
        folder.mkdir(parents=True, exist_ok=True)
    ads, collages = [], []
    by_number = {n: c for c in categories for n in c["numbers"]}
    for number in SELECTED_NUMBERS:
        category = by_number[number]
        record = render_ad(photos[number], number, category, OUT / "ads" / f"{number:02d}.jpg")
        ads.append({"number": number, "visible_index": f"{number:02d}",
                    "cake_type": category["label"], **record})
    for category in categories:
        record = render_collage(category, photos, OUT / "collages" / f"{category['folder']}.jpg")
        collages.append({"cake_type": category["label"], "category_order": category["order"],
                         "numbers": category["numbers"], **record})
    manifest = {"date": art.COPY["date"], "bakery_name": design.VIDEO_COPY["brand"],
                "selected_numbers": list(SELECTED_NUMBERS), "index_label_prefix": "",
                "index_badge_shape": "circle", "index_badge_position": "top-right",
                "instruction": COPY["instruction"], "photo_sources": sources,
                "individual_ads": ads, "category_collages": collages}
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    lines = ["# Shortened cake ad collection", "",
             f"**{design.VIDEO_COPY['brand']} · {art.COPY['date']}**", "",
             f"Only the {len(SELECTED_NUMBERS)} confirmed selections are included. The number beside each cake",
             "is its original index; it is never reset or renumbered. Labels contain only",
             "digits (02, 03, …), without the word ‘Mẫu’. Customer instructions also avoid it.",
             "Each number is a small circle in the photo card's upper-right corner. No bottom",
             "number strip is reserved: photos fill the card and have more room.", "",
             "## Category collages — original type order", "",
             "| Cake type | Photo indexes | Collage |", "|---|---|---|"]
    for record in collages:
        indexes = ", ".join(f"{n:02d}" for n in record["numbers"])
        lines.append(f"| {record['cake_type']} | {indexes} | [{Path(record['file']).name}]({record['file']}) |")
    lines.extend(["", "Collages: **1080 × 1920**. Each photograph and numeric label share a card.",
                  "Category filename prefixes (02, 03, 05) are category positions, not photo IDs.",
                  "", "## Individual ads — 1080 × 1350", ""])
    for record in ads:
        lines.append(f"- [{record['visible_index']}.jpg]({record['file']}) — {record['cake_type']}")
    lines.extend(["", "The official logo lettering and full campaign date appear on every image.",
                  "All product photos are fitted without cropping. Existing ads, video, raw",
                  "uploads, and library approvals/exclusions are unchanged. No ZIP is created.",
                  "", "Rerun after approval/exclusion or campaign-date changes. The generator rejects",
                  "missing, pending, or excluded selected IDs instead of silently publishing them.",
                  "", "Reproduce with the existing image environment and NixOS library setup:", "",
                  "```sh", "/tmp/womens-day-image-env/bin/python ads/20261020/create_shortened_ads.py", "```", ""])
    (OUT / "INDEX.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"Created {len(ads)} numeric-only ads and {len(collages)} category collages in {OUT}.")


if __name__ == "__main__":
    main()
