"""Run with unittest discover; protects raw -> index -> approval -> ads workflow."""
import importlib
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image, ImageOps

import create_womens_day_ads as renderer
from ad_library_policy import COLLECTION, EXCLUDED_NUMBERS, POLICY, REVIEW, is_approved, is_excluded
from cake_categories import CATEGORIES


class AdLibraryPolicyTests(unittest.TestCase):
    def test_exclusion_keys_are_index_filenames(self):
        collection = POLICY["collections"][COLLECTION]
        self.assertEqual(set(collection["excluded_index_files"]),
                         {"06.jpg", "07.jpg", "08.jpg", "13.jpg", "14.jpg", "18.jpg", "19.jpg", "20.jpg"})
        self.assertEqual(EXCLUDED_NUMBERS, {6, 7, 8, 13, 14, 18, 19, 20})
        for entry in POLICY["exclusions"]:
            self.assertEqual(entry["index_file"], f"{COLLECTION}/index/{entry['number']:02d}.jpg")
            self.assertNotIn("source", entry)

    def test_retired_indexes_cannot_be_reused_with_another_source(self):
        source = renderer.RAW / "IMG_2849.jpg"
        for number in EXCLUDED_NUMBERS:
            self.assertTrue(is_excluded(number, source))
            self.assertFalse(is_approved(number))

    def test_pending_uploads_do_not_reach_final_rendering(self):
        registered = set(range(1, POLICY["collections"][COLLECTION]["highest_assigned_number"]+1))-EXCLUDED_NUMBERS
        approved = {n for n in registered if is_approved(n) and n in renderer.TYPE_FOR_NUMBER}
        self.assertEqual({row[0] for row in renderer.PRODUCTS}, approved)
        self.assertEqual({row[0] for row in renderer.REGISTERED_PRODUCTS}, registered)
        self.assertFalse(is_approved(POLICY["collections"][COLLECTION]["next_number"]))
        try:
            with patch.dict(REVIEW, {"approved_index_files": [f"{n:02d}.jpg" for n in approved-{30}],
                                    "pending_index_files": ["30.jpg"]}):
                importlib.reload(renderer)
                self.assertFalse(is_approved(30))
                self.assertNotIn(30, {row[0] for row in renderer.PRODUCTS})
                self.assertIn(30, {row[0] for row in renderer.REGISTERED_PRODUCTS})
        finally:
            importlib.reload(renderer)

    def test_untyped_upload_cannot_publish_even_if_approved(self):
        number = max(row[0] for row in renderer.PRODUCTS)
        types = {n: category for n, category in renderer.TYPE_FOR_NUMBER.items() if n != number}
        try:
            with patch.dict(renderer.TYPE_FOR_NUMBER, types, clear=True):
                importlib.reload(renderer)
                self.assertTrue(is_approved(number))
                self.assertIn(number, {row[0] for row in renderer.REGISTERED_PRODUCTS})
                self.assertNotIn(number, {row[0] for row in renderer.PRODUCTS})
        finally:
            importlib.reload(renderer)

    def test_renamed_excluded_upload_is_blocked_in_future_collection(self):
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory) / "brand-new-filename.jpg"
            shutil.copy2(renderer.RAW / "signal-2026-10-11-08-11-45-184.jpg", copied)
            self.assertTrue(is_excluded(1, copied, collection="future-collection"))

    def test_lossless_copy_is_blocked_by_decoded_image_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory) / "different-format.png"
            with Image.open(renderer.RAW / "signal-2026-10-11-08-11-45-184.jpg") as source:
                ImageOps.exif_transpose(source).convert("RGB").save(copied)
            self.assertTrue(is_excluded(30, copied))

    def test_excluded_collage_crop_does_not_block_other_tiles(self):
        filename = renderer.RAW / renderer.COLLAGE
        box = (382, 887, 680, 1201)
        self.assertTrue(is_excluded(30, filename, box))
        self.assertFalse(is_excluded(1, filename, (1, 120, 324, 449)))
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory) / "exported-tile.png"
            with Image.open(filename) as source:
                source.convert("RGB").crop(box).save(copied)
            self.assertTrue(is_excluded(30, copied))

    def test_new_type_corrections_are_preserved(self):
        types = {n: title for n, _source, _box, title in renderer.REGISTERED_PRODUCTS}
        self.assertEqual(types[24], "Bánh mousse chanh dây")
        self.assertEqual(types[27], "Bánh mousse chanh dây")
        self.assertEqual(types[29], "Bánh su dai")
        self.assertEqual(types[30], "Bánh kem")
        self.assertEqual(types[31], "Bánh kem")

    def test_full_campaign_date_is_shared(self):
        self.assertEqual(renderer.COPY["date"], "20.10.2026")
        self.assertEqual(renderer.COPY["year"], "2026")
        self.assertIn(renderer.COPY["date"], renderer.COPY["eyebrow"])
        box = renderer.font(22, scale=1).getbbox(renderer.COPY["date"])
        self.assertLess(box[2]-box[0], 220)

    def test_final_category_order(self):
        self.assertEqual([c["label"] for c in CATEGORIES], [
            "Bó hoa kem sữa tươi", "Bánh kem", "Bánh rau câu flan", "Bánh bông lan trứng muối",
            "Bánh mousse mix vị", "Bánh mousse chanh dây", "Bánh su dai",
        ])
        self.assertEqual([c["order"] for c in CATEGORIES], list(range(1, 8)))
        self.assertTrue(all(c["folder"].startswith(f"{c['order']:02d}-") for c in CATEGORIES))


if __name__ == "__main__":
    unittest.main()
