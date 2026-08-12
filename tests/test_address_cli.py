"""DG-387 Phase 4 — tests for ``baker address missing-links`` CLI command.

Covers FR4 (CLI outputs unique ``(delivery_address, order_count)`` pairs
for door-delivery orders missing Google Maps links), NFR3 (read-only — no
database mutations), and AC5 (the command lists unique
``(delivery_address, order_count)`` for door-delivery orders where
``google_maps_url IS NULL OR google_maps_url = ''``).

The command lives in ``src/baker/commands/address.py`` and is registered
as the ``address`` group on the ``baker`` CLI (``src/baker/cli.py``).
"""

import click.testing

from baker.cli import app
from baker.db.connection import get_db
from baker.db.schema import ensure_schema


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _invoke(*args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, list(args))


def _insert_order(
    conn,
    *,
    order_ref,
    delivery_type="door",
    delivery_address="",
    google_maps_url=None,
    status="delivered",
):
    conn.execute(
        """
        INSERT INTO orders (
            order_ref, customer_name, items, total_price, status,
            delivery_type, delivery_address, google_maps_url, customer_id
        ) VALUES (?, ?, '[]', 0, ?, ?, ?, ?, NULL)
        """,
        (
            order_ref,
            "Khách test",
            status,
            delivery_type,
            delivery_address,
            google_maps_url,
        ),
    )


# ---------------------------------------------------------------------------
# Registration / help
# ---------------------------------------------------------------------------


def test_address_group_registered():
    result = _invoke("--help")
    assert result.exit_code == 0
    assert "address" in result.output


def test_address_missing_links_help():
    result = _invoke("address", "missing-links", "--help")
    assert result.exit_code == 0
    assert "missing-links" in result.output


def test_address_subcommand_help_lists_missing_links():
    result = _invoke("address", "--help")
    assert result.exit_code == 0
    assert "missing-links" in result.output


# ---------------------------------------------------------------------------
# AC5 / FR4 — output correctness
# ---------------------------------------------------------------------------


def test_missing_links_lists_unique_addresses_with_counts(use_memory_db):
    """AC5/FR4: unique ``(delivery_address, order_count)`` for door-delivery
    orders with empty/NULL ``google_maps_url``."""
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D2",
            delivery_type="delivery",
            delivery_address="123 Lê Lợi",
            google_maps_url="",
        )
        _insert_order(
            conn,
            order_ref="D3",
            delivery_type="door",
            delivery_address="45 Trần Hưng Đạo",
            google_maps_url=None,
        )
        # Has a link — should be excluded.
        _insert_order(
            conn,
            order_ref="D4",
            delivery_type="door",
            delivery_address="78 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/x",
        )
        conn.commit()

    result = _invoke("address", "missing-links")
    assert result.exit_code == 0
    # 123 Lê Lợi appears once with order_count = 2.
    assert "123 Lê Lợi" in result.output
    assert "45 Trần Hưng Đạo" in result.output
    assert "78 Nguyễn Huệ" not in result.output
    # Summary mentions 2 unique addresses and 3 orders needing links.
    assert "2 địa chỉ" in result.output
    assert "3 đơn" in result.output


def test_missing_links_empty_when_all_have_links(use_memory_db):
    """AC5: when every door-delivery order has a link, output is the
    empty-state message."""
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url="https://maps.google.com/x",
        )
        conn.commit()

    result = _invoke("address", "missing-links")
    assert result.exit_code == 0
    assert "không có địa chỉ" in result.output


def test_missing_links_excludes_pickup_and_bus(use_memory_db):
    """FR4 guard: only ``door`` and ``delivery`` orders are considered;
    ``pickup`` and ``bus`` orders with missing links must NOT appear."""
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="P1",
            delivery_type="pickup",
            delivery_address="Pickup counter",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="B1",
            delivery_type="bus",
            delivery_address="Bến xe Nha Trang",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="12 Độc Lập",
            google_maps_url=None,
        )
        conn.commit()

    result = _invoke("address", "missing-links")
    assert result.exit_code == 0
    assert "12 Độc Lập" in result.output
    assert "Pickup counter" not in result.output
    assert "Bến xe" not in result.output


def test_missing_links_excludes_empty_delivery_address(use_memory_db):
    """FR4 guard: door-delivery orders with an empty ``delivery_address``
    are excluded from the gap list (matching the v102 backfill + Phase 3
    sync guard)."""
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D2",
            delivery_type="door",
            delivery_address=None,
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D3",
            delivery_type="door",
            delivery_address="45 Trần Hưng Đạo",
            google_maps_url=None,
        )
        conn.commit()

    result = _invoke("address", "missing-links")
    assert result.exit_code == 0
    assert "45 Trần Hưng Đạo" in result.output
    # Only one unique address; summary says 1 địa chỉ, 1 đơn.
    assert "1 địa chỉ" in result.output
    assert "1 đơn" in result.output


# ---------------------------------------------------------------------------
# NFR3 — read-only
# ---------------------------------------------------------------------------


def test_missing_links_is_read_only(use_memory_db):
    """NFR3: running the command does not mutate the database."""
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url=None,
        )
        conn.commit()
        before = conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0]

    result = _invoke("address", "missing-links")
    assert result.exit_code == 0

    with get_db() as conn:
        after = conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
        # No new rows inserted, no rows modified.
        assert after == before
        # google_maps_url still NULL — command did not backfill anything.
        row = conn.execute(
            "SELECT google_maps_url FROM orders WHERE order_ref = ?", ("D1",)
        ).fetchone()
        assert row["google_maps_url"] is None


def test_missing_links_groups_by_delivery_address_not_normalized(use_memory_db):
    """FR4: grouping is on raw ``delivery_address`` (not normalized) — two
    diacritic-variant addresses that normalize to the same value must appear
    as two separate rows since staff sees the raw text."""
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="Số 123 Lê Lợi",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D2",
            delivery_type="door",
            delivery_address="so 123 le loi",
            google_maps_url=None,
        )
        conn.commit()

    result = _invoke("address", "missing-links")
    assert result.exit_code == 0
    # Both raw forms appear (not collapsed by normalization).
    assert "Số 123 Lê Lợi" in result.output
    assert "so 123 le loi" in result.output
    assert "2 địa chỉ" in result.output