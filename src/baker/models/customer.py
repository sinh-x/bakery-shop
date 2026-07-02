from dataclasses import dataclass, field
from typing import Optional

from baker.utils.time import now_utc


@dataclass
class Customer:
    name: str
    phone: str = ""
    id: Optional[int] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    phones: list[dict] = field(default_factory=list)

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO customers (name, phone, created_at, updated_at) "
            "VALUES (?, ?, ?, ?)",
            (self.name, self.phone, now_utc(), now_utc()),
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
            "UPDATE customers SET name = ?, phone = ?, updated_at = ? WHERE id = ?",
            (self.name, self.phone, now_utc(), self.id),
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
        return {
            "id": self.id,
            "name": self.name,
            "phone": self.phone,
            "phones": self.phones,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }


def _load_customer_phones(conn, customer_id: int) -> list[dict]:
    try:
        rows = conn.execute(
            "SELECT phone, is_primary FROM customer_phones "
            "WHERE customer_id = ? ORDER BY is_primary DESC, id ASC",
            (customer_id,),
        ).fetchall()
    except Exception:
        return []
    return [
        {"phone": r["phone"], "isPrimary": bool(r["is_primary"])}
        for r in rows
    ]


def _primary_phone(phones: list[dict]) -> str:
    for p in phones:
        if p.get("isPrimary"):
            return p.get("phone", "")
    return phones[0].get("phone", "") if phones else ""


def _sync_customer_phones(conn, customer_id: int, phones: list[dict]) -> None:
    # Guard: customer_phones table may not exist yet during pre-v58 migrations.
    try:
        conn.execute("SELECT 1 FROM customer_phones LIMIT 1").fetchone()
    except Exception:
        return
    conn.execute(
        "DELETE FROM customer_phones WHERE customer_id = ?", (customer_id,)
    )
    for p in phones:
        conn.execute(
            "INSERT INTO customer_phones (customer_id, phone, is_primary) "
            "VALUES (?, ?, ?)",
            (
                customer_id,
                p.get("phone", ""),
                1 if p.get("isPrimary") else 0,
            ),
        )