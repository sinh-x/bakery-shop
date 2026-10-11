#!/usr/bin/env python3
"""Apply confirmed cake types to existing exports; no AI rerun and no ZIP."""
from __future__ import annotations

import argparse
import json
import math
import shutil
from pathlib import Path

from PIL import Image, ImageOps

import create_womens_day_ads as renderer
from cake_categories import CATEGORIES, PENDING_LABEL, PENDING_CONFIRMATION_LABEL, TYPE_FOR_NUMBER

ROOT = Path(__file__).resolve().parent
DEFAULT_OUT = ROOT / "processed-enhanced"


def catalog(out: Path, categories, destination: Path):
    occupied = [category for category in categories if category["numbers"]]
    pending = [category for category in categories if not category["numbers"]]
    height = 190 + sum(76 + math.ceil(len(c["numbers"])/5)*288 + 32 for c in occupied)
    height += len(pending)*116 + 42
    c = renderer.Canvas(1800, height)
    c.text((60, 42), "Gửi nàng điều ngọt ngào", 64, family="serif")
    c.text((64, 131), f"Bộ sưu tập {renderer.COPY['date']} • Chọn bánh theo loại", 30, renderer.MUTED)
    y = 190
    for category in occupied:
        c.text((64, y), category["label"], 40, family="serif")
        c.text((1736, y+12), f"{len(category['numbers'])} mẫu", 24, renderer.MUTED, anchor="rt")
        c.line([(64, y+59), (1736, y+59)], "#DECABC", 1)
        y += 76
        for i, number in enumerate(category["numbers"]):
            x, top = 64+(i%5)*344, y+(i//5)*288
            c.rounded((x, top, x+320, top+230), 12, "#F1E9E2", "#DECABC", 1)
            with Image.open(out / "cleaned" / f"mau-{number:02d}.png") as photo:
                fitted = ImageOps.contain(photo, (312*renderer.SCALE, 222*renderer.SCALE),
                                          Image.Resampling.LANCZOS)
            c.image.paste(fitted, (x*renderer.SCALE+(320*renderer.SCALE-fitted.width)//2,
                                  top*renderer.SCALE+(230*renderer.SCALE-fitted.height)//2))
            c.text((x+160, top+244), f"MẪU {number}", 26, anchor="mt")
        y += math.ceil(len(category["numbers"])/5)*288 + 32
    for category in pending:
        c.rounded((64, y, 1736, y+96), 16, "#F5E4DE", "#DECABC", 1)
        c.text((90, y+25), category["label"], 34, family="serif")
        label = PENDING_CONFIRMATION_LABEL if category.get("pending_numbers") else PENDING_LABEL
        c.text((1708, y+32), label, 24, renderer.MUTED, anchor="rt")
        y += 116
    c.save(destination)


def export_final_catalogs(out: Path, categories):
    folder = out.parent / "final-catalogs"
    folder.mkdir(parents=True, exist_ok=True)
    records = [{"file": "00-all-types.jpg", "label": "Tất cả loại bánh", "count": sum(
        len(category["numbers"]) for category in categories), "source": "catalog-20-10.jpg"}]
    for category in sorted(categories, key=lambda c: c["order"]):
        if category["numbers"]:
            records.append({"file": f"{category['folder']}.jpg", "label": category["label"],
                            "count": len(category["numbers"]),
                            "source": f"by-type/{category['folder']}/catalog.jpg"})
    previous = folder / "manifest.json"
    allowed = {record["file"] for record in records}
    if previous.exists():
        for record in json.loads(previous.read_text(encoding="utf-8")):
            name = record["file"]
            if Path(name).name == name and name not in allowed:
                (folder / name).unlink(missing_ok=True)
    for record in records:
        record["campaign_date"] = renderer.COPY["date"]
        shutil.copy2(out / record["source"], folder / record["file"])
    previous.write_text(json.dumps(records, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    lines = ["# Final catalog images — confirmed order", "",
             f"Campaign date: **{renderer.COPY['date']}**.", "",
             "00 is the all-types overview; 01–07 are category positions, not photo indexes.",
             "Photo index numbers inside the catalogs are unchanged. No ZIP.", "",
             "| Catalog image | Cake type | Photo selections |", "| --- | --- | --- |"]
    lines += [f"| [{r['file']}]({r['file']}) | {r['label']} | {r['count']} |" for r in records]
    (folder / "INDEX.md").write_text("\n".join(lines)+"\n", encoding="utf-8")
    print(f"Exported {len(records)} ordered catalog images to {folder}")


def write_index(out: Path, entries):
    from build_photo_index import build_index
    build_index()
    for entry in entries:
        entry["index_photo"] = f"../index/{entry['number']:02d}.jpg"


def group_output(out: Path, rerender: bool = True):
    manifest_path = out / "manifest.json"
    entries = json.loads(manifest_path.read_text(encoding="utf-8"))
    numbers = [entry["number"] for entry in entries]
    active = {product[0] for product in renderer.PRODUCTS}
    registered = {product[0] for product in renderer.REGISTERED_PRODUCTS}
    categories = tuple({**category,
                        "numbers": tuple(n for n in category["numbers"] if n in active),
                        "pending_numbers": tuple(n for n in category["numbers"] if n in registered-active)}
                       for category in CATEGORIES)
    if sorted(numbers) != sorted(active) or len(set(numbers)) != len(numbers):
        raise ValueError("Photo numbers must match the user-confirmed cake groups exactly.")
    for entry in entries:
        number = entry["number"]
        category = TYPE_FOR_NUMBER[number]
        entry["title"] = category["label"]
        entry["cake_type"] = category["label"]
        entry["group"] = category["slug"]
        if rerender:
            with Image.open(out / "cleaned" / f"mau-{number:02d}.png") as photo:
                renderer.render_ad(photo, number, category["label"], out / entry["ad"])
                renderer.render_numbered(photo, number, category["label"], out / entry["numbered_photo"])
        for kind, field in (("ads", "ad"), ("numbered", "numbered_photo"), ("photos", "photo")):
            source = out / entry[field]
            destination = out / "by-type" / category["folder"] / kind / source.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            entry[f"grouped_{field}"] = str(destination.relative_to(out))
    # Remove only obsolete folders recorded as generated groups, not arbitrary folders.
    types_path = out / "cake-types.json"
    if types_path.exists():
        old_groups = json.loads(types_path.read_text(encoding="utf-8"))
        desired = {category["folder"] for category in categories}
        for old in old_groups:
            old_folder = old.get("folder", old["slug"])
            if old_folder not in desired:
                path = out / "by-type" / old_folder
                if path.is_dir():
                    shutil.rmtree(path)
    for category in categories:
        folder = out / "by-type" / category["folder"]
        folder.mkdir(parents=True, exist_ok=True)
        if category["numbers"]:
            catalog(out, [category], folder / "catalog.jpg")
            content = (f"# {category['label']}\n\n"
                       f"Mẫu: {', '.join(str(n) for n in category['numbers'])}.\n\n"
                       f"- `ads/`: ảnh quảng cáo {renderer.COPY['date']}.\n"
                       "- `numbered/`: ảnh có số mẫu.\n"
                       "- `photos/`: ảnh không thêm chữ.\n"
                       "- `catalog.jpg`: danh mục của loại bánh này.\n")
        else:
            label = PENDING_CONFIRMATION_LABEL if category["pending_numbers"] else PENDING_LABEL
            pending = ', '.join(f"{n:02d}.jpg" for n in category['pending_numbers'])
            content = (f"# {category['label']}\n\n{label}.\n\n"
                       f"Ảnh xem trước trong index/: {pending or 'chưa có'}.\n"
                       "Chỉ tạo quảng cáo sau khi được xác nhận theo tên file index.\n")
        (folder / "README.md").write_text(content, encoding="utf-8")
    catalog(out, categories, out / "catalog-20-10.jpg")
    write_index(out, entries)
    manifest_path.write_text(json.dumps(entries, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    groups = [{**category, "status": ("ready" if category["numbers"] else
                                      "awaiting_confirmation" if category["pending_numbers"] else "awaiting_photos")}
              for category in categories]
    (out / "cake-types.json").write_text(json.dumps(groups, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    export_final_catalogs(out, groups)
    final_lines = ["# Final cake list", "", f"Campaign date: **{renderer.COPY['date']}**.", "",
                   "Confirmed category order. Communicate using index filenames.",
                   "Originals: `raw/` · numbered photos: `index/` · ads: `processed-enhanced/by-type/`.",
                   "Ordered catalog images: `final-catalogs/` (00 overview, 01–07 cake types).", ""]
    for category in categories:
        final_lines += [f"## {category['order']}. {category['label']}", "",
                        ", ".join(f"{n:02d}.jpg" for n in category["numbers"]) or PENDING_LABEL, ""]
    final_lines += ["Permanent exclusions are stored by index filename in `../library-exclusions.json`.", ""]
    (out.parent / "final-list.md").write_text("\n".join(final_lines), encoding="utf-8")
    readme = out / "README.md"
    content = readme.read_text(encoding="utf-8").split("\n## Cake types\n")[0]
    content += "\n## Cake types\n\nIndividual descriptive titles are replaced by the confirmed cake types.\n\n"
    for category in categories:
        selection = ", ".join(f"{n:02d}.jpg" for n in category["numbers"]) or PENDING_LABEL
        if category["pending_numbers"]:
            selection += " · " + PENDING_CONFIRMATION_LABEL + ": " + ", ".join(
                f"{n:02d}.jpg" for n in category["pending_numbers"])
        content += f"- **{category['label']}**: {selection} — `by-type/{category['folder']}/`\n"
    content += ("\nEach populated type folder contains its own catalog and copies of the ads,\n"
                "numbered photos, and unlabeled photos. Stable photo numbers are retained.\n"
                "The flat `../index/` folder uses filenames such as `01.jpg` and `21.jpg`.\n"
                "Raw uploads become index previews first; pending files require index-based\n"
                "confirmation in `../index-status.json` before final ad generation.\n"
                "Original uploads are kept in `../raw/`.\n"
                "`catalog-20-10.jpg` is grouped by type. Any category without photos is\n"
                "marked as awaiting photos. No placeholder product image or ZIP is generated.\n\n"
                "To regroup/relabel existing enhanced files without rerunning AI:\n\n"
                "```sh\n/tmp/womens-day-image-env/bin/python "
                "ads/20261020/group_womens_day_photos.py\n```\n")
    from ad_library_policy import EXCLUDED_NUMBERS, POLICY, COLLECTION
    content += ("\n## Permanent library exclusions\n\n"
                f"Removed numbers: {', '.join(str(n) for n in sorted(EXCLUDED_NUMBERS))}. "
                "These numbers remain reserved and must never be reused.\n\n"
                "The authoritative shared registry is `../../library-exclusions.json`. "
                "All preparation, enhancement, append, and grouping paths enforce it. "
                "Known matching files and decoded images are also blocked if renamed. "
                "Other collage tiles are unaffected.\n\n"
                f"Next unused number: **{POLICY['collections'][COLLECTION]['next_number']}**. "
                "Use the next unused ID when registering genuinely new photos.\n")
    readme.write_text(content, encoding="utf-8")
    print(f"Grouped {len(entries)} photos by confirmed cake type in {out / 'by-type'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--catalogs-only", action="store_true", help="Copy final catalog images without rerendering")
    args = parser.parse_args()
    if args.catalogs_only:
        export_final_catalogs(args.output, json.loads((args.output / "cake-types.json").read_text(encoding="utf-8")))
    else:
        group_output(args.output)


if __name__ == "__main__":
    main()
