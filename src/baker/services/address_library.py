"""Address library service (DG-385 Phase 2).

Business logic for the ``address_library`` + ``customer_addresses`` tables
created in the v101 migration (Phase 1). The service centralizes:

- ``normalize_address`` matching-key derivation (FR1 / NFR3): trim, lowercase,
  strip Vietnamese diacritics. The matching key is reused for both the
  ``LIKE`` autocomplete query and the unique upsert key
  ``(normalized_address, google_maps_url)``.
- Autocomplete query (FR7 / NFR1): paginated to 20 results, uses the
  ``idx_address_library_normalized_address`` index from v101, and ranks
  the caller customer's own addresses first when ``customer_id`` is
  supplied (FR5).
- Library CRUD (FR8): list, create, update, delete on ``address_library``,
  including the ``customer_addresses`` link management that the Phase 3
  auto-sync will hook into.

The service is intentionally DB-only — it operates on a caller-supplied
``conn`` so endpoints can run it inside a single ``get_db()`` transaction
(NFR3, atomic with the audit log).
"""

from typing import Optional

from baker.db.schema import _strip_diacritics
from baker.models.address import Address, normalize_address
from baker.utils.db import escape_like as _escape_like
from baker.utils.time import now_utc

AUTOCOMPLETE_LIMIT = 20
AUTOCOMPLETE_MIN_QUERY_LEN = 2


def _row_to_address(row) -> Address:
    return Address.from_row(row)


def list_library(conn, search: Optional[str] = None) -> list[Address]:
    """List all library entries, optionally filtered by address text (FR6/FR8).

    When ``search`` is provided, matches against ``normalized_address`` with
    the diacritics-stripped query so the management screen search behaves
    the same as autocomplete (FR1 normalization). Ordered by most-recently
    updated first so newly-edited entries surface at the top of the
    management screen.
    """
    if search and search.strip():
        normalized_query = _strip_diacritics(search.strip())
        like = f"%{_escape_like(normalized_query)}%"
        rows = conn.execute(
            "SELECT * FROM address_library "
            "WHERE normalized_address LIKE ? ESCAPE '\\' "
            "ORDER BY updated_at DESC, id DESC",
            (like,),
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM address_library ORDER BY updated_at DESC, id DESC"
        ).fetchall()
    return [_row_to_address(r) for r in rows]


def get_library_entry(conn, entry_id: int) -> Optional[Address]:
    row = conn.execute(
        "SELECT * FROM address_library WHERE id = ?", (entry_id,)
    ).fetchone()
    return _row_to_address(row) if row else None


def create_library_entry(
    conn,
    display_address: str,
    google_maps_url: Optional[str] = None,
) -> Address:
    """Insert a new ``address_library`` row (FR8).

    The unique index ``idx_address_library_normalized_url_unique`` enforces
    one row per ``(normalized_address, google_maps_url)`` pair. When the
    pair already exists, the existing row is returned instead of raising
    (idempotent create — matches the Phase 3 upsert semantics so manual
    library creation and order-save auto-sync do not collide).
    """
    normalized = normalize_address(display_address)
    url = google_maps_url.strip() if google_maps_url else None
    existing = conn.execute(
        "SELECT * FROM address_library "
        "WHERE normalized_address = ? AND "
        "  (google_maps_url IS ? OR google_maps_url = ?)",
        (normalized, url, url),
    ).fetchone()
    if existing:
        return _row_to_address(existing)
    cursor = conn.execute(
        "INSERT INTO address_library "
        "(normalized_address, display_address, google_maps_url, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?)",
        (normalized, display_address.strip(), url, now_utc(), now_utc()),
    )
    row = conn.execute(
        "SELECT * FROM address_library WHERE id = ?", (cursor.lastrowid,)
    ).fetchone()
    return _row_to_address(row)


