"""Product code generation utilities.

Convention:
  Simple product:  PREFIX-NN       e.g. BMI-01, CKI-03
  Set product:     PREFIX-SNN      e.g. BNG-S06, BNG-S10
  Cake (standard): BKS-NN          e.g. BKS-16 (16cm)
  Cake (tall):     BKS-NNC         e.g. BKS-16C (16cm cao)
  Cake (tiered):   BKS-NNT         e.g. BKS-16T (16cm nhiều tầng)
"""

import re

# Accepted format: 2-3 uppercase letters, dash, 1-4 uppercase letters/digits
_CODE_FORMAT = re.compile(r"^[A-Z]{2,3}-[A-Z0-9]{1,4}$")

# Map legacy product.category values → categories.slug
_LEGACY_CATEGORY_MAP = {
    "bread": "banh_mi",
    "cake": "banh_kem",
    "pastry": "banh_ngot",
    "cookie": "cookie",
    "other": "khac",
}


def validate_code_format(code: str) -> bool:
    """Return True if *code* matches the required format ^[A-Z]{2,3}-[A-Z0-9]{1,4}$."""
    return bool(_CODE_FORMAT.match(code))


def get_category_prefix(conn, category_slug: str) -> str | None:
    """Return code_prefix for a category slug (new or legacy).

    Returns None if the category is not found in the categories table.
    """
    slug = _LEGACY_CATEGORY_MAP.get(category_slug, category_slug)
    row = conn.execute(
        "SELECT code_prefix FROM categories WHERE slug = ? AND active = 1",
        (slug,),
    ).fetchone()
    return row["code_prefix"] if row else None


def _max_sequential_number(conn, prefix: str) -> int:
    """Find the highest sequential number used for PREFIX-NN codes.

    Ignores set codes (PREFIX-SNN) and cake-size codes (PREFIX-NNC / PREFIX-NNT).
    Returns 0 if no matching codes exist.
    """
    rows = conn.execute(
        "SELECT product_code FROM products WHERE product_code LIKE ?",
        (f"{prefix}-%",),
    ).fetchall()

    pattern = re.compile(rf"^{re.escape(prefix)}-(\d{{2}})$")
    max_num = 0
    for row in rows:
        code = row["product_code"]
        m = pattern.match(code)
        if m:
            num = int(m.group(1))
            if num > max_num:
                max_num = num
    return max_num


def generate_code(conn, category_slug: str) -> str | None:
    """Auto-generate a sequential product code for a category.

    Returns 'PREFIX-NN' (e.g. 'BMI-01', 'CKI-03').
    Returns None if the category is not found.
    """
    prefix = get_category_prefix(conn, category_slug)
    if not prefix:
        return None
    n = _max_sequential_number(conn, prefix) + 1
    return f"{prefix}-{n:02d}"


def generate_set_code(conn, category_slug: str, quantity: int) -> str | None:
    """Generate a set product code for a given quantity.

    Returns 'PREFIX-SNN' (e.g. 'BNG-S06', 'BNG-S10').
    Returns None if the category is not found.
    """
    prefix = get_category_prefix(conn, category_slug)
    if not prefix:
        return None
    return f"{prefix}-S{quantity:02d}"


def generate_cake_code(conn, size_cm: int, cake_type: str = "standard") -> str | None:
    """Generate a cake product code by size and type.

    cake_type:
      'standard' -> BKS-16 (thường)
      'tall'     -> BKS-16C (cao)
      'tiered'   -> BKS-16T (nhiều tầng)

    Returns None if the banh_kem category is not found.
    """
    prefix = get_category_prefix(conn, "banh_kem")
    if not prefix:
        return None
    suffix_map = {"standard": "", "tall": "C", "tiered": "T"}
    suffix = suffix_map.get(cake_type, "")
    return f"{prefix}-{size_cm}{suffix}"
