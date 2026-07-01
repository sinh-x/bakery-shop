from dataclasses import dataclass
from typing import Optional

from baker.utils.time import now_utc


@dataclass
class Customer:
    name: str
    phone: str = ""
    id: Optional[int] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO customers (name, phone, created_at, updated_at) "
            "VALUES (?, ?, ?, ?)",
            (self.name, self.phone, now_utc(), now_utc()),
        )
        self.id = cursor.lastrowid
        return self.id

    def update(self, conn, name: Optional[str] = None, phone: Optional[str] = None) -> None:
        if name is not None:
            self.name = name
        if phone is not None:
            self.phone = phone
        conn.execute(
            "UPDATE customers SET name = ?, phone = ?, updated_at = ? WHERE id = ?",
            (self.name, self.phone, now_utc(), self.id),
        )

    @staticmethod
    def from_row(row) -> "Customer":
        return Customer(
            id=row["id"],
            name=row["name"],
            phone=row["phone"] or "",
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    def to_api_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "phone": self.phone,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }