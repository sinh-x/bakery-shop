"""Cash drawer model (DG-324 Phase 2 / DG-347 Phase 2).

A :class:`CashDrawer` records one daily cash drawer session. The expected
balance is derived (FR1) from 1101 journal lines linked via the
``cash_drawer_journal_entries`` join table for open drawers, or from the
persisted ``closing_balance`` for closed drawers (FR2). Balance-affecting
fields are stored as INTEGER (VND) per NFR1 so drawer balance computation is
accurate to within 1 VND. The counted amount and discrepancy are persisted at
close time (FR7).

Traceability: FR1, FR2, FR4, FR7, FR8, FR10, NFR1.
"""

from dataclasses import dataclass
from typing import Optional

from baker.utils.time import now_utc


@dataclass
class CashDrawer:
    opened_at: str
    opening_balance: int = 0
    status: str = "open"
    closed_at: Optional[str] = None
    counted_amount: Optional[int] = None
    discrepancy: Optional[int] = None
    closing_balance: Optional[int] = None
    counted_opening_balance: Optional[int] = None
    id: Optional[int] = None

    def expected_balance(self, conn=None) -> int:
        """FR3: derive the expected balance.

        For closed drawers with a persisted ``closing_balance``, return it
        directly (no journal query). For open drawers, when a ``conn`` is
        provided, return ``opening_balance + SUM(1101 debit - credit)`` over
        the journal lines linked to this drawer via the
        ``cash_drawer_journal_entries`` join table. ``opening_balance`` holds
        the 1101 accounting balance at open time (FR1), so the linked-entry sum
        captures only the activity that occurred during this drawer session.
        Without a ``conn`` (e.g. tests that construct the model directly), fall
        back to ``opening_balance`` so the method never raises.
        """
        if self.status == "closed" and self.closing_balance is not None:
            return self.closing_balance
        if conn is None:
            return self.opening_balance
        row = conn.execute(
            """
            SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
            FROM cash_drawer_journal_entries cdje
            JOIN journal_lines jl ON jl.journal_entry_id = cdje.journal_entry_id
            JOIN accounts a ON a.id = jl.account_id
            WHERE cdje.cash_drawer_id = ? AND a.code = '1101'
            """,
            (self.id,),
        ).fetchone()
        return int(self.opening_balance) + int(row["balance"])

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO cash_drawer "
            "(opened_at, opening_balance, counted_opening_balance, status) "
            "VALUES (?, ?, ?, 'open')",
            (
                self.opened_at,
                int(self.opening_balance),
                int(self.counted_opening_balance) if self.counted_opening_balance is not None else None,
            ),
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
            counted_amount=int(row["counted_amount"]) if row["counted_amount"] is not None else None,
            discrepancy=int(row["discrepancy"]) if row["discrepancy"] is not None else None,
            closing_balance=(
                int(row["closing_balance"])
                if row["closing_balance"] is not None
                else None
            ),
            counted_opening_balance=(
                int(row["counted_opening_balance"])
                if row["counted_opening_balance"] is not None
                else None
            ),
        )

    def to_api_dict(self, conn=None) -> dict:
        return {
            "id": str(self.id),
            "openedAt": self.opened_at,
            "closedAt": self.closed_at,
            "status": self.status,
            "openingBalance": self.opening_balance,
            "countedOpeningBalance": self.counted_opening_balance,
            "countedAmount": self.counted_amount,
            "discrepancy": self.discrepancy,
            "closingBalance": self.closing_balance,
            "expectedBalance": self.expected_balance(conn),
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

    def close(self, conn, *, counted_amount: int, closed_at: Optional[str] = None) -> int:
        """FR7: set counted_amount, compute discrepancy, mark closed.

        Persists ``closing_balance = expected_balance`` so historical drawer
        data remains accurate after close (FR2/AC2). Returns the discrepancy
        (counted - expected).
        """
        expected = self.expected_balance(conn)
        discrepancy = int(counted_amount) - expected
        closed_ts = closed_at or now_utc()
        cursor = conn.execute(
            "UPDATE cash_drawer "
            "SET status = 'closed', closed_at = ?, counted_amount = ?, "
            "    discrepancy = ?, closing_balance = ? "
            "WHERE id = ? AND status = 'open'",
            (closed_ts, int(counted_amount), discrepancy, expected, self.id),
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
        self.closing_balance = expected
        return discrepancy

    def auto_close(self, conn, *, closed_at: Optional[str] = None) -> int:
        """FR8: auto-close at midnight using expected_balance as the counted
        amount, so the discrepancy is 0 (NFR1).

        Persists ``closing_balance = expected_balance`` (FR2/AC12). Unlike
        :meth:`close` (manual count, may record an adjustment journal entry),
        auto-close trusts the books: ``counted_amount = expected_balance`` and
        ``discrepancy = 0``. No close-adjustment journal entry is created
        because there is no discrepancy to absorb (NFR3).

        Race-condition safety: the caller wraps this in a transaction with a
        ``WHERE status = 'open'`` guard so concurrent writers cannot double-close.
        Returns the discrepancy (always 0).
        """
        expected = self.expected_balance(conn)
        closed_ts = closed_at or now_utc()
        conn.execute(
            "UPDATE cash_drawer "
            "SET status = 'closed', closed_at = ?, counted_amount = ?, "
            "    discrepancy = 0, closing_balance = ? "
            "WHERE id = ? AND status = 'open'",
            (closed_ts, expected, expected, self.id),
        )
        self.status = "closed"
        self.closed_at = closed_ts
        self.counted_amount = expected
        self.discrepancy = 0
        self.closing_balance = expected
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