#!/usr/bin/env python3
"""Create a silent vertical collage video from approved by-type cake photos.

Uses the same photos as the final ads, preserving every product and Mẫu number.
No source images are edited. Needs the image environment, FFmpeg, and ffprobe.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

import create_womens_day_ads as art
from ad_library_policy import EXCLUDED_NUMBERS, is_approved

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "processed-enhanced"
OUT = ROOT / "video"
WIDTH, HEIGHT, FPS = 1080, 1920, 30
INTRO_SECONDS = OUTRO_SECONDS = 3
SCENE_SECONDS = 5.5
TRANSITION_SECONDS = 0.5
VIDEO_NAME = "20-10-2026-silent-collage.mp4"
LOGO_REFERENCE = ROOT / "raw/branding/tiem-banh-doan-gia-reference.png"
VIDEO_COPY = {
    "brand": "Tiệm Bánh Đoàn Gia",
    "brand_prefix": "TIỆM BÁNH",
    "instruction": "Nhắn tin kèm số mẫu để đặt bánh",
    "thanks": "Cảm ơn khách yêu đã chọn tiệm!",
    "collection": "Bộ sưu tập bánh",
}


def approved_sources():
    categories = sorted(json.loads((SOURCE / "cake-types.json").read_text()), key=lambda c: c["order"])
    entries = {e["number"]: e for e in json.loads((SOURCE / "manifest.json").read_text())}
    if set(entries) != {p[0] for p in art.PRODUCTS}:
        raise ValueError("Final photos are stale; regenerate approved by-type outputs first.")
    provenance, photos, seen = [], {}, []
    for category in categories:
        for number in category["numbers"]:
            if number in EXCLUDED_NUMBERS or not is_approved(number):
                raise ValueError(f"Unapproved/excluded index {number:02d}.jpg cannot enter the video.")
            entry = entries[number]
            if entry["title"] != category["label"]:
                raise ValueError(f"Stale cake type for index {number}.")
            photo_path = SOURCE / entry["grouped_photo"]
            ad_path = SOURCE / entry["grouped_ad"]
            if photo_path.read_bytes() != (SOURCE / entry["photo"]).read_bytes():
                raise ValueError(f"Stale grouped photo: {photo_path}")
            if ad_path.read_bytes() != (SOURCE / entry["ad"]).read_bytes():
                raise ValueError(f"Stale grouped ad: {ad_path}")
            with Image.open(photo_path) as image:
                photos[number] = image.convert("RGB")
            provenance.append({"number": number, "cake_type": category["label"],
                               "photo": str(photo_path.relative_to(ROOT)),
                               "photo_sha256": hashlib.sha256(photo_path.read_bytes()).hexdigest(),
                               "ad": str(ad_path.relative_to(ROOT)),
                               "ad_sha256": hashlib.sha256(ad_path.read_bytes()).hexdigest()})
            seen.append(number)
    if len(seen) != len(set(seen)) or set(seen) != set(entries):
        raise ValueError("Every approved photo must appear exactly once in the main collage scenes.")
    return categories, photos, provenance


def background():
    c = art.Canvas(WIDTH, HEIGHT)
    c.ellipse((-340, 1470, 590, 2340), "#F6E5DF")
    c.ellipse((815, -190, 1310, 360), "#FAEBE3")
    art.floral_corner(c, 1102, 308, -1)
    art.floral_corner(c, -135, 1790)
    return c


def centered(c, y, text, size=46, family="serif", fill=art.BERRY):
    while art.font(size, family).getlength(text) > 970 * art.SCALE:
        size -= 2
    c.text((540, y), text, size, fill, family, anchor="mt")


@lru_cache(maxsize=1)
def logo_text():
    """Preserve the supplied cursive lettering; remove only its colored backdrop."""
    with Image.open(LOGO_REFERENCE) as reference:
        if reference.size != (725, 1024):
            raise ValueError("Bakery reference changed; review the logo text crop before publishing.")
        crop = reference.convert("RGB").crop((290, 114, 437, 156))
    alpha = Image.new("L", crop.size)
    pixels = [crop.getpixel((x, y)) for y in range(crop.height) for x in range(crop.width)]
    alpha.putdata([round(255*max(0, min(1, (240-max(p))/210)))
                   if max(p)-min(p) < 25 else 0 for p in pixels])
    alpha = alpha.point(lambda a: 0 if a < 24 else a)
    alpha = alpha.resize((crop.width*8, crop.height*8), Image.Resampling.LANCZOS)
    alpha = alpha.filter(ImageFilter.UnsharpMask(radius=2, percent=130, threshold=3))
    logo = Image.new("RGBA", alpha.size, (12, 12, 12, 0))
    logo.putalpha(alpha)
    return logo


def brand_stamp(c, bookend=False):
    width = 385 if bookend else 265
    label_y, image_y = (37, 84) if bookend else (28, 56)
    centered(c, label_y, VIDEO_COPY["brand_prefix"], 23 if bookend else 19, "sans", "#222222")
    logo = logo_text()
    mark = logo.resize((width*art.SCALE, round(width*logo.height/logo.width*art.SCALE)),
                       Image.Resampling.LANCZOS)
    c.image.paste(mark, ((WIDTH*art.SCALE-mark.width)//2, image_y*art.SCALE), mark.getchannel("A"))


def card(photo, width, height, number, label_prefix="MẪU ", index_style="pill"):
    if index_style not in {"pill", "circle"}:
        raise ValueError(f"Unknown index style: {index_style}")
    c = art.Canvas(width, height, "#FFFDF9")
    c.rounded((1, 1, width-2, height-2), 24, "#FFFDF9", "#D6BAA3", 1)
    if index_style == "circle":
        # Fill the card: the numeric badge overlays its upper-right corner.
        art.paste_photo(c, photo, (12, 12, width-12, height-12))
        radius = min(34, max(26, round(width*.065)))
        cx, cy = width-20-radius, 20+radius
        c.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), art.BERRY, art.CREAM, 2)
        c.text((cx, cy), f"{number:02d}", radius, art.CREAM, anchor="mm")
    else:
        art.paste_photo(c, photo, (18, 18, width-18, height-92))
        c.rounded((width/2-98, height-69, width/2+98, height-13), 28, art.BERRY)
        c.text((width/2, height-54), f"{label_prefix}{number:02d}",
               29 if label_prefix else 34, art.CREAM, anchor="mt")
    image = c.image.convert("RGBA")
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width-1, image.height-1), 24*art.SCALE, fill=255)
    image.putalpha(mask)
    return image


def place(c, photo, number, cx, cy, width, height, angle, label_prefix="MẪU ", index_style="pill"):
    image = card(photo, width, height, number, label_prefix=label_prefix, index_style=index_style).rotate(
        angle, Image.Resampling.BICUBIC, expand=True)
    xy = (round(cx*art.SCALE-image.width/2), round(cy*art.SCALE-image.height/2))
    alpha = image.getchannel("A")
    shadow = Image.new("RGBA", image.size, (92, 55, 63, 0))
    shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(10*art.SCALE)).point(lambda v: round(v*.18)))
    c.image.paste(shadow, (xy[0]+7*art.SCALE, xy[1]+11*art.SCALE), shadow.getchannel("A"))
    c.image.paste(image, xy, alpha)


def finish(c):
    return c.image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)


def collage(category, numbers, photos, category_count):
    c = background()
    brand_stamp(c)
    centered(c, 155, art.COPY["date"], 23, "sans", art.MUTED)
    centered(c, 207, category["label"], 44)
    centered(c, 282, art.COPY["headline_1"]+" "+art.COPY["headline_2"], 25, "italic")
    c.line([(110, 326), (970, 326)], "#D4B69D", 1)
    layouts = {
        1: [(540, 1050, 900, 1170, -0.8)],
        2: [(540, 700, 870, 650, -1.3), (540, 1400, 870, 650, 1.3)],
        3: [(540, 700, 910, 650, -0.7), (290, 1400, 455, 640, -1.2), (790, 1400, 455, 640, 1.2)],
        4: [(290, 700, 455, 640, -1.3), (790, 700, 455, 640, 1.2),
            (290, 1400, 455, 640, 1.1), (790, 1400, 455, 640, -1.2)],
    }
    placement = list(numbers)
    if len(placement) == 3:
        # A landscape photo works best in the wide feature card; all codes stay unchanged.
        hero = max(placement, key=lambda n: photos[n].width/photos[n].height)
        placement = [hero]+[n for n in placement if n != hero]
    for number, layout in zip(placement, layouts[len(numbers)], strict=True):
        place(c, photos[number], number, *layout)
    for i in range(category_count):
        x = 540+(i-(category_count-1)/2)*31
        fill = art.BERRY if i+1 == category["order"] else "#D7BBAA"
        c.ellipse((x-5, 1756, x+5, 1766), fill)
    centered(c, 1814, VIDEO_COPY["instruction"], 29, "sans")
    return finish(c)


def bookend(photos, categories, ending=False):
    c = background()
    brand_stamp(c, bookend=True)
    centered(c, 222, art.COPY["occasion"], 27, "sans", art.MUTED)
    c.rounded((330, 281, 750, 366), 42, "#F5E3DB", "#CFAD94", 1)
    centered(c, 302, art.COPY["date"], 35)
    if ending:
        first, second = art.COPY["message"].split(", ", 1)
        centered(c, 532, first+",", 52)
        centered(c, 628, second, 52)
        art.blossom(c, 540, 967, 92, .3)
        centered(c, 1240, VIDEO_COPY["instruction"], 40, "sans")
        centered(c, 1364, VIDEO_COPY["thanks"], 27, "sans", art.MUTED)
    else:
        centered(c, 461, art.COPY["headline_1"], 70, "italic")
        centered(c, 564, art.COPY["headline_2"], 63)
        centered(c, 687, f"{len(photos)} mẫu • {len(categories)} loại bánh", 30, "sans", art.MUTED)
        preferred = [n for n in (15, 21, 24) if n in photos]
        chosen = preferred + [n for n in photos if n not in preferred]
        for n, layout in zip(chosen[:3], [(218, 1000, 300, 410, -5),
                                          (540, 1065, 300, 410, 0), (862, 1000, 300, 410, 5)], strict=True):
            place(c, photos[n], n, *layout)
        centered(c, 1450, art.COPY["cta"], 35, "sans")
    c.line([(245, 1665), (835, 1665)], "#D4B69D", 1)
    centered(c, 1745, art.COPY["date"], 30, "sans", art.MUTED)
    return finish(c)


def scenes_for(categories, photos):
    scenes = [{"kind": "intro", "label": "Mở đầu", "seconds": INTRO_SECONDS,
               "photo_numbers": [], "image": bookend(photos, categories)}]
    for category in categories:
        numbers = category["numbers"]
        pages = math.ceil(len(numbers)/4)
        for page in range(pages):
            selected = numbers[page*4:page*4+4]
            scenes.append({"kind": "collage", "label": category["label"], "group_order": category["order"],
                           "page": page+1, "pages_in_group": pages, "seconds": SCENE_SECONDS,
                           "photo_numbers": selected,
                           "image": collage(category, selected, photos, len(categories))})
    scenes.append({"kind": "outro", "label": "Lời nhắn", "seconds": OUTRO_SECONDS,
                   "photo_numbers": [], "image": bookend(photos, categories, ending=True)})
    return scenes


def gentle_zoom(image, progress):
    zoom = 1+.016*(.5-.5*math.cos(math.pi*progress))
    width, height = WIDTH/zoom, HEIGHT/zoom
    box = ((WIDTH-width)/2, (HEIGHT-height)/2, (WIDTH+width)/2, (HEIGHT+height)/2)
    return image.transform((WIDTH, HEIGHT), Image.Transform.EXTENT, box, Image.Resampling.BICUBIC)


def encode(scenes, destination, log_path):
    command = ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-y", "-f", "rawvideo",
               "-pixel_format", "rgb24", "-video_size", f"{WIDTH}x{HEIGHT}", "-framerate", str(FPS),
               "-i", "pipe:0", "-an", "-vf", "scale=in_range=pc:out_range=tv:out_color_matrix=bt709,setsar=1",
               "-c:v", "libx264", "-preset", "medium", "-crf", "19", "-threads", "4",
               "-pix_fmt", "yuv420p", "-profile:v", "high", "-level:v", "4.1",
               "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
               "-movflags", "+faststart", "-metadata", f"title={VIDEO_COPY['brand']} | Gửi nàng điều ngọt ngào | {art.COPY['date']}",
               str(destination)]
    transition = round(TRANSITION_SECONDS*FPS)
    written = 0
    with log_path.open("w") as log:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=log)
        try:
            for i, scene in enumerate(scenes):
                print(f"Rendering scene {i+1}/{len(scenes)}: {scene['label']}", flush=True)
                if i:
                    previous = gentle_zoom(scenes[i-1]["image"], 1)
                    incoming = scene["image"]
                    for frame in range(transition):
                        image = Image.blend(previous, incoming, (frame+1)/transition)
                        process.stdin.write(image.tobytes())
                        written += 1
                overlaps = (1 if i else 0)+(1 if i+1 < len(scenes) else 0)
                hold = round(scene["seconds"]*FPS)-overlaps*transition
                if hold < 1:
                    raise ValueError("Scene duration is shorter than its transitions.")
                for frame in range(hold):
                    image = gentle_zoom(scene["image"], frame/max(1, hold-1))
                    process.stdin.write(image.tobytes())
                    written += 1
            process.stdin.close()
            code = process.wait(timeout=120)
        except Exception as error:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=30)
            log.flush()
            raise RuntimeError("Video encoding failed: "+log_path.read_text()[-6000:]) from error
    if code:
        raise RuntimeError("FFmpeg failed: "+log_path.read_text()[-6000:])
    return written


def probe(path):
    data = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format",
                                               "-of", "json", str(path)], text=True))
    streams = data["streams"]
    if len(streams) != 1 or streams[0]["codec_type"] != "video":
        raise ValueError("Output must contain exactly one video stream and no audio.")
    if streams[0]["codec_name"] != "h264" or (streams[0]["width"], streams[0]["height"]) != (WIDTH, HEIGHT):
        raise ValueError("Incorrect codec or portrait dimensions.")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("preview", "all"), default="all", nargs="?")
    args = parser.parse_args()
    for executable in ("ffmpeg", "ffprobe"):
        if not shutil.which(executable):
            raise RuntimeError(f"Install {executable} first.")
    categories, photos, sources = approved_sources()
    scenes = scenes_for(categories, photos)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "scenes").mkdir(exist_ok=True)
    logo_text().save(OUT / "logo-text.png")
    for i, scene in enumerate(scenes):
        name = f"{i:02d}-{scene['kind']}.jpg"
        scene["preview"] = f"scenes/{name}"
        scene["image"].save(OUT / scene["preview"], quality=95, subsampling=0)
    scenes[0]["image"].save(OUT / "cover.jpg", quality=95, subsampling=0)
    sheet = Image.new("RGB", (1080, math.ceil(len(scenes)/6)*320), art.CREAM)
    for i, scene in enumerate(scenes):
        sheet.paste(scene["image"].resize((180, 320), Image.Resampling.LANCZOS), ((i%6)*180, (i//6)*320))
    sheet.save(OUT / "storyboard.jpg", quality=95, subsampling=0)
    frames = sum(round(s["seconds"]*FPS) for s in scenes)-round(TRANSITION_SECONDS*FPS)*(len(scenes)-1)
    metadata = {"video": VIDEO_NAME, "status": "encoded" if args.stage == "all" else "preview",
                "bakery_name": VIDEO_COPY["brand"],
                "logo_text": "logo-text.png", "logo_reference": str(LOGO_REFERENCE.relative_to(ROOT)),
                "logo_reference_sha256": hashlib.sha256(LOGO_REFERENCE.read_bytes()).hexdigest(),
                "date": art.COPY["date"], "width": WIDTH, "height": HEIGHT,
                "fps": FPS, "silent": True, "duration_seconds": frames/FPS, "frame_count": frames,
                "transition_seconds": TRANSITION_SECONDS, "photo_sources": sources,
                "scenes": [{k: v for k, v in s.items() if k != "image"} for s in scenes]}
    if args.stage == "all":
        with tempfile.TemporaryDirectory(prefix="bakery-collage-video-") as directory:
            temporary = Path(directory) / "render.mp4"
            written = encode(scenes, temporary, Path(directory) / "ffmpeg.log")
            if written != frames:
                raise ValueError("Encoded frame count differs from the planned timeline.")
            data = probe(temporary)
            if abs(float(data["format"]["duration"])-frames/FPS) > .1:
                raise ValueError("Video duration differs from the planned timeline.")
            shutil.copy2(temporary, OUT / VIDEO_NAME)
            metadata["video_sha256"] = hashlib.sha256((OUT / VIDEO_NAME).read_bytes()).hexdigest()
    (OUT / "manifest.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    (OUT / "README.md").write_text(f"""# Silent Women's Day collage video

