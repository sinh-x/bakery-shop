#!/usr/bin/env python3
"""Enhance low-resolution photos, retaining previous exports. Never creates a ZIP.

Needs the existing renderer's dependencies plus onnxruntime. Supply --model with
Real-ESRGAN-General-x4v3_float/onnx/model.onnx (see the output README).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps

import create_womens_day_ads as renderer

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "processed"
OUT = ROOT / "processed-enhanced"
MODEL_URL = "https://huggingface.co/tamnvcc/Real-ESRGAN-General-x4v3_float/resolve/main/onnx/model.onnx"
MODEL_HASH = "83adcbbe5f96dc323c839abef6ca540e719bbdbd4c1bc91ffc7526f83073bedf"
# Collage photos and the 540-pixel-wide standalone photo benefit from reconstruction.
STRENGTHS = {**{i: 0.85 for i in range(1, 8)}, 14: 0.70, 28: 0.70}


def session(model: Path) -> ort.InferenceSession:
    if hashlib.sha256(model.read_bytes()).hexdigest() != MODEL_HASH:
        raise ValueError("Model hash mismatch; use the model specified in the README.")
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    result = ort.InferenceSession(str(model), sess_options=options,
                                 providers=["CPUExecutionProvider"])
    if result.get_inputs()[0].shape != [1, 3, 128, 128]:
        raise ValueError("Expected a 128×128 RGB model with 4× output.")
    return result


def upscale(photo: Image.Image, model: ort.InferenceSession, strength: float) -> Image.Image:
    rgb = np.asarray(photo.convert("RGB"))
    height, width = rgb.shape[:2]
    tile, halo, factor = 128, 40, 4
    core = tile - halo * 2
    # Wide reflected halos keep tile boundaries out of the model's useful result.
    padded = np.pad(rgb, ((halo, halo+tile), (halo, halo+tile), (0, 0)), mode="reflect")
    output = np.empty((height*factor, width*factor, 3), dtype=np.uint8)
    input_name = model.get_inputs()[0].name
    for y in range(0, height, core):
        for x in range(0, width, core):
            patch = padded[y:y+tile, x:x+tile].astype(np.float32) / 255
            tensor = np.ascontiguousarray(patch.transpose(2, 0, 1)[None])
            prediction = model.run(None, {input_name: tensor})[0]
            if prediction.shape != (1, 3, tile*factor, tile*factor):
                raise ValueError(f"Unexpected model output: {prediction.shape}")
            reconstructed = prediction[0].transpose(1, 2, 0)
            h, w = min(core, height-y)*factor, min(core, width-x)*factor
            border = halo * factor
            pixels = reconstructed[border:border+h, border:border+w]
            output[y*factor:y*factor+h, x*factor:x*factor+w] = np.rint(
                pixels.clip(0, 1)*255
            ).astype(np.uint8)
    neural = Image.fromarray(output)
    original = photo.resize(neural.size, Image.Resampling.LANCZOS)
    # Retain some original texture rather than using aggressive full-strength output.
    return Image.blend(original, neural, strength)


def comparison(before: Image.Image, after: Image.Image, number: int, destination: Path):
    c = renderer.Canvas(2160, 1170)
    c.text((64, 35), f"Mẫu {number} • So sánh chất lượng ảnh", 46, family="serif")
    c.text((64, 112), "Trước • Phóng to thông thường", 30, renderer.MUTED)
    c.text((1120, 112), "Sau • Tăng độ nét bằng AI", 30, renderer.MUTED)
    for photo, box in [(before, (40, 180, 1060, 1130)), (after, (1100, 180, 2120, 1130))]:
        x0, y0, x1, y1 = box
        fitted = ImageOps.contain(photo, ((x1-x0)*renderer.SCALE, (y1-y0)*renderer.SCALE),
                                  Image.Resampling.LANCZOS)
        x = x0*renderer.SCALE + ((x1-x0)*renderer.SCALE-fitted.width)//2
        y = y0*renderer.SCALE + ((y1-y0)*renderer.SCALE-fitted.height)//2
        c.image.paste(fitted, (x, y))
    c.save(destination)


def sample(model: ort.InferenceSession):
    with Image.open(SOURCE / "cleaned" / "mau-04.png") as photo:
        result = upscale(photo, model, STRENGTHS[4])
        result.save("/tmp/womens-day-enhancement-sample.png")
        comparison(photo, result, 4, Path("/tmp/womens-day-enhancement-comparison.jpg"))
    print("Sample: /tmp/womens-day-enhancement-comparison.jpg", flush=True)


def enhance(model: ort.InferenceSession):
    for folder in ("cleaned", "photos", "ads", "numbered", "comparisons"):
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    original_entries = json.loads((SOURCE / "manifest.json").read_text(encoding="utf-8"))
    original_by_number = {entry["number"]: entry for entry in original_entries}
    manifest = []
    for number, filename, box, title in renderer.PRODUCTS:
        started = time.monotonic()
        if number in original_by_number:
            entry = original_by_number[number]
            with Image.open(SOURCE / "cleaned" / f"mau-{number:02d}.png") as photo:
                before = photo.convert("RGB")
        else:
            # Newly registered photos need not mutate the previous processed/ set.
            before = renderer.prepare_photo(filename, box)
            entry = renderer.source_entry(number, filename, box, title, before)
        manifest.append(entry)
        strength = STRENGTHS.get(number)
        result = upscale(before, model, strength) if strength is not None else before.copy()
        result.save(OUT / "cleaned" / f"mau-{number:02d}.png")
        result.save(OUT / "photos" / f"mau-{number:02d}.jpg", quality=97, subsampling=0)
        if number in (4, 6):
            comparison(before, result, number, OUT / "comparisons" / f"mau-{number:02d}-before-after.jpg")
        entry["pre_enhancement_size"] = list(before.size)
        entry["cleaned_size"] = list(result.size)
        entry["photo"] = f"photos/mau-{number:02d}.jpg"
        entry["enhancement"] = {
            "method": "neural 4× super-resolution" if strength is not None else "unchanged",
            "scale": 4 if strength is not None else 1,
            "neural_blend": strength,
            "model_url": MODEL_URL if strength is not None else None,
            "model_sha256": MODEL_HASH if strength is not None else None,
        }
        print(f"Mẫu {number}: {before.size} → {result.size}, {time.monotonic()-started:.1f}s", flush=True)
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    renderer.OUT = OUT
    for number, _source, _crop, title in renderer.PRODUCTS:
        with Image.open(OUT / "cleaned" / f"mau-{number:02d}.png") as photo:
            renderer.render_ad(photo, number, title, OUT / "ads" / f"mau-{number:02d}.jpg")
            renderer.render_numbered(photo, number, title, OUT / "numbered" / f"mau-{number:02d}.jpg")
    write_readme()
    # Share the confirmed cake types with the fast relabel/regroup command.
    from group_womens_day_photos import group_output
    group_output(OUT, rerender=False)
    print(f"Enhanced images and regenerated ads: {OUT} (no ZIP)", flush=True)


def write_readme():
    (OUT / "README.md").write_text(f"""# Enhanced Women's Day photos — 20/10

