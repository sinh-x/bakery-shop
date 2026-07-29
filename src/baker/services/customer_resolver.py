"""Customer resolution logic extracted from ``api/orders.py`` (DG-308 Phase 4.4, FR-ARCH-1).

This module centralises the business logic that resolves or creates a
``customer_id`` for an order, keeping HTTP handlers in ``api/orders.py`` thin.
The functions here are pure (take a connection, return an int / Optional[int])
so they can be reused by other callers (e.g. repair commands) without going
through the FastAPI layer.

Resolution chain (matches DG-205 Phase 3 / DG-227 / DG-252):

1. ``_resolve_customer_id_by_phone`` — phone-then-name lookup with
   earliest-order-wins tiebreak against ``customer_phones`` /
   legacy ``customers.phone`` / ``customers.search_name``.
2. ``_get_or_create_walk_in_customer_id`` — the single shared "Khách lẻ"
   walk-in customer (v66 semantics).
3. ``_resolve_or_create_customer_id`` — the public entry point that chains
   the two above with auto-create-when-named/phone-bearing semantics.
"""

import sqlite3
from typing import Optional

from baker.db.schema import _strip_diacritics

# DG-252 Phase 1 (FR1/FR2/FR3) — the canonical shared walk-in customer name.
# Reuses the v66 convention (``schema.py:_migrate_v66_repair_customer_links``)
# so there is exactly one shared "Khách lẻ" record for all identity-less orders.
WALK_IN_SHARED_CUSTOMER_NAME = "Khách lẻ"


def _resolve_customer_id_by_phone(conn, phone: str, customer_name: Optional[str] = None) -> Optional[int]:
    """Resolve a customer_id from a phone number via the ``customer_phones`` table.

    DG-205 Phase 3 (FR8). Matches the normalized phone against every row in
    ``customer_phones`` (not just the primary), so an order with a secondary
    phone still links to the owning customer. When several customers share the
    same phone, the earliest-order-wins rule (consistent with v57) picks the
    customer whose earliest order has the smallest created_at/id.

    Falls back to the legacy ``customers.phone`` column when ``customer_phones``
    has no match (e.g. pre-v58 databases or customers created before Phase 1).

    DG-227 Phase 1 (FR1). When phone lookup returns nothing, falls back to a
    name-based lookup via ``customers.search_name`` (case-insensitive,
    diacritic-insensitive). Returns the first match ordered by id ASC.
    Returns ``None`` when no customer matches.
    """
    from baker.db.schema import _normalize_phone

    nphone = _normalize_phone(phone or "")
    if not nphone:
        return None

    # Primary path: match against customer_phones.phone (any row, normalized).
    # SQLite stores phones as free text; we normalize for comparison, so the
    # query pulls candidate rows and resolves the winner in Python to apply the
    # earliest-order-wins tiebreak consistently with v57.
    try:
        rows = conn.execute(
            "SELECT DISTINCT cp.customer_id FROM customer_phones cp WHERE cp.phone = ?",
            (nphone,),
        ).fetchall()
    except sqlite3.OperationalError:
        rows = []
    if rows:
        customer_ids = [r["customer_id"] for r in rows]
        if len(customer_ids) == 1:
            return customer_ids[0]
        # FR8: multiple customers share the phone — earliest-order-wins. Pick
        # the customer whose earliest order has the minimum created_at, then id.
        placeholders = ",".join("?" for _ in customer_ids)
        winner = conn.execute(
            f"SELECT customer_id, MIN(created_at) AS first_at "
            f"FROM orders WHERE customer_id IN ({placeholders}) "
            f"GROUP BY customer_id ORDER BY first_at ASC, customer_id ASC LIMIT 1",
            customer_ids,
        ).fetchone()
        if winner is not None:
            return winner["customer_id"]
        # No orders yet for any candidate — fall back to the lowest customer_id
        # for deterministic behavior.
        return min(customer_ids)

    # Secondary path: legacy customers.phone fallback (pre-v58 / direct writes).
    # M-1: normalize the stored column at query time so legacy rows that still
    # contain separators (dashes/dots/spaces) match the normalized search value.
    # This mirrors _normalize_phone (strip spaces, dots, dashes) in SQL.
    legacy = conn.execute(
        "SELECT id FROM customers "
        "WHERE REPLACE(REPLACE(REPLACE(phone, ' ', ''), '.', ''), '-', '') = ? "
        "ORDER BY id ASC LIMIT 1",
        (nphone,),
    ).fetchone()
    if legacy:
        return legacy["id"]

    # Tertiary path: name-based fallback (DG-227 FR1).
    # Strip diacritics for case-insensitive, diacritic-insensitive matching
    # against the pre-computed ``customers.search_name`` column.
    if customer_name and customer_name.strip():
        normalized_name = _strip_diacritics(customer_name.strip())
        name_match = conn.execute(
            "SELECT id FROM customers WHERE search_name = ? ORDER BY id ASC LIMIT 1",
            (normalized_name,),
        ).fetchone()
        return name_match["id"] if name_match else None

    return None


def _get_or_create_walk_in_customer_id(conn) -> int:
    """Return the id of the single shared "Khách lẻ" walk-in customer.

    DG-252 Phase 1 (FR2). Matches the v66 semantics at
    ``schema.py:_migrate_v66_repair_customer_links``: exactly one shared record
    (LOWERCASE comparison on ``customers.name``), never one-per-order. Creates
    the row if it does not yet exist so the first identity-less order
    materialises it.
    """
    existing = conn.execute(
        "SELECT id FROM customers WHERE LOWER(name) = ? ORDER BY id ASC LIMIT 1",
        (WALK_IN_SHARED_CUSTOMER_NAME.lower(),),
    ).fetchone()
    if existing is not None:
        return existing["id"]
    from baker.models.customer import Customer

    cust = Customer(name=WALK_IN_SHARED_CUSTOMER_NAME, phone="")
    return cust.save(conn)


def _resolve_or_create_customer_id(
    conn, phone: Optional[str], customer_name: Optional[str]
) -> int:
    """Guarantee a non-NULL ``customer_id`` for an order (DG-252 Phase 1).

    Resolution chain (matches FR1/FR2/AC1):
      1. ``phone``→``name`` resolution via ``_resolve_customer_id_by_phone``
         (existing phone-then-name lookup with earliest-order-wins tiebreak).
      2. Auto-create a server-side customer when step 1 returns ``None`` AND
         the order carries a name and/or a phone (FR1).
      3. Otherwise (no name AND no phone) link to the shared "Khách lẻ"
         walk-in record via ``_get_or_create_walk_in_customer_id`` (FR2).

    Always returns a positive integer customer id.
    """
    resolved = _resolve_customer_id_by_phone(conn, phone, customer_name=customer_name)
    if resolved is not None:
        return resolved

    has_name = bool(customer_name and customer_name.strip())
    has_phone = bool(phone and phone.strip())
    if has_name or has_phone:
        from baker.models.customer import Customer

        name = customer_name.strip() if has_name else "Khách"
        # DG-252 r3 [MAJOR]: materialize a `customer_phones` row so the new
        # customer is visible to `/duplicates` (which joins on customer_phones)
        # and so a later merge preserves its phone. Without this row the
        # phone-only lives in the legacy `customers.phone` column, which the
        # dedup finder and merge copy loop never consult.
        phones = (
            [{"phone": phone, "isPrimary": True}] if has_phone else []
        )
        cust = Customer(name=name, phone=phone or "", phones=phones)
        return cust.save(conn)

    return _get_or_create_walk_in_customer_id(conn)