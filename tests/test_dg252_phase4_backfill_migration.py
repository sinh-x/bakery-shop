"""DG-252 Phase 4 — backfill migration linking all NULL customer_id orders.

Covers FR9 (backfill links every remaining ``customer_id IS NULL`` order via
phone → name → new customer → "Khách lẻ", idempotent, pre/post counts),
NFR2 (second run changes 0 rows), and AC5 (100% of orders have
``customer_id`` after the backfill, second run changes 0 rows, pre/post
counts reported).

The backfill is implemented as schema migration v74, which delegates to the
shared ``_repair_null_customer_links`` body also used by v66 (DG-227). These
tests exercise the migration both via the migration chain (``ensure_schema``
on a DB seeded with NULL-customer orders) and via direct callable invocation
to inspect the returned pre/post count dict.
"""

from __future__ import annotations

from baker.db.connection import get_db
from baker.db.schema import (
    MIGRATIONS,
    _migrate_v74_backfill_null_customer_links,
    _migrate_v66_repair_customer_links,
    _repair_null_customer_links,
    ensure_schema,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _insert_order(
    conn,
    customer_id=None,
    customer_name=None,
    customer_phone="",
    total_price=10000,
    created_at="2026-07-01T00:00:00Z",
    order_ref="ORD-?",
):
    conn.execute(
        """
        INSERT INTO orders (
            order_ref, customer_id, customer_name, customer_phone,
            total_price, status, created_at, due_date
        ) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)
        """,
        (order_ref, customer_id, customer_name, customer_phone, total_price, created_at, created_at),
    )


def _null_count(conn) -> int:
    return conn.execute(
        "SELECT COUNT(*) FROM orders WHERE customer_id IS NULL"
    ).fetchone()[0]


def _seed_null_orders(conn) -> None:
    """Seed a representative mix of NULL-customer orders across the 3 categories."""
    # (1) phone-having order whose phone matches an existing customer.
    conn.execute(
        "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
        "VALUES ('Nguyễn Văn A', '8490111222', 'nguyen van a', '2026-01-01', '2026-01-01')"
    )
    cust_a_id = conn.execute(
        "SELECT id FROM customers WHERE phone = '8490111222'"
    ).fetchone()["id"]
    conn.execute(
        "INSERT INTO customer_phones (customer_id, phone) VALUES (?, '8490111222')",
        (cust_a_id,),
    )

    # (2) phone-having order with no matching customer → must auto-create.
    # (3) name-only order → match via search_name or create.
    # (4) name-only order matching an existing customer's search_name.
    conn.execute(
        "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
        "VALUES ('Trần Thị B', '', 'tran thi b', '2026-01-01', '2026-01-01')"
    )
    cust_b_id = conn.execute(
        "SELECT id FROM customers WHERE search_name = 'tran thi b'"
    ).fetchone()["id"]

    # (5) walk-in order (no phone, no name) → link to shared "Khách lẻ".
    # (6) ensure a "Khách lẻ" row exists already.
    conn.execute(
        "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
        "VALUES ('Khách lẻ', '', 'khach le', '2026-01-01', '2026-01-01')"
    )
    khach_le_id = conn.execute(
        "SELECT id FROM customers WHERE LOWER(name) = 'khách lẻ' ORDER BY id ASC LIMIT 1"
    ).fetchone()["id"]

    _insert_order(
        conn, customer_id=None, customer_name="Nguyễn Văn A",
        customer_phone="8490111222", order_ref="ORD-PHONE-MATCH",
    )
    _insert_order(
        conn, customer_id=None, customer_name="Lê Minh C",
        customer_phone="8491234567", order_ref="ORD-PHONE-NEW",
    )
    _insert_order(
        conn, customer_id=None, customer_name="Trần Thị B",
        customer_phone="", order_ref="ORD-NAME-MATCH",
    )
    _insert_order(
        conn, customer_id=None, customer_name="Phạm D",
        customer_phone="", order_ref="ORD-NAME-NEW",
    )
    _insert_order(
        conn, customer_id=None, customer_name="", customer_phone="",
        order_ref="ORD-WALK-IN",
    )
    conn.commit()
    return {
        "cust_a_id": cust_a_id,
        "cust_b_id": cust_b_id,
        "khach_le_id": khach_le_id,
    }


def _apply_migrations_through(conn, target_version: int) -> None:
    """Apply migrations up to and including ``target_version``."""
    row = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
    ).fetchone()
    current = 0
    if row:
        current = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0] or 0
    for version in sorted(MIGRATIONS.keys()):
        if version <= current or version > target_version:
            continue
        conn.executescript(MIGRATIONS[version]["sql"])
        seed = MIGRATIONS[version].get("seed")
        if seed:
            for name, category, base_price, cost, recipe_notes in seed:
                conn.execute(
                    "INSERT OR IGNORE INTO products "
                    "(name, category, base_price, cost, recipe_notes) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (name, category, base_price, cost, recipe_notes),
                )
        callable_fn = MIGRATIONS[version].get("callable")
        if callable_fn:
            callable_fn(conn)
        conn.execute(
            "INSERT INTO schema_version (version, description) VALUES (?, ?)",
            (version, MIGRATIONS[version]["description"]),
        )
    conn.commit()


