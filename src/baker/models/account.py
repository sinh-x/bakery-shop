from dataclasses import dataclass
from typing import Optional


@dataclass
class Account:
    code: str
    name: str
    type: str
    parent_id: Optional[int] = None
    is_active: int = 1
    id: Optional[int] = None
    created_at: Optional[str] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO accounts (code, name, type, parent_id, is_active) "
            "VALUES (?, ?, ?, ?, ?)",
            (self.code, self.name, self.type, self.parent_id, self.is_active),
        )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def from_row(row) -> "Account":
        return Account(
            id=row["id"],
            code=row["code"],
            name=row["name"],
            type=row["type"],
            parent_id=row["parent_id"],
            is_active=row["is_active"],
            created_at=row["created_at"],
        )

    def to_api_dict(self) -> dict:
        return {
            "id": str(self.id),
            "code": self.code,
            "name": self.name,
            "type": self.type,
            "parentId": str(self.parent_id) if self.parent_id is not None else None,
            "isActive": bool(self.is_active),
            "createdAt": self.created_at,
        }

    @staticmethod
    def get_by_code(conn, code: str) -> Optional["Account"]:
        row = conn.execute(
            "SELECT * FROM accounts WHERE code = ?", (code,)
        ).fetchone()
        return Account.from_row(row) if row else None

    @staticmethod
    def get_by_id(conn, account_id: int) -> Optional["Account"]:
        row = conn.execute(
            "SELECT * FROM accounts WHERE id = ?", (account_id,)
        ).fetchone()
        return Account.from_row(row) if row else None

    @staticmethod
    def list_all(conn) -> list["Account"]:
        rows = conn.execute(
            "SELECT * FROM accounts ORDER BY code"
        ).fetchall()
        return [Account.from_row(r) for r in rows]

    @staticmethod
    def list_active(conn) -> list["Account"]:
        rows = conn.execute(
            "SELECT * FROM accounts WHERE is_active = 1 ORDER BY code"
        ).fetchall()
        return [Account.from_row(r) for r in rows]

    @staticmethod
    def get_sub_accounts(conn, parent_id: int) -> list["Account"]:
        rows = conn.execute(
            "SELECT * FROM accounts WHERE parent_id = ? ORDER BY code",
            (parent_id,),
        ).fetchall()
        return [Account.from_row(r) for r in rows]