def update_library_entry(
    conn,
    entry_id: int,
    display_address: Optional[str] = None,
    google_maps_url: Optional[str] = None,
) -> Optional[Address]:
    """Patch an ``address_library`` row (FR8).

    Only the supplied fields are updated. When ``display_address`` changes,
    ``normalized_address`` is recomputed so the matching key stays in sync
    with the display text. When the new ``(normalized_address, google_maps_url)``
    pair collides with another existing row, the update is rejected with a
    ``ValueError`` so the router can translate it to a 409 response.
    """
    entry = get_library_entry(conn, entry_id)
    if not entry:
        return None

    new_display = entry.display_address
    new_url = entry.google_maps_url
    if display_address is not None:
        new_display = display_address.strip()
    if google_maps_url is not None:
        new_url = google_maps_url.strip() if google_maps_url else None

    new_normalized = normalize_address(new_display)

    # Collision check against a different row with the same (normalized, url).
    collision = conn.execute(
        "SELECT id FROM address_library "
        "WHERE normalized_address = ? AND "
        "  (google_maps_url IS ? OR google_maps_url = ?) AND "
        "  id != ?",
        (new_normalized, new_url, new_url, entry_id),
    ).fetchone()
    if collision:
        raise ValueError("Địa chỉ và link đã tồn tại trong thư viện")

    conn.execute(
        "UPDATE address_library "
        "SET normalized_address = ?, display_address = ?, google_maps_url = ?, updated_at = ? "
        "WHERE id = ?",
        (new_normalized, new_display, new_url, now_utc(), entry_id),
    )
    return get_library_entry(conn, entry_id)


def delete_library_entry(conn, entry_id: int) -> bool:
    """Hard-delete a library entry (FR8). ``customer_addresses`` rows cascade.

    Returns True when a row was deleted, False when the id was not found.
    """
    cursor = conn.execute(
        "DELETE FROM address_library WHERE id = ?", (entry_id,)
    )
    return cursor.rowcount > 0


def autocomplete(
    conn,
    query: str,
    customer_id: Optional[int] = None,
    limit: int = AUTOCOMPLETE_LIMIT,
) -> list[dict]:
    """Return matching library entries for the autocomplete dropdown (FR7/FR1).

    The query is normalized (trim, lowercase, strip diacritics) and matched
    against ``address_library.normalized_address`` via a ``LIKE`` prefix
    scan that leverages the v101 index (NFR1: p95 < 300ms at 10k rows).
    Results are paginated to ``limit`` (default 20).

    When ``customer_id`` is provided, the customer's own addresses (rows
    linked via ``customer_addresses``) are ranked first, then the remaining
    library matches follow (FR5). Each result carries ``googleMapsUrl`` so
    the frontend can auto-bind the link on selection (FR2 / AC2), and an
    ``isCustomerAddress`` flag so the UI can badge customer-specific
    suggestions (FR5).
    """
    q = (query or "").strip()
    if len(q) < AUTOCOMPLETE_MIN_QUERY_LEN:
        return []
    normalized_query = _strip_diacritics(q)
    like = f"%{_escape_like(normalized_query)}%"

    if customer_id is not None:
        # FR5: customer's own matching addresses first, then the rest.
        rows = conn.execute(
            "SELECT al.*, "
            "  CASE WHEN ca.customer_id IS NOT NULL THEN 1 ELSE 0 END AS is_customer "
            "FROM address_library al "
            "LEFT JOIN customer_addresses ca "
            "  ON ca.address_library_id = al.id AND ca.customer_id = ? "
            "WHERE al.normalized_address LIKE ? ESCAPE '\\' "
            "ORDER BY is_customer DESC, al.updated_at DESC, al.id DESC "
            "LIMIT ?",
            (customer_id, like, limit),
        ).fetchall()
        results = []
        for r in rows:
            results.append(
                {
                    "id": r["id"],
                    "displayAddress": r["display_address"],
                    "googleMapsUrl": r["google_maps_url"],
                    "isCustomerAddress": bool(r["is_customer"]),
                }
            )
        return results

    rows = conn.execute(
        "SELECT * FROM address_library "
        "WHERE normalized_address LIKE ? ESCAPE '\\' "
        "ORDER BY updated_at DESC, id DESC "
        "LIMIT ?",
        (like, limit),
    ).fetchall()
    return [
        {
            "id": r["id"],
            "displayAddress": r["display_address"],
            "googleMapsUrl": r["google_maps_url"],
            "isCustomerAddress": False,
        }
        for r in rows
    ]


def link_customer_address(conn, customer_id: int, address_library_id: int) -> None:
    """Link a customer to an address library entry (FR4 / Phase 3 hook).

    Idempotent — the composite PK on ``customer_addresses`` makes re-linking
    a no-op. Used by Phase 3 order-save auto-sync; exposed here so the
    library CRUD can also associate a customer when the management screen
    gains that capability later.
    """
    conn.execute(
        "INSERT OR IGNORE INTO customer_addresses (customer_id, address_library_id) "
        "VALUES (?, ?)",
        (customer_id, address_library_id),
    )