"""Integration tests for v59 migration: deduplicate customers by name.

DG-205 follow-up. Covers merging duplicate customers that share the same
case-insensitive trimmed name, reassigning orders to the winner, and deleting
duplicates. Idempotent — re-running is a no-op.
"""

import sqlite3

from baker.db.schema import _migrate_v59_deduplicate_customers


def _setup_db() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE TABLE customer_phones (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER NOT NULL REFERENCES customers(id),
            phone TEXT NOT NULL,
            is_primary INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE TABLE orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER REFERENCES customers(id),
            customer_name TEXT NOT NULL DEFAULT '',
            customer_phone TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        """
    )
    return conn


def test_v59_no_duplicates_is_noop():
    conn = _setup_db()
    conn.execute("INSERT INTO customers (name, phone) VALUES ('A', '1')")
    conn.execute("INSERT INTO customers (name, phone) VALUES ('B', '2')")
    conn.commit()

    _migrate_v59_deduplicate_customers(conn)

    rows = conn.execute("SELECT id, name FROM customers ORDER BY id").fetchall()
    assert len(rows) == 2
    assert rows[0]["name"] == "A"
    assert rows[1]["name"] == "B"


def test_v59_merges_exact_name_duplicates():
    conn = _setup_db()
    conn.execute("INSERT INTO customers (name, phone) VALUES ('Yu Ri', '0368865293')")
    conn.execute("INSERT INTO customers (name, phone) VALUES ('Yu Ri', '')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (1, 'Yu Ri')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (2, 'Yu Ri')")
    conn.commit()

    _migrate_v59_deduplicate_customers(conn)

    rows = conn.execute("SELECT id, name FROM customers ORDER BY id").fetchall()
    assert len(rows) == 1
    assert rows[0]["name"] == "Yu Ri"

    orders = conn.execute(
        "SELECT customer_id FROM orders ORDER BY id"
    ).fetchall()
    assert all(o["customer_id"] == rows[0]["id"] for o in orders)


def test_v59_merges_case_insensitive_duplicates():
    conn = _setup_db()
    conn.execute("INSERT INTO customers (name, phone) VALUES ('Hương Giang', '0984615614')")
    conn.execute("INSERT INTO customers (name, phone) VALUES ('hương giang', '')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (1, 'Hương Giang')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (2, 'hương giang')")
    conn.commit()

    _migrate_v59_deduplicate_customers(conn)

    rows = conn.execute("SELECT id, name FROM customers ORDER BY id").fetchall()
    assert len(rows) == 1

    orders = conn.execute(
        "SELECT customer_id FROM orders ORDER BY id"
    ).fetchall()
    assert all(o["customer_id"] == rows[0]["id"] for o in orders)


def test_v59_keeps_customer_with_most_orders():
    conn = _setup_db()
    conn.execute("INSERT INTO customers (name, phone) VALUES ('A', '')")
    conn.execute("INSERT INTO customers (name, phone) VALUES ('A', '1')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (1, 'A')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (2, 'A')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (2, 'A')")
    conn.commit()

    _migrate_v59_deduplicate_customers(conn)

    rows = conn.execute("SELECT id, name, phone FROM customers ORDER BY id").fetchall()
    assert len(rows) == 1
    assert rows[0]["id"] == 2
    assert rows[0]["phone"] == "1"


def test_v59_earliest_id_wins_on_tie():
    conn = _setup_db()
    conn.execute("INSERT INTO customers (name, phone) VALUES ('A', '1')")
    conn.execute("INSERT INTO customers (name, phone) VALUES ('A', '2')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (1, 'A')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (2, 'A')")
    conn.commit()

    _migrate_v59_deduplicate_customers(conn)

    rows = conn.execute("SELECT id, name FROM customers ORDER BY id").fetchall()
    assert len(rows) == 1
    assert rows[0]["id"] == 1


def test_v59_idempotent():
    conn = _setup_db()
    conn.execute("INSERT INTO customers (name, phone) VALUES ('A', '1')")
    conn.execute("INSERT INTO customers (name, phone) VALUES ('A', '')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (1, 'A')")
    conn.execute("INSERT INTO orders (customer_id, customer_name) VALUES (2, 'A')")
    conn.commit()

    _migrate_v59_deduplicate_customers(conn)
    rows1 = conn.execute("SELECT id FROM customers ORDER BY id").fetchall()
    assert len(rows1) == 1

    _migrate_v59_deduplicate_customers(conn)
    rows2 = conn.execute("SELECT id FROM customers ORDER BY id").fetchall()
    assert len(rows2) == 1
    assert rows2[0]["id"] == rows1[0]["id"]


def test_v59_cleans_up_customer_phones():
    conn = _setup_db()
    conn.execute("INSERT INTO customers (name, phone) VALUES ('A', '1')")
    conn.execute("INSERT INTO customers (name, phone) VALUES ('A', '2')")
    conn.execute("INSERT INTO customer_phones (customer_id, phone, is_primary) VALUES (1, '1', 1)")
    conn.execute("INSERT INTO customer_phones (customer_id, phone, is_primary) VALUES (2, '2', 1)")
    conn.commit()

    _migrate_v59_deduplicate_customers(conn)

    phones = conn.execute(
        "SELECT customer_id, phone FROM customer_phones"
    ).fetchall()
    assert len(phones) == 1
    assert phones[0]["customer_id"] == 1
    assert phones[0]["phone"] == "1"


def test_v59_skips_empty_name():
    conn = _setup_db()
    conn.execute("INSERT INTO customers (name, phone) VALUES ('', '')")
    conn.execute("INSERT INTO customers (name, phone) VALUES ('', '')")
    conn.commit()

    _migrate_v59_deduplicate_customers(conn)

    rows = conn.execute("SELECT id FROM customers").fetchall()
    assert len(rows) == 2
