from dataclasses import dataclass
from enum import Enum
from typing import Optional

from baker.db.schema import PAYMENT_OUTFLOW_TYPES


class TransactionType(str, Enum):
    DEPOSIT = "deposit"
    PAYMENT = "payment"
    FULL_PAYMENT = "full_payment"
    REFUND = "refund"
    TIEN_RUT = "tien_rut"


class PaymentMethod(str, Enum):
    CASH = "cash"
    TRANSFER = "transfer"
    CARD = "card"


# Outflow transaction types as a tuple (deterministic order for SQL IN
# parameterization). Mirrors baker.db.schema.PAYMENT_OUTFLOW_TYPES — kept as a
# module-level tuple so the SQL placeholder count is stable per process.
_OUTFLOW_TYPES = tuple(PAYMENT_OUTFLOW_TYPES)


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
    def total_paid_excl_tien_rut(conn, order_id: int) -> float:
        """Sum of payment transactions EXCLUDING all outflow (cash-back) types.

        Outflow types (``refund``, ``tien_rut``) are cash returned to the
        customer, not customer payments toward the order. Excluding them
        ensures receipt balance math and completion guards are correct.

        Note: for revenue recognition use :meth:`total_paid_net` instead, which
        subtracts outflows so the 2100 (Customer Deposits) debit matches the
        actual deposit balance being converted to revenue.
        """
        placeholders = ",".join("?" * len(_OUTFLOW_TYPES))
        row = conn.execute(
            f"SELECT COALESCE(SUM(amount), 0) as total FROM payment_transactions WHERE order_id = ? AND type NOT IN ({placeholders})",
            (order_id, *_OUTFLOW_TYPES),
        ).fetchone()
        return float(row[0]) if row else 0.0

    @staticmethod
    def total_tien_rut(conn, order_id: int) -> float:
        """Sum of all outflow (cash-back) transactions for an order.

        Includes every type in :data:`baker.db.schema.PAYMENT_OUTFLOW_TYPES`
        (``refund`` and ``tien_rut``). Outflow amounts are stored as positive
        values; revenue recognition subtracts them via :meth:`total_paid_net`.
        """
        placeholders = ",".join("?" * len(_OUTFLOW_TYPES))
        row = conn.execute(
            f"SELECT COALESCE(SUM(amount), 0) as total FROM payment_transactions "
            f"WHERE order_id = ? AND type IN ({placeholders})",
            (order_id, *_OUTFLOW_TYPES),
        ).fetchone()
        return float(row[0]) if row else 0.0

    @staticmethod
    def total_paid_net(conn, order_id: int) -> float:
        """Net deposits for an order: payments (excl outflows) minus outflows.

        Revenue recognition should use this value so the 2100 (Customer Deposits)
        debit matches the actual deposit balance being converted to revenue.
        ``net = total_paid_excl_tien_rut - total_tien_rut``. When net <= 0 there
        is no deposit balance to convert and no revenue entry should be created.
        """
        excl = PaymentTransaction.total_paid_excl_tien_rut(conn, order_id)
        rut = PaymentTransaction.total_tien_rut(conn, order_id)
        return excl - rut