- `photos/`: {len(renderer.PRODUCTS)} full-resolution JPG photos without added labels, for further editing.
- `ads/`: {len(renderer.PRODUCTS)} regenerated 1080 × 1350 Women's Day ads, with the same numbers and design.
- `numbered/`: {len(renderer.PRODUCTS)} photo exports with clean numbered footers.
- `catalog-20-10.jpg`: overview of all {len(renderer.PRODUCTS)} regenerated ads.
- `comparisons/`: before/after examples for retained photos.
- `cleaned/`: lossless PNG versions used by the renderer.
- `manifest.json`: source mappings, sizes, enhancement settings, and model checksum.

Photos **{', '.join(str(n) for n, *_ in renderer.PRODUCTS if n in STRENGTHS)}**
were enhanced using 4× neural super-resolution blended with the enlarged source.
Other retained photos use the original resolution with small natural color
adjustments. Permanently excluded selections are never regenerated.
The wide tile overlap avoids visible stitching boundaries. Output dimensions
are four times larger in each direction for enhanced photos; this is not a
claim that all missing photographic detail has been recovered.

AI enhancement reduces compression noise and reconstructs cleaner edges, but
very small lettering may remain ambiguous or be reconstructed inaccurately.
Check fine decorations and text before publishing. Source watermarks are not
intentionally removed. Original JPGs are preserved for reference; excluded
generated files are pruned under the shared ads-library policy. No ZIP is generated.

## Reproduce

Dependencies: those of `../create_womens_day_ads.py`, plus `onnxruntime`.
Fonts and the same NixOS library setup described in `../processed/README.md`
are also required. Run from the repository root:

```sh
uv pip install --python /tmp/womens-day-image-env/bin/python onnxruntime
mkdir -p /tmp/womens-day-models
curl -L --fail -o /tmp/womens-day-models/realesr-general-x4v3.onnx '{MODEL_URL}'
/tmp/womens-day-image-env/bin/python ads/20261020/enhance_womens_day_photos.py \\
  --model /tmp/womens-day-models/realesr-general-x4v3.onnx all
```

Model SHA-256: `{MODEL_HASH}`. The script checks this before inference.
Use `sample` instead of `all` to generate a comparison in `/tmp/` first.
""", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("sample", "all"), default="all", nargs="?")
    parser.add_argument("--model", required=True, type=Path)
    args = parser.parse_args()
    model = session(args.model)
    sample(model) if args.stage == "sample" else enhance(model)


if __name__ == "__main__":
    main()
