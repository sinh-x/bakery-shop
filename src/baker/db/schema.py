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

    # Update category values from old slugs to new slugs
    for old_cat, new_slug in _OLD_CATEGORY_TO_SLUG.items():
        conn.execute(
            "UPDATE products SET category = ? WHERE category = ?",
            (new_slug, old_cat),
        )

    # Add unique index after all codes are assigned
    conn.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_products_code "
        "ON products(product_code) WHERE product_code != ''"
    )


def _migrate_v5_update_categories(conn):
    """Update product categories from old slugs to new slugs (safety for existing v4 DBs)."""
    for old_cat, new_slug in _OLD_CATEGORY_TO_SLUG.items():
        conn.execute(
            "UPDATE products SET category = ? WHERE category = ?",
            (new_slug, old_cat),
        )


SEED_CAKE_VARIANTS = [
    # (name, category, base_price, cost, recipe_notes, product_code)
    # 16 cm
    ("Bánh kem 16cm", "banh_kem", 200000, 90000, "Đường kính 16cm, thường", "BKS-16"),
    ("Bánh kem 16cm cao", "banh_kem", 250000, 110000, "Đường kính 16cm, cao", "BKS-16C"),
    ("Bánh kem 16cm nhiều tầng", "banh_kem", 350000, 160000, "Đường kính 16cm, nhiều tầng", "BKS-16T"),
    # 18 cm
    ("Bánh kem 18cm", "banh_kem", 250000, 110000, "Đường kính 18cm, thường", "BKS-18"),
    ("Bánh kem 18cm cao", "banh_kem", 300000, 135000, "Đường kính 18cm, cao", "BKS-18C"),
    ("Bánh kem 18cm nhiều tầng", "banh_kem", 450000, 200000, "Đường kính 18cm, nhiều tầng", "BKS-18T"),
    # 20 cm
    ("Bánh kem 20cm", "banh_kem", 350000, 160000, "Đường kính 20cm, thường", "BKS-20"),
    ("Bánh kem 20cm cao", "banh_kem", 400000, 180000, "Đường kính 20cm, cao", "BKS-20C"),
    ("Bánh kem 20cm nhiều tầng", "banh_kem", 600000, 270000, "Đường kính 20cm, nhiều tầng", "BKS-20T"),
    # 22 cm
    ("Bánh kem 22cm", "banh_kem", 450000, 200000, "Đường kính 22cm, thường", "BKS-22"),
    ("Bánh kem 22cm cao", "banh_kem", 500000, 225000, "Đường kính 22cm, cao", "BKS-22C"),
    ("Bánh kem 22cm nhiều tầng", "banh_kem", 750000, 340000, "Đường kính 22cm, nhiều tầng", "BKS-22T"),
]

SEED_SU_KEM_SETS = [
    # (name, category, base_price, cost, recipe_notes, product_code)
    ("Bánh su kem set 6", "banh_ngot", 45000, 19000, "Set 6 cái bánh su kem", "BNG-S06"),
    ("Bánh su kem set 8", "banh_ngot", 58000, 25000, "Set 8 cái bánh su kem", "BNG-S08"),
    ("Bánh su kem set 10", "banh_ngot", 70000, 30000, "Set 10 cái bánh su kem", "BNG-S10"),
    ("Bánh su kem set 12", "banh_ngot", 82000, 36000, "Set 12 cái bánh su kem", "BNG-S12"),
    ("Bánh su kem set 15", "banh_ngot", 100000, 44000, "Set 15 cái bánh su kem", "BNG-S15"),
]


def _migrate_v6_seed_variants(conn):
    """Seed cake size×type variants and su kem set products."""
    for name, cat, price, cost, notes, code in SEED_CAKE_VARIANTS + SEED_SU_KEM_SETS:
        conn.execute(
            "INSERT OR IGNORE INTO products "
            "(name, category, base_price, cost, recipe_notes, product_code) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (name, cat, price, cost, notes, code),
        )


PRODUCT_CATALOG_PHOTOS_SCHEMA = """
CREATE TABLE IF NOT EXISTS product_catalog_photos (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id  INTEGER NOT NULL REFERENCES products(id),
    file_path   TEXT NOT NULL,
    caption     TEXT DEFAULT '',
    tags        TEXT DEFAULT '',
    position    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_catalog_photos_product ON product_catalog_photos(product_id);
"""

PHOTOS_TABLE_AND_PHOTO_IDS_SCHEMA = """
ALTER TABLE categories ADD COLUMN icon TEXT DEFAULT '';
ALTER TABLE categories ADD COLUMN position INTEGER DEFAULT 0;

CREATE TABLE IF NOT EXISTS photos (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    hash        TEXT UNIQUE NOT NULL,
    original_name TEXT DEFAULT '',
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_photos_hash ON photos(hash);

ALTER TABLE products ADD COLUMN photo_id INTEGER REFERENCES photos(id);
ALTER TABLE product_catalog_photos ADD COLUMN photo_id INTEGER REFERENCES photos(id);
"""


def _migrate_v8_photos(conn):
    """Hash existing photos, populate photos table, update FKs, copy files to flat dir."""
    import hashlib
    import shutil
    import baker.config

    flat_dir = baker.config.DATA_DIR / "photos"
    flat_dir.mkdir(parents=True, exist_ok=True)

    def _ensure_photo(src_path, original_name):
        if not src_path.exists():
            return None
        data = src_path.read_bytes()
        hash_hex = hashlib.sha256(data).hexdigest()
        dest = flat_dir / f"{hash_hex}.jpg"
        if not dest.exists():
            shutil.copy2(src_path, dest)
        row = conn.execute("SELECT id FROM photos WHERE hash = ?", (hash_hex,)).fetchone()
        if row:
            return row[0]
        cursor = conn.execute(
            "INSERT INTO photos (hash, original_name) VALUES (?, ?)",
            (hash_hex, original_name),
        )
        return cursor.lastrowid

    # Migrate product main photos
    rows = conn.execute(
        "SELECT id, photo_path FROM products WHERE photo_path != '' AND photo_path IS NOT NULL"
    ).fetchall()
    for row in rows:
        photo_id = _ensure_photo(
            baker.config.DATA_DIR / row["photo_path"], row["photo_path"]
        )
        if photo_id:
            conn.execute(
                "UPDATE products SET photo_id = ? WHERE id = ?", (photo_id, row["id"])
            )

    # Migrate catalog photos
    rows = conn.execute(
        "SELECT id, file_path FROM product_catalog_photos"
        " WHERE file_path != '' AND file_path IS NOT NULL"
    ).fetchall()
    for row in rows:
        photo_id = _ensure_photo(
            baker.config.DATA_DIR / row["file_path"], row["file_path"]
        )
        if photo_id:
            conn.execute(
                "UPDATE product_catalog_photos SET photo_id = ? WHERE id = ?",
                (photo_id, row["id"]),
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
    5: {
        "description": "Update product categories to new slugs",
        "sql": "",
        "callable": _migrate_v5_update_categories,
    },
    6: {
        "description": "Seed cake variants (16/18/20/22cm × thường/cao/tầng) and su kem sets",
        "sql": "",
        "callable": _migrate_v6_seed_variants,
    },
    7: {
        "description": "Product catalog photos table for gallery feature",
        "sql": PRODUCT_CATALOG_PHOTOS_SCHEMA,
    },
    8: {
        "description": "Photos table (flat hash storage), categories icon+position, product FK",
        "sql": PHOTOS_TABLE_AND_PHOTO_IDS_SCHEMA,
        "callable": _migrate_v8_photos,
    },
    9: {
        "description": "Rename event type 'incident' to 'equipment'",
        "sql": "UPDATE events SET type = 'equipment' WHERE type = 'incident';",
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