# ---------------------------------------------------------------------------
# FR9 — backfill links every NULL order across all 3 resolution categories
# ---------------------------------------------------------------------------


def test_fr9_backfill_links_all_null_orders(use_memory_db):
    """FR9/AC5 — after v74 runs, 100% of orders have a non-NULL customer_id."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)  # everything before v74
        _seed_null_orders(conn)
        assert _null_count(conn) == 5

        _migrate_v74_backfill_null_customer_links(conn)
        conn.commit()

        assert _null_count(conn) == 0
        # Every row genuinely has a positive customer_id (not just NULL-ish).
        rows = conn.execute(
            "SELECT order_ref, customer_id FROM orders ORDER BY order_ref"
        ).fetchall()
        for row in rows:
            assert row["customer_id"] is not None
            assert row["customer_id"] > 0


def test_fr9_backfill_phone_match_links_to_existing_customer(use_memory_db):
    """FR9 — a phone-having order matches an existing customer by phone."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        ids = _seed_null_orders(conn)
        _migrate_v74_backfill_null_customer_links(conn)
        conn.commit()
        row = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref = 'ORD-PHONE-MATCH'"
        ).fetchone()
        assert row["customer_id"] == ids["cust_a_id"]


def test_fr9_backfill_phone_new_auto_creates_customer(use_memory_db):
    """FR9 — a phone with no existing customer auto-creates one."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        _seed_null_orders(conn)
        _migrate_v74_backfill_null_customer_links(conn)
        conn.commit()
        row = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref = 'ORD-PHONE-NEW'"
        ).fetchone()
        cust = conn.execute(
            "SELECT name, phone FROM customers WHERE id = ?", (row["customer_id"],)
        ).fetchone()
        assert cust["name"] == "Lê Minh C"
        assert cust["phone"] == "8491234567"


def test_fr9_backfill_name_match_links_to_existing_customer(use_memory_db):
    """FR9 — a name-only order matches an existing customer by search_name."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        ids = _seed_null_orders(conn)
        _migrate_v74_backfill_null_customer_links(conn)
        conn.commit()
        row = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref = 'ORD-NAME-MATCH'"
        ).fetchone()
        assert row["customer_id"] == ids["cust_b_id"]


def test_fr9_backfill_name_new_auto_creates_customer(use_memory_db):
    """FR9 — a name-only order with no match auto-creates a customer."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        _seed_null_orders(conn)
        _migrate_v74_backfill_null_customer_links(conn)
        conn.commit()
        row = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref = 'ORD-NAME-NEW'"
        ).fetchone()
        cust = conn.execute(
            "SELECT name, phone FROM customers WHERE id = ?", (row["customer_id"],)
        ).fetchone()
        assert cust["name"] == "Phạm D"


def test_fr9_backfill_walk_in_links_to_shared_khach_le(use_memory_db):
    """FR9 — identity-less order links to the single shared "Khách lẻ" record."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        ids = _seed_null_orders(conn)
        _migrate_v74_backfill_null_customer_links(conn)
        conn.commit()
        row = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref = 'ORD-WALK-IN'"
        ).fetchone()
        assert row["customer_id"] == ids["khach_le_id"]


