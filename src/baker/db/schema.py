INITIAL_SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')),
    type        TEXT NOT NULL DEFAULT 'note',
    summary     TEXT NOT NULL,
    data        TEXT DEFAULT '{}',
    tags        TEXT DEFAULT '',
    source      TEXT DEFAULT 'cli'
);

CREATE INDEX IF NOT EXISTS idx_events_type ON events(type);
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
CREATE INDEX IF NOT EXISTS idx_events_tags ON events(tags);

CREATE TABLE IF NOT EXISTS orders (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    order_ref       TEXT UNIQUE NOT NULL,
    customer_name   TEXT NOT NULL,
    customer_phone  TEXT DEFAULT '',
    items           TEXT NOT NULL DEFAULT '[]',
    total_price     REAL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'new',
    due_date        TEXT,
    due_time        TEXT,
    delivery_type   TEXT DEFAULT 'pickup',
    delivery_address TEXT DEFAULT '',
    notes           TEXT DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_due_date ON orders(due_date);

CREATE TABLE IF NOT EXISTS inventory (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT UNIQUE NOT NULL,
    category    TEXT DEFAULT 'ingredient',
    quantity    REAL NOT NULL DEFAULT 0,
    unit        TEXT NOT NULL DEFAULT 'kg',
    low_threshold REAL DEFAULT 0,
    cost_per_unit REAL DEFAULT 0,
    supplier    TEXT DEFAULT '',
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE TABLE IF NOT EXISTS products (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT UNIQUE NOT NULL,
    category    TEXT DEFAULT 'bread',
    base_price  REAL DEFAULT 0,
    cost        REAL DEFAULT 0,
    recipe_notes TEXT DEFAULT '',
    active      INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS schema_version (
    version     INTEGER PRIMARY KEY,
    applied_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')),
    description TEXT
);
"""

STAFF_AND_PEOPLE_SCHEMA = """
CREATE TABLE IF NOT EXISTS staff (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT UNIQUE NOT NULL,
    role        TEXT DEFAULT '',
    phone       TEXT DEFAULT '',
    active      INTEGER DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE TABLE IF NOT EXISTS event_people (
    event_id    INTEGER NOT NULL REFERENCES events(id),
    staff_id    INTEGER NOT NULL REFERENCES staff(id),
    role        TEXT NOT NULL DEFAULT 'involved',
    PRIMARY KEY (event_id, staff_id, role)
);

CREATE INDEX IF NOT EXISTS idx_event_people_staff ON event_people(staff_id);
CREATE INDEX IF NOT EXISTS idx_event_people_event ON event_people(event_id);
CREATE INDEX IF NOT EXISTS idx_events_logged_by ON events(logged_by);
"""

MIGRATIONS = {
    1: {
        "description": "Initial schema",
        "sql": INITIAL_SCHEMA,
    },
    2: {
        "description": "Staff tracking and event people",
        "sql": "ALTER TABLE events ADD COLUMN logged_by TEXT DEFAULT '';\n"
               + STAFF_AND_PEOPLE_SCHEMA,
    },
}


def ensure_schema(conn):
    """Apply any pending migrations."""
    cursor = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
    )
    if not cursor.fetchone():
        current_version = 0
    else:
        cursor = conn.execute("SELECT MAX(version) FROM schema_version")
        row = cursor.fetchone()
        current_version = row[0] if row[0] is not None else 0

    for version in sorted(MIGRATIONS.keys()):
        if version > current_version:
            conn.executescript(MIGRATIONS[version]["sql"])
            conn.execute(
                "INSERT INTO schema_version (version, description) VALUES (?, ?)",
                (version, MIGRATIONS[version]["description"]),
            )
    conn.commit()
