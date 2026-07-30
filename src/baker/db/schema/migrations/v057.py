"""Migration v057: _migrate_v57_generate_customers_from_orders (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v57_generate_customers_from_orders(conn):
    """Generate customer records from existing orders and link orders to them.

    DG-204 Phase 2. Scans all orders that have no customer_id yet, groups them
    by normalized phone (FR1/FR2), resolves a single customer name per group via
    the most-common-name rule (FR3), applies the earliest-order-wins rule for a
    phone shared by distinct name groups (FR4), inserts customer records via
    direct SQLite (FR5), links matching orders via customer_id (FR6), and also
    creates customers for phone-less orders using customer_name (FR8). The
    migration is idempotent (FR7): orders already linked and phones that already
    have a matching customer are skipped. A summary line is logged (FR9).

    Reusing `_normalize_phone()` and `_pick_most_common_name()` from Phase 1 and
    `Customer.save(conn)` for inserts, following the v56 migration-callable
    pattern (direct SQL, no API round-trips — NFR1/NFR3). The whole callable
    runs within the `ensure_schema` migration transaction (NFR2).
    """
    import logging

    from baker.models.customer import Customer

    logger = logging.getLogger("baker.db")

    # Existing customer phones (normalized) for idempotency — FR7/NFR4.
    existing_phones: dict[str, int] = {}
    for crow in conn.execute("SELECT id, phone FROM customers").fetchall():
        nphone = _normalize_phone(crow["phone"])
        if nphone and nphone not in existing_phones:
            existing_phones[nphone] = crow["id"]

    # Existing customers keyed by case-insensitive name (for phone-less links).
    existing_names: dict[str, int] = {}
    for crow in conn.execute("SELECT id, name FROM customers").fetchall():
        key = (crow["name"] or "").strip().lower()
        if key and key not in existing_names:
            existing_names[key] = crow["id"]

    customers_created = 0
    orders_linked = 0

    def _link_order(conn, oid: int, cust_id: int) -> None:
        nonlocal orders_linked
        cur = conn.execute(
            "UPDATE orders SET customer_id = ? WHERE id = ? AND customer_id IS NULL",
            (cust_id, oid),
        )
        if cur.rowcount > 0:
            orders_linked += 1

    # ── Phone-having orders (FR1–FR7) ─────────────────────────────────────
    # Scan orders with non-empty customer_phone where customer_id IS NULL,
    # ordered so the first row per phone is the earliest order.
    phone_rows = conn.execute(
        """
        SELECT id, customer_name, customer_phone, created_at
        FROM orders
        WHERE customer_id IS NULL
          AND customer_phone IS NOT NULL
          AND customer_phone != ''
        ORDER BY created_at ASC, id ASC
        """
    ).fetchall()

    # Group orders by normalized phone (FR1/FR2).
    phone_groups: dict[str, list[tuple[int, str]]] = {}
    for orow in phone_rows:
        nphone = _normalize_phone(orow["customer_phone"])
        if not nphone:
            continue
        phone_groups.setdefault(nphone, []).append(
            (orow["id"], orow["customer_name"] or "")
        )

    for nphone, orders in phone_groups.items():
        # Idempotency (FR7): phone already has a customer — link its orders.
        if nphone in existing_phones:
            cust_id = existing_phones[nphone]
            for oid, _name in orders:
                _link_order(conn, oid, cust_id)
            continue

        # Partition orders into distinct name groups (FR4). The group key uses
        # the same case-insensitive, trimmed rule as _pick_most_common_name so
        # name variants collapse into one group (FR3).
        name_to_orders: dict[str, list[tuple[int, str]]] = {}
        for oid, name in orders:
            gkey = (name or "").strip().lower()
            name_to_orders.setdefault(gkey, []).append((oid, name))

        # Resolve a representative name per group and capture each group's
        # earliest order. `orders` is already ASC by created_at/id, and we
        # appended in that order, so the first entry per group is earliest.
        group_info: list[tuple[str, list[tuple[int, str]], str]] = []
        for gkey, gorders in name_to_orders.items():
            resolved_name = _pick_most_common_name([o[1] for o in gorders])
            group_info.append((gkey, gorders, resolved_name))

        if not group_info:
            continue

        # FR4: earliest-order-wins. `orders` was ordered by created_at ASC,
        # id ASC, and `name_to_orders` preserved that insertion order, so the
        # first group seen has the earliest order and wins the phone. Iterate
        # in insertion order; idx 0 keeps the phone, later groups get "".
        for idx, (_gkey, gorders, resolved_name) in enumerate(group_info):
            phone_assigned = nphone if idx == 0 else ""
            cust = Customer(name=resolved_name or "Khách", phone=phone_assigned)
            cust_id = cust.save(conn)
            customers_created += 1
            # Track the new customer so a later phone group can reuse it.
            if phone_assigned:
                existing_phones[nphone] = cust_id
            # Also register the name so phone-less orders with the same name
            # reuse this customer instead of creating a duplicate.
            name_key = (resolved_name or "Khách").strip().lower()
            if name_key and name_key not in existing_names:
                existing_names[name_key] = cust_id
            for oid, _name in gorders:
                _link_order(conn, oid, cust_id)

    # ── Phone-less orders with a name (FR8) ───────────────────────────────
    nameless_rows = conn.execute(
        """
        SELECT id, customer_name
        FROM orders
        WHERE customer_id IS NULL
          AND (customer_phone IS NULL OR customer_phone = '')
          AND customer_name IS NOT NULL
          AND customer_name != ''
        """
    ).fetchall()

    # Group phone-less orders by case-insensitive name so a single customer is
    # created per distinct name, not per order.
    nameless_groups: dict[str, list[int]] = {}
    nameless_names: dict[str, list[str]] = {}
    for orow in nameless_rows:
        key = (orow["customer_name"] or "").strip().lower()
        if not key:
            continue
        nameless_groups.setdefault(key, []).append(orow["id"])
        nameless_names.setdefault(key, []).append(orow["customer_name"])

    for key, oids in nameless_groups.items():
        # Idempotency (FR7): name already has a customer — link its orders.
        if key in existing_names:
            cust_id = existing_names[key]
            for oid in oids:
                _link_order(conn, oid, cust_id)
            continue
        resolved = _pick_most_common_name(nameless_names[key])
        cust = Customer(name=resolved, phone="")
        cust_id = cust.save(conn)
        customers_created += 1
        existing_names[key] = cust_id
        for oid in oids:
            _link_order(conn, oid, cust_id)

    # FR9: summary log.
    logger.info("Đã tạo %d khách hàng, liên kết %d đơn hàng.", customers_created, orders_linked)
