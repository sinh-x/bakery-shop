"""Tests for DG-302 Phase 1: expense_categories table + seed data + account
codes + mapping updates.

Verifies:
- The v86 migration creates the ``expense_categories`` table with the
  expected schema (id, name, account_code, parent_id, created_at).
- 8 parent categories + 7 subcategories are seeded (idempotent on re-run).
- Subcategory account codes 5110–5140, 5210–5230 exist in the chart of
  accounts (accounts table).
- ``EXPENSE_CATEGORY_TO_ACCOUNT_CODE`` contains every subcategory key with
  the FR4 mapping.
- ``INVENTORY_PURCHASE_CATEGORIES`` contains every subcategory name (so
  subcategory expenses still debit Inventory, not the subcategory expense
  account).
- AC4 partial: an expense event with subcategory "Trứng" resolves to account
  code 5110 through the static mapping (full journal verification is
  deferred to Phase 6 accounting integration).
"""

import pytest

from baker.db.connection import get_db
from baker.db.schema import (
    EXPENSE_CATEGORY_TO_ACCOUNT_CODE,
    INVENTORY_PURCHASE_CATEGORIES,
    SEED_EXPENSE_CATEGORIES,
    ensure_schema,
)

pytestmark = pytest.mark.critical


# Expected FR4 subcategory → account code mapping (DG-302 §6 FR4).
EXPECTED_SUBCATEGORY_ACCOUNT_CODES = {
    "Trứng": "5110",
    "Kem": "5120",
    "Bột": "5130",
    "Phụ gia khác": "5140",
    "Hộp & đế": "5210",
    "Phụ kiện": "5220",
    "Bọc nilon": "5230",
}

EXPECTED_PARENT_CATEGORIES = {
    "Nguyên liệu",
    "Bao bì",
    "Vận chuyển",
    "Điện/nước",
    "Dụng cụ",
    "Sửa chữa",
    "Lương/phụ cấp",
    "Khác",
}


def _expense_category_rows(conn):
    return conn.execute(
        "SELECT id, name, account_code, parent_id FROM expense_categories"
    ).fetchall()


def _account_code_exists(conn, code: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM accounts WHERE code = ?", (code,)
    ).fetchone()
    return row is not None


def test_expense_categories_table_schema():
    """The v86 migration creates expense_categories with the required columns."""
    with get_db() as conn:
        ensure_schema(conn)
        cols = {
            row["name"]: row
            for row in conn.execute("PRAGMA table_info(expense_categories)").fetchall()
        }
    assert {"id", "name", "account_code", "parent_id", "created_at"} <= set(cols)
    # name and account_code are NOT NULL (id is PK, created_at has DEFAULT).
    assert cols["name"]["notnull"] == 1
    assert cols["account_code"]["notnull"] == 1
    # parent_id is nullable (subcategories reference parents, parents have NULL).
    assert cols["parent_id"]["notnull"] == 0


def test_expense_categories_seed_count():
    """Seed data: 8 parents + 7 subcategories = 15 rows."""
    with get_db() as conn:
        ensure_schema(conn)
        rows = _expense_category_rows(conn)
    assert len(rows) == 15
    parents = [r for r in rows if r["parent_id"] is None]
    subcategories = [r for r in rows if r["parent_id"] is not None]
    assert len(parents) == 8
    assert len(subcategories) == 7


def test_expense_categories_seed_contains_parent_names():
    """All 8 parent category names are seeded with NULL parent_id."""
    with get_db() as conn:
        ensure_schema(conn)
        rows = _expense_category_rows(conn)
    parent_names = {r["name"] for r in rows if r["parent_id"] is None}
    assert parent_names == EXPECTED_PARENT_CATEGORIES


def test_expense_categories_seed_contains_subcategory_names():
    """All 7 subcategory names are seeded with non-NULL parent_id."""
    with get_db() as conn:
        ensure_schema(conn)
        rows = _expense_category_rows(conn)
    subcategory_names = {r["name"] for r in rows if r["parent_id"] is not None}
    assert subcategory_names == set(EXPECTED_SUBCATEGORY_ACCOUNT_CODES.keys())


def test_expense_categories_subcategory_account_codes_match_fr4():
    """Each subcategory row's account_code matches the FR4 mapping."""
    with get_db() as conn:
        ensure_schema(conn)
        rows = _expense_category_rows(conn)
    for row in rows:
        if row["parent_id"] is None:
            continue
        assert row["account_code"] == EXPECTED_SUBCATEGORY_ACCOUNT_CODES[row["name"]]


