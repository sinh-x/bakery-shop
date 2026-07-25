"""Blank models — phôi bánh (bán thành phẩm) foundation.

Provides dataclasses for the four blanks-related tables created by
migration v81 (see ``src/baker/db/schema.py``):

* ``blanks``            — definition of a blank (name, category, unit, notes)
* ``product_blank_bom`` — BOM mapping price_chip/product → blank + quantity
* ``blank_stock``       — current stock level per blank (production lots)
* ``blank_stock_log``   — audit trail for every stock change

The dataclasses follow the ``WorkItem`` pattern (``from_row()`` +
``to_api_dict()`` with camelCase API keys) so the response convention is
consistent with the rest of the codebase (NFR3).
"""

from dataclasses import dataclass
from typing import Optional

from baker.utils.time import now_utc


@dataclass
class Blank:
    """A phôi (semi-finished good) that must be prepared before assembly.

    Category is free-form text used to group blanks (e.g. "cot", "kem",
    "nhan"). The schema is intentionally category-agnostic — it is not
    hardcoded for any specific product line.
    """

    name: str
    category: str = ""
    unit: str = ""
    notes: str = ""
    id: Optional[int] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            """INSERT INTO blanks (name, category, unit, notes, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (self.name, self.category, self.unit, self.notes, now_utc(), now_utc()),
        )
        self.id = cursor.lastrowid
        return self.id

    def update(self, conn) -> bool:
        if self.id is None:
            return False
        conn.execute(
            """UPDATE blanks
               SET name = ?, category = ?, unit = ?, notes = ?, updated_at = ?
               WHERE id = ?""",
            (self.name, self.category, self.unit, self.notes, now_utc(), self.id),
        )
        return True

    @staticmethod
    def from_row(row) -> "Blank":
        return Blank(
            id=row["id"],
            name=row["name"],
            category=row["category"] or "",
            unit=row["unit"] or "",
            notes=row["notes"] or "",
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    def to_api_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "category": self.category,
            "unit": self.unit,
            "notes": self.notes,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }


@dataclass
class ProductBlankBom:
    """BOM mapping row: a price_chip (or product) → blank + quantity."""

    blank_id: int
    quantity: float = 1.0
    product_id: Optional[int] = None
    price_chip_id: Optional[int] = None
    id: Optional[int] = None
    created_at: Optional[str] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            """INSERT INTO product_blank_bom
               (product_id, price_chip_id, blank_id, quantity, created_at)
               VALUES (?, ?, ?, ?, ?)""",
            (self.product_id, self.price_chip_id, self.blank_id, self.quantity, now_utc()),
        )
        self.id = cursor.lastrowid
        return self.id

    def update(self, conn) -> bool:
        if self.id is None:
            return False
        conn.execute(
            "UPDATE product_blank_bom SET quantity = ? WHERE id = ?",
            (self.quantity, self.id),
        )
        return True

    @staticmethod
    def from_row(row) -> "ProductBlankBom":
        return ProductBlankBom(
            id=row["id"],
            product_id=row["product_id"],
            price_chip_id=row["price_chip_id"],
            blank_id=row["blank_id"],
            quantity=row["quantity"],
            created_at=row["created_at"],
        )

    def to_api_dict(self) -> dict:
        return {
            "id": self.id,
            "productId": self.product_id,
            "priceChipId": self.price_chip_id,
            "blankId": self.blank_id,
            "quantity": self.quantity,
            "createdAt": self.created_at,
        }


@dataclass
class BlankStock:
    """A production/usage lot row tracking blank inventory.

    ``type`` is either ``"production"`` (adds stock) or ``"usage"``
    (subtracts stock). For production lots ``produced_date`` and
    ``expiry_date`` record the production batch freshness.
    """

    blank_id: int
    quantity: float = 0.0
    produced_date: str = ""
    expiry_date: Optional[str] = None
    type: str = "production"
    id: Optional[int] = None
    created_at: Optional[str] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            """INSERT INTO blank_stock
               (blank_id, quantity, produced_date, expiry_date, type, created_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (
                self.blank_id,
                self.quantity,
                self.produced_date,
                self.expiry_date,
                self.type,
                now_utc(),
            ),
        )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def from_row(row) -> "BlankStock":
        return BlankStock(
            id=row["id"],
            blank_id=row["blank_id"],
            quantity=row["quantity"],
            produced_date=row["produced_date"] or "",
            expiry_date=row["expiry_date"],
            type=row["type"],
            created_at=row["created_at"],
        )

    def to_api_dict(self) -> dict:
        return {
            "id": self.id,
            "blankId": self.blank_id,
            "quantity": self.quantity,
            "producedDate": self.produced_date,
            "expiryDate": self.expiry_date,
            "type": self.type,
            "createdAt": self.created_at,
        }


@dataclass
class BlankStockLog:
    """Audit-log entry for every blank stock change (FR5)."""

    blank_id: int
    quantity_change: float
    type: str
    produced_date: Optional[str] = None
    expiry_date: Optional[str] = None
    id: Optional[int] = None
    created_at: Optional[str] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            """INSERT INTO blank_stock_log
               (blank_id, quantity_change, type, produced_date, expiry_date, created_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (
                self.blank_id,
                self.quantity_change,
                self.type,
                self.produced_date,
                self.expiry_date,
                now_utc(),
            ),
        )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def from_row(row) -> "BlankStockLog":
        return BlankStockLog(
            id=row["id"],
            blank_id=row["blank_id"],
            quantity_change=row["quantity_change"],
            type=row["type"],
            produced_date=row["produced_date"],
            expiry_date=row["expiry_date"],
            created_at=row["created_at"],
        )

    def to_api_dict(self) -> dict:
        return {
            "id": self.id,
            "blankId": self.blank_id,
            "quantityChange": self.quantity_change,
            "type": self.type,
            "producedDate": self.produced_date,
            "expiryDate": self.expiry_date,
            "createdAt": self.created_at,
        }
