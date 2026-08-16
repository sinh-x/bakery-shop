"""Migration v104: payment_transaction_photos join table (DG-410 Phase 1).

Creates the ``payment_transaction_photos`` join table linking a single photo
to an individual payment transaction. The table is applied via the
``PAYMENT_TRANSACTION_PHOTOS_SCHEMA`` SQL block registered in
``MIGRATIONS[104]["sql"]``; this module has no callable because the migration
is pure DDL (no data backfill, no conditional rebuild). The shared
``CREATE TABLE IF NOT EXISTS`` / ``CREATE INDEX IF NOT EXISTS`` statements
make re-running v104 on an already-migrated DB a no-op (idempotent — NFR2).

Schema (from plan §13 Phase 1):

- ``payment_transaction_photos``: id (PK), payment_transaction_id
  (FK → payment_transactions, CASCADE), photo_id (FK → photos), created_at.
  UNIQUE on payment_transaction_id enforces the single-photo-per-transaction
  rule (FR1) at the DB level. Indexes on both FK columns support
  per-transaction photo lookup and per-photo reverse lookup.

The ``photos`` table and ``save_photo`` storage layer are reused unchanged
(no new storage layer — see plan §12 Reuse Analysis). Order-level
``order_photos`` remain independent and unaffected (FR5).
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403