def test_fr9_backfill_creates_khach_le_when_absent(use_memory_db):
    """FR9 — if no "Khách lẻ" row exists, the backfill creates one and links to it."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        _insert_order(
            conn, customer_id=None, customer_name="", customer_phone="",
            order_ref="ORD-WALK-IN-NO-LE",
        )
        conn.commit()
        assert _null_count(conn) == 1
        assert conn.execute(
            "SELECT COUNT(*) FROM customers WHERE LOWER(name) = 'khách lẻ'"
        ).fetchone()[0] == 0

        _migrate_v74_backfill_null_customer_links(conn)
        conn.commit()

        assert _null_count(conn) == 0
        khach = conn.execute(
            "SELECT id FROM customers WHERE LOWER(name) = 'khách lẻ' ORDER BY id ASC LIMIT 1"
        ).fetchone()
        assert khach is not None
        row = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref = 'ORD-WALK-IN-NO-LE'"
        ).fetchone()
        assert row["customer_id"] == khach["id"]


def test_fr9_backfill_recomputes_customer_year_summary(use_memory_db):
    """FR9 — year summaries are recomputed for affected customers after linking."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        ids = _seed_null_orders(conn)
        _migrate_v74_backfill_null_customer_links(conn)
        conn.commit()

        # The phone-matched customer (cust_a) now owns ORD-PHONE-MATCH.
        summary = conn.execute(
            "SELECT order_count, total_volume FROM customer_year_summary "
            "WHERE customer_id = ? AND year = 2026",
            (ids["cust_a_id"],),
        ).fetchone()
        assert summary is not None
        assert summary["order_count"] >= 1
        assert summary["total_volume"] >= 10000


# ---------------------------------------------------------------------------
# NFR2 — idempotency: second run changes 0 rows
# ---------------------------------------------------------------------------


