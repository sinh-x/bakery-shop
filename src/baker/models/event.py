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
    id: Optional[int] = None
    timestamp: Optional[str] = None

    def __post_init__(self):
        self.type = TYPE_ALIASES.get(self.type, self.type)

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO events (type, summary, data, tags, source) VALUES (?, ?, ?, ?, ?)",
            (self.type, self.summary, json.dumps(self.data),
             ",".join(self.tags), self.source),
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
        )