- `{VIDEO_NAME}`: {WIDTH} × {HEIGHT}, {FPS} fps, H.264 MP4, **{frames/FPS:.1f} seconds**, **no audio**.
- `cover.jpg`: opening poster.
- `logo-text.png`: transparent official Đoàn Gia lettering extracted from the provided reference.
- `storyboard.jpg` / `scenes/`: preview of the sequence.
- `manifest.json`: timeline, original Mẫu numbers, and input file hashes.

All {len(sources)} approved cake photos from the by-type ads appear in {len(scenes)-2}
main collage scenes, following the seven confirmed cake types in order. Larger
groups are split into pages of at most four photos. Original numbered labels
are preserved. Full product photos fit inside the cards without product cropping;
the subtle camera movement affects only safe outer page margins. Ivory/blush
styling, soft shadows, floral accents, and gentle dissolves match the ads.
The supplied cursive **Đoàn Gia** logo lettering, with **{VIDEO_COPY['brand_prefix']}**
above it, appears on the opening, every collage scene, and the closing screen.
The campaign date is **{art.COPY['date']}**. No ZIP is generated.
The provided bakery reference is preserved at
`../raw/branding/tiem-banh-doan-gia-reference.png`. Only its shop-name lettering
is extracted; the colored card/cake artwork and phone numbers are not included.

The video uses the approved product photos behind the ads, rather than shrinking
entire ad posters into tiny collage tiles. Rerun after approval/exclusion, photo,
or campaign-date changes. Rejected and pending pictures fail validation.

Reproduce from the repository root, using the image environment and NixOS
library setup in `../processed/README.md`:

```sh
/tmp/womens-day-image-env/bin/python ads/20261020/create_catalog_video.py all
```

Use `preview` instead of `all` to generate storyboard images without encoding.
Requires FFmpeg with libx264 and ffprobe. Existing source images are unchanged.
""", encoding="utf-8")
    print(f"{'Video' if args.stage == 'all' else 'Preview'} ready in {OUT}; {frames/FPS:.1f}s, silent.", flush=True)


if __name__ == "__main__":
    main()
