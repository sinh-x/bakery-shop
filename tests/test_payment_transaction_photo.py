"""Tests for the PaymentTransactionPhoto model — DG-410 Phase 1.

Covers the dataclass model backing the ``payment_transaction_photos`` join
table introduced by migration v104. The schema-level tests (table/columns/
FKs/indexes/UNIQUE constraint) live in ``tests/test_db_schema.py``; this
file exercises the model's save / upsert / get / delete behavior against a
real SQLite DB with the full schema applied, including the
single-photo-per-transaction rule enforced by the UNIQUE constraint (FR1)
and the swap (add/replace) semantics (FR3).
"""

import pytest

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.models.payment_transaction import PaymentTransaction
from baker.models.payment_transaction_photo import PaymentTransactionPhoto

pytestmark = pytest.mark.critical


def _seed_order_and_txn(conn) -> tuple[int, int]:
    """Insert a minimal order + payment_transaction and return (order_id, txn_id)."""
    conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, created_at, updated_at) "
        "VALUES (?, ?, 0, 'new', '2026-08-16T00:00:00Z', '2026-08-16T00:00:00Z')",
        ("ORD-TXN-PHOTO-1", "Test Khach"),
    )
    order_id = conn.execute(
        "SELECT id FROM orders WHERE order_ref = 'ORD-TXN-PHOTO-1'"
    ).fetchone()[0]
    txn = PaymentTransaction(order_id=order_id, amount=100000.0, type="deposit")
    txn.save(conn)
    return order_id, txn.id


def _seed_photo(conn) -> int:
    conn.execute(
        "INSERT INTO photos (hash, original_name, created_at) VALUES (?, '', '2026-08-16T00:00:00Z')",
        ("a" * 64,),
    )
    return conn.execute("SELECT id FROM photos WHERE hash = ?", ("a" * 64,)).fetchone()[0]


def test_save_inserts_link_row():
    with get_db() as conn:
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        photo_id = _seed_photo(conn)

        link = PaymentTransactionPhoto(
            payment_transaction_id=txn_id, photo_id=photo_id
        )
        link_id = link.save(conn)
        conn.commit()

        assert link_id is not None
        row = conn.execute(
            "SELECT * FROM payment_transaction_photos WHERE id = ?", (link_id,)
        ).fetchone()
        assert row["payment_transaction_id"] == txn_id
        assert row["photo_id"] == photo_id
        assert row["created_at"] is not None


def test_get_for_transaction_returns_attached_photo():
    with get_db() as conn:
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        photo_id = _seed_photo(conn)
        PaymentTransactionPhoto.upsert_for_transaction(conn, txn_id, photo_id)
        conn.commit()

        link = PaymentTransactionPhoto.get_for_transaction(conn, txn_id)
        assert link is not None
        assert link.payment_transaction_id == txn_id
        assert link.photo_id == photo_id


def test_get_for_transaction_returns_none_when_no_photo():
    with get_db() as conn:
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        assert PaymentTransactionPhoto.get_for_transaction(conn, txn_id) is None


def test_upsert_swaps_photo_for_transaction():
    """FR1/FR3: attaching a new photo replaces the existing link (single-photo rule)."""
    with get_db() as conn:
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        photo_id_1 = _seed_photo(conn)

        # Insert a second photo row with a distinct hash.
        conn.execute(
            "INSERT INTO photos (hash, original_name, created_at) VALUES (?, '', '2026-08-16T00:00:00Z')",
            ("b" * 64,),
        )
        photo_id_2 = conn.execute(
            "SELECT id FROM photos WHERE hash = ?", ("b" * 64,)
        ).fetchone()[0]

        first_id = PaymentTransactionPhoto.upsert_for_transaction(conn, txn_id, photo_id_1)
        second_id = PaymentTransactionPhoto.upsert_for_transaction(conn, txn_id, photo_id_2)
        conn.commit()

        assert second_id != first_id
        # Only ONE row exists for this transaction (UNIQUE enforced + upsert replaced).
        rows = conn.execute(
            "SELECT * FROM payment_transaction_photos WHERE payment_transaction_id = ?",
            (txn_id,),
        ).fetchall()
        assert len(rows) == 1
        assert rows[0]["id"] == second_id
        assert rows[0]["photo_id"] == photo_id_2


def test_save_raises_on_duplicate_transaction_unique_constraint():
    """FR1: the UNIQUE(payment_transaction_id) constraint rejects a second row."""
    with get_db() as conn:
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        photo_id_1 = _seed_photo(conn)
        conn.execute(
            "INSERT INTO photos (hash, original_name, created_at) VALUES (?, '', '2026-08-16T00:00:00Z')",
            ("b" * 64,),
        )
        photo_id_2 = conn.execute(
            "SELECT id FROM photos WHERE hash = ?", ("b" * 64,)
        ).fetchone()[0]

        PaymentTransactionPhoto(payment_transaction_id=txn_id, photo_id=photo_id_1).save(conn)
        with pytest.raises(Exception):  # sqlite3.IntegrityError
            PaymentTransactionPhoto(
                payment_transaction_id=txn_id, photo_id=photo_id_2
            ).save(conn)


def test_delete_for_transaction_removes_link():
    """FR3: remove deletes the link row."""
    with get_db() as conn:
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        photo_id = _seed_photo(conn)
        PaymentTransactionPhoto.upsert_for_transaction(conn, txn_id, photo_id)
        conn.commit()

        deleted = PaymentTransactionPhoto.delete_for_transaction(conn, txn_id)
        conn.commit()
        assert deleted is True
        assert PaymentTransactionPhoto.get_for_transaction(conn, txn_id) is None


def test_delete_for_transaction_returns_false_when_no_link():
    with get_db() as conn:
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        assert PaymentTransactionPhoto.delete_for_transaction(conn, txn_id) is False


def test_to_api_dict_serializes_string_ids():
    with get_db() as conn:
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        photo_id = _seed_photo(conn)
        link_id = PaymentTransactionPhoto.upsert_for_transaction(conn, txn_id, photo_id)
        conn.commit()
        link = PaymentTransactionPhoto.get_for_transaction(conn, txn_id)

        payload = link.to_api_dict()
        assert payload["id"] == str(link_id)
        assert payload["paymentTransactionId"] == str(txn_id)
        assert payload["photoId"] == str(photo_id)
        assert payload["createdAt"] is not None


def test_from_row_round_trips_columns():
    with get_db() as conn:
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        photo_id = _seed_photo(conn)
        PaymentTransactionPhoto.upsert_for_transaction(conn, txn_id, photo_id)
        conn.commit()
        row = conn.execute(
            "SELECT * FROM payment_transaction_photos WHERE payment_transaction_id = ?",
            (txn_id,),
        ).fetchone()
        link = PaymentTransactionPhoto.from_row(row)
        assert link.payment_transaction_id == txn_id
        assert link.photo_id == photo_id
        assert link.id is not None
        assert link.created_at is not None


def test_cascade_delete_when_transaction_deleted():
    """ON DELETE CASCADE on the FK removes the link when the txn row is deleted."""
    with get_db() as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        ensure_schema(conn)
        _, txn_id = _seed_order_and_txn(conn)
        photo_id = _seed_photo(conn)
        PaymentTransactionPhoto.upsert_for_transaction(conn, txn_id, photo_id)
        conn.commit()

        conn.execute("DELETE FROM payment_transactions WHERE id = ?", (txn_id,))
        conn.commit()
        assert PaymentTransactionPhoto.get_for_transaction(conn, txn_id) is None