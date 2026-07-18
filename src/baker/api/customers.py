"""Customer management API routes (DG-182 Phase 1, DG-205 Phase 2, DG-252 Phase 3)."""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

_BS = "\\"


def _escape_like(value: str) -> str:
    return value.replace("%", _BS + "%").replace("_", _BS + "_")
from pydantic import BaseModel, field_validator, model_validator

from baker.api.auth import RequireRole, record_audit_log
from baker.db.connection import get_db
from baker.db.schema import (
    _recompute_customer_year_summary,
    _strip_diacritics,
)
from baker.models.customer import (
    Customer,
    _load_customer_phones_for_many,
    _primary_phone,
    load_year_summary,
)
from baker.models.order import Order


router = APIRouter(prefix="/api/customers", tags=["customers"])


# DG-252 Phase 2 / FR10 / AC7 — centralized VN message for the delete guard.
# Kept close to the route that emits it; reused by tests to avoid string drift.
CUSTOMER_DELETE_LINKED_ORDERS_MSG = (
    "Không thể xóa khách hàng đang có đơn hàng liên kết. "
    "Vui lòng gộp khách hoặc huỷ liên kết đơn trước khi xóa."
)

# DG-252 Phase 3 / FR5 / AC3 — centralized VN messages for the merge endpoint.
# Reused by tests to avoid string drift.
CUSTOMER_MERGE_SELF_MSG = "Không thể gộp một khách hàng vào chính nó."
CUSTOMER_MERGE_NOT_FOUND_MSG = "Không tìm thấy khách hàng"
CUSTOMER_MERGE_SOURCE_NOT_FOUND_MSG = "Không tìm thấy khách hàng nguồn cần gộp"


class PhoneInput(BaseModel):
    phone: str
    isPrimary: bool = False

    @field_validator("phone")
    @classmethod
    def normalize(cls, v: str) -> str:
        return (v or "").strip()


class CustomerCreate(BaseModel):
    name: str
    phone: str = ""
    phones: Optional[list[PhoneInput]] = None

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Tên khách hàng không được để trống")
        return v.strip()

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, v: str) -> str:
        return (v or "").strip()

    @model_validator(mode="after")
    def resolve_phones(self) -> "CustomerCreate":
        if self.phones is None:
            if self.phone:
                self.phones = [PhoneInput(phone=self.phone, isPrimary=True)]
            else:
                self.phones = []
        elif self.phones:
            if not any(p.isPrimary for p in self.phones):
                raise ValueError("Ít nhất một số điện thoại phải là số chính (isPrimary=true)")
        return self


class CustomerUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    phones: Optional[list[PhoneInput]] = None

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("Tên khách hàng không được để trống")
        return v.strip() if v is not None else None

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        return v.strip()

    @model_validator(mode="after")
    def resolve_phones(self) -> "CustomerUpdate":
        if self.phones is not None and self.phones:
            if not any(p.isPrimary for p in self.phones):
                raise ValueError("Ít nhất một số điện thoại phải là số chính (isPrimary=true)")
        return self


def _phones_to_dicts(phones: Optional[list[PhoneInput]]) -> list[dict]:
    if phones is None:
        return []
    return [{"phone": p.phone, "isPrimary": p.isPrimary} for p in phones]


def _find_customers_sharing_phone(conn, phone: str, exclude_id: int) -> list[dict]:
    """Return other customers sharing the given phone (excluding exclude_id)."""
    if not phone:
        return []
    # M-1: stored phones are normalized, so normalize the search value too.
    from baker.db.schema import _normalize_phone

    nphone = _normalize_phone(phone)
    if not nphone:
        return []
    rows = conn.execute(
        "SELECT DISTINCT c.* FROM customers c "
        "JOIN customer_phones cp ON cp.customer_id = c.id "
        "WHERE cp.phone = ? AND cp.phone != '' AND c.id != ? "
        "ORDER BY c.id",
        (nphone, exclude_id),
    ).fetchall()
    return [Customer.from_row(r, conn).to_api_dict() for r in rows]


def _customer_response(conn, customer: Customer) -> dict:
    """Build API response including phone-sharing visibility (FR2a) and phones array (FR6)."""
    result = customer.to_api_dict()
    result["sharedPhoneCustomers"] = _find_customers_sharing_phone(
        conn, customer.phone, customer.id
    )
    return result


@router.get("")
def list_customers(search: Optional[str] = Query(None, description="Tìm theo tên hoặc SĐT")):
    """Danh sách khách hàng, hỗ trợ tìm kiếm partial theo tên/SĐT (FR1, FR7)."""
    with get_db() as conn:
        if search and search.strip():
            escaped = _escape_like(search.strip())
            like = f"%{escaped}%"
            search_like = f"%{_strip_diacritics(escaped)}%"
            rows = conn.execute(
                "SELECT DISTINCT c.* FROM customers c "
                "LEFT JOIN customer_phones cp ON cp.customer_id = c.id "
                "WHERE c.search_name LIKE ? OR c.phone LIKE ? OR cp.phone LIKE ? "
                "ORDER BY c.id DESC",
                (search_like, like, like),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM customers ORDER BY id DESC"
            ).fetchall()
        # Mn-3: batch-load phones for all returned customers in a single query
        # instead of one query per customer via Customer.from_row(r, conn).
        customers = [Customer.from_row(r) for r in rows]
        phones_map = _load_customer_phones_for_many(conn, [c.id for c in customers if c.id is not None])
        for c in customers:
            if c.id is not None and c.id in phones_map:
                c.phones = phones_map[c.id]
        return [c.to_api_dict() for c in customers]


@router.get("/duplicates")
def list_duplicate_customers(actor: str = Depends(RequireRole("admin"))):
    """Tìm khách hàng trùng lặp (FR6).

    Admin-only. Returns duplicate candidate groups keyed by either:
      - normalized phone (``customer_phones.phone`` after ``_normalize_phone``)
      - diacritic-stripped ``customers.search_name``

    Each group lists the customers sharing that key with their current order
    count. Groups with fewer than 2 customers are omitted. Powers the admin
    duplicate-finder UI; the per-customer order count drives the confirmation
    dialog shown before a merge is confirmed.

    Registered before ``/{customer_id}`` so the static ``/duplicates`` path
    is not shadowed by the int path parameter.
    """
    with get_db() as conn:
        # Mn-6: compute order counts once with a single grouped query rather
        # than issuing one COUNT(*) per customer row (the previous N+1).
        order_counts = _load_order_counts_by_customer(conn)

        # --- Phone-keyed groups: any normalized phone shared by ≥2 customers.
        phone_groups_raw = conn.execute(
            "SELECT cp.phone AS key, c.id AS customer_id, c.name, c.phone, "
            "       c.search_name "
            "FROM customer_phones cp "
            "JOIN customers c ON c.id = cp.customer_id "
            "WHERE cp.phone != '' "
            "ORDER BY cp.phone, c.id"
        ).fetchall()
        phone_groups: dict[str, list[dict]] = {}
        for r in phone_groups_raw:
            phone_groups.setdefault(r["key"], []).append(
                _duplicate_customer_row(
                    conn,
                    r["customer_id"],
                    r["name"],
                    r["phone"],
                    order_counts=order_counts,
                )
            )

        # --- Name-keyed groups: diacritic-stripped search_name shared by ≥2.
        name_groups_raw = conn.execute(
            "SELECT id, name, phone, search_name FROM customers "
            "WHERE search_name != '' ORDER BY id"
        ).fetchall()
        name_groups: dict[str, list[dict]] = {}
        for r in name_groups_raw:
            name_groups.setdefault(r["search_name"], []).append(
                _duplicate_customer_row(
                    conn,
                    r["id"],
                    r["name"],
                    r["phone"],
                    order_counts=order_counts,
                )
            )

        groups: list[dict] = []
        # Dedupe across group kinds: emit each customer set at most once.
        # Phone groups win since they are emitted first (more specific key).
        seen_customer_sets: set[tuple[int, ...]] = set()

        def _emit_group(key: str, kind: str, members: list[dict]) -> None:
            if len(members) < 2:
                return
            # Dedupe customers within a group (a customer could appear twice
            # if it has the same phone twice — defensive).
            unique: list[dict] = []
            ids_seen: set[int] = set()
            for m in members:
                cid = m["id"]
                if cid in ids_seen:
                    continue
                ids_seen.add(cid)
                unique.append(m)
            if len(unique) < 2:
                return
            # Mn-4: dedupe across group kinds — drop `kind` from the set key so
            # the same customer set is emitted once even when a phone group
            # and a name group cover the same ids. Phone groups are emitted
            # first, so they win.
            set_key = tuple(sorted(ids_seen))
            if set_key in seen_customer_sets:
                return
            seen_customer_sets.add(set_key)
            groups.append(
                {
                    "key": key,
                    "kind": kind,
                    "customers": unique,
                }
            )

        for key, members in phone_groups.items():
            _emit_group(key, "phone", members)
        for key, members in name_groups.items():
            _emit_group(key, "name", members)

        return {"groups": groups}


@router.post("", status_code=201)
def create_customer(body: CustomerCreate):
    """Tạo khách hàng mới. Trả về danh sách khách hàng khác cùng SĐT (FR2, FR2a, FR4)."""
    with get_db() as conn:
        phones_dicts = _phones_to_dicts(body.phones)
        primary = _primary_phone(phones_dicts)
        customer = Customer(name=body.name, phone=primary or body.phone, phones=phones_dicts)
        customer.save(conn)
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer.id,)).fetchone()
        loaded = Customer.from_row(row, conn)
        return _customer_response(conn, loaded)


@router.get("/{customer_id}")
def get_customer(customer_id: int):
    """Chi tiết một khách hàng (FR3, FR6, FR7 — includes yearSummary)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")
        customer = Customer.from_row(row, conn)
        # DG-206 FR7/AC5: include the current year's order count + total volume.
        from datetime import datetime, timezone

        current_year = datetime.now(timezone.utc).year
        customer.year_summary = load_year_summary(conn, customer_id, current_year)
        return customer.to_api_dict()


@router.patch("/{customer_id}")
def update_customer(customer_id: int, body: CustomerUpdate):
    """Cập nhật tên và/hoặc SĐT. Trả về khách hàng khác cùng SĐT (FR4, FR2a, FR5)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")

        customer = Customer.from_row(row, conn)
        if body.name is None and body.phone is None and body.phones is None:
            return _customer_response(conn, customer)

        phones_dicts = _phones_to_dicts(body.phones) if body.phones is not None else None
        # Legacy phone field: sync customer_phones primary row to new value
        if body.phones is None and body.phone is not None:
            phones_dicts = [
                {"phone": p["phone"], "isPrimary": p["isPrimary"]}
                for p in customer.phones
            ]
            if phones_dicts:
                primary_idx = next(
                    (i for i, p in enumerate(phones_dicts) if p["isPrimary"]), 0
                )
                phones_dicts[primary_idx]["phone"] = body.phone
            else:
                phones_dicts = [{"phone": body.phone, "isPrimary": True}]
        customer.update(conn, name=body.name, phone=body.phone, phones=phones_dicts)
        updated_row = conn.execute(
            "SELECT * FROM customers WHERE id = ?", (customer_id,)
        ).fetchone()
        loaded = Customer.from_row(updated_row, conn)
        return _customer_response(conn, loaded)


@router.delete("/{customer_id}")
def delete_customer(
    customer_id: int,
    actor: str = Depends(RequireRole("admin")),
):
    """Xóa khách hàng (hard-delete).

    FR10/AC7: nếu khách hàng đang liên kết với ≥1 đơn hàng, trả về 409 và
    KHÔNG thay đổi dữ liệu. Khách hàng không liên kết đơn nào vẫn xóa được.
    Gợi ý thay thế: gộp khách (merge) thay vì xóa khi còn đơn liên kết.

    Mn-5 (DG-252 review): admin-only via ``RequireRole("admin")`` and
    audited via ``record_audit_log``, mirroring the merge endpoint. The
    grace-period pass-through (``AUTH_REQUIRED=false``) preserves the
    DG-119 backward-compat baseline.
    """
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")

        linked_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (customer_id,)
        ).fetchone()[0]

        if linked_orders > 0:
            raise HTTPException(
                status_code=409,
                detail=CUSTOMER_DELETE_LINKED_ORDERS_MSG,
            )

        old_value = _row_to_customer_dict(row)

        # FR9: cascade-delete customer_phones rows (also handled by ON DELETE CASCADE,
        # but explicit DELETE ensures correctness even if FK enforcement is off)
        conn.execute("DELETE FROM customer_phones WHERE customer_id = ?", (customer_id,))
        conn.execute("DELETE FROM customers WHERE id = ?", (customer_id,))

        record_audit_log(
            conn,
            actor,
            "delete",
            "customer",
            customer_id,
            old_value=old_value,
            new_value=None,
        )

        return {
            "ok": True,
            "id": customer_id,
            "linkedOrdersCleared": 0,
        }


@router.get("/{customer_id}/orders")
def get_customer_orders(customer_id: int):
    """Lịch sử đơn hàng của khách hàng (FR6)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")

        order_rows = conn.execute(
            "SELECT * FROM orders WHERE customer_id = ? ORDER BY id DESC",
            (customer_id,),
        ).fetchall()
        return [Order.from_row(r, conn).to_api_dict() for r in order_rows]


# ---------------------------------------------------------------------------
# DG-252 Phase 3 — Merge + duplicates APIs (FR5, FR6, NFR3, AC3)
#
# Both endpoints are admin-only via ``RequireRole("admin")``. The merge
# endpoint reuses v59 merge semantics (relink orders → dedupe phones →
# recompute year summary → hard-delete source) but as a runtime service
# function executing inside a single ``get_db()`` transaction so any failure
# rolls back completely (NFR3). The duplicates endpoint groups customers by
# normalized phone or diacritic-stripped ``search_name`` and includes
# per-customer order counts to power the finder UI's confirmation dialog.
# ---------------------------------------------------------------------------


class MergeRequest(BaseModel):
    """Body for ``POST /api/customers/{id}/merge`` (FR5).

    ``sourceCustomerId`` is the customer to merge *into* the target (the
    ``{id}`` path param). The source is hard-deleted after relink.
    """

    sourceCustomerId: int

    @field_validator("sourceCustomerId")
    @classmethod
    def positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("sourceCustomerId phải là số nguyên dương")
        return v


def _merge_customer_into_target(
    conn,
    target_id: int,
    source_id: int,
) -> dict:
    """Runtime merge of ``source_id`` into ``target_id`` (v59 semantics).

    Executes inside the caller's open transaction so the whole merge commits
    atomically (NFR3). Steps (mirroring ``_migrate_v59_deduplicate_customers``
    at ``schema.py:3196`` but for a single explicit pair):

    1. Relink all ``orders.customer_id = source_id`` → ``target_id``.
    2. Dedupe phones: copy source's phones to target, skipping phones the
       target already has (normalized form). Drop the source's phone rows.
    3. Recompute ``customer_year_summary`` for every year the target now has
       orders (existing target years + any years the source contributed).
    4. Hard-delete the source customer row.
    5. Update the target's denormalized ``customers.phone`` to its primary
       phone (after dedupe) so legacy fallback queries stay consistent.

    Returns a summary dict with counts used by the API response and audit log.
    """
    # 1. Relink orders.
    moved_orders = conn.execute(
        "UPDATE orders SET customer_id = ? WHERE customer_id = ?",
        (target_id, source_id),
    ).rowcount

    # 2. Dedupe phones. Load target's existing normalized phones, then copy
    #    source phones that the target does not already have. Source phone
    #    rows are removed by the subsequent DELETE FROM customer_phones.
    target_phone_rows = conn.execute(
        "SELECT phone FROM customer_phones WHERE customer_id = ?",
        (target_id,),
    ).fetchall()
    target_phones = {r["phone"] for r in target_phone_rows}
    target_had_no_phones = len(target_phone_rows) == 0
    # DG-252 r4 [MAJOR] defense-in-depth (mirror of the source fallback
    # below): if the target has zero `customer_phones` rows but a non-empty
    # legacy `customers.phone` (e.g. a pre-v58/v66 customer whose phone was
    # never materialized into a row), materialize that legacy phone as the
    # target's primary `customer_phones` row BEFORE copying source phones.
    # Without this, the step-5 overwrite at the bottom would set
    # `customers.phone` to the first source phone and the target's original
    # legacy phone would be silently dropped — a data-loss bug symmetric to
    # the source-side r3 fix. The legacy column is already normalized at
    # write time.
    if target_had_no_phones:
        target_legacy_row = conn.execute(
            "SELECT phone FROM customers WHERE id = ?", (target_id,)
        ).fetchone()
        target_legacy_phone = (
            target_legacy_row["phone"] if target_legacy_row is not None else ""
        ) or ""
        if target_legacy_phone:
            conn.execute(
                "INSERT INTO customer_phones (customer_id, phone, is_primary) "
                "VALUES (?, ?, ?)",
                (target_id, target_legacy_phone, 1),
            )
            target_phones.add(target_legacy_phone)
            # The target now owns a primary phone row, so the source-copy
            # loop below must NOT promote any of its copied phones to
            # primary (the target's original legacy phone stays primary,
            # mirroring CustomerUpdate semantics where the existing primary
            # is preserved unless explicitly changed).
            target_had_no_phones = False
    source_phone_rows = conn.execute(
        "SELECT phone, is_primary FROM customer_phones WHERE customer_id = ? "
        "ORDER BY is_primary DESC, id ASC",
        (source_id,),
    ).fetchall()
    # DG-252 r3 [MAJOR] defense-in-depth: if the source has no
    # `customer_phones` rows (e.g. customers created before the r3 fix or
    # pre-v58 rows), fall back to the legacy `customers.phone` column so the
    # source's phone is not silently dropped on merge — the next order with
    # that phone would otherwise auto-create a fresh duplicate, undoing the
    # merge. The legacy column is already normalized at write time.
    if not source_phone_rows:
        legacy_row = conn.execute(
            "SELECT phone FROM customers WHERE id = ?", (source_id,)
        ).fetchone()
        legacy_phone = (legacy_row["phone"] or "") if legacy_row else ""
        if legacy_phone:
            source_phone_rows = [{"phone": legacy_phone, "is_primary": 1}]
    added_phones = 0
    first_copied = True
    for r in source_phone_rows:
        nphone = r["phone"]
        if not nphone or nphone in target_phones:
            continue
        # DG-252 r3 [MINOR]: when the target had no phone rows, promote the
        # first copied phone to primary so the merged customer satisfies the
        # "exactly one primary when non-empty" invariant enforced by
        # CustomerCreate/CustomerUpdate everywhere else.
        is_primary = 1 if (target_had_no_phones and first_copied) else 0
        conn.execute(
            "INSERT INTO customer_phones (customer_id, phone, is_primary) "
            "VALUES (?, ?, ?)",
            (target_id, nphone, is_primary),
        )
        target_phones.add(nphone)
        added_phones += 1
        first_copied = False

    # 3. Recompute year summary for every year the target now has orders.
    years = [
        int(r["year"])
        for r in conn.execute(
            "SELECT DISTINCT CAST(strftime('%Y', created_at) AS INTEGER) AS year "
            "FROM orders WHERE customer_id = ? AND created_at IS NOT NULL "
            "  AND created_at != '' ORDER BY year",
            (target_id,),
        ).fetchall()
    ]
    for year in years:
        _recompute_customer_year_summary(conn, target_id, year)

    # Wipe any stale year-summary rows the source still owns (defensive — the
    # source is about to be hard-deleted, but FK CASCADE on
    # customer_year_summary.customer_id handles this once the customer row is
    # gone; we still clear first so a mid-transaction read sees consistent data).
    conn.execute(
        "DELETE FROM customer_year_summary WHERE customer_id = ?", (source_id,)
    )

    # 4. Hard-delete source: phones first (FK CASCADE also covers this, but
    #    explicit DELETE keeps correctness when FK enforcement is off), then
    #    the customer row itself.
    conn.execute("DELETE FROM customer_phones WHERE customer_id = ?", (source_id,))
    conn.execute("DELETE FROM customers WHERE id = ?", (source_id,))

    # 5. Sync the target's denormalized ``customers.phone`` to its current
    #    primary phone so legacy fallback queries stay consistent with the
    #    merged phone set.
    primary_row = conn.execute(
        "SELECT phone FROM customer_phones WHERE customer_id = ? "
        "ORDER BY is_primary DESC, id ASC LIMIT 1",
        (target_id,),
    ).fetchone()
    new_primary = primary_row["phone"] if primary_row is not None else ""
    conn.execute(
        "UPDATE customers SET phone = ?, updated_at = ? WHERE id = ?",
        (new_primary, _now_utc(), target_id),
    )

    return {
        "movedOrders": moved_orders,
        "addedPhones": added_phones,
        "recomputedYears": years,
    }


def _now_utc() -> str:
    from baker.utils.time import now_utc

    return now_utc()


@router.post("/{customer_id}/merge")
def merge_customer(
    customer_id: int,
    body: MergeRequest,
    actor: str = Depends(RequireRole("admin")),
):
    """Gộp khách hàng nguồn vào khách hàng đích (FR5/AC3).

    Admin-only. Relinks source's orders and phones to the target, dedupes
    phones, recomputes the target's ``customer_year_summary``, hard-deletes
    the source, and writes an audit-log entry — all in one SQLite
    transaction (NFR3: any failure rolls back completely).

    Status codes:
      - 200: merge succeeded
      - 400: self-merge (source == target)
      - 403: non-admin caller
      - 404: target or source customer id not found
    """
    target_id = customer_id
    source_id = body.sourceCustomerId

    if source_id == target_id:
        raise HTTPException(status_code=400, detail=CUSTOMER_MERGE_SELF_MSG)

    with get_db() as conn:
        target_row = conn.execute(
            "SELECT * FROM customers WHERE id = ?", (target_id,)
        ).fetchone()
        if not target_row:
            raise HTTPException(
                status_code=404, detail=CUSTOMER_MERGE_NOT_FOUND_MSG
            )
        source_row = conn.execute(
            "SELECT * FROM customers WHERE id = ?", (source_id,)
        ).fetchone()
        if not source_row:
            raise HTTPException(
                status_code=404, detail=CUSTOMER_MERGE_SOURCE_NOT_FOUND_MSG
            )

        # Snapshot for audit-log old_value (pre-merge state of source + target).
        old_value = {
            "target": _row_to_customer_dict(target_row),
            "source": _row_to_customer_dict(source_row),
        }

        result = _merge_customer_into_target(conn, target_id, source_id)

        # Reload target after merge for the new_value snapshot + response.
        merged_row = conn.execute(
            "SELECT * FROM customers WHERE id = ?", (target_id,)
        ).fetchone()
        new_value = {
            "target": _row_to_customer_dict(merged_row),
            "sourceDeletedId": source_id,
            **result,
        }

        record_audit_log(
            conn,
            actor,
            "merge",
            "customer",
            target_id,
            old_value=old_value,
            new_value=new_value,
        )

        loaded = Customer.from_row(merged_row, conn)
        return {
            "ok": True,
            "targetId": target_id,
            "sourceId": source_id,
            "customer": _customer_response(conn, loaded),
            **result,
        }


def _row_to_customer_dict(row) -> dict:
    """Minimal snapshot of a customers row for audit-log JSON serialization."""
    return {
        "id": row["id"],
        "name": row["name"],
        "phone": row["phone"] or "",
    }


def _duplicate_customer_row(
    conn,
    customer_id: int,
    name: str,
    phone: str,
    order_counts: dict[int, int] | None = None,
) -> dict:
    """Build one customer entry for a duplicates-group payload (FR6).

    Includes the per-customer order count used by the finder UI's
    confirmation dialog. When [order_counts] is supplied (Mn-6: a single
    grouped ``SELECT customer_id, COUNT(*) FROM orders GROUP BY
    customer_id`` result), the count is read from the dict instead of
    issuing a per-row COUNT query. This eliminates the previous N+1
    pattern where every ``customer_phones`` row and every customer with a
    non-empty ``search_name`` issued its own ``COUNT(*)`` query.
    """
    if order_counts is not None:
        order_count = order_counts.get(customer_id, 0)
    else:
        order_count = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (customer_id,)
        ).fetchone()[0]
    return {
        "id": customer_id,
        "name": name,
        "phone": phone or "",
        "orderCount": int(order_count),
    }


def _load_order_counts_by_customer(conn) -> dict[int, int]:
    """Single grouped query returning ``{customer_id: order_count}`` (Mn-6).

    Replaces the previous N+1 pattern of issuing one ``COUNT(*)`` per
    customer row in ``/duplicates``. Returns a dict keyed by customer id
    so the per-row helper can look up counts in O(1).
    """
    rows = conn.execute(
        "SELECT customer_id, COUNT(*) AS n FROM orders GROUP BY customer_id"
    ).fetchall()
    return {r["customer_id"]: int(r["n"]) for r in rows}