def test_expense_categories_subcategory_parent_links():
    """Subcategories' parent_id points at the correct parent category row."""
    with get_db() as conn:
        ensure_schema(conn)
        rows = _expense_category_rows(conn)
    name_to_row = {r["name"]: r for r in rows}

    # Nguyên liệu subcategories
    nguyen_lieu_id = name_to_row["Nguyên liệu"]["id"]
    bao_bi_id = name_to_row["Bao bì"]["id"]
    for sub in ["Trứng", "Kem", "Bột", "Phụ gia khác"]:
        assert name_to_row[sub]["parent_id"] == nguyen_lieu_id, sub
    for sub in ["Hộp & đế", "Phụ kiện", "Bọc nilon"]:
        assert name_to_row[sub]["parent_id"] == bao_bi_id, sub


def test_expense_categories_seed_is_idempotent():
    """Re-running the v86 callable on an already-seeded DB is a no-op."""
    from baker.db.schema import _migrate_v86_expense_categories

    with get_db() as conn:
        ensure_schema(conn)
        rows_before = _expense_category_rows(conn)
        _migrate_v86_expense_categories(conn)
        rows_after = _expense_category_rows(conn)
    # Same row count and same (name, parent_id) set — no duplicates.
    assert len(rows_before) == len(rows_after) == 15
    assert {r["name"] for r in rows_before} == {r["name"] for r in rows_after}


def test_seed_expense_categories_constant_matches_expected():
    """The SEED_EXPENSE_CATEGORIES constant declares 8 parents + 7 subcategories."""
    parents = [row for row in SEED_EXPENSE_CATEGORIES if row[2] is None]
    subcategories = [row for row in SEED_EXPENSE_CATEGORIES if row[2] is not None]
    assert len(parents) == 8
    assert len(subcategories) == 7


def test_chart_of_accounts_has_subcategory_codes():
    """The new subcategory account codes 5110-5140, 5210-5230 exist in accounts."""
    expected_codes = list(EXPECTED_SUBCATEGORY_ACCOUNT_CODES.values())
    with get_db() as conn:
        ensure_schema(conn)
        for code in expected_codes:
            assert _account_code_exists(conn, code), f"missing account code {code}"


def test_chart_of_accounts_subcategory_parents():
    """Subcategory accounts are children of their parent expense account."""
    with get_db() as conn:
        ensure_schema(conn)
        # 5110-5140 parent is 5100; 5210-5230 parent is 5200.
        for code in ["5110", "5120", "5130", "5140"]:
            row = conn.execute(
                """SELECT a.code AS pcode FROM accounts a
                   JOIN accounts c ON c.parent_id = a.id
                   WHERE c.code = ?""",
                (code,),
            ).fetchone()
            assert row is not None, f"{code} has no parent account"
            assert row["pcode"] == "5100", f"{code} parent is {row['pcode']}, want 5100"
        for code in ["5210", "5220", "5230"]:
            row = conn.execute(
                """SELECT a.code AS pcode FROM accounts a
                   JOIN accounts c ON c.parent_id = a.id
                   WHERE c.code = ?""",
                (code,),
            ).fetchone()
            assert row is not None, f"{code} has no parent account"
            assert row["pcode"] == "5200", f"{code} parent is {row['pcode']}, want 5200"


def test_expense_category_to_account_code_includes_subcategories():
    """EXPENSE_CATEGORY_TO_ACCOUNT_CODE contains the FR4 subcategory mapping."""
    for sub, code in EXPECTED_SUBCATEGORY_ACCOUNT_CODES.items():
        assert EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(sub) == code, sub


def test_expense_category_to_account_code_retains_parent_keys():
    """Parent category keys remain for backward compatibility (FR6)."""
    for parent, code in {
        "Nguyên liệu": "5100",
        "Bao bì": "5200",
        "Vận chuyển": "5300",
        "Điện/nước": "5400",
        "Dụng cụ": "5500",
        "Sửa chữa": "5600",
        "Lương/phụ cấp": "5700",
        "Khác": "5800",
    }.items():
        assert EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(parent) == code, parent


def test_inventory_purchase_categories_includes_subcategories():
    """INVENTORY_PURCHASE_CATEGORIES includes Nguyên liệu/Bao bì subcategory
    names so subcategory-tagged expenses still debit Inventory (1300)."""
    for sub in EXPECTED_SUBCATEGORY_ACCOUNT_CODES.keys():
        assert sub in INVENTORY_PURCHASE_CATEGORIES, sub
    # Parent keys retained.
    assert "Nguyên liệu" in INVENTORY_PURCHASE_CATEGORIES
    assert "Bao bì" in INVENTORY_PURCHASE_CATEGORIES


def test_ac4_partial_trung_resolves_to_5110():
    """AC4 (partial): expense with subcategory 'Trứng' resolves to account 5110
    through the static mapping. Full journal verification is Phase 6."""
    assert EXPENSE_CATEGORY_TO_ACCOUNT_CODE["Trứng"] == "5110"