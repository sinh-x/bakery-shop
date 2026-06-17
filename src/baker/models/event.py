import json
from dataclasses import dataclass, field
from typing import Optional

TYPE_ALIASES = {
    "prod": "production",
    "inv": "inventory",
    "exp": "expense",
    "del": "delivery",
    "ord": "order",
}


@dataclass
class Event:
    summary: str
    type: str = "note"
    data: dict = field(default_factory=dict)
    tags: list[str] = field(default_factory=list)
    source: str = "cli"
    logged_by: str = ""
    id: Optional[int] = None
    timestamp: Optional[str] = None
    order_id: Optional[int] = None

    def __post_init__(self):
        self.type = TYPE_ALIASES.get(self.type, self.type)

    def save(self, conn) -> int:
        if self.timestamp:
            cursor = conn.execute(
                "INSERT INTO events (type, summary, data, tags, source, logged_by, timestamp, order_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (self.type, self.summary, json.dumps(self.data),
                 ",".join(self.tags), self.source, self.logged_by, self.timestamp, self.order_id),
            )
        else:
            cursor = conn.execute(
                "INSERT INTO events (type, summary, data, tags, source, logged_by, order_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (self.type, self.summary, json.dumps(self.data),
                 ",".join(self.tags), self.source, self.logged_by, self.order_id),
            )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def from_row(row) -> "Event":
        tags_str = row["tags"] or ""
        return Event(
            id=row["id"],
            timestamp=row["timestamp"],
            type=row["type"],
            summary=row["summary"],
            data=json.loads(row["data"]) if row["data"] else {},
            tags=[t for t in tags_str.split(",") if t],
            source=row["source"],
            logged_by=row["logged_by"] if "logged_by" in row.keys() else "",
            order_id=row["order_id"] if "order_id" in row.keys() else None,
        )
