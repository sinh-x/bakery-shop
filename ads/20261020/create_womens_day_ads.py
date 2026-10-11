#!/usr/bin/env python3
"""Prepare source photos and render the 20/10 catalog. Originals are read-only.

Dependencies: Pillow, numpy, opencv-python-headless. See processed/README.md.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
from functools import lru_cache
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

from ad_library_policy import is_approved, is_excluded
from cake_categories import TYPE_FOR_NUMBER, PENDING_CONFIRMATION_LABEL

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
OUT = ROOT / "processed"
PREFIX = "signal-2026-10-11-08-11-45-184"
NEW_PREFIX = "signal-2026-10-11-08-35-00-021"
COLLAGE = f"{PREFIX}_007.jpg"
# Rectangles are measured against the original collage, not the cropped tiles.
# The color masks target ONLY the handwritten pen and numeral in background areas.
MARKS = [
    ((234, 19, 315, 96), "red"), ((264, 48, 290, 86), "green"),
    ((839, 19, 977, 158), "red"), ((886, 53, 928, 106), "cyan"),
    ((422, 459, 531, 583), "red"), ((457, 480, 494, 527), "green"),
    ((849, 459, 978, 575), "red"), ((899, 485, 938, 529), "green"),
    ((266, 807, 374, 899), "red"), ((303, 829, 337, 873), "green"),
    ((604, 910, 681, 1008), "red"), ((631, 956, 662, 990), "cyan"),
    ((899, 807, 976, 885), "red"), ((922, 823, 952, 861), "green"),
]
PRODUCT_SOURCES = [
    (1, COLLAGE, (1, 120, 324, 449)),
    (2, COLLAGE, (335, 18, 982, 449)),
    (3, COLLAGE, (1, 459, 533, 797)),
    (4, COLLAGE, (545, 459, 982, 797)),
    (5, COLLAGE, (1, 871, 371, 1201)),
    (6, COLLAGE, (382, 887, 680, 1201)),
    (7, COLLAGE, (690, 894, 982, 1178)),
    (8, f"{PREFIX}.jpg", None),
    (9, f"{PREFIX}_002.jpg", None),
    (10, f"{PREFIX}_003.jpg", None),
    (11, f"{PREFIX}_004.jpg", None),
    (12, f"{PREFIX}_005.jpg", None),
    (13, f"{PREFIX}_006.jpg", None),
    (14, f"{PREFIX}_008.jpg", None),
    (15, f"{PREFIX}_009.jpg", None),
    (16, f"{NEW_PREFIX}.jpg", None),
    (17, f"{NEW_PREFIX}_002.jpg", None),
    (18, f"{NEW_PREFIX}_003.jpg", None),
    (19, f"{NEW_PREFIX}_004.jpg", None),
    (20, f"{NEW_PREFIX}_005.jpg", None),
    (21, "IMG_2849.jpg", None),
    (22, "IMG_2646.jpg", None),
    (23, "IMG_2643.jpg", None),
    (24, "IMG_2620.jpg", None),
    (25, "IMG_2594.jpg", None),
    (26, "IMG_2574.jpg", None),
    (27, "1000005124.jpg", None),
    (28, "1000001780.jpg", None),
    (29, "1000001610.jpg", None),
    (30, "1000000567.jpg", None),
    (31, "signal-2026-10-11-105803.jpeg", None),
]
# Keep PRODUCT_SOURCES as the stable ID ledger, including permanently retired IDs.
REGISTERED_PRODUCTS = [(number, f"raw/{source}", box,
                        TYPE_FOR_NUMBER.get(number, {"label": PENDING_CONFIRMATION_LABEL})["label"])
                       for number, source, box in PRODUCT_SOURCES
                       if not is_excluded(number, RAW / source, box)]
# Final generation requires approval AND a confirmed type; unknown uploads are previews only.
PRODUCTS = [product for product in REGISTERED_PRODUCTS
            if is_approved(product[0]) and product[0] in TYPE_FOR_NUMBER]


def clean_collage(image: Image.Image) -> Image.Image:
    rgb = np.array(image)
    mask = np.zeros(rgb.shape[:2], dtype=np.uint8)
    for (x0, y0, x1, y1), color in MARKS:
        patch = rgb[y0:y1, x0:x1].astype(np.float32)
        r, g, b = patch[:, :, 0], patch[:, :, 1], patch[:, :, 2]
        if color == "red":
            selected = (r > 110) & (r > g * 1.35) & (r > b * 1.25)
        elif color == "green":
            selected = (g > 140) & (g > r * 1.18) & (g > b * 1.13)
        else:
            selected = (g > 145) & (b > 130) & (g > r * 1.2) & (b > r * 1.2)
        mask[y0:y1, x0:x1] |= selected.astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((5, 5), np.uint8))
    result = cv2.inpaint(rgb, mask, 5, cv2.INPAINT_TELEA)
    return Image.fromarray(result)


def prepare_photo(filename, box=None, collage=None):
    with Image.open(ROOT / filename) as source:
        photo = ImageOps.exif_transpose(source).convert("RGB")
    if box:
        if collage is None:
            collage = clean_collage(photo)
        photo = collage.crop(box)
    # Small natural adjustments, without replacing the actual cake design.
    photo = ImageEnhance.Brightness(photo).enhance(1.025)
    photo = ImageEnhance.Contrast(photo).enhance(1.025)
    return ImageEnhance.Color(photo).enhance(1.015)


def source_entry(number, filename, box, title, photo):
    return {
        "number": number, "title": title, "source": filename,
        "source_sha256": hashlib.sha256((ROOT / filename).read_bytes()).hexdigest(),
        "crop_xyxy": box, "cleaned_size": list(photo.size),
        "handwritten_number_removed": bool(box),
        "ad": f"ads/mau-{number:02d}.jpg",
        "numbered_photo": f"numbered/mau-{number:02d}.jpg",
    }


def prepare() -> None:
    (OUT / "cleaned").mkdir(parents=True, exist_ok=True)
    collage = clean_collage(Image.open(RAW / COLLAGE).convert("RGB"))
    entries = []
    for number, filename, box, title in PRODUCTS:
        photo = prepare_photo(filename, box, collage)
        photo.save(OUT / "cleaned" / f"mau-{number:02d}.png")
        entries.append(source_entry(number, filename, box, title, photo))
    (OUT / "manifest.json").write_text(
        json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Prepared {len(entries)} photos in {OUT / 'cleaned'}")


# Shared Vietnamese copy; no invented prices, business details, or offers.
COPY = {
    "eyebrow": "BỘ SƯU TẬP BÁNH • 20.10.2026",
    "headline_1": "Gửi nàng",
    "headline_2": "điều ngọt ngào",
    "occasion": "Mừng Ngày Phụ nữ Việt Nam",
    "message": "Một chút ngọt ngào, gửi trọn yêu thương.",
    "cta": "Nhắn tin để chọn mẫu bánh",
    "date": "20.10.2026",
    "year": "2026",
}
CREAM = "#FFF9F3"
BERRY = "#763D4F"
GOLD = "#C4A177"
ROSE = "#F1DBDA"
MUTED = "#876D70"
SCALE = 2


@lru_cache(maxsize=None)
def font(size: int, family: str = "sans", scale: int = SCALE) -> ImageFont.FreeTypeFont:
    name = {"sans": "Noto Sans", "serif": "Noto Serif", "italic": "Noto Serif:style=Italic"}[family]
    path = subprocess.check_output(
        ["fc-match", name, "-f", "%{file}"], stderr=subprocess.DEVNULL, text=True
    ).strip()
    if not path or not Path(path).is_file():
        raise RuntimeError(f"Install {name} (with Vietnamese glyphs) and fontconfig first.")
    face = ImageFont.truetype(path, size * scale)
    try:
        face.set_variation_by_name("Italic" if family == "italic" else "Regular")
    except (ValueError, OSError):
        pass
    return face


class Canvas:
    def __init__(self, width: int, height: int, color: str = CREAM):
        self.image = Image.new("RGB", (width * SCALE, height * SCALE), color)
        self.draw = ImageDraw.Draw(self.image)

    def box(self, box):
        return tuple(round(v * SCALE) for v in box)

    def text(self, xy, text, size, fill=BERRY, family="sans", anchor="lt"):
        self.draw.text(self.box(xy), text, font=font(size, family), fill=fill, anchor=anchor)

    def line(self, points, fill=GOLD, width=1):
        self.draw.line([self.box(p) for p in points], fill=fill, width=max(1, round(width * SCALE)), joint="curve")

    def rounded(self, box, radius, fill, outline=None, width=1):
        self.draw.rounded_rectangle(self.box(box), radius=radius * SCALE, fill=fill,
                                    outline=outline, width=width * SCALE)

    def ellipse(self, box, fill, outline=None, width=1):
        self.draw.ellipse(self.box(box), fill=fill, outline=outline, width=width * SCALE)

    def save(self, path):
        self.image.resize((self.image.width // SCALE, self.image.height // SCALE),
                          Image.Resampling.LANCZOS).save(path, quality=95, subsampling=0)


def curve(c, p0, p1, p2, p3, color=GOLD, width=1):
    points = []
    for i in range(81):
        t = i / 80
        u = 1 - t
        points.append(tuple(u**3 * p0[j] + 3*u*u*t*p1[j] + 3*u*t*t*p2[j] + t**3*p3[j] for j in (0, 1)))
    c.line(points, color, width)


def blossom(c, x, y, radius, rotation=0):
    points = []
    for i in range(241):
        angle = i * 2 * math.pi / 240
        r = radius * (0.77 + 0.23 * math.cos(5 * (angle + rotation)))
        points.append((x + r * math.cos(angle), y + r * math.sin(angle)))
    c.draw.polygon([c.box(p) for p in points], fill="#F4E2DF")
    c.line(points, "#D1AD9F", 1)
    c.ellipse((x - 5, y - 5, x + 5, y + 5), GOLD)
    for angle in range(0, 360, 72):
        rad = math.radians(angle)
        c.line([(x + 9*math.cos(rad), y + 9*math.sin(rad)),
                (x + 21*math.cos(rad), y + 21*math.sin(rad))], GOLD, 1)


def floral_corner(c, x, y, mirror=1):
    def p(dx, dy):
        return (x + mirror * dx, y + dy)
    curve(c, p(0, 100), p(75, 18), p(64, -87), p(135, -159), "#C4BAA1", 1.4)
    curve(c, p(44, 18), p(8, -40), p(-9, -67), p(-39, -74), "#C4BAA1", 1.2)
    curve(c, p(75, -66), p(123, -66), p(155, -74), p(170, -103), "#C4BAA1", 1.2)
    for dx, dy, r, rot in [(5, 0, 44, .2), (82, -76, 35, .7), (135, -154, 26, .3), (-37, -74, 24, 0)]:
        blossom(c, *p(dx, dy), r, rot)
    for dx, dy in [(57, -15), (110, -112), (154, -82)]:
        leaf = [p(dx, dy), p(dx+25, dy-10), p(dx+37, dy-34), p(dx+8, dy-27), p(dx, dy)]
        c.draw.polygon([c.box(point) for point in leaf], fill="#E5E7DC")
        c.line(leaf, "#BFBEA3", 1)
        c.line([p(dx,dy),p(dx+30,dy-28)], "#BFBEA3", 1)


def paste_photo(c, photo, box):
    x0, y0, x1, y1 = box
    w, h = (x1 - x0) * SCALE, (y1 - y0) * SCALE
    # Very soft source-colored matte fills unused space without cropping the product.
    matte = ImageOps.fit(photo, (w, h), method=Image.Resampling.LANCZOS)
    matte = matte.filter(ImageFilter.GaussianBlur(44 * SCALE))
    matte = Image.blend(matte, Image.new("RGB", (w, h), CREAM), .86)
    fitted = ImageOps.contain(photo, (w-24*SCALE, h-24*SCALE), Image.Resampling.LANCZOS)
    matte.paste(fitted, ((w-fitted.width)//2, (h-fitted.height)//2))
    mask = Image.new("L", (w,h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,w-1,h-1), 18*SCALE, fill=255)
    c.image.paste(matte, (x0*SCALE,y0*SCALE), mask)
    c.rounded(box, 18, None, "#DAC1AF", 1)


def render_ad(photo, number, title, path):
    c = Canvas(1080, 1350)
    # Subtle editorial framing, rather than changing the cake or its decorations.
    c.ellipse((-250, 1080, 440, 1720), "#F7E8E3")
    c.ellipse((890, -200, 1350, 340), "#FAEDE6")
    floral_corner(c, 1079, 315, -1)
    floral_corner(c, -140, 1325)
    c.text((64, 48), COPY["eyebrow"], 20, MUTED)
    c.text((60, 92), COPY["headline_1"], 58, family="italic")
    c.text((60, 168), COPY["headline_2"], 64, family="serif")
    c.text((64, 272), COPY["occasion"], 25, MUTED)
    c.rounded((865, 53, 1016, 231), 70, "#F5E4DE", "#D5B49C", 1)
    c.text((940, 85), "20", 61, family="serif", anchor="mt")
    c.line([(902, 168), (978, 168)], GOLD, 1)
    c.text((940, 182), "THÁNG 10", 16, MUTED, anchor="mt")
    c.text((940, 211), COPY["year"], 14, MUTED, anchor="mt")
    c.line([(64, 319), (1016, 319)], "#DECABC", 1)
    paste_photo(c, photo, (64, 345, 1016, 1105))
    c.rounded((64, 1133, 216, 1197), 32, BERRY)
    c.text((140, 1152), f"MẪU {number}", 24, CREAM, anchor="mt")
    c.text((240, 1147), title, 32, family="serif")
    c.text((64, 1220), COPY["message"], 23, MUTED)
    c.line([(64, 1270), (1016, 1270)], "#D7BFAE", 1)
    c.text((64, 1294), COPY["cta"], 22)
    c.text((1016, 1294), COPY["date"], 22, MUTED, anchor="rt")
    c.save(path)


def render_numbered(photo, number, title, path):
    width = 1080
    height = round(photo.height * width / photo.width)
    c = Canvas(width, height + 112)
    c.image.paste(photo.resize((width*SCALE, height*SCALE), Image.Resampling.LANCZOS), (0,0))
    c.rounded((32, height+24, 202, height+88), 32, BERRY)
    c.text((117, height+43), f"MẪU {number}", 24, CREAM, anchor="mt")
    c.text((232, height+41), title, 30, family="serif")
    c.save(path)


def render_catalog(products=None):
    products = PRODUCTS if products is None else products
    c = Canvas(1800, 214 + math.ceil(len(products)/5)*478 + 42)
    c.text((60, 47), COPY["headline_1"] + " " + COPY["headline_2"], 64, family="serif")
    c.text((64, 137), f"{len(products)} mẫu bánh • Mừng Ngày Phụ nữ Việt Nam {COPY['date']}", 30, MUTED)
    for i, (number, _source, _crop, _title) in enumerate(products):
        x, y = 48 + (i % 5)*344, 214 + (i // 5)*478
        with Image.open(OUT / "ads" / f"mau-{number:02d}.jpg") as ad:
            ad = ad.resize((320*SCALE, 400*SCALE), Image.Resampling.LANCZOS)
        c.image.paste(ad, (x*SCALE, y*SCALE))
        c.text((x+160,y+414), f"MẪU {number}", 26, anchor="mt")
    c.save(OUT / "catalog-20-10.jpg")


def render():
    for directory in ("ads", "numbered"):
        (OUT / directory).mkdir(parents=True, exist_ok=True)
    for number, _, _, title in PRODUCTS:
        with Image.open(OUT / "cleaned" / f"mau-{number:02d}.png") as photo:
            render_ad(photo, number, title, OUT / "ads" / f"mau-{number:02d}.jpg")
            render_numbered(photo, number, title, OUT / "numbered" / f"mau-{number:02d}.jpg")
    render_catalog()
    print(f"Rendered {len(PRODUCTS)} portrait ads and numbered photos, plus catalog in {OUT} (no ZIP)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("prepare", "render", "all"), default="all", nargs="?")
    args = parser.parse_args()
    if args.stage in ("prepare", "all"):
        prepare()
    if args.stage in ("render", "all"):
        render()


if __name__ == "__main__":
    main()
