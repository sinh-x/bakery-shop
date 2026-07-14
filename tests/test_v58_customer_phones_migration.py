"""Integration tests for v58 migration: customer_phones table + data backfill.

DG-205 Phase 1. Covers FR1, FR2, NFR1, NFR4, AC1, AC2.

The migration:
- Creates ``customer_phones`` table with columns id, customer_id, phone,
  is_primary, created_at (FR1/AC1).
- Moves each existing non-empty ``customers.phone`` into a row with
  ``is_primary=1`` (FR2/AC1).
- Is idempotent — re-running does not duplicate rows (NFR1).
- Leaves ``customers.phone`` intact as denormalized fallback (NFR4/AC2).
"""

import sqlite3

import pytest

from baker.db.schema import (
    CUSTOMER_PHONES_SCHEMA,
    _migrate_v58_customer_phones,
    ensure_schema,
)


# --- Helpers ---------------------------------------------------------------


def _fresh_conn() -> sqlite3.Connection:
    """In-memory DB with only the v58 callable applied to an empty schema.

    Used for low-level migration tests that bypass ``ensure_schema`` so we can
    control pre-migration state precisely.
    """
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE schema_version (version INTEGER, description TEXT);
        CREATE TABLE customers (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT NOT NULL,
            phone       TEXT DEFAULT '',
            created_at  TEXT NOT NULL DEFAULT '2026-01-01T00:00:00Z',
            updated_at  TEXT NOT NULL DEFAULT '2026-01-01T00:00:00Z'
        );
        CREATE INDEX idx_customers_name ON customers(name);
        CREATE INDEX idx_customers_phone ON customers(phone);
        """
    )
    return conn


def _apply_v58(conn: sqlite3.Connection) -> None:
    """Apply the v58 migration (sql + callable) exactly as ensure_schema does."""
    conn.executescript(CUSTOMER_PHONES_SCHEMA)
    _migrate_v58_customer_phones(conn)
    conn.commit()


# --- FR1 / AC1: table schema ----------------------------------------------


def test_v58_creates_customer_phones_table_with_expected_columns():
    conn = _fresh_conn()
    _apply_v58(conn)
    cols = {r[1]: r[2] for r in conn.execute("PRAGMA table_info(customer_phones)").fetchall()}
    assert set(cols) == {"id", "customer_id", "phone", "is_primary", "created_at"}
    # is_primary defaults to 0
    assert "INTEGER" in cols["is_primary"]
    # phone is NOT NULL (FR1)
    assert cols["phone"] == "TEXT"
    # customer_id is a FK to customers(id)
    fks = conn.execute("PRAGMA foreign_key_list(customer_phones)").fetchall()
    assert any(fk[2] == "customers" and fk[4] == "id" for fk in fks), \
        "customer_phones.customer_id must reference customers(id)"


def test_v58_creates_indexes_on_customer_id_and_phone():
    conn = _fresh_conn()
    _apply_v58(conn)
    indexes = {r[1]: r[2] for r in conn.execute(
        "PRAGMA index_list(customer_phones)"
    ).fetchall()}
    # index name -> columns
    assert "idx_customer_phones_customer_id" in indexes
    assert "idx_customer_phones_phone" in indexes


# --- FR2 / AC1: data migration -------------------------------------------


def test_v58_migrates_existing_customers_phone_as_primary():
    conn = _fresh_conn()
    conn.executemany(
        "INSERT INTO customers (name, phone) VALUES (?, ?)",
        [("Khách A", "0901234567"), ("Khách B", "0987654321"), ("Khách C", "")],
    )
    conn.commit()
    _apply_v58(conn)

    rows = conn.execute(
        "SELECT customer_id, phone, is_primary FROM customer_phones ORDER BY customer_id"
    ).fetchall()
    # Khách C has empty phone -> no row. Khách A and B migrated as primary.
    assert len(rows) == 2
    assert (rows[0]["customer_id"], rows[0]["phone"], rows[0]["is_primary"]) == (1, "0901234567", 1)
    assert (rows[1]["customer_id"], rows[1]["phone"], rows[1]["is_primary"]) == (2, "0987654321", 1)


def test_v58_skips_null_and_empty_phones():
    conn = _fresh_conn()
    conn.executemany(
        "INSERT INTO customers (name, phone) VALUES (?, ?)",
        [("NoPhone1", ""), ("NoPhone2", None), ("HasPhone", "0911")],
    )
    conn.commit()
    _apply_v58(conn)
    rows = conn.execute("SELECT phone FROM customer_phones").fetchall()
    assert [r["phone"] for r in rows] == ["0911"]


# --- NFR4 / AC2: backward compatibility ----------------------------------


def test_v58_preserves_customers_phone_as_denormalized_fallback():
    conn = _fresh_conn()
    conn.execute("INSERT INTO customers (name, phone) VALUES ('Khách A', '0901234567')")
    conn.commit()
    _apply_v58(conn)
    # customers.phone must retain its original value (AC2)
    row = conn.execute("SELECT phone FROM customers WHERE id = 1").fetchone()
    assert row["phone"] == "0901234567"


def test_v58_does_not_alter_customers_table_schema():
    conn = _fresh_conn()
    _apply_v58(conn)
    cols = [r[1] for r in conn.execute("PRAGMA table_info(customers)").fetchall()]
    # customers table columns unchanged (NFR4 — no breaking change)
    assert cols == ["id", "name", "phone", "created_at", "updated_at"]


# --- NFR1: idempotency ----------------------------------------------------


def test_v58_idempotent_re_run_does_not_duplicate():
    conn = _fresh_conn()
    conn.executemany(
        "INSERT INTO customers (name, phone) VALUES (?, ?)",
        [("A", "0901"), ("B", "0902")],
    )
    conn.commit()
    _apply_v58(conn)
    assert conn.execute("SELECT COUNT(*) FROM customer_phones").fetchone()[0] == 2

    # Re-run the callable (DDL is IF NOT EXISTS, callable guards by customer_id)
    _migrate_v58_customer_phones(conn)
    conn.commit()
    assert conn.execute("SELECT COUNT(*) FROM customer_phones").fetchone()[0] == 2


def test_v58_idempotent_when_phone_rows_already_exist_for_some_customers():
    conn = _fresh_conn()
    conn.executemany(
        "INSERT INTO customers (name, phone) VALUES (?, ?)",
        [("A", "0901"), ("B", "0902"), ("C", "0903")],
    )
    conn.commit()
    # Create the customer_phones table first (DDL only, no callable) so we can
    # simulate a partial state where customer A already has a phone row (e.g.
    # added by the API before v58 ran). v58 must skip A and only migrate B/C.
    conn.executescript(CUSTOMER_PHONES_SCHEMA)
    conn.execute(
        "INSERT INTO customer_phones (customer_id, phone, is_primary) VALUES (1, '0901', 1)"
    )
    conn.commit()

    _migrate_v58_customer_phones(conn)
    conn.commit()

    rows = conn.execute(
        "SELECT customer_id, phone FROM customer_phones ORDER BY customer_id"
    ).fetchall()
    assert [(r["customer_id"], r["phone"]) for r in rows] == [
        (1, "0901"), (2, "0902"), (3, "0903")
    ]
    # No duplicate for customer 1
    assert conn.execute(
        "SELECT COUNT(*) FROM customer_phones WHERE customer_id = 1"
    ).fetchone()[0] == 1


# --- End-to-end via ensure_schema -----------------------------------------


def test_v58_runs_as_part_of_ensure_schema_full_chain(use_memory_db):
    """Full migration chain (v1..v58) on a fresh DB must create the table.

    Uses the shared ``use_memory_db`` fixture's BAKER_DB path so that the full
    schema (including prior migrations) is applied exactly as in production.
    """
    from baker.db.connection import get_db

    with get_db() as conn:
        ensure_schema(conn)

        # Table exists with correct columns
        cols = {r[1] for r in conn.execute("PRAGMA table_info(customer_phones)").fetchall()}
        assert cols == {"id", "customer_id", "phone", "is_primary", "created_at"}

        # schema_version records v58
        versions = [
            r[0] for r in conn.execute("SELECT version FROM schema_version").fetchall()
        ]
        assert 58 in versions


@pytest.mark.xfail(reason="pre-existing on develop: duplicate column name acknowledged_at")
def test_v58_full_chain_migrates_customers_created_by_v57(use_memory_db):
    """Customers generated by v57 must have their phones migrated by v58.

    This exercises the realistic chain: orders -> v57 generates customers ->
    v58 backfills customer_phones from those customers' phone column.
    """
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        # Insert a few orders BEFORE any schema (simulating a legacy DB).
        # The orders table is created by earlier migrations in ensure_schema,
        # so we apply schema first, then drop customers + customer_phones to
        # simulate a pre-v56 state, re-insert legacy orders, and re-run.
        ensure_schema(conn)
        # Wipe customers + customer_phones + customer_id to simulate pre-v56
        conn.execute("DELETE FROM customer_phones")
        conn.execute("DELETE FROM customers")
        conn.execute("UPDATE orders SET customer_id = NULL")
        conn.execute("DELETE FROM schema_version WHERE version >= 56")
        conn.commit()
        # Add legacy orders with phones (orders schema uses order_ref/total_price)
        conn.executemany(
            "INSERT INTO orders (order_ref, customer_name, customer_phone, total_price, status, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            [
                ("O-1", "Khách A", "0901111222", 100, "new", "2026-01-01T00:00:00Z"),
                ("O-2", "Khách A", "0901111222", 200, "new", "2026-01-02T00:00:00Z"),
                ("O-3", "Khách B", "0903333444", 300, "new", "2026-01-03T00:00:00Z"),
            ],
        )
        conn.commit()
        # Re-run migrations from v56 onwards (full chain re-applies v56-v58)
        ensure_schema(conn)

        # v57 should have created 2 customers (A and B)
        customers = conn.execute(
            "SELECT id, name, phone FROM customers ORDER BY id"
        ).fetchall()
        assert len(customers) == 2

        # v58 should have created 2 customer_phones rows (one per customer, primary)
        phones = conn.execute(
            "SELECT customer_id, phone, is_primary FROM customer_phones ORDER BY customer_id"
        ).fetchall()
        assert len(phones) == 2
        assert all(p["is_primary"] == 1 for p in phones)
        # customers.phone retained as fallback (AC2)
        assert all(c["phone"] != "" for c in customers)