def test_nfr2_backfill_is_idempotent_second_run_changes_zero_rows(use_memory_db):
    """NFR2 — running the backfill a second time links 0 additional orders."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        _seed_null_orders(conn)
        assert _null_count(conn) == 5

        first = _repair_null_customer_links(conn)
        conn.commit()
        assert first["linked"] == 5
        assert first["null_after"] == 0
        assert _null_count(conn) == 0

        # Snapshot customer/order counts to compare against the second run.
        customers_before = conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0]
        orders_before = conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
        links_before = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
        ).fetchone()[0]

        second = _repair_null_customer_links(conn)
        conn.commit()

        assert second["null_before"] == 0
        assert second["linked"] == 0
        assert second["null_after"] == 0
        assert second["phone_match"] == 0
        assert second["name_match"] == 0
        assert second["new_customer"] == 0
        assert second["walk_in"] == 0

        customers_after = conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0]
        orders_after = conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
        links_after = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
        ).fetchone()[0]
        assert customers_after == customers_before
        assert orders_after == orders_before
        assert links_after == links_before


def test_nfr2_backfill_noop_when_no_null_orders(use_memory_db):
    """NFR2 — the backfill is a no-op on a DB with no NULL-customer orders."""
    with get_db() as conn:
        _apply_migrations_through(conn, 74)  # fresh DB, v74 already ran on empty
        # Seed one fully-linked order.
        conn.execute(
            "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
            "VALUES ('Đã có', '', 'da co', '2026-01-01', '2026-01-01')"
        )
        cust_id = conn.execute(
            "SELECT id FROM customers WHERE name = 'Đã có'"
        ).fetchone()["id"]
        _insert_order(
            conn, customer_id=cust_id, customer_name="Đã có",
            customer_phone="", order_ref="ORD-LINKED",
        )
        conn.commit()
        assert _null_count(conn) == 0

        result = _repair_null_customer_links(conn)
        assert result["null_before"] == 0
        assert result["linked"] == 0
        assert result["null_after"] == 0


# ---------------------------------------------------------------------------
# AC5 — pre/post counts are reported
# ---------------------------------------------------------------------------


def test_ac5_backfill_reports_pre_and_post_counts(use_memory_db):
    """AC5 — the returned summary includes pre and post NULL counts."""
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        _seed_null_orders(conn)
        result = _repair_null_customer_links(conn)
        conn.commit()

        assert result["null_before"] == 5
        assert result["null_after"] == 0
        # Per-category counts sum to the total linked.
        assert (
            result["phone_match"] + result["name_match"]
            + result["new_customer"] + result["walk_in"]
        ) == result["linked"] == 5


def test_ac5_backfill_reports_zero_counts_on_already_clean_db(use_memory_db):
    """AC5 — on an already-clean DB the summary reports all-zero counts."""
    with get_db() as conn:
        _apply_migrations_through(conn, 74)
        result = _repair_null_customer_links(conn)
        assert result["null_before"] == 0
        assert result["null_after"] == 0
        assert result["linked"] == 0
        assert result["phone_match"] == 0
        assert result["name_match"] == 0
        assert result["new_customer"] == 0
        assert result["walk_in"] == 0


# ---------------------------------------------------------------------------
# Migration chain — v74 runs via ensure_schema and respects schema_version
# ---------------------------------------------------------------------------


def test_v74_runs_in_full_migration_chain_and_clears_nulls(use_memory_db):
    """ensure_schema applies v74 in the chain and clears any NULLs on a fresh DB."""
    with get_db() as conn:
        # Apply everything up to v73, then seed NULLs that v74 should clear.
        _apply_migrations_through(conn, 73)
        _seed_null_orders(conn)
        assert _null_count(conn) == 5

        # Now run ensure_schema (which applies v74 and stamps schema_version).
        ensure_schema(conn)
        conn.commit()

        assert _null_count(conn) == 0
        # schema_version recorded v74.
        versions = {
            row["version"] for row in conn.execute(
                "SELECT version FROM schema_version"
            ).fetchall()
        }
        assert 74 in versions


def test_v74_skipped_when_already_applied(use_memory_db):
    """ensure_schema does not re-apply v74 once it is in schema_version."""
    with get_db() as conn:
        _apply_migrations_through(conn, 74)
        # Stamp v74 so ensure_schema treats it as already applied.
        # (``_apply_migrations_through`` already stamped it.)
        before = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id IS NULL"
        ).fetchone()[0]
        ensure_schema(conn)  # should be a no-op for v74
        after = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id IS NULL"
        ).fetchone()[0]
        assert before == after


def test_v66_and_v74_share_repair_body(use_memory_db):
    """v66 and v74 both delegate to ``_repair_null_customer_links``.

    Two separate DBs are used (one per wrapper) to avoid seeding the same
    orders twice on a single DB.
    """
    # v66 wrapper
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        _seed_null_orders(conn)
        _migrate_v66_repair_customer_links(conn)
        assert _null_count(conn) == 0

    # v74 wrapper — fresh DB so the seed inserts do not collide.
    import os
    from pathlib import Path
    import baker.config
    db_path2 = str(Path(use_memory_db).parent / "test_v74_second.db")
    baker.config.DB_PATH = Path(db_path2)
    os.environ["BAKER_DB"] = db_path2
    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        _seed_null_orders(conn)
        _migrate_v74_backfill_null_customer_links(conn)
        assert _null_count(conn) == 0


# ---------------------------------------------------------------------------
# NFR2 — performance smoke (completes quickly on a modest seeded DB)
# ---------------------------------------------------------------------------


def test_nfr2_backfill_completes_under_60s_on_modest_db(use_memory_db):
    """NFR2 — backfill of a few thousand NULL orders completes well under 60 s.

    The production budget is 60 s; on a CI memory DB this is a smoke check
    that the per-order work is O(1) lookups, not an exhaustive benchmark.
    """
    import time

    with get_db() as conn:
        _apply_migrations_through(conn, 73)
        # Seed 2000 walk-in NULL orders (cheapest path, exercises the shared
        # "Khách lẻ" link which is the highest-volume category in prod).
        conn.execute(
            "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
            "VALUES ('Khách lẻ', '', 'khach le', '2026-01-01', '2026-01-01')"
        )
        rows = [(f"ORD-BULK-{i:05d}", None, "", "", 5000, "2026-07-01T00:00:00Z", "2026-07-01T00:00:00Z")
                for i in range(2000)]
        conn.executemany(
            "INSERT INTO orders (order_ref, customer_id, customer_name, customer_phone, "
            "total_price, status, created_at, due_date) "
            "VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)",
            rows,
        )
        conn.commit()
        assert _null_count(conn) == 2000

        start = time.monotonic()
        _repair_null_customer_links(conn)
        elapsed = time.monotonic() - start
        conn.commit()

        assert _null_count(conn) == 0
        # Generous smoke bound (CI machines vary); the real NFR2 budget is 60s
        # on the production DB which is far larger but also on real hardware.
        assert elapsed < 30.0, f"backfill took {elapsed:.2f}s on 2000 rows"