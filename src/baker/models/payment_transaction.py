from dataclasses import dataclass
from enum import Enum
from functools import lru_cache
from typing import Optional

from baker.db.schema import PAYMENT_OUTFLOW_TYPES
from baker.utils.time import now_utc


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

# Schema migration version that introduced the ``invalidated_at`` column on
# ``payment_transactions`` (DG-196 Phase 1). Used by ``_invalidation_filter``
# to avoid running ``PRAGMA table_info`` on every query.
_INVALIDATION_MIGRATION_VERSION = 53


@lru_cache(maxsize=1)
def _schema_version(conn) -> int:
    """Return the current ``schema_version`` max, or 0 if the table is absent.

    Cached per-process because migrations are applied once at startup; the
    schema does not change mid-process. The connection is not held by the
    cache — only the resolved integer version is retained.
    """
    cursor = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
    )
    if not cursor.fetchone():
        return 0
    row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
    return int(row[0]) if row and row[0] is not None else 0


def _invalidation_filter(conn) -> str:
    """Return the SQL fragment excluding invalidated rows, or '' if the
    ``invalidated_at`` column is not present yet.

    The ``total_*`` methods are invoked both after the full schema is applied
    (normal runtime, where v53 has added the column) and during earlier
    migrations (v44/v49/v51 backfills call ``total_paid_net`` before v53 has
    run). Querying ``invalidated_at`` before the column exists raises
    ``sqlite3.OperationalError``, so the filter is omitted when the column is
    absent — at that point no transactions can be invalidated anyway.

    The schema version is resolved once per process via :func:`_schema_version`
    (cached) to avoid running ``PRAGMA table_info`` on every query
    (review finding CQ-6). When the cached version is below the invalidation
    migration, the empty filter is returned without any extra query.
    """
    if _schema_version(conn) >= _INVALIDATION_MIGRATION_VERSION:
        return "AND invalidated_at IS NULL"
    return ""


@dataclass
class PaymentTransaction:
    order_id: int
    amount: float
    type: str = "deposit"
    method: str = "cash"
    note: str = ""
    payment_source: str = ""
    id: Optional[int] = None
    created_at: Optional[str] = None
    invalidated_at: Optional[str] = None
    invalidated_by: str = ""

    def save(self, conn) -> int:
        if self.type not in [t.value for t in TransactionType]:
            raise ValueError(f"Invalid transaction type: {self.type}")
        if self.method not in [m.value for m in PaymentMethod]:
            raise ValueError(f"Invalid payment method: {self.method}")
        cursor = conn.execute(
            """INSERT INTO payment_transactions (order_id, amount, type, method, note, payment_source, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (self.order_id, self.amount, self.type, self.method, self.note,
             self.payment_source or "", now_utc()),
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
            payment_source=row["payment_source"] if "payment_source" in row.keys() else "",
            created_at=row["created_at"],
            invalidated_at=row["invalidated_at"] if "invalidated_at" in row.keys() else None,
            invalidated_by=row["invalidated_by"] if "invalidated_by" in row.keys() else "",
        )

    def to_api_dict(self) -> dict:
        return {
            "id": str(self.id),
            "orderId": str(self.order_id),
            "amount": self.amount,
            "type": self.type,
            "method": self.method,
            "note": self.note,
            "paymentSource": self.payment_source or "",
            "createdAt": self.created_at,
            "invalidatedAt": self.invalidated_at,
            "invalidatedBy": self.invalidated_by,
        }

    @staticmethod
    def total_for_order(conn, order_id: int) -> float:
        """Sum of all transaction amounts for an order (all types).

        Excludes invalidated (soft-deleted) transactions — invalidated rows
        must not contribute to any payment total.
        """
        row = conn.execute(
            "SELECT COALESCE(SUM(amount), 0) as total FROM payment_transactions "
            f"WHERE order_id = ? {_invalidation_filter(conn)}",
            (order_id,),
        ).fetchone()
        return float(row[0]) if row else 0.0

    @staticmethod
    def total_paid_excl_outflows(conn, order_id: int) -> float:
        """Sum of payment transactions EXCLUDING all outflow (cash-back) types.

        Outflow types (``refund``) are cash returned to the customer, not
        customer payments toward the order. Excluding them ensures receipt
        balance math and completion guards are correct.

        ``tien_rut`` is NOT an outflow (DG-198 reversal): it is a deposit
        inflow — the customer gives cash to the shop for safekeeping — so it
        IS included in this total. It journals to 2400 (Tien Rut Held), not
        2100, and is returned to the customer at delivery via a separate
        journal entry.

        Invalidated (soft-deleted) transactions are also excluded so the total
        reflects only valid payments.

        Note: for revenue recognition use :meth:`total_paid_net` instead, which
        subtracts outflows so the 2100 (Customer Deposits) debit matches the
        actual deposit balance being converted to revenue.
        """
        placeholders = ",".join("?" * len(_OUTFLOW_TYPES))
        row = conn.execute(
            f"SELECT COALESCE(SUM(amount), 0) as total FROM payment_transactions "
            f"WHERE order_id = ? AND type NOT IN ({placeholders}) "
            f"{_invalidation_filter(conn)}",
            (order_id, *_OUTFLOW_TYPES),
        ).fetchone()
        return float(row[0]) if row else 0.0

    @staticmethod
    def total_outflows(conn, order_id: int) -> float:
        """Sum of all outflow (cash-back) transactions for an order.

        Includes every type in :data:`baker.db.schema.PAYMENT_OUTFLOW_TYPES`
        (``refund`` only — ``tien_rut`` is a deposit inflow, not an outflow,
        per the DG-198 reversal). Outflow amounts are stored as positive
        values; revenue recognition subtracts them via :meth:`total_paid_net`.

        Invalidated (soft-deleted) transactions are excluded.
        """
        placeholders = ",".join("?" * len(_OUTFLOW_TYPES))
        row = conn.execute(
            f"SELECT COALESCE(SUM(amount), 0) as total FROM payment_transactions "
            f"WHERE order_id = ? AND type IN ({placeholders}) "
            f"{_invalidation_filter(conn)}",
            (order_id, *_OUTFLOW_TYPES),
        ).fetchone()
        return float(row[0]) if row else 0.0

    @staticmethod
    def total_tien_rut(conn, order_id: int) -> float:
        """Sum of all ``tien_rut`` transactions for an order.

        ``tien_rut`` is a deposit inflow (DG-198 reversal): the customer gives
        cash to the shop for safekeeping. It journals to 2400 (Tien Rut Held)
        and is returned at delivery via a separate journal entry. Revenue
        recognition must EXCLUDE tien_rut from the deposit balance (deposits
        go to 2100/4100; tien_rut goes to 2400 and is returned separately),
        so callers subtract this from :meth:`total_paid_excl_outflows`.

        Invalidated (soft-deleted) transactions are excluded.
        """
        row = conn.execute(
            f"SELECT COALESCE(SUM(amount), 0) as total FROM payment_transactions "
            f"WHERE order_id = ? AND type = 'tien_rut' "
            f"{_invalidation_filter(conn)}",
            (order_id,),
        ).fetchone()
        return float(row[0]) if row else 0.0

    @staticmethod
    def total_paid_net(conn, order_id: int) -> float:
        """Net deposits for an order: payments (excl refund outflows) minus refunds.

        Revenue recognition should use this value so the 2100 (Customer Deposits)
        debit matches the actual deposit balance being converted to revenue.
        ``net = total_paid_excl_outflows - total_outflows``. When net <= 0 there
        is no deposit balance to convert and no revenue entry should be created.

        NOTE (DG-198 reversal): ``tien_rut`` is now a deposit inflow, so it IS
        included in ``total_paid_excl_outflows`` and therefore in this net. The
        revenue entry's deposit balance must EXCLUDE tien_rut (it journals to
        2400 and is returned separately) — callers that need the deposits-only
        balance should subtract :meth:`total_tien_rut` from this value.

        Both inputs exclude invalidated transactions, so the net is computed
        only from valid rows.
        """
        excl = PaymentTransaction.total_paid_excl_outflows(conn, order_id)
        rut = PaymentTransaction.total_outflows(conn, order_id)
        return excl - rut
