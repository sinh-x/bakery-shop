#!/usr/bin/env python3
"""Prune rejected ads-library selections, refresh catalogs, and remove old ZIPs.

Raw uploads are never deleted. Retained plain photos stay unchanged; ad labels,
numbered exports, and catalogs are refreshed to match the confirmed final list.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import create_womens_day_ads as renderer
from ad_library_policy import EXCLUDED_NUMBERS, is_excluded
from group_womens_day_photos import group_output

ROOT = Path(__file__).resolve().parent


def prune(folder: Path):
    manifest_path = folder / "manifest.json"
    if not manifest_path.exists():
        return []
    entries = json.loads(manifest_path.read_text(encoding="utf-8"))
    removed = set(EXCLUDED_NUMBERS)
    retained = []
    for entry in entries:
        if not entry["source"].startswith("raw/"):
            entry["source"] = f"raw/{entry['source']}"
        if is_excluded(entry["number"], ROOT / entry["source"], entry["crop_xyxy"]):
            removed.add(entry["number"])
        else:
            retained.append(entry)
    deleted = []
    for path in folder.rglob("*"):
        if not path.is_file():
            continue
        match = re.match(r"mau-(\d+)(?:\D|$)", path.name)
        if (match and int(match[1]) in removed) or path.suffix.lower() == ".zip":
            path.unlink()
            deleted.append(str(path.relative_to(ROOT)))
    manifest_path.write_text(json.dumps(retained, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(f"{folder.name}: removed {len(deleted)} generated files; retained {len(retained)} selections.")
    return retained


def main():
    legacy = ROOT / "processed"
    entries = prune(legacy)
    if entries:
        active = {entry["number"] for entry in entries}
        previous = renderer.OUT
        renderer.OUT = legacy
        try:
            renderer.render_catalog([product for product in renderer.PRODUCTS if product[0] in active])
        finally:
            renderer.OUT = previous
        (legacy / "README.md").write_text(f"""# Legacy prepared images

This older, non-AI-enhanced set retains {len(entries)} selections for reference.
Use `../processed-enhanced/` for the latest category-labelled ads and grouped library.
Rejected numbers {', '.join(str(n) for n in sorted(EXCLUDED_NUMBERS))} are removed.
Their original uploads remain read-only references. The obsolete ZIP was removed.

Folders: `cleaned/`, `ads/`, `numbered/`. `manifest.json` and `catalog-20-10.jpg`
contain only retained selections. Do not reuse retired numbers or create ZIPs.
The authoritative exclusion registry is `../../library-exclusions.json`.

## Environment

Scripts require Python 3.12+, Pillow, numpy, opencv-python-headless, fontconfig,
and Noto Sans/Noto Serif fonts with Vietnamese glyphs. AI enhancement additionally
requires onnxruntime and the model documented in the enhanced folder.

```sh
uv venv /tmp/womens-day-image-env --python python
uv pip install --python /tmp/womens-day-image-env/bin/python \\
  pillow numpy opencv-python-headless onnxruntime
```

On this NixOS host, wheel imports also require GCC and zlib on `LD_LIBRARY_PATH`:

```sh
export LD_LIBRARY_PATH=/nix/store/j2kgllgds4w7na8zqv1msi0mpvpjxda8-gcc-15.2.0-lib/lib:/nix/store/ri9paa3mri4kqakljak8ldvbcp7lpmif-zlib-1.3.1/lib:$LD_LIBRARY_PATH
```

These library paths are host-specific.
""", encoding="utf-8")
    enhanced = ROOT / "processed-enhanced"
    retained = prune(enhanced)
    # Only approved additions may reach final ads; pending uploads stay in index/.
    if {entry["number"] for entry in retained} != {product[0] for product in renderer.PRODUCTS}:
        from append_womens_day_photos import main as append_new
        append_new(refresh_groups=False)
    # Refresh documentation counts without rerunning inference or changing photos.
    from enhance_womens_day_photos import write_readme
    write_readme()
    group_output(enhanced, rerender=True)
    print("Permanent library exclusions applied. Original uploads retained. No ZIP.")


if __name__ == "__main__":
    main()
