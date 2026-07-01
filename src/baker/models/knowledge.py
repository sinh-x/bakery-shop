"""Knowledge entry dataclass — follows the Event model pattern."""

from dataclasses import dataclass, field
from typing import Optional

from baker.utils.time import now_utc


VALID_TYPES = {"recipe", "procedure", "equipment", "supplier", "reference", "note"}


@dataclass
class Knowledge:
    title: str
    content: str = ""
    type: str = "note"
    tags: list[str] = field(default_factory=list)
    source: str = "app"
    logged_by: str = ""
    id: Optional[int] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    pinned: bool = False
    pinned_at: Optional[str] = None

    def save(self, conn) -> int:
        """Insert new knowledge entry, set id and timestamps."""
        cursor = conn.execute(
            """INSERT INTO knowledge_entries
               (title, content, type, tags, source, logged_by, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                self.title,
                self.content,
                self.type,
                ",".join(self.tags),
                self.source,
                self.logged_by,
                now_utc(),
                now_utc(),
            ),
        )
        self.id = cursor.lastrowid
        # Refresh timestamps from DB
        row = conn.execute(
            "SELECT created_at, updated_at FROM knowledge_entries WHERE id = ?",
            (self.id,),
        ).fetchone()
        self.created_at = row["created_at"]
        self.updated_at = row["updated_at"]
        return self.id

    def update(self, conn) -> bool:
        """Update existing entry fields in place. Returns True if updated."""
        fields: list[str] = []
        values: list = []

        fields.append("title = ?")
        values.append(self.title)
        fields.append("content = ?")
        values.append(self.content)
        fields.append("type = ?")
        values.append(self.type)
        fields.append("tags = ?")
        values.append(",".join(self.tags))

        values.append(self.id)
        conn.execute(
            f"UPDATE knowledge_entries SET {', '.join(fields)} WHERE id = ?",
            values,
        )
        # Refresh updated_at
        row = conn.execute(
            "SELECT updated_at FROM knowledge_entries WHERE id = ?",
            (self.id,),
        ).fetchone()
        self.updated_at = row["updated_at"]
        return True

    @staticmethod
    def from_row(row) -> "Knowledge":
        """Convert sqlite Row to Knowledge instance."""
        tags_str = row["tags"] or ""
        return Knowledge(
            id=row["id"],
            title=row["title"],
            content=row["content"] or "",
            type=row["type"] or "note",
            tags=[t for t in tags_str.split(",") if t],
            source=row["source"] or "app",
            logged_by=row["logged_by"] or "",
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            pinned=bool(row["pinned"]) if "pinned" in row.keys() else False,
            pinned_at=row["pinned_at"] if "pinned_at" in row.keys() else None,
        )
