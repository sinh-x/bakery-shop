"""Protect the shortened-set circular indexes and legacy video card defaults."""
import unittest
from unittest.mock import patch

from PIL import Image

import create_catalog_video as design
import create_shortened_ads as shortened
import create_womens_day_ads as art


class ShortenedAdTests(unittest.TestCase):
    def test_circle_index_is_numeric_top_right_and_frees_photo_area(self):
        photo = Image.new("RGB", (600, 800), "#D6A2AA")
        original_text, original_ellipse = art.Canvas.text, art.Canvas.ellipse
        for width, height in ((300, 435), (455, 435), (960, 860)):
            with self.subTest(width=width):
                with patch.object(art, "paste_photo", wraps=art.paste_photo) as paste, \
                     patch.object(art.Canvas, "text", autospec=True, side_effect=original_text) as text, \
                     patch.object(art.Canvas, "ellipse", autospec=True, side_effect=original_ellipse) as ellipse:
                    image = design.card(photo, width, height, 31, index_style="circle")
                self.assertEqual(image.size, (width*art.SCALE, height*art.SCALE))
                self.assertEqual(paste.call_args.args[2], (12, 12, width-12, height-12))
                self.assertEqual(text.call_args.args[2], "31")
                self.assertEqual(text.call_args.kwargs["anchor"], "mm")
                x, y = text.call_args.args[1]
                self.assertGreater(x, width*.7)
                self.assertLess(y, height*.3)
                x0, y0, x1, y1 = ellipse.call_args.args[1]
                self.assertEqual(x1-x0, y1-y0)
                self.assertGreaterEqual(x0, 12)
                self.assertLessEqual(x1, width-12)
                self.assertGreaterEqual(y0, 12)
                self.assertGreater(height-24, height-110)

    def test_default_video_card_keeps_legacy_pill(self):
        photo = Image.new("RGB", (600, 800), "#D6A2AA")
        original = art.Canvas.text
        with patch.object(art, "paste_photo", wraps=art.paste_photo) as paste, \
             patch.object(art.Canvas, "text", autospec=True, side_effect=original) as text:
            design.card(photo, 300, 435, 31)
        self.assertEqual(paste.call_args.args[2], (18, 18, 282, 343))
        self.assertEqual(text.call_args.args[2], "MẪU 31")

    def test_layouts_keep_every_selected_index(self):
        self.assertEqual(shortened.SELECTED_NUMBERS, (2, 3, 4, 5, 9, 12, 21, 26, 30, 31))
        for count in range(1, 10):
            self.assertEqual(len(shortened.collage_layouts(count)), count)
        self.assertNotIn("mẫu", shortened.COPY["instruction"].casefold())

    def test_unknown_badge_style_is_rejected(self):
        with self.assertRaises(ValueError):
            design.card(Image.new("RGB", (10, 10)), 300, 435, 31, index_style="unknown")


if __name__ == "__main__":
    unittest.main()
