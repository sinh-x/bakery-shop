from dataclasses import dataclass
from typing import Optional

from baker.utils.time import now_utc


@dataclass
class JournalLine:
    journal_entry_id: int
    account_id: int
    debit: float = 0.0
    credit: float = 0.0
    description: str = ""
    id: Optional[int] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (
                self.journal_entry_id,
                self.account_id,
                float(self.debit),
                float(self.credit),
                self.description,
            ),
        )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def from_row(row) -> "JournalLine":
        return JournalLine(
            id=row["id"],
            journal_entry_id=row["journal_entry_id"],
            account_id=row["account_id"],
            debit=row["debit"],
            credit=row["credit"],
            description=row["description"] or "",
        )

    def to_api_dict(self) -> dict:
        return {
            "id": str(self.id),
            "journalEntryId": str(self.journal_entry_id),
            "accountId": str(self.account_id),
            "debit": self.debit,
            "credit": self.credit,
            "description": self.description,
        }

    @staticmethod
    def list_for_entry(conn, journal_entry_id: int) -> list["JournalLine"]:
        rows = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id = ? ORDER BY id",
            (journal_entry_id,),
        ).fetchall()
        return [JournalLine.from_row(r) for r in rows]


@dataclass
class JournalEntry:
    description: str
    source_type: str
    source_id: Optional[int] = None
    locked_at: Optional[str] = None
    locked_by: str = ""
    id: Optional[int] = None
    created_at: Optional[str] = None
    transaction_date: Optional[str] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, locked_at, locked_by, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                self.description,
                self.source_type,
                self.source_id,
                self.locked_at,
                self.locked_by,
                now_utc(),
            ),
        )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def from_row(row) -> "JournalEntry":
        return JournalEntry(
            id=row["id"],
            description=row["description"],
            source_type=row["source_type"],
            source_id=row["source_id"],
            locked_at=row["locked_at"],
            locked_by=row["locked_by"] or "",
            created_at=row["created_at"],
            transaction_date=row["transaction_date"],
        )

    def to_api_dict(self, lines: Optional[list[JournalLine]] = None) -> dict:
        return {
            "id": str(self.id),
            "description": self.description,
            "sourceType": self.source_type,
            "sourceId": str(self.source_id) if self.source_id is not None else None,
            "lockedAt": self.locked_at,
            "lockedBy": self.locked_by,
            "createdAt": self.created_at,
            "transactionDate": self.transaction_date,
            "lines": [line.to_api_dict() for line in (lines or [])],
        }

    @staticmethod
    def list_by_date_range(
        conn, since: Optional[str] = None, until: Optional[str] = None
    ) -> list["JournalEntry"]:
        if since and until:
            rows = conn.execute(
                "SELECT * FROM journal_entries "
                "WHERE created_at >= ? AND created_at <= ? ORDER BY created_at DESC",
                (since, until),
            ).fetchall()
        elif since:
            rows = conn.execute(
                "SELECT * FROM journal_entries WHERE created_at >= ? ORDER BY created_at DESC",
                (since,),
            ).fetchall()
        elif until:
            rows = conn.execute(
                "SELECT * FROM journal_entries WHERE created_at <= ? ORDER BY created_at DESC",
                (until,),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM journal_entries ORDER BY created_at DESC"
            ).fetchall()
        return [JournalEntry.from_row(r) for r in rows]

    @staticmethod
    def list_by_account(conn, account_id: int) -> list["JournalEntry"]:
        rows = conn.execute(
            "SELECT je.* FROM journal_entries je "
            "JOIN journal_lines jl ON jl.journal_entry_id = je.id "
            "WHERE jl.account_id = ? "
            "GROUP BY je.id ORDER BY je.created_at DESC",
            (account_id,),
        ).fetchall()
        return [JournalEntry.from_row(r) for r in rows]

    @staticmethod
    def list_by_source(
        conn, source_type: str, source_id: Optional[int] = None
    ) -> list["JournalEntry"]:
        if source_id is not None:
            rows = conn.execute(
                "SELECT * FROM journal_entries "
                "WHERE source_type = ? AND source_id = ? ORDER BY created_at DESC",
                (source_type, source_id),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM journal_entries WHERE source_type = ? ORDER BY created_at DESC",
                (source_type,),
            ).fetchall()
        return [JournalEntry.from_row(r) for r in rows]

    @staticmethod
    def lock_range(
        conn,
        since: str,
        until: str,
        locked_at: str,
        locked_by: str = "",
    ) -> int:
        """Lock all journal entries in the [since, until] date range.

        Returns the number of entries locked.
        """
        cursor = conn.execute(
            "UPDATE journal_entries SET locked_at = ?, locked_by = ? "
            "WHERE transaction_date >= ? AND transaction_date <= ? AND locked_at IS NULL",
            (locked_at, locked_by, since, until),
        )
        return int(cursor.rowcount)

    @staticmethod
    def get_balances(conn) -> list[dict]:
        """Return current balance per account.

        Asset/Expense: balance = SUM(debit) - SUM(credit).
        Liability/Equity/Income: balance = SUM(credit) - SUM(debit).
        """
        rows = conn.execute(
            """
            SELECT a.id, a.code, a.name, a.type, a.parent_id,
                   COALESCE(SUM(jl.debit), 0) AS total_debit,
                   COALESCE(SUM(jl.credit), 0) AS total_credit
            FROM accounts a
            LEFT JOIN journal_lines jl ON jl.account_id = a.id
            GROUP BY a.id
            ORDER BY a.code
            """
        ).fetchall()
        balances = []
        for row in rows:
            debit = float(row["total_debit"])
            credit = float(row["total_credit"])
            acc_type = row["type"]
            if acc_type in ("asset", "expense"):
                balance = debit - credit
            else:
                balance = credit - debit
            balances.append(
                {
                    "accountId": str(row["id"]),
                    "code": row["code"],
                    "name": row["name"],
                    "type": acc_type,
                    "parentId": (
                        str(row["parent_id"]) if row["parent_id"] is not None else None
                    ),
                    "debit": debit,
                    "credit": credit,
                    "balance": balance,
                }
            )
        return balances