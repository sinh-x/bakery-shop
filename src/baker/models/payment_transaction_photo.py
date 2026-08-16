"""PaymentTransactionPhoto model — links a single photo to a payment transaction.

DG-410 Phase 1: introduces the ``payment_transaction_photos`` join table
(schema in ``baker.db.schema._constants.PAYMENT_TRANSACTION_PHOTOS_SCHEMA``,
migration ``v104``) and this dataclass model that backs it.

Design constraints (from plan §3 Goals / §6 FR1):

- **Single photo per transaction.** Enforced at the DB level by a
  ``UNIQUE(payment_transaction_id)`` constraint on the join table. The
  :meth:`PaymentTransactionPhoto.upsert_for_transaction` helper uses
  ``INSERT OR REPLACE`` so attaching a new photo to a transaction that
  already has one swaps the link atomically (FR3 add/replace semantics).
- **Reuse the ``photos`` table + ``save_photo`` storage layer.** This model
  only records the ``(transaction ↔ photo)`` edge; image bytes, hashing,
  and dedup live in ``baker.api.photos`` (plan §12 Reuse Analysis).
- **Order-level ``order_photos`` are independent.** This join table has no
  relationship to ``order_photos``; the order-level ``chuyen-khoan`` strip
  is unchanged (FR5).

The `` PaymentTransactionPhoto`` dataclass mirrors the
``PaymentTransaction`` model pattern (:mod:`baker.models.payment_transaction`):
a ``save`` insert, a ``from_row`` factory, and static lookup helpers.
"""

from dataclasses import dataclass
from typing import Optional

from baker.utils.time import now_utc


@dataclass
class PaymentTransactionPhoto:
    """A single photo linked to a payment transaction (DG-410 FR1).

    Fields mirror the ``payment_transaction_photos`` columns. ``id`` and
    ``created_at`` are populated on insert.
    """

    payment_transaction_id: int
    photo_id: int
    id: Optional[int] = None
    created_at: Optional[str] = None

    def save(self, conn) -> int:
        """Insert the link row and return its id.

        Phase 1 only records the edge; callers that need swap semantics
        (add/replace) should use :meth:`upsert_for_transaction`, which
        relies on the table's ``UNIQUE(payment_transaction_id)`` constraint
        and ``INSERT OR REPLACE`` to atomically replace an existing link.
        """
        cursor = conn.execute(
            "INSERT INTO payment_transaction_photos "
            "(payment_transaction_id, photo_id, created_at) VALUES (?, ?, ?)",
            (self.payment_transaction_id, self.photo_id, now_utc()),
        )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def upsert_for_transaction(conn, payment_transaction_id: int, photo_id: int) -> int:
        """Attach (or replace) the photo for a transaction (FR1/FR3).

        Uses ``INSERT OR REPLACE`` against the
        ``UNIQUE(payment_transaction_id)`` constraint so a transaction can
        hold only one photo at a time — re-attaching a different photo swaps
        the link atomically. Returns the link row id.
        """
        cursor = conn.execute(
            "INSERT OR REPLACE INTO payment_transaction_photos "
            "(payment_transaction_id, photo_id, created_at) VALUES (?, ?, ?)",
            (payment_transaction_id, photo_id, now_utc()),
        )
        return int(cursor.lastrowid)

    @staticmethod
    def from_row(row) -> "PaymentTransactionPhoto":
        return PaymentTransactionPhoto(
            id=row["id"],
            payment_transaction_id=row["payment_transaction_id"],
            photo_id=row["photo_id"],
            created_at=row["created_at"],
        )

    @staticmethod
    def get_for_transaction(conn, payment_transaction_id: int) -> Optional["PaymentTransactionPhoto"]:
        """Return the photo link for a transaction, or ``None`` if none attached.

        Single-row lookup enforced by the
        ``UNIQUE(payment_transaction_id)`` constraint.
        """
        row = conn.execute(
            "SELECT * FROM payment_transaction_photos "
            "WHERE payment_transaction_id = ?",
            (payment_transaction_id,),
        ).fetchone()
        return PaymentTransactionPhoto.from_row(row) if row else None

    @staticmethod
    def delete_for_transaction(conn, payment_transaction_id: int) -> bool:
        """Remove the photo link for a transaction (FR3 remove). Returns
        ``True`` if a row was deleted, ``False`` if there was no link.
        """
        cursor = conn.execute(
            "DELETE FROM payment_transaction_photos WHERE payment_transaction_id = ?",
            (payment_transaction_id,),
        )
        return cursor.rowcount > 0

    def to_api_dict(self) -> dict:
        return {
            "id": str(self.id) if self.id is not None else None,
            "paymentTransactionId": str(self.payment_transaction_id),
            "photoId": str(self.photo_id),
            "createdAt": self.created_at,
        }