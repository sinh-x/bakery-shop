from dataclasses import dataclass, field
from typing import Optional

import sqlite3

from baker.db.schema import _normalize_phone, _strip_diacritics
from baker.utils.time import now_utc


@dataclass
class Customer:
    name: str
    phone: str = ""
    id: Optional[int] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    phones: list[dict] = field(default_factory=list)
    # DG-206 FR7: per-year order count + total volume for the current year.
    # Populated by GET /api/customers/:id (or other callers with a conn) via
    # ``load_year_summary``; left as None when not requested.
    year_summary: Optional[dict] = None

    def save(self, conn) -> int:
        # M-1: store the normalized phone in the legacy `customers.phone`
        # column so the fallback query in _resolve_customer_id_by_phone can
        # match it directly against the normalized search value.
        cursor = conn.execute(
            "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (self.name, _normalize_phone(self.phone), _strip_diacritics(self.name), now_utc(), now_utc()),
        )
        self.id = cursor.lastrowid
        _sync_customer_phones(conn, self.id, self.phones)
        return self.id

    def update(
        self,
        conn,
        name: Optional[str] = None,
        phone: Optional[str] = None,
        phones: Optional[list[dict]] = None,
    ) -> None:
        if name is not None:
            self.name = name
        if phone is not None:
            self.phone = phone
        if phones is not None:
            self.phones = phones
            self.phone = _primary_phone(phones) or self.phone
        conn.execute(
            "UPDATE customers SET name = ?, phone = ?, search_name = ?, updated_at = ? WHERE id = ?",
            (self.name, _normalize_phone(self.phone), _strip_diacritics(self.name), now_utc(), self.id),
        )
        if phones is not None:
            _sync_customer_phones(conn, self.id, phones)

    @staticmethod
    def from_row(row, conn=None) -> "Customer":
        customer = Customer(
            id=row["id"],
            name=row["name"],
            phone=row["phone"] or "",
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
        if conn is not None:
            customer.phones = _load_customer_phones(conn, customer.id)
        return customer

    def to_api_dict(self) -> dict:
        result = {
            "id": self.id,
            "name": self.name,
            "phone": self.phone,
            "phones": self.phones,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }
        if self.year_summary is not None:
            result["yearSummary"] = self.year_summary
        return result


def _load_customer_phones(conn, customer_id: int) -> list[dict]:
    try:
        rows = conn.execute(
            "SELECT phone, is_primary FROM customer_phones "
            "WHERE customer_id = ? ORDER BY is_primary DESC, id ASC",
            (customer_id,),
        ).fetchall()
    except sqlite3.OperationalError:
        return []
    return [
        {"phone": r["phone"], "isPrimary": bool(r["is_primary"])}
        for r in rows
    ]


def load_year_summary(conn, customer_id: int, year: int) -> dict:
    """Load the (customer_id, year) row from ``customer_year_summary``.

    DG-206 FR7. Returns ``{"year": <year>, "orderCount": N, "totalVolume": X}``
    with zeros when no row exists yet (e.g. a fresh customer with no orders).
    """
    try:
        row = conn.execute(
            "SELECT order_count, total_volume FROM customer_year_summary "
            "WHERE customer_id = ? AND year = ?",
            (customer_id, int(year)),
        ).fetchone()
    except sqlite3.OperationalError:
        row = None
    if row is None:
        return {"year": int(year), "orderCount": 0, "totalVolume": 0.0}
    return {
        "year": int(year),
        "orderCount": int(row["order_count"] or 0),
        "totalVolume": float(row["total_volume"] or 0),
    }


def _load_customer_phones_for_many(conn, customer_ids: list[int]) -> dict[int, list[dict]]:
    """Batch-load phones for multiple customers in a single query (avoids N+1).

    Returns a mapping customer_id -> list of phone dicts (ordered is_primary DESC, id ASC).
    Customers without phones map to [].
    """
    result: dict[int, list[dict]] = {cid: [] for cid in customer_ids}
    if not customer_ids:
        return result
    try:
        placeholders = ",".join("?" for _ in customer_ids)
        rows = conn.execute(
            f"SELECT customer_id, phone, is_primary FROM customer_phones "
            f"WHERE customer_id IN ({placeholders}) "
            f"ORDER BY is_primary DESC, id ASC",
            tuple(customer_ids),
        ).fetchall()
    except sqlite3.OperationalError:
        return result
    for r in rows:
        cid = r["customer_id"]
        result.setdefault(cid, []).append(
            {"phone": r["phone"], "isPrimary": bool(r["is_primary"])}
        )
    return result


def _primary_phone(phones: list[dict]) -> str:
    for p in phones:
        if p.get("isPrimary"):
            return p.get("phone", "")
    return phones[0].get("phone", "") if phones else ""


def _sync_customer_phones(conn, customer_id: int, phones: list[dict]) -> None:
    # Guard: customer_phones table may not exist yet during pre-v58 migrations.
    try:
        conn.execute("SELECT 1 FROM customer_phones LIMIT 1").fetchone()
    except sqlite3.OperationalError:
        return
    conn.execute(
        "DELETE FROM customer_phones WHERE customer_id = ?", (customer_id,)
    )
    for p in phones:
        # M-1: store the normalized phone so order-customer matching (which
        # normalizes the search value) can find it regardless of separators.
        conn.execute(
            "INSERT INTO customer_phones (customer_id, phone, is_primary) "
            "VALUES (?, ?, ?)",
            (
                customer_id,
                _normalize_phone(p.get("phone", "")),
                1 if p.get("isPrimary") else 0,
            ),
        )