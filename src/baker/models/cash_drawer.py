"""Cash drawer model (DG-324 Phase 2).

A :class:`CashDrawer` records one daily cash drawer session. Balance-affecting
fields are stored as INTEGER (VND) per NFR1 so drawer balance computation is
accurate to within 1 VND. The expected balance is derived (FR4) rather than
stored to avoid drift; only the counted amount and discrepancy are persisted
at close time (FR7).

Traceability: FR1, FR4, FR7, FR8, FR10, NFR1.
"""

from dataclasses import dataclass
from typing import Optional

from baker.utils.time import now_utc


@dataclass
class CashDrawer:
    opened_at: str
    opening_balance: int = 0
    cash_sales: int = 0
    owner_in: int = 0
    owner_out: int = 0
    cash_expenses: int = 0
    status: str = "open"
    closed_at: Optional[str] = None
    counted_amount: Optional[int] = None
    discrepancy: Optional[int] = None
    id: Optional[int] = None

    def expected_balance(self) -> int:
        """FR4: opening + cash_sales + owner_in - owner_out - cash_expenses."""
        return (
            self.opening_balance
            + self.cash_sales
            + self.owner_in
            - self.owner_out
            - self.cash_expenses
        )

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO cash_drawer "
            "(opened_at, opening_balance, status) VALUES (?, ?, 'open')",
            (self.opened_at, int(self.opening_balance)),
        )
        self.id = cursor.lastrowid
        self.status = "open"
        return self.id

    @staticmethod
    def from_row(row) -> "CashDrawer":
        return CashDrawer(
            id=row["id"],
            opened_at=row["opened_at"],
            closed_at=row["closed_at"],
            status=row["status"],
            opening_balance=int(row["opening_balance"]),
            cash_sales=int(row["cash_sales"]),
            owner_in=int(row["owner_in"]),
            owner_out=int(row["owner_out"]),
            cash_expenses=int(row["cash_expenses"]),
            counted_amount=int(row["counted_amount"]) if row["counted_amount"] is not None else None,
            discrepancy=int(row["discrepancy"]) if row["discrepancy"] is not None else None,
        )

    def to_api_dict(self) -> dict:
        return {
            "id": str(self.id),
            "openedAt": self.opened_at,
            "closedAt": self.closed_at,
            "status": self.status,
            "openingBalance": self.opening_balance,
            "cashSales": self.cash_sales,
            "ownerIn": self.owner_in,
            "ownerOut": self.owner_out,
            "cashExpenses": self.cash_expenses,
            "countedAmount": self.counted_amount,
            "discrepancy": self.discrepancy,
            "expectedBalance": self.expected_balance(),
        }

    @staticmethod
    def get_active(conn) -> "CashDrawer | None":
        row = conn.execute(
            "SELECT * FROM cash_drawer WHERE status = 'open' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        return CashDrawer.from_row(row) if row else None

    @staticmethod
    def get_by_id(conn, drawer_id: int) -> "CashDrawer | None":
        row = conn.execute(
            "SELECT * FROM cash_drawer WHERE id = ?", (drawer_id,)
        ).fetchone()
        return CashDrawer.from_row(row) if row else None

    @staticmethod
    def list_history(
        conn,
        *,
        since: Optional[str] = None,
        until: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[list["CashDrawer"], int]:
        conditions = []
        params = []
        if since is not None:
            conditions.append("opened_at >= ?")
            params.append(since)
        if until is not None:
            conditions.append("opened_at <= ?")
            params.append(until)
        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        total = int(
            conn.execute(f"SELECT COUNT(*) AS c FROM cash_drawer {where}", params).fetchone()["c"]
        )
        rows = conn.execute(
            f"SELECT * FROM cash_drawer {where} ORDER BY opened_at DESC, id DESC LIMIT ? OFFSET ?",
            [*params, limit, offset],
        ).fetchall()
        return [CashDrawer.from_row(r) for r in rows], total

    def add_owner_in(self, conn, amount: int) -> None:
        conn.execute(
            "UPDATE cash_drawer SET owner_in = owner_in + ? WHERE id = ?",
            (int(amount), self.id),
        )
        self.owner_in += int(amount)

    def add_owner_out(self, conn, amount: int) -> None:
        conn.execute(
            "UPDATE cash_drawer SET owner_out = owner_out + ? WHERE id = ?",
            (int(amount), self.id),
        )
        self.owner_out += int(amount)

    def add_cash_sale(self, conn, amount: int) -> None:
        """FR5: accumulate a cash payment into the drawer's cash_sales total."""
        conn.execute(
            "UPDATE cash_drawer SET cash_sales = cash_sales + ? WHERE id = ?",
            (int(amount), self.id),
        )
        self.cash_sales += int(amount)

    def add_cash_expense(self, conn, amount: int) -> None:
        """FR6: accumulate a cash expense into the drawer's cash_expenses total."""
        conn.execute(
            "UPDATE cash_drawer SET cash_expenses = cash_expenses + ? WHERE id = ?",
            (int(amount), self.id),
        )
        self.cash_expenses += int(amount)

    def close(self, conn, *, counted_amount: int, closed_at: Optional[str] = None) -> int:
        """FR7: set counted_amount, compute discrepancy, mark closed.

        Returns the discrepancy (counted - expected).
        """
        expected = self.expected_balance()
        discrepancy = int(counted_amount) - expected
        closed_ts = closed_at or now_utc()
        cursor = conn.execute(
            "UPDATE cash_drawer "
            "SET status = 'closed', closed_at = ?, counted_amount = ?, discrepancy = ? "
            "WHERE id = ? AND status = 'open'",
            (closed_ts, int(counted_amount), discrepancy, self.id),
        )
        if cursor.rowcount != 1:
            raise ValueError(
                f"CashDrawer.close(): expected 1 row updated, got "
                f"{cursor.rowcount} (drawer id={self.id} not open)"
            )
        self.status = "closed"
        self.closed_at = closed_ts
        self.counted_amount = int(counted_amount)
        self.discrepancy = discrepancy
        return discrepancy

    def auto_close(self, conn, *, closed_at: Optional[str] = None) -> int:
        """FR8: auto-close at midnight using expected_balance as the counted
        amount, so the discrepancy is 0 (NFR1).

        Unlike :meth:`close` (manual count, may record an adjustment journal
        entry), auto-close trusts the books: ``counted_amount = expected_balance``
        and ``discrepancy = 0``. No close-adjustment journal entry is created
        because there is no discrepancy to absorb (NFR3).

        Race-condition safety: the caller wraps this in a transaction with a
        ``WHERE status = 'open'`` guard so concurrent writers cannot double-close.
        Returns the discrepancy (always 0).
        """
        expected = self.expected_balance()
        closed_ts = closed_at or now_utc()
        conn.execute(
            "UPDATE cash_drawer "
            "SET status = 'closed', closed_at = ?, counted_amount = ?, discrepancy = 0 "
            "WHERE id = ? AND status = 'open'",
            (closed_ts, expected, self.id),
        )
        self.status = "closed"
        self.closed_at = closed_ts
        self.counted_amount = expected
        self.discrepancy = 0
        return 0

    @staticmethod
    def get_most_recent_closed(conn) -> "CashDrawer | None":
        row = conn.execute(
            "SELECT * FROM cash_drawer WHERE status = 'closed' "
            "ORDER BY closed_at DESC LIMIT 1"
        ).fetchone()
        return CashDrawer.from_row(row) if row else None

    @staticmethod
    def get_stale_open_before(conn, *, before_iso: str) -> list["CashDrawer"]:
        """FR8 helper: list open drawers whose ``opened_at`` is strictly before
        the given ISO-8601 timestamp (typically the start of the current local
        day). Returns drawers ordered by ``opened_at`` ASC so the oldest
        stale drawer is auto-closed first. Used by the lazy auto-close check
        in the API layer.
        """
        rows = conn.execute(
            "SELECT * FROM cash_drawer "
            "WHERE status = 'open' AND opened_at < ? "
            "ORDER BY opened_at ASC, id ASC",
            (before_iso,),
        ).fetchall()
        return [CashDrawer.from_row(r) for r in rows]