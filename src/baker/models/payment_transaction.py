from dataclasses import dataclass
from enum import Enum
from typing import Optional


class TransactionType(str, Enum):
    DEPOSIT = "deposit"
    PAYMENT = "payment"
    FULL_PAYMENT = "full_payment"
    REFUND = "refund"
    RUT_TIEN = "rut_tien"


class PaymentMethod(str, Enum):
    CASH = "cash"
    TRANSFER = "transfer"
    CARD = "card"


@dataclass
class PaymentTransaction:
    order_id: int
    amount: float
    type: str = "deposit"
    method: str = "cash"
    note: str = ""
    id: Optional[int] = None
    created_at: Optional[str] = None

    def save(self, conn) -> int:
        if self.type not in [t.value for t in TransactionType]:
            raise ValueError(f"Invalid transaction type: {self.type}")
        if self.method not in [m.value for m in PaymentMethod]:
            raise ValueError(f"Invalid payment method: {self.method}")
        cursor = conn.execute(
            """INSERT INTO payment_transactions (order_id, amount, type, method, note)
               VALUES (?, ?, ?, ?, ?)""",
            (self.order_id, self.amount, self.type, self.method, self.note),
        )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def from_row(row) -> "PaymentTransaction":
        return PaymentTransaction(
            id=row["id"],
            order_id=row["order_id"],
            amount=row["amount"],
            type=row["type"],
            method=row["method"],
            note=row["note"] or "",
            created_at=row["created_at"],
        )

    def to_api_dict(self) -> dict:
        return {
            "id": str(self.id),
            "orderId": str(self.order_id),
            "amount": self.amount,
            "type": self.type,
            "method": self.method,
            "note": self.note,
            "createdAt": self.created_at,
        }

    @staticmethod
    def total_for_order(conn, order_id: int) -> float:
        """Sum of all transaction amounts for an order (all types)."""
        row = conn.execute(
            "SELECT COALESCE(SUM(amount), 0) as total FROM payment_transactions WHERE order_id = ?",
            (order_id,),
        ).fetchone()
        return float(row[0]) if row else 0.0

    @staticmethod
    def total_paid_excl_rut_tien(conn, order_id: int) -> float:
        """Sum of payment transactions EXCLUDING rut_tien cash-back transactions.

        rut_tien is a cash-back to the customer, not a customer payment toward the order.
        Excluding it ensures receipt balance math and completion guards are correct.
        """
        row = conn.execute(
            "SELECT COALESCE(SUM(amount), 0) as total FROM payment_transactions WHERE order_id = ? AND type != 'rut_tien'",
            (order_id,),
        ).fetchone()
        return float(row[0]) if row else 0.0
