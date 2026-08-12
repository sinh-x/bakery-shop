"""Migration v101: address library + customer_addresses (DG-385 Phase 1).

Creates the ``address_library`` and ``customer_addresses`` tables. Both
tables are applied via the ``ADDRESS_LIBRARY_SCHEMA`` SQL block registered
in ``MIGRATIONS[101]["sql"]``; this module has no callable because the
migration is pure DDL (no data backfill, no conditional rebuild). The
shared ``CREATE TABLE IF NOT EXISTS`` / ``CREATE INDEX IF NOT EXISTS``
statements make re-running v101 on an already-migrated DB a no-op
(idempotent — NFR3).

Schema (from plan §13 Phase 1):

- ``address_library``: id (PK), normalized_address (TEXT NOT NULL),
  display_address (TEXT NOT NULL), google_maps_url (TEXT), created_at,
  updated_at. Unique on (normalized_address, google_maps_url) so the
  Phase 3 upsert can resolve a re-saved address+link pair to the existing
  row (FR3). Indexed on normalized_address for LIKE-based autocomplete
  (FR1 / NFR1: p95 < 300ms at 10k rows).
- ``customer_addresses``: customer_id (FK → customers, CASCADE),
  address_library_id (FK → address_library, CASCADE), composite PK. Lets
  the autocomplete endpoint prioritize the caller's previously used
  addresses (FR4) and keeps the library reference-count aware of which
  customers use which addresses.
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403