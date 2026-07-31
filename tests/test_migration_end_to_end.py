"""End-to-end migration test: v0 → current max on a fresh database.

DG-308 Phase 5 (FR-DB-1): verifies that applying the full migration chain
from an empty database produces every expected table, key index, and seed
data row. This complements the per-version tests in ``test_db_schema.py``
(which target individual migrations) by asserting the *combined* result of
the entire chain.

The plan specifies ``v0→v87``; the chain has since been extended to v88
(composite indexes only). This test runs the full chain to the current max
(v88, which includes v87's delivery-GPS columns) and asserts v87's surface
explicitly, so it satisfies the FR-DB-1 requirement and stays accurate as
the chain grows.
"""

import pytest

from baker.db.connection import get_db
from baker.db.schema import MIGRATIONS, ensure_schema

pytestmark = pytest.mark.critical

# Every table created across all migrations (v1–v88). Sourced from the
# migration survey; kept in sync with ``docs/database-schema.md``.
_EXPECTED_TABLES = {
    # v1
    "events", "orders", "inventory", "products", "schema_version",
    # v2
    "staff", "event_people",
    # v4
    "categories",
    # v7
    "product_catalog_photos",
    # v8
    "photos",
    # v11
    "order_photos",
    # v12
    "order_items", "payment_transactions",
    # v14
    "app_config",
    # v15
    "server_logs", "log_triggers",
    # v18
    "checklist_templates", "checklist_entries",
    # v19
    "order_history",
    # v22
    "knowledge_entries", "knowledge_entry_photos",
    # v23
    "product_attributes", "product_attribute_values",
    # v26 (product_stock is created here but migrated/dropped in v36)
    "stock_movements",
    # v27/28
    "catalog_photo_tags",
    # v30
    "product_price_chips",
    # v31
    "product_attribute_options",
    # v32
    "print_log",
    # v33/34
    "reconciliation_sessions", "reconciliation_lines", "reconciliation_sale_rows",
    # v36
    "stock_lots", "inventory_items",
    # v40/41
    "event_photos",
    # v43
    "event_history",
    # v44
    "accounts", "journal_entries", "journal_lines",
    # v45
    "cost_history",
    # v56/58/60
    "customers", "customer_phones", "customer_year_summary",
    # v62
    "negative_balance",
    # v65
    "journal_sync_failure_log",
    # v68/69/70
    "users", "audit_log", "sessions",
    # v81/83
    "blanks", "product_blank_bom", "blank_stock", "blank_stock_log",
    "order_item_blanks",
    # v86
    "expense_categories",
}

# Key composite / unique indexes that must exist after the full chain.
_EXPECTED_INDEXES = {
    "idx_orders_status_due_date",            # v88
    "idx_orders_customer_id_created_at",     # v88
    "idx_orders_due_date_public_order_code_unique",
    "idx_stock_lots_fifo",
    "idx_stock_lots_product_chip",
    "idx_negative_balance_product_chip",
    "idx_journal_entries_source",
    "idx_journal_entries_transaction_date",
    "idx_order_item_blanks_item_blank_unique",
    "idx_cost_history_product_effective",
    "idx_failure_log_type_id",
    "idx_checklist_entries_unique",
    "idx_catalog_photo_tags_unique",
    "idx_event_history_event",
}

# Chart-of-accounts codes that must be seeded (v44 + runtime additions v54/v73/v76/v85).
_EXPECTED_COA_CODES = {
    "1000", "1100", "1200", "1210", "1220", "1290", "1300", "1500", "1600",
    "2000", "2100", "2200", "2300", "2400", "2500",
    "3000", "3100",
    "4000", "4100",
    "5000", "5100", "5110", "5120", "5130", "5140",
    "5200", "5210", "5220", "5230",
    "5300", "5400", "5500", "5600", "5700", "5800", "5900",
}


def _table_names(conn) -> set[str]:
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ).fetchall()
    return {r[0] for r in rows}


def _index_names(conn) -> set[str]:
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name IS NOT NULL"
    ).fetchall()
    return {r[0] for r in rows}


def test_end_to_end_migration_v0_to_current_max_on_fresh_db():
    """Apply the full migration chain on an empty DB and verify the result.

    This is the FR-DB-1 automated verification of the full migration chain.
    """
    with get_db() as conn:
        # Fresh DB: no schema_version table yet.
        assert conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
        ).fetchone() is None

        # Run the full chain via the real entry point.
        ensure_schema(conn)

        current_max = max(MIGRATIONS.keys())
        row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
        assert row[0] == current_max, (
            f"schema_version max = {row[0]!r}, expected {current_max}"
        )
        # Explicitly assert v87 (FR-DB-1) and v88 (current) both applied.
        applied = {
            r[0] for r in conn.execute("SELECT version FROM schema_version").fetchall()
        }
        assert 87 in applied, "v87 (delivery GPS) not in applied migrations"
        assert 88 in applied, "v88 (composite indexes) not in applied migrations"
        assert 89 in applied, "v89 (assigned_staff_id) not in applied migrations"
        assert len(applied) == current_max, (
            f"expected {current_max} applied version rows, got {len(applied)}"
        )


def test_end_to_end_migration_creates_all_expected_tables():
    with get_db() as conn:
        ensure_schema(conn)
        tables = _table_names(conn)
        missing = _EXPECTED_TABLES - tables
        assert not missing, f"Missing tables after full migration: {sorted(missing)}"
        # No unexpected extra tables (other than temporary/rebuild artifacts).
        unexpected = tables - _EXPECTED_TABLES
        # Allow the catalog_photo_tags rebuild artifact if present.
        unexpected -= {"catalog_photo_tags_new"}
        assert not unexpected, f"Unexpected extra tables: {sorted(unexpected)}"


def test_end_to_end_migration_creates_key_indexes():
    with get_db() as conn:
        ensure_schema(conn)
        indexes = _index_names(conn)
        missing = _EXPECTED_INDEXES - indexes
        assert not missing, f"Missing key indexes after full migration: {sorted(missing)}"


def test_end_to_end_migration_v87_delivery_gps_columns_present():
    """FR-DB-1: v87 adds the delivery-schedule + GPS columns to orders."""
    with get_db() as conn:
        ensure_schema(conn)
        cols = {
            r[1]
            for r in conn.execute("PRAGMA table_info(orders)").fetchall()
        }
        for col in ("latitude", "longitude", "google_maps_url", "delivery_time_slot"):
            assert col in cols, f"orders.{col} missing after v87 migration"


def test_end_to_end_migration_seeds_chart_of_accounts():
    with get_db() as conn:
        ensure_schema(conn)
        codes = {
            r[0]
            for r in conn.execute("SELECT code FROM accounts WHERE is_active = 1").fetchall()
        }
        missing = _EXPECTED_COA_CODES - codes
        assert not missing, f"Missing active chart-of-accounts codes: {sorted(missing)}"


def test_end_to_end_migration_seeds_products_and_categories():
    """v3 seeds 23 products; v4 seeds categories."""
    with get_db() as conn:
        ensure_schema(conn)
        product_count = conn.execute("SELECT COUNT(*) FROM products").fetchone()[0]
        assert product_count >= 23, f"expected >=23 seeded products, got {product_count}"
        category_count = conn.execute("SELECT COUNT(*) FROM categories").fetchone()[0]
        assert category_count >= 1, f"expected seeded categories, got {category_count}"


def test_end_to_end_migration_seeds_staff():
    """v16 seeds 5 staff members."""
    with get_db() as conn:
        ensure_schema(conn)
        staff_count = conn.execute("SELECT COUNT(*) FROM staff").fetchone()[0]
        assert staff_count >= 5, f"expected >=5 seeded staff, got {staff_count}"


def test_end_to_end_migration_seeds_checklist_templates():
    """v18 seeds opening + closing checklist templates."""
    with get_db() as conn:
        ensure_schema(conn)
        template_count = conn.execute(
            "SELECT COUNT(*) FROM checklist_templates"
        ).fetchone()[0]
        assert template_count >= 2, (
            f"expected >=2 seeded checklist templates, got {template_count}"
        )


def test_end_to_end_migration_seeds_nhan_banh_options():
    """v31 seeds 5 filling options for the nhan_banh attribute."""
    with get_db() as conn:
        ensure_schema(conn)
        attr_row = conn.execute(
            "SELECT id FROM product_attributes WHERE attribute_type = 'nhan_banh'"
        ).fetchone()
        assert attr_row is not None, "nhan_banh attribute not seeded"
        opt_count = conn.execute(
            "SELECT COUNT(*) FROM product_attribute_options WHERE attribute_id = ?",
            (attr_row[0],),
        ).fetchone()[0]
        assert opt_count == 5, f"expected 5 nhan_banh options, got {opt_count}"


def test_end_to_end_migration_seeds_expense_categories():
    """v86 seeds expense subcategories."""
    with get_db() as conn:
        ensure_schema(conn)
        ec_count = conn.execute(
            "SELECT COUNT(*) FROM expense_categories"
        ).fetchone()[0]
        assert ec_count >= 1, f"expected seeded expense_categories, got {ec_count}"


def test_end_to_end_migration_seeds_users_from_staff():
    """v68 seeds existing staff as users."""
    with get_db() as conn:
        ensure_schema(conn)
        user_count = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        assert user_count >= 5, f"expected >=5 seeded users, got {user_count}"


def test_end_to_end_migration_double_entry_integrity():
    """Any journal entries backfilled by the chain must balance (debit==credit)."""
    with get_db() as conn:
        ensure_schema(conn)
        rows = conn.execute(
            """
            SELECT je.id, SUM(jl.debit) AS d, SUM(jl.credit) AS c
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            GROUP BY je.id
            """
        ).fetchall()
        for r in rows:
            assert abs(float(r[1]) - float(r[2])) < 0.005, (
                f"journal entry {r[0]} unbalanced: debit={r[1]} credit={r[2]}"
            )


def test_end_to_end_migration_idempotent():
    """Re-running ensure_schema on a fully-migrated DB is a no-op."""
    with get_db() as conn:
        ensure_schema(conn)
        first_counts = (
            conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0],
            conn.execute("SELECT COUNT(*) FROM products").fetchone()[0],
            conn.execute("SELECT COUNT(*) FROM users").fetchone()[0],
            conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0],
        )
        ensure_schema(conn)
        second_counts = (
            conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0],
            conn.execute("SELECT COUNT(*) FROM products").fetchone()[0],
            conn.execute("SELECT COUNT(*) FROM users").fetchone()[0],
            conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0],
        )
        assert first_counts == second_counts, (
            f"idempotent re-run changed counts: {first_counts} -> {second_counts}"
        )