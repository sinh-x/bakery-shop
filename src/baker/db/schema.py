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

PHOTO_PATH_AND_SEED = """
ALTER TABLE products ADD COLUMN photo_path TEXT DEFAULT '';
"""

SEED_PRODUCTS = [
    # (name, category, base_price, cost, recipe_notes)
    ("Bánh mì trắng", "bread", 10000, 5000, ""),
    ("Bánh mì ngọt", "bread", 12000, 6000, "Nhân kem bơ"),
    ("Bánh mì bơ tỏi", "bread", 15000, 7000, "Bơ tỏi phết mặt"),
    ("Bánh mì socola", "bread", 15000, 7000, "Nhân socola"),
    ("Bánh mì ruốc", "bread", 18000, 8000, "Ruốc heo"),
    ("Bánh bông lan", "cake", 50000, 25000, "Bông lan cơ bản"),
    ("Bánh bông lan trứng muối", "cake", 120000, 55000, "Nhân trứng muối"),
    ("Bánh kem sinh nhật size S", "cake", 200000, 90000, "Đường kính 16cm"),
    ("Bánh kem sinh nhật size M", "cake", 300000, 130000, "Đường kính 20cm"),
    ("Bánh kem sinh nhật size L", "cake", 450000, 200000, "Đường kính 24cm"),
    ("Bánh mousse chanh dây", "cake", 280000, 120000, "Mousse chanh dây"),
    ("Bánh mousse socola", "cake", 280000, 120000, "Mousse socola đen"),
    ("Bánh su kem", "pastry", 8000, 3500, "Nhân kem tươi"),
    ("Bánh croissant", "pastry", 25000, 12000, "Bơ Pháp"),
    ("Bánh croissant socola", "pastry", 30000, 14000, "Nhân socola"),
    ("Bánh puff pastry xúc xích", "pastry", 20000, 9000, "Xúc xích quấn pastry"),
    ("Bánh tart trứng", "pastry", 15000, 7000, "Trứng + kem sữa"),
    ("Cookie socola chip", "cookie", 5000, 2000, "Socola chip"),
    ("Cookie bơ đậu phộng", "cookie", 5000, 2000, "Đậu phộng rang"),
    ("Cookie yến mạch nho khô", "cookie", 6000, 2500, "Yến mạch + nho khô"),
    ("Bánh quy bơ", "cookie", 4000, 1500, "Bơ thơm"),
    ("Bánh flan", "other", 12000, 5000, "Flan caramel"),
    ("Bánh chuối nướng", "other", 35000, 15000, "Chuối + nước cốt dừa"),
]

PRODUCT_CODE_AND_CATEGORIES_SCHEMA = """
ALTER TABLE products ADD COLUMN product_code TEXT DEFAULT '';

CREATE TABLE IF NOT EXISTS categories (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    slug        TEXT UNIQUE NOT NULL,
    name        TEXT NOT NULL,
    code_prefix TEXT NOT NULL,
    active      INTEGER DEFAULT 1
);
"""

SEED_CATEGORIES = [
    # (slug, name, code_prefix)
    ("banh_mi", "Bánh mì", "BMI"),
    ("banh_kem", "Bánh kem", "BKS"),
    ("banh_ngot", "Bánh ngọt", "BNG"),
    ("cookie", "Cookie", "CKI"),
    ("khac", "Khác", "KHA"),
]

# Map old product categories to new category slugs
_OLD_CATEGORY_TO_SLUG = {
    "bread": "banh_mi",
    "cake": "banh_kem",
    "pastry": "banh_ngot",
    "cookie": "cookie",
    "other": "khac",
}


def _migrate_v4_assign_codes(conn):
    """Seed categories and assign product codes to existing products."""
    # Seed categories
    for slug, name, code_prefix in SEED_CATEGORIES:
        conn.execute(
            "INSERT OR IGNORE INTO categories (slug, name, code_prefix) "
            "VALUES (?, ?, ?)",
            (slug, name, code_prefix),
        )

    # Build prefix lookup: old category -> code_prefix
    slug_to_prefix = {slug: prefix for slug, _, prefix in SEED_CATEGORIES}
    prefix_counters = {}

    # Fetch all products ordered by id to assign codes deterministically
    rows = conn.execute(
        "SELECT id, category FROM products ORDER BY id"
    ).fetchall()

    for row in rows:
        product_id = row[0]
        old_cat = row[1]
        slug = _OLD_CATEGORY_TO_SLUG.get(old_cat, "khac")
        prefix = slug_to_prefix[slug]

        count = prefix_counters.get(prefix, 0) + 1
        prefix_counters[prefix] = count
        code = f"{prefix}-{count:02d}"

        conn.execute(
            "UPDATE products SET product_code = ? WHERE id = ?",
            (code, product_id),
        )

    # Add unique index after all codes are assigned
    conn.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_products_code "
        "ON products(product_code) WHERE product_code != ''"
    )


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
    3: {
        "description": "Product photo_path column and seed 23 products",
        "sql": PHOTO_PATH_AND_SEED,
        "seed": SEED_PRODUCTS,
    },
    4: {
        "description": "Product codes and categories table",
        "sql": PRODUCT_CODE_AND_CATEGORIES_SCHEMA,
        "callable": _migrate_v4_assign_codes,
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

            # Seed data if present
            seed = MIGRATIONS[version].get("seed")
            if seed:
                for name, category, base_price, cost, recipe_notes in seed:
                    conn.execute(
                        "INSERT OR IGNORE INTO products "
                        "(name, category, base_price, cost, recipe_notes) "
                        "VALUES (?, ?, ?, ?, ?)",
                        (name, category, base_price, cost, recipe_notes),
                    )

            # Run callable if present (for complex migrations)
            callable_fn = MIGRATIONS[version].get("callable")
            if callable_fn:
                callable_fn(conn)

            conn.execute(
                "INSERT INTO schema_version (version, description) VALUES (?, ?)",
                (version, MIGRATIONS[version]["description"]),
            )
    conn.commit()
