# Ads library

The latest 20/10 collection is in `20261020/processed-enhanced/`.
Use `20261020/index/` for a flat set named `01.jpg`, `21.jpg`, etc., or the
`by-type/` folders and `catalog-20-10.jpg` inside `processed-enhanced/`.
Original uploads are in `20261020/raw/`, kept for reference rather than
automatically approved for advertising.

## Permanent exclusions

**Always read `library-exclusions.json` before importing or generating more ads.**

For collection `20261020`, selections **6, 7, 8, 13, 14, 18, 19, and 20** were removed
at the user's request. Never re-add these images, regenerate their outputs, or
reuse those numbers. Keep remaining numbers unchanged. The highest assigned ID
is **31**; the next genuinely new selection starts at **32**.

The registry uses **index filenames** as its exclusion keys, not raw filenames.
File hashes, collage crops, decoded-image signatures, and known output hashes
are internal duplicate guards. The policy checks retired indexes, identical
source files even when renamed, lossless copies with different metadata,
and known generated versions. For selection 6, exclude only that
collage tile, not the other tiles from the same collage. Do not advertise the
whole collage containing the rejected tile.

The scripts in `20261020/` enforce this shared registry through
`ad_library_policy.py`. Future collection scripts must read the same registry
and apply the same source/crop checks, including exclusions from older collections.
Recompressed, resized, or otherwise edited duplicates may evade exact hash
matching: inspect new uploads against the recorded original references too.
Only explicit user approval may reverse an exclusion.

## Workflow

1. Keep original uploads in `20261020/raw/`. Register new sources using unused
   IDs in `create_womens_day_ads.py`. Unknown types remain pending preview labels;
   record a confirmed type in `cake_categories.py` before publishing.
   Add their index filenames to `index-status.json` as **pending**, not approved.
2. Run `20261020/build_photo_index.py`. It creates `index/01.jpg`, etc., and an
   `INDEX.md`/`catalog.jpg` review sheet from raw originals, without AI reconstruction.
3. Communicate and confirm by **index filename**. On explicit confirmation,
   confirm the cake type and move approved filenames from pending to approved in `index-status.json`;
   rejected filenames go into the shared `library-exclusions.json` registry.
4. Run `append_womens_day_photos.py` only to produce final ads for approved files.
   `apply_ad_library_exclusions.py` prunes rejected outputs and old ZIPs.
5. All generation is ZIP-free. Do not create archives.

## Local assets and setup

`ads/.gitignore` excludes raw uploads, image/video exports, generated manifests
and documentation, archives, and model binaries. They remain on disk but are
not committed. Scripts, approval state, exclusion policy, and this guide are
tracked. Restore the original `20261020/raw/` files from your own backup before
running scripts or tests; importing the renderer validates the source images.
The logo reference must also be restored under `raw/branding/`.

Dependencies: Python, Pillow, numpy, opencv-python-headless, onnxruntime;
fontconfig (`fc-match`), Noto Sans, and Noto Serif including Italic with Vietnamese
glyphs. Video export additionally needs FFmpeg with libx264 and ffprobe.

```sh
uv venv /tmp/womens-day-image-env
uv pip install --python /tmp/womens-day-image-env/bin/python \
  pillow numpy opencv-python-headless onnxruntime
```

On NixOS, binary Python wheels need libstdc++ and zlib exposed. On the current
host the working setup is below; adjust the store paths for another environment:

```sh
export LD_LIBRARY_PATH=/nix/store/j2kgllgds4w7na8zqv1msi0mpvpjxda8-gcc-15.2.0-lib/lib:/nix/store/ri9paa3mri4kqakljak8ldvbcp7lpmif-zlib-1.3.1/lib:$LD_LIBRARY_PATH
```

To bootstrap ignored outputs after restoring the original photos, run the base
renderer, then enhancement with the model URL/checksum in
`20261020/enhance_womens_day_photos.py`. The enhancement command creates the
by-type outputs and catalogs needed by the shortened-set and video commands:

```sh
/tmp/womens-day-image-env/bin/python ads/20261020/create_womens_day_ads.py all
/tmp/womens-day-image-env/bin/python ads/20261020/enhance_womens_day_photos.py \
  --model /path/to/realesr-general-x4v3.onnx all
/tmp/womens-day-image-env/bin/python ads/20261020/create_shortened_ads.py
/tmp/womens-day-image-env/bin/python ads/20261020/create_catalog_video.py all
```

Verification (requires local original photos and fonts):

```sh
/tmp/womens-day-image-env/bin/python -m unittest discover -s ads/20261020 -p 'test_*.py' -v
python -m ruff check ads/20261020/*.py --select E9,F63,F7,F82
```

## Confirmed final list

The user retired **07.jpg**, approved the final list, and explicitly confirmed
**30.jpg** and the newly added **31.jpg** as **Bánh kem**. Files **24.jpg** and **27.jpg** are **Bánh mousse chanh dây**;
**29.jpg** is **Bánh su dai**. The confirmed index filenames are in
`20261020/index-status.json`. All future uploads still require index-based review.

The final category order is:

1. Bó hoa kem sữa tươi
2. Bánh kem
3. Bánh rau câu flan
4. Bánh bông lan trứng muối
5. Bánh mousse mix vị
6. Bánh mousse chanh dây
7. Bánh su dai

All final catalog JPGs are collected in `20261020/final-catalogs/`: `00-all-types.jpg`
is the overview and files `01-…` through `07-…` follow the confirmed category order.
See its `INDEX.md`, `20261020/final-list.md`, and the corresponding numbered
folders in `20261020/processed-enhanced/by-type/`.
`quality-review.json` records the prior review; `index-status.json` records current approvals.

## Shortened ads and video

`20261020/create_shortened_ads.py` exports the selected indexes
**02, 03, 04, 05, 09, 12, 21, 26, 30, 31** into
`20261020/shorten-processed-images/`: ten individual ads and three per-type
collages. Each photo has a numeric-only circle at its upper-right corner,
without a bottom number strip. Official Đoàn Gia logo lettering and the campaign
date **20.10.2026** are retained. Update `SELECTED_NUMBERS` only after confirming
new index filenames and types; the full library and its numbering are unchanged.

`20261020/create_catalog_video.py` creates a silent 1080 × 1920 H.264 MP4,
grouped collages, cover, and previews in the ignored `20261020/video/` directory.
It extracts the supplied logo lettering from the unchanged local reference.
Rerun it explicitly when a new approved photo should also enter the video;
adding a photo to the shortened set does not overwrite the existing video.
