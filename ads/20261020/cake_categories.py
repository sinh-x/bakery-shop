"""User-confirmed category order; index exclusions keep retired IDs reserved."""
from ad_library_policy import EXCLUDED_NUMBERS

CATEGORIES = (
    {"label": "Bó hoa kem sữa tươi", "slug": "bo-hoa-kem-sua-tuoi", "numbers": (14, 15, 22)},
    {"label": "Bánh kem", "slug": "banh-kem", "numbers": (1, 2, 3, 4, 5, 6, 7, 21, 23, 25, 26, 28, 30, 31)},
    {"label": "Bánh rau câu flan", "slug": "banh-rau-cau-flan", "numbers": (8, 9, 10, 11)},
    {"label": "Bánh bông lan trứng muối", "slug": "banh-bong-lan-trung-muoi", "numbers": (16, 17, 18, 19, 20)},
    {"label": "Bánh mousse mix vị", "slug": "banh-mousse-mix-vi", "numbers": (12, 13)},
    {"label": "Bánh mousse chanh dây", "slug": "banh-mousse-chanh-day", "numbers": (24, 27)},
    {"label": "Bánh su dai", "slug": "banh-su-dai", "numbers": (29,)},
)
CATEGORIES = tuple({**category, "order": i+1, "folder": f"{i+1:02d}-{category['slug']}",
                    "numbers": tuple(n for n in category["numbers"] if n not in EXCLUDED_NUMBERS)}
                   for i, category in enumerate(CATEGORIES))
TYPE_FOR_NUMBER = {number: category for category in CATEGORIES for number in category["numbers"]}
PENDING_LABEL = "Chờ bổ sung ảnh"
PENDING_CONFIRMATION_LABEL = "Chờ xác nhận ảnh"
