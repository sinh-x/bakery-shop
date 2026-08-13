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

# DG-388 Phase 2 / F2: cap on past-order addresses returned per customer.
PAST_ORDERS_LIMIT = 10


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

    The upsert is implemented as ``INSERT OR IGNORE`` followed by a
    ``SELECT`` of the matching pair. This is a single atomic statement in
    SQLite, so concurrent calls cannot race between the SELECT and INSERT
    and surface an ``IntegrityError`` to the caller (CQ-1 fix). The
    subsequent ``SELECT`` resolves to the winning row whether it was just
    inserted by this call or already existed from a concurrent one.
    """
    normalized = normalize_address(display_address)
    url = google_maps_url.strip() if google_maps_url else None
    conn.execute(
        "INSERT OR IGNORE INTO address_library "
        "(normalized_address, display_address, google_maps_url, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?)",
        (normalized, display_address.strip(), url, now_utc(), now_utc()),
    )
    row = conn.execute(
        "SELECT * FROM address_library "
        "WHERE normalized_address = ? AND "
        "  (google_maps_url IS ? OR google_maps_url = ?)",
        (normalized, url, url),
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
) -> dict:
    """Return grouped autocomplete suggestions for the dropdown (FR3/FR1/FR5).

    DG-388 Phase 2: the response is ALWAYS a grouped dict with two keys so
    the frontend can render two labeled sections ("Địa chỉ đã giao" /
    "Thư viện địa chỉ"):

    - ``pastOrders``: the caller customer's previous door-delivery
      addresses drawn from the ``orders`` table (raw
      ``delivery_address`` text + its most recent ``google_maps_url``),
      filtered by the normalized query and capped at
      :data:`PAST_ORDERS_LIMIT` (F2). Empty when ``customer_id`` is None
      or no past orders match.
    - ``library``: matching ``address_library`` entries (the previous
      flat-list behavior), ranked with the caller customer's own linked
      addresses first when ``customer_id`` is supplied (FR5), capped at
      ``limit`` (default 20). Each entry carries ``googleMapsUrl`` for
      auto-bind (FR2 / AC2) and an ``isCustomerAddress`` flag.

    The query is normalized (trim, lowercase, strip diacritics) and
    matched against ``normalized_address`` / normalized
    ``delivery_address`` via ``LIKE`` so diacritics- and case-variants
    resolve to the same key (FR1 / NFR3). Both lists may be empty; the
    grouped dict is always returned so consumers can iterate safely.
    """
    q = (query or "").strip()
    if len(q) < AUTOCOMPLETE_MIN_QUERY_LEN:
        return {"pastOrders": [], "library": []}
    return {
        "pastOrders": _autocomplete_past_orders(conn, q, customer_id),
        "library": _autocomplete_library(conn, q, customer_id, limit),
    }


def _autocomplete_past_orders(
    conn,
    query: str,
    customer_id: Optional[int],
) -> list[dict]:
    """Return the customer's past door-delivery addresses matching ``query``.

    DG-388 Phase 2 / F1 / F2. Draws from the ``orders`` table (not the
    address library) so the past-orders group reflects addresses the
    customer actually used on prior door-delivery orders, regardless of
    whether a library entry exists. Each unique raw
    ``delivery_address`` is returned once with the most recent
    ``google_maps_url`` seen for that address (so auto-bind still works
    when a link was captured on a later order). Results are capped at
    :data:`PAST_ORDERS_LIMIT` (F2) and ordered by most-recently used
    first. Returns an empty list when ``customer_id`` is None.
    """
    if customer_id is None:
        return []
    _ensure_normalize_function(conn)
    normalized_query = _strip_diacritics(query)
    like = f"%{_escape_like(normalized_query)}%"
    placeholders = ",".join("?" for _ in DOOR_DELIVERY_TYPES)
    status_placeholders = ",".join("?" for _ in DELIVERED_STATUSES)
    rows = conn.execute(
        f"""
        SELECT o.delivery_address AS delivery_address,
               o.google_maps_url AS google_maps_url,
               latest.last_order_id AS last_order_id,
               latest.latest_link_id AS latest_link_id
        FROM orders o
        INNER JOIN (
            SELECT delivery_address,
                   MAX(id) AS last_order_id,
                   MAX(CASE WHEN google_maps_url IS NOT NULL
                             AND google_maps_url != ''
                        THEN id END) AS latest_link_id
            FROM orders
            WHERE customer_id = ?
              AND delivery_type IN ({placeholders})
              AND status IN ({status_placeholders})
              AND delivery_address IS NOT NULL
              AND delivery_address != ''
            GROUP BY delivery_address
        ) latest ON o.id = COALESCE(latest.latest_link_id, latest.last_order_id)
        WHERE normalize_address(o.delivery_address) LIKE ? ESCAPE '\\'
        ORDER BY latest.last_order_id DESC
        LIMIT ?
        """,
        (
            customer_id,
            *DOOR_DELIVERY_TYPES,
            *DELIVERED_STATUSES,
            like,
            PAST_ORDERS_LIMIT,
        ),
    ).fetchall()
    return [
        {
            "displayAddress": r["delivery_address"],
            "googleMapsUrl": (r["google_maps_url"] or None),
        }
        for r in rows
    ]


def _autocomplete_library(
    conn,
    query: str,
    customer_id: Optional[int],
    limit: int,
) -> list[dict]:
    """Return matching ``address_library`` entries (DG-385 Phase 2 behavior).

    When ``customer_id`` is provided, the customer's own linked addresses
    rank first (FR5); each entry carries ``googleMapsUrl`` (FR2/AC2) and
    an ``isCustomerAddress`` flag. Capped at ``limit`` (default 20).
    """
    normalized_query = _strip_diacritics(query)
    like = f"%{_escape_like(normalized_query)}%"

    if customer_id is not None:
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
        return [
            {
                "id": r["id"],
                "displayAddress": r["display_address"],
                "googleMapsUrl": r["google_maps_url"],
                "isCustomerAddress": bool(r["is_customer"]),
            }
            for r in rows
        ]

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


# ---------------------------------------------------------------------------
# DG-385 Phase 3 — order-save auto-sync hooks (FR3 / FR4 / AC3 / AC4 / AC8)
#
# These helpers run inside the caller's ``get_db()`` transaction (NFR3) and
# are invoked from ``create_order`` and ``edit_order`` in
# ``baker.api.orders``. Sync fires ONLY for door-to-door delivery orders
# (``delivery_type IN ('door', 'delivery')``) and ONLY when a Google Maps
# link is present, added, updated, or removed — never for pickup orders
# and never when a link is simply absent (AC3, AC4).
#
# Reference-count rule (AC8): when a link is removed or replaced on an
# order, the corresponding ``address_library`` row is deleted only when
# NO other door-delivery order still references the same
# ``(normalized_address, google_maps_url)`` pair. This keeps entries that
# other active orders depend on intact.
# ---------------------------------------------------------------------------

# Door-to-door delivery types that trigger library sync. Includes the
# legacy ``"delivery"`` value which behaves like ``"door"`` (see
# ``OrderDeliverySection._isDoorDelivery`` on the Flutter side). ``"bus"``
# is intentionally excluded — bus orders use a central pickup point, not a
# per-customer address+link pair that should populate the library.
DOOR_DELIVERY_TYPES = ("door", "delivery")

# DG-388 Phase 5.6-c4 Mn-3: only orders that reached a delivered state
# contribute to the "Địa chỉ đã giao" (previously delivered) section of
# autocomplete. Matches the codebase-wide DELIVERED_STATUSES convention
# (e.g. baker.commands.repair._common) so cancelled/rejected/draft orders
# are excluded.
DELIVERED_STATUSES = ("delivered", "completed")


def is_door_delivery(delivery_type: str) -> bool:
    """Return True when ``delivery_type`` is a door-to-door type (FR3/AC3).

    ``"door"`` is the current value; ``"delivery"`` is the legacy alias
    kept for backward compatibility with older rows. ``"bus"`` and
    ``"pickup"`` are NOT door delivery and do not trigger library sync.
    """
    return delivery_type in DOOR_DELIVERY_TYPES


def sync_on_order_save(
    conn,
    delivery_type: str,
    delivery_address: str,
    google_maps_url: Optional[str],
    customer_id: Optional[int] = None,
) -> Optional[int]:
    """Upsert an address+link pair into the library after an order save (FR3/AC3).

    Runs ONLY for door-to-door delivery orders with a non-empty
    ``delivery_address`` and a non-empty ``google_maps_url``. When both
    conditions hold, the pair is upserted (idempotent) and — when a
    ``customer_id`` is supplied — linked to the customer in
    ``customer_addresses`` so subsequent autocomplete results rank the
    customer's own addresses first (FR5).

    Returns the ``address_library.id`` of the upserted entry, or ``None``
    when the sync was skipped (non-door delivery, missing address, or
    missing link).
    """
    if not is_door_delivery(delivery_type):
        return None
    address = (delivery_address or "").strip()
    if not address:
        return None
    url = (google_maps_url or "").strip() or None
    if not url:
        return None
    entry = create_library_entry(conn, display_address=address, google_maps_url=url)
    if customer_id is not None:
        link_customer_address(conn, customer_id, entry.id)
    return entry.id


def _ensure_normalize_function(conn) -> None:
    """Register ``normalize_address`` as a SQLite custom function on ``conn``.

    Idempotent — re-registering with the same name simply replaces the
    previous binding. Used by ``_count_other_orders_with_pair`` so the
    address-normalization comparison can run inside SQLite (CQ-2) instead
    of post-filtering fetched rows in Python.
    """
    conn.create_function("normalize_address", 1, normalize_address)


def _count_other_orders_with_pair(
    conn,
    normalized_address: str,
    google_maps_url: Optional[str],
    exclude_order_id: int,
) -> int:
    """Count door-delivery orders referencing the same (address, link) pair.

    Used by the reference-count rule (AC8). ``exclude_order_id`` is the
    order whose link was just removed/changed — it no longer references
    the pair so it is excluded from the count. The address match uses the
    normalized form so diacritics/case variants collapse to the same key
    (FR1).

    The door-delivery type filter and the address-normalization comparison
    are pushed into the SQL ``WHERE`` clause (CQ-2) by registering
    ``normalize_address`` as a SQLite custom function. This lets SQLite
    compute ``COUNT(*)`` server-side using the
    ``idx_address_library_normalized_url_unique`` normalized key semantics
    instead of fetching every url-matching order row and post-filtering in
    Python.
    """
    _ensure_normalize_function(conn)
    placeholders = ",".join("?" for _ in DOOR_DELIVERY_TYPES)
    row = conn.execute(
        f"SELECT COUNT(*) AS cnt FROM orders "
        f"WHERE google_maps_url = ? "
        f"  AND delivery_type IN ({placeholders}) "
        f"  AND delivery_address IS NOT NULL "
        f"  AND delivery_address != '' "
        f"  AND normalize_address(delivery_address) = ? "
        f"  AND id != ?",
        (google_maps_url, *DOOR_DELIVERY_TYPES, normalized_address, exclude_order_id),
    ).fetchone()
    return int(row["cnt"]) if row else 0


def _maybe_delete_library_pair(
    conn,
    normalized_address: str,
    google_maps_url: Optional[str],
    exclude_order_id: int,
) -> None:
    """Delete the library entry for a pair when no other orders reference it (AC8).

    Looks up the ``address_library`` row keyed by
    ``(normalized_address, google_maps_url)``. When found, counts the
    remaining door-delivery orders still referencing the pair (excluding
    ``exclude_order_id``). When the count is zero, the entry is deleted —
    its ``customer_addresses`` links cascade via the v101 FK. When other
    orders still use the pair, the entry is preserved (AC8).
    """
    if not google_maps_url:
        return
    row = conn.execute(
        "SELECT id FROM address_library "
        "WHERE normalized_address = ? AND google_maps_url = ?",
        (normalized_address, google_maps_url),
    ).fetchone()
    if not row:
        return
    remaining = _count_other_orders_with_pair(
        conn, normalized_address, google_maps_url, exclude_order_id
    )
    if remaining == 0:
        delete_library_entry(conn, row["id"])


def list_missing_links(conn, limit: int = 100) -> list[dict]:
    """Return unique delivery addresses missing Google Maps links (FR5/AC6).

    Read-only SELECT that groups door-to-door delivery orders
    (``delivery_type IN ('door', 'delivery')``) by raw ``delivery_address``
    where ``google_maps_url`` is NULL or empty, returning each unique
    address with its order count. Grouping is on the raw text (not
    normalized) so staff see the address exactly as typed on the order —
    matching the Phase 4 CLI command behavior (FR4).

    Results are ordered by ``order_count DESC`` then ``delivery_address ASC``
    so the most-referenced gap surfaces first, and paginated via ``limit``
    (default 100) to keep the API response bounded (NFR4). The
    ``delivery_type IN (...)`` predicate is backed by the
    ``idx_orders_delivery_type`` index (created in migration v103) for
    sub-500ms response at up to 10k door delivery orders (NFR4). The
    ``google_maps_url`` column is not indexed; its NULL/empty filter is
    applied after the indexed ``delivery_type`` scan.

    Returns a list of dicts with ``deliveryAddress`` and ``orderCount`` keys
    (camelCase for API JSON compatibility with the rest of the addresses
    API).
    """
    placeholders = ",".join("?" for _ in DOOR_DELIVERY_TYPES)
    rows = conn.execute(
        f"""
        SELECT delivery_address AS delivery_address,
               COUNT(*) AS order_count
        FROM orders
        WHERE delivery_type IN ({placeholders})
          AND delivery_address IS NOT NULL
          AND delivery_address != ''
          AND (google_maps_url IS NULL OR google_maps_url = '')
        GROUP BY delivery_address
        ORDER BY order_count DESC, delivery_address ASC
        LIMIT ?
        """,
        (*DOOR_DELIVERY_TYPES, limit),
    ).fetchall()
    return [
        {
            "deliveryAddress": r["delivery_address"],
            "orderCount": int(r["order_count"]),
        }
        for r in rows
    ]


def sync_on_order_edit(
    conn,
    order_id: int,
    old_delivery_type: str,
    old_delivery_address: str,
    old_google_maps_url: Optional[str],
    new_delivery_type: str,
    new_delivery_address: str,
    new_google_maps_url: Optional[str],
    customer_id: Optional[int] = None,
) -> None:
    """Sync the address library after an order edit (FR4/AC4/AC8).

    Handles the four link-change scenarios on a door-delivery order:

    1. **Link added** (old empty → new present): upsert the new pair.
    2. **Link updated** (old present → new present, different): upsert the
       new pair; delete the old pair's library entry when no other orders
       reference it (AC8).
    3. **Link removed** (old present → new empty): delete the old pair's
       library entry when no other orders reference it (AC8).
    4. **No link change**: no-op — sync only fires when the link changes
       (per Sinh's clarification: "Sync ONLY triggers when a Google Maps
       link is added/updated/removed — not on every order save").

    When the order transitions OUT of door delivery (e.g. door → pickup),
    the old link pair is cleaned up via the reference-count rule. When the
    order transitions INTO door delivery with a link present, the new pair
    is upserted. Address-only changes (link unchanged) do NOT trigger
    sync — the library is keyed on the (address, link) pair and the
    display text is owned by the order, not the library.
    """
    old_url = (old_google_maps_url or "").strip() or None
    new_url = (new_google_maps_url or "").strip() or None
    old_addr = (old_delivery_address or "").strip()
    new_addr = (new_delivery_address or "").strip()
    old_is_door = is_door_delivery(old_delivery_type)
    new_is_door = is_door_delivery(new_delivery_type)

    # Cleanup the OLD pair when the order no longer references it — either
    # because the link changed/removed on a door order, or because the
    # order left door delivery entirely.
    old_pair_active = old_is_door and bool(old_addr) and bool(old_url)
    new_pair_uses_old_url = (
        new_is_door
        and bool(new_addr)
        and bool(new_url)
        and old_url == new_url
        and normalize_address(new_addr) == normalize_address(old_addr)
    )
    if old_pair_active and not new_pair_uses_old_url:
        _maybe_delete_library_pair(
            conn, normalize_address(old_addr), old_url, order_id
        )

    # Upsert the NEW pair when the order is now a door delivery with a
    # link. The upsert is idempotent and also re-links the customer.
    if new_is_door and bool(new_addr) and bool(new_url):
        sync_on_order_save(
            conn, new_delivery_type, new_addr, new_url, customer_id
        )