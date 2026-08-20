"""DG-387 Phase 3 — backfill correctness tests for the v102 migration.

Covers FR2 (backfill all unique ``(normalize_address, google_maps_url)``
pairs from door-delivery orders with non-empty Google Maps links into
``address_library``), FR3 (link ``customer_addresses`` for each
contributing customer), NFR1 (idempotent — re-run is a no-op reporting 0
new entries), and AC1/AC2/AC3/AC7.

The v102 migration callable is
``_migrate_v102_backfill_address_library`` in
``src/baker/db/schema/migrations/v102.py``. It is registered in the
``MIGRATIONS`` registry at version 102 and runs automatically inside
``ensure_schema``. These tests exercise the migration in three modes:

1. **Full ``ensure_schema`` path** — seed orders, run ``ensure_schema``
   (which applies v101 → v102), and assert the library/junction state.
2. **Direct callable re-run** — invoke
   ``_migrate_v102_backfill_address_library`` a second time on the same
   DB and assert 0 new rows (idempotency, NFR1/AC2).
3. **Summary log capture** — assert the
   ``"Đã backfill X địa chỉ, liên kết Y khách hàng."`` INFO line fires
   with the correct counts (AC7).

All tests use ``:memory:`` SQLite databases (per the deployment-primer
guardrails) so they are fast and hermetic. ``ensure_schema`` is the
production entry point; the direct-callable tests use the same
in-memory DB pattern.
"""

from __future__ import annotations

import logging

import pytest

from baker.db.schema import MIGRATIONS, ensure_schema
from baker.db.schema.migrations.v102 import _migrate_v102_backfill_address_library

pytestmark = pytest.mark.critical


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _new_memory_conn():
    """Return a fresh in-memory SQLite connection with the baker schema.

    Uses the same connection setup as ``baker.db.connection.get_db`` but on
    ``:memory:`` so each test gets an isolated DB without touching the
    filesystem.
    """
    import sqlite3

    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    ensure_schema(conn)
    return conn


def _insert_customer(conn, name="Khách A", phone="0901111222"):
    """Insert a customer row and return its id."""
    cursor = conn.execute(
        "INSERT INTO customers (name, phone, search_name) VALUES (?, ?, ?)",
        (name, phone, name.lower()),
    )
    return int(cursor.lastrowid)


def _insert_order(
    conn,
    *,
    order_ref,
    customer_id=None,
    delivery_type="door",
    delivery_address="",
    google_maps_url=None,
    status="delivered",
):
    """Insert an order row with the given delivery attributes.

    Only the columns relevant to the v102 backfill are parameterized; the
    rest get their defaults from the ``orders`` table schema.
    """
    conn.execute(
        """
        INSERT INTO orders (
            order_ref, customer_name, items, total_price, status,
            delivery_type, delivery_address, google_maps_url, customer_id
        ) VALUES (?, ?, '[]', 0, ?, ?, ?, ?, ?)
        """,
        (
            order_ref,
            "Khách test",
            status,
            delivery_type,
            delivery_address,
            google_maps_url,
            customer_id,
        ),
    )


def _library_count(conn):
    return int(
        conn.execute("SELECT COUNT(*) FROM address_library").fetchone()[0]
    )


def _customer_address_count(conn):
    return int(
        conn.execute("SELECT COUNT(*) FROM customer_addresses").fetchone()[0]
    )


def _library_rows(conn):
    return conn.execute(
        "SELECT normalized_address, display_address, google_maps_url "
        "FROM address_library ORDER BY normalized_address, google_maps_url"
    ).fetchall()


def _customer_address_rows(conn):
    return conn.execute(
        "SELECT customer_id, address_library_id "
        "FROM customer_addresses ORDER BY customer_id, address_library_id"
    ).fetchall()


# ---------------------------------------------------------------------------
# AC1 — backfill correctness (FR2)
# ---------------------------------------------------------------------------


def test_backfill_inserts_unique_pairs_from_door_delivery_orders():
    """AC1/FR2: unique ``(normalized_address, google_maps_url)`` pairs from
    door-delivery orders with non-empty links are inserted into
    ``address_library`` with no duplicates.
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        cust_b = _insert_customer(conn, name="Khách B", phone="0903333444")

        # 5 orders producing exactly 2 unique library pairs:
        #   - 2 orders share "123 Nguyễn Huệ" with the same url (dedup → 1)
        #   - 1 order has a diacritic variant "123 NGUYỄN HUỆ" with the same
        #     url → normalize_address collapses it to the same key (dedup → 1)
        #   - 1 order has a distinct address "45 Lê Lợi" with a different
        #     url (unique → 1)... but paired with the shared url above that
        #     gives 2 pairs total.
        #   - 1 order has an empty google_maps_url (skip)
        #   - 1 order is a pickup order (skip)
        _insert_order(
            conn,
            order_ref="ORD-1",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/1",
        )
        _insert_order(
            conn,
            order_ref="ORD-2",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 NGUYỄN HUỆ",
            google_maps_url="https://maps.google.com/1",
        )
        _insert_order(
            conn,
            order_ref="ORD-3",
            customer_id=cust_b,
            delivery_type="delivery",
            delivery_address="45 Lê Lợi",
            google_maps_url="https://maps.google.com/2",
        )
        _insert_order(
            conn,
            order_ref="ORD-4",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="78 Trần Hưng Đạo",
            google_maps_url="",
        )
        _insert_order(
            conn,
            order_ref="ORD-5",
            customer_id=cust_b,
            delivery_type="pickup",
            delivery_address="Cửa hàng",
            google_maps_url="https://maps.google.com/3",
        )
        conn.commit()

        # Re-run the backfill callable directly on the already-migrated DB
        # (ensure_schema already ran it once). The direct re-run lets us
        # assert against a known seed; for the very first run we instead
        # reset the library and re-invoke to capture the from-scratch state.
        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        assert _library_count(conn) == 2

        rows = _library_rows(conn)
        pairs = {(r["normalized_address"], r["google_maps_url"]) for r in rows}
        assert pairs == {
            ("123 nguyen hue", "https://maps.google.com/1"),
            ("45 le loi", "https://maps.google.com/2"),
        }


def test_backfill_skips_orders_with_empty_delivery_address():
    """FR2 guard: orders with non-empty ``google_maps_url`` but empty
    ``delivery_address`` are skipped (no library row created).
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        _insert_order(
            conn,
            order_ref="ORD-EMPTY-ADDR",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="",
            google_maps_url="https://maps.google.com/addr",
        )
        _insert_order(
            conn,
            order_ref="ORD-NULL-ADDR",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address=None,
            google_maps_url="https://maps.google.com/addr2",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        assert _library_count(conn) == 0


def test_backfill_skips_orders_with_empty_google_maps_url():
    """FR2 guard: door-delivery orders with empty/NULL ``google_maps_url``
    do not contribute to the library.
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        _insert_order(
            conn,
            order_ref="ORD-EMPTY-URL",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="",
        )
        _insert_order(
            conn,
            order_ref="ORD-NULL-URL",
            customer_id=cust_a,
            delivery_type="delivery",
            delivery_address="45 Lê Lợi",
            google_maps_url=None,
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        assert _library_count(conn) == 0


def test_backfill_skips_non_door_delivery_orders():
    """FR2 guard: pickup and bus orders do not contribute to the library
    even when they have a non-empty ``google_maps_url``.
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        _insert_order(
            conn,
            order_ref="ORD-PICKUP",
            customer_id=cust_a,
            delivery_type="pickup",
            delivery_address="Cửa hàng",
            google_maps_url="https://maps.google.com/pickup",
        )
        _insert_order(
            conn,
            order_ref="ORD-BUS",
            customer_id=cust_a,
            delivery_type="bus",
            delivery_address="Bến xe",
            google_maps_url="https://maps.google.com/bus",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        assert _library_count(conn) == 0


def test_backfill_dedupes_diacritic_variants_to_one_library_row():
    """FR2: ``normalize_address`` collapses diacritic variants to the same
    matching key, so orders with different display text but the same
    normalized address AND the same url produce exactly one library row.
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        _insert_order(
            conn,
            order_ref="ORD-D1",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/x",
        )
        _insert_order(
            conn,
            order_ref="ORD-D2",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 nguyen hue",
            google_maps_url="https://maps.google.com/x",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        assert _library_count(conn) == 1
        row = _library_rows(conn)[0]
        assert row["normalized_address"] == "123 nguyen hue"
        assert row["google_maps_url"] == "https://maps.google.com/x"


# ---------------------------------------------------------------------------
# AC3 — customer linking (FR3)
# ---------------------------------------------------------------------------


def test_backfill_links_customer_addresses_for_contributing_customers():
    """AC3/FR3: each customer whose orders contributed to a backfilled
    library entry is linked via ``customer_addresses``.
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        cust_b = _insert_customer(conn, name="Khách B", phone="0903333444")

        _insert_order(
            conn,
            order_ref="ORD-A1",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/1",
        )
        _insert_order(
            conn,
            order_ref="ORD-A2",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/1",
        )
        _insert_order(
            conn,
            order_ref="ORD-B1",
            customer_id=cust_b,
            delivery_type="delivery",
            delivery_address="45 Lê Lợi",
            google_maps_url="https://maps.google.com/2",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        # 2 library rows, 2 customer_addresses links (one per contributing
        # customer per library entry).
        assert _library_count(conn) == 2
        assert _customer_address_count(conn) == 2

        # Each link maps to a real library entry id.
        lib_ids = {
            r["id"]
            for r in conn.execute("SELECT id FROM address_library").fetchall()
        }
        for row in _customer_address_rows(conn):
            assert row["customer_id"] in (cust_a, cust_b)
            assert row["address_library_id"] in lib_ids

        # cust_a is linked to the pair it contributed to; cust_b to its own.
        a_links = {
            r["address_library_id"]
            for r in _customer_address_rows(conn)
            if r["customer_id"] == cust_a
        }
        b_links = {
            r["address_library_id"]
            for r in _customer_address_rows(conn)
            if r["customer_id"] == cust_b
        }
        assert len(a_links) == 1
        assert len(b_links) == 1
        assert a_links != b_links


def test_backfill_links_multiple_customers_to_same_library_entry():
    """AC3/FR3: when two distinct customers have orders with the same
    (normalized_address, google_maps_url) pair, both are linked to the
    single resulting library entry.
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        cust_b = _insert_customer(conn, name="Khách B", phone="0903333444")

        _insert_order(
            conn,
            order_ref="ORD-A",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/x",
        )
        _insert_order(
            conn,
            order_ref="ORD-B",
            customer_id=cust_b,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/x",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        assert _library_count(conn) == 1
        assert _customer_address_count(conn) == 2

        lib_id = conn.execute("SELECT id FROM address_library").fetchone()["id"]
        linked_customers = {
            r["customer_id"] for r in _customer_address_rows(conn)
        }
        assert linked_customers == {cust_a, cust_b}
        for r in _customer_address_rows(conn):
            assert r["address_library_id"] == lib_id


def test_backfill_skips_linking_orders_without_customer_id():
    """FR3 guard: orders with ``customer_id IS NULL`` contribute to the
    library entry but do not produce ``customer_addresses`` links.
    """
    with _new_memory_conn() as conn:
        _insert_order(
            conn,
            order_ref="ORD-NO-CUST",
            customer_id=None,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/x",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        assert _library_count(conn) == 1
        assert _customer_address_count(conn) == 0


# ---------------------------------------------------------------------------
# AC2 / NFR1 — idempotency
# ---------------------------------------------------------------------------


def test_backfill_is_idempotent_rerun_creates_no_new_rows():
    """AC2/NFR1: re-running the migration on an already-backfilled DB is a
    no-op — no new ``address_library`` or ``customer_addresses`` rows.
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        _insert_order(
            conn,
            order_ref="ORD-1",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/1",
        )
        _insert_order(
            conn,
            order_ref="ORD-2",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="45 Lê Lợi",
            google_maps_url="https://maps.google.com/2",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()
        first_lib = _library_count(conn)
        first_links = _customer_address_count(conn)
        assert first_lib == 2
        assert first_links == 2

        # Re-run the callable — idempotent: INSERT OR IGNORE on both tables.
        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        assert _library_count(conn) == first_lib
        assert _customer_address_count(conn) == first_links


def test_backfill_rerun_logs_zero_new_entries(caplog):
    """AC2/AC7: a second run reports 0 new entries in the summary log."""
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        _insert_order(
            conn,
            order_ref="ORD-1",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/1",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        caplog.clear()
        with caplog.at_level(logging.INFO, logger="baker.db"):
            _migrate_v102_backfill_address_library(conn)
            conn.commit()

        summary = next(
            (
                r.getMessage()
                for r in caplog.records
                if r.name == "baker.db" and r.levelno == logging.INFO
            ),
            None,
        )
        assert summary is not None, "expected a summary INFO log on re-run"
        assert "0 địa chỉ" in summary
        assert "0 khách hàng" in summary


# ---------------------------------------------------------------------------
# AC7 — summary log
# ---------------------------------------------------------------------------


def test_backfill_logs_summary_with_correct_counts(caplog):
    """AC7: the migration logs
    ``"Đã backfill X địa chỉ, liên kết Y khách hàng."`` at INFO with the
    correct counts of newly-created library entries and customer links.
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        cust_b = _insert_customer(conn, name="Khách B", phone="0903333444")
        _insert_order(
            conn,
            order_ref="ORD-1",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/1",
        )
        _insert_order(
            conn,
            order_ref="ORD-2",
            customer_id=cust_b,
            delivery_type="delivery",
            delivery_address="45 Lê Lợi",
            google_maps_url="https://maps.google.com/2",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        caplog.clear()
        with caplog.at_level(logging.INFO, logger="baker.db"):
            _migrate_v102_backfill_address_library(conn)
            conn.commit()

        summary = next(
            (
                r.getMessage()
                for r in caplog.records
                if r.name == "baker.db" and r.levelno == logging.INFO
            ),
            None,
        )
        assert summary is not None, "expected a summary INFO log"
        assert "2 địa chỉ" in summary
        assert "2 khách hàng" in summary


def test_backfill_summary_counts_only_newly_created_entries(caplog):
    """AC7 precision: the summary counts only *newly created* rows, not
    the total library size. Pre-existing rows (from a prior run) are not
    re-counted.
    """
    with _new_memory_conn() as conn:
        cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
        _insert_order(
            conn,
            order_ref="ORD-1",
            customer_id=cust_a,
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/1",
        )
        conn.commit()

        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        # First run: 1 new entry, 1 new link.
        with caplog.at_level(logging.INFO, logger="baker.db"):
            _migrate_v102_backfill_address_library(conn)
            conn.commit()

        # Second run: 0 new entries, 0 new links.
        caplog.clear()
        with caplog.at_level(logging.INFO, logger="baker.db"):
            _migrate_v102_backfill_address_library(conn)
            conn.commit()

        summary = next(
            (
                r.getMessage()
                for r in caplog.records
                if r.name == "baker.db" and r.levelno == logging.INFO
            ),
            None,
        )
        assert summary is not None
        assert "0 địa chỉ" in summary
        assert "0 khách hàng" in summary


# ---------------------------------------------------------------------------
# ensure_schema integration — the migration runs as part of the full chain
# ---------------------------------------------------------------------------


def test_ensure_schema_runs_v102_backfill_on_fresh_db():
    """The full ``ensure_schema`` chain runs v102 and backfills the library
    from any door-delivery orders seeded *before* migrations are applied.

    This mirrors the production deployment path: an existing DB with
    historical orders gets the v102 backfill automatically on the next
    ``ensure_schema`` call. We simulate that by seeding orders after v101
    has applied but before v102 runs.
    """
    import sqlite3

    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")

    # Apply migrations up to v101 only, seed historical orders, then run
    # ensure_schema (which will apply v102).
    from tests.test_db_schema import _migrate_to_version

    _migrate_to_version(conn, 101)

    cust_a = _insert_customer(conn, name="Khách A", phone="0901111222")
    _insert_order(
        conn,
        order_ref="ORD-HIST-1",
        customer_id=cust_a,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/1",
    )
    _insert_order(
        conn,
        order_ref="ORD-HIST-2",
        customer_id=cust_a,
        delivery_type="door",
        delivery_address="45 Lê Lợi",
        google_maps_url="https://maps.google.com/2",
    )
    conn.commit()

    # ensure_schema picks up v102 and runs the backfill.
    ensure_schema(conn)

    assert _library_count(conn) == 2
    assert _customer_address_count(conn) == 2

    pairs = {
        (r["normalized_address"], r["google_maps_url"])
        for r in _library_rows(conn)
    }
    assert pairs == {
        ("123 nguyen hue", "https://maps.google.com/1"),
        ("45 le loi", "https://maps.google.com/2"),
    }

    conn.close()


def test_v102_is_registered_in_migrations_registry():
    """Guardrail: v102 must be registered in the ``MIGRATIONS`` dict so
    ``ensure_schema`` runs it automatically on upgrade.
    """
    assert 102 in MIGRATIONS
    entry = MIGRATIONS[102]
    assert entry["callable"] is _migrate_v102_backfill_address_library
    assert "sql" in entry
    # v102 adds no schema objects — the SQL block is empty.
    assert entry["sql"] == ""


def test_backfill_empty_db_is_noop():
    """An empty DB (no orders) yields an empty library and zero links."""
    with _new_memory_conn() as conn:
        conn.execute("DELETE FROM customer_addresses")
        conn.execute("DELETE FROM address_library")
        conn.commit()

        _migrate_v102_backfill_address_library(conn)
        conn.commit()

        assert _library_count(conn) == 0
        assert _customer_address_count(conn) == 0