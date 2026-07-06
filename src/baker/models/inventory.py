from dataclasses import dataclass
from typing import Optional

from baker.models.event import Event
from baker.utils.time import now_utc


@dataclass
class InventoryItem:
    name: str
    category: str = "ingredient"
    quantity: float = 0.0
    unit: str = "kg"
    low_threshold: float = 0.0
    cost_per_unit: float = 0.0
    supplier: str = ""
    id: Optional[int] = None
    updated_at: Optional[str] = None

    @property
    def is_low(self) -> bool:
        return self.low_threshold > 0 and self.quantity <= self.low_threshold

    def save(self, conn) -> int:
        cursor = conn.execute(
            """INSERT INTO inventory (name, category, quantity, unit, low_threshold,
               cost_per_unit, supplier, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (self.name, self.category, self.quantity, self.unit,
             self.low_threshold, self.cost_per_unit, self.supplier, now_utc()),
        )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def receive(conn, name: str, amount: float, note: str = "", cost: float = None):
        row = conn.execute("SELECT * FROM inventory WHERE name = ?", (name,)).fetchone()
        if not row:
            raise ValueError(f"Item '{name}' not found in inventory. Add it first with: baker inv add {name}")

        new_qty = row["quantity"] + amount
        params: list = [new_qty, now_utc()]
        sql = "UPDATE inventory SET quantity = ?, updated_at = ?"
        if cost is not None:
            sql += ", cost_per_unit = ?"
            params.append(cost)
        params.append(row["id"])
        sql += " WHERE id = ?"
        conn.execute(sql, params)

        data = {"item": name, "amount": amount, "new_qty": new_qty, "unit": row["unit"]}
        if note:
            data["note"] = note
        Event(summary=f"Received {amount} {row['unit']} {name}", type="inventory", data=data).save(conn)
        return new_qty

    @staticmethod
    def use(conn, name: str, amount: float, purpose: str = ""):
        row = conn.execute("SELECT * FROM inventory WHERE name = ?", (name,)).fetchone()
        if not row:
            raise ValueError(f"Item '{name}' not found in inventory.")

        new_qty = row["quantity"] - amount
        conn.execute(
            "UPDATE inventory SET quantity = ?, updated_at = ? WHERE id = ?",
            (new_qty, now_utc(), row["id"]),
        )

        data = {"item": name, "amount": -amount, "new_qty": new_qty, "unit": row["unit"]}
        if purpose:
            data["for"] = purpose
        Event(summary=f"Used {amount} {row['unit']} {name}", type="inventory", data=data).save(conn)
        return new_qty

    @staticmethod
    def set_quantity(conn, name: str, quantity: float, reason: str = ""):
        row = conn.execute("SELECT * FROM inventory WHERE name = ?", (name,)).fetchone()
        if not row:
            raise ValueError(f"Item '{name}' not found in inventory.")

        old_qty = row["quantity"]
        conn.execute(
            "UPDATE inventory SET quantity = ?, updated_at = ? WHERE id = ?",
            (quantity, now_utc(), row["id"]),
        )

        data = {"item": name, "old_qty": old_qty, "new_qty": quantity, "unit": row["unit"]}
        if reason:
            data["reason"] = reason
        Event(summary=f"Adjusted {name}: {old_qty} -> {quantity} {row['unit']}", type="inventory", data=data).save(conn)
        return quantity

    @staticmethod
    def from_row(row) -> "InventoryItem":
        return InventoryItem(
            id=row["id"], name=row["name"], category=row["category"],
            quantity=row["quantity"], unit=row["unit"],
            low_threshold=row["low_threshold"], cost_per_unit=row["cost_per_unit"],
            supplier=row["supplier"], updated_at=row["updated_at"],
        )
