"""Unit tests for baker.code_gen — product code generation and validation."""

import pytest

from baker.code_gen import (
    generate_cake_code,
    generate_code,
    generate_set_code,
    get_category_prefix,
    validate_code_format,
)
from baker.db.connection import get_db
from baker.db.schema import ensure_schema


@pytest.fixture
def db_conn(use_memory_db):
    """Open a DB connection with schema (categories seeded)."""
    with get_db() as conn:
        ensure_schema(conn)
        yield conn


# --- validate_code_format ---


@pytest.mark.parametrize("code", [
    "BMI-01",
    "BKS-16",
    "BKS-16C",
    "BNG-S06",
    "CKI-03",
    "KHA-01",
    "AB-1",
    "AB-AB",
    "ABC-1234",
    # Relaxed: 4-char prefix, long suffix, mixed-case suffix, single-char prefix
    "ABCD-01",
    "BMI-12345",
    "BMI-0a",
    "B-01",
])
def test_validate_code_format_valid(code):
    assert validate_code_format(code) is True


@pytest.mark.parametrize("code", [
    "",
    "bmi-01",           # lowercase prefix
    "BMI01",            # no dash
    "BMI-",             # empty suffix
    "BMI 01",           # space instead of dash
])
def test_validate_code_format_invalid(code):
    assert validate_code_format(code) is False


# --- get_category_prefix ---


def test_get_prefix_by_slug(db_conn):
    assert get_category_prefix(db_conn, "banh_mi") == "BMI"
    assert get_category_prefix(db_conn, "banh_kem") == "BKS"
    assert get_category_prefix(db_conn, "banh_ngot") == "BNG"
    assert get_category_prefix(db_conn, "cookie") == "CKI"
    assert get_category_prefix(db_conn, "khac") == "KHA"


def test_get_prefix_by_legacy_category(db_conn):
    """Legacy category names ('bread', 'cake', etc.) still resolve to prefix."""
    assert get_category_prefix(db_conn, "bread") == "BMI"
    assert get_category_prefix(db_conn, "cake") == "BKS"
    assert get_category_prefix(db_conn, "pastry") == "BNG"
    assert get_category_prefix(db_conn, "cookie") == "CKI"
    assert get_category_prefix(db_conn, "other") == "KHA"


def test_get_prefix_unknown_category_returns_none(db_conn):
    assert get_category_prefix(db_conn, "nonexistent") is None


# --- generate_code (sequential) ---


def test_generate_code_for_empty_prefix(db_conn):
    """When no products exist with this prefix, starts at 01."""
    # Remove seeded products to get a clean slate for counting
    db_conn.execute("DELETE FROM products WHERE product_code LIKE 'BMI-%'")
    code = generate_code(db_conn, "banh_mi")
    assert code == "BMI-01"


def test_generate_code_increments_after_existing(db_conn):
    """Next code is one above the highest existing sequential number."""
    # After seeding, 5 bread products have BMI-01 .. BMI-05
    code = generate_code(db_conn, "banh_mi")
    assert code == "BMI-06"


def test_generate_code_ignores_set_codes(db_conn):
    """Set codes (PREFIX-SNN) do not affect sequential numbering."""
    # banh_ngot has seeded sequential BNG-01..BNG-05 + set codes BNG-S06,S08,S10,S12,S15
    code = generate_code(db_conn, "banh_ngot")
    assert code == "BNG-06"


def test_generate_code_unknown_category_returns_none(db_conn):
    assert generate_code(db_conn, "nonexistent") is None


# --- generate_set_code ---


def test_generate_set_code_format(db_conn):
    assert generate_set_code(db_conn, "banh_ngot", 6) == "BNG-S06"
    assert generate_set_code(db_conn, "banh_ngot", 10) == "BNG-S10"
    assert generate_set_code(db_conn, "banh_ngot", 15) == "BNG-S15"


def test_generate_set_code_unknown_category_returns_none(db_conn):
    assert generate_set_code(db_conn, "nonexistent", 6) is None


# --- generate_cake_code ---


def test_generate_cake_code_standard(db_conn):
    assert generate_cake_code(db_conn, 16) == "BKS-16"
    assert generate_cake_code(db_conn, 18) == "BKS-18"
    assert generate_cake_code(db_conn, 20) == "BKS-20"
    assert generate_cake_code(db_conn, 22) == "BKS-22"


def test_generate_cake_code_tall(db_conn):
    assert generate_cake_code(db_conn, 16, "tall") == "BKS-16C"
    assert generate_cake_code(db_conn, 22, "tall") == "BKS-22C"


def test_generate_cake_code_tiered(db_conn):
    assert generate_cake_code(db_conn, 16, "tiered") == "BKS-16T"
    assert generate_cake_code(db_conn, 20, "tiered") == "BKS-20T"


def test_generate_cake_code_unknown_category_returns_none(db_conn):
    """Fails gracefully if banh_kem category is missing."""
    db_conn.execute("DELETE FROM categories WHERE slug = 'banh_kem'")
    assert generate_cake_code(db_conn, 16) is None
