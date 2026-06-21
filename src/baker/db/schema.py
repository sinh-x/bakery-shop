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


ORDER_PHOTOS_SCHEMA = """
CREATE TABLE IF NOT EXISTS order_photos (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id    INTEGER NOT NULL REFERENCES orders(id),
    photo_id    INTEGER NOT NULL REFERENCES photos(id),
    tags        TEXT DEFAULT '',
    position    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_order_photos_order ON order_photos(order_id);
"""

ORDER_ITEMS_AND_PAYMENT_TRANSACTIONS_SCHEMA = """
CREATE TABLE IF NOT EXISTS order_items (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id        INTEGER NOT NULL REFERENCES orders(id),
    product_id      TEXT DEFAULT '',
    product_name    TEXT NOT NULL,
    quantity        INTEGER NOT NULL DEFAULT 1,
    unit_price      REAL NOT NULL DEFAULT 0,
    notes           TEXT DEFAULT '',
    position        INTEGER NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'pending',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

CREATE TABLE IF NOT EXISTS payment_transactions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id        INTEGER NOT NULL REFERENCES orders(id),
    amount          REAL NOT NULL,
    type            TEXT NOT NULL DEFAULT 'deposit',
    method          TEXT NOT NULL DEFAULT 'cash',
    note            TEXT DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_order ON payment_transactions(order_id);
"""

PER_ITEM_BIRTHDAY_AND_PHOTO_LINK_SCHEMA = """
ALTER TABLE order_items ADD COLUMN is_birthday INTEGER NOT NULL DEFAULT 0;
ALTER TABLE order_items ADD COLUMN age INTEGER DEFAULT NULL;
ALTER TABLE order_photos ADD COLUMN work_item_id INTEGER DEFAULT NULL REFERENCES order_items(id);
"""

APP_CONFIG_AND_ORDER_SOURCE_SCHEMA = """
CREATE TABLE IF NOT EXISTS app_config (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    config_key  TEXT NOT NULL,
    config_value TEXT NOT NULL,
    sort_order  INTEGER DEFAULT 0,
    active      INTEGER DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_config_key_value ON app_config(config_key, config_value);
ALTER TABLE orders ADD COLUMN source TEXT DEFAULT '';
"""

SEED_ORDER_SOURCES = [
    ("order_source", "Facebook-DoanGia", 1),
    ("order_source", "Zalo", 2),
    ("order_source", "Facebook-Page-mới", 3),
    ("order_source", "Tại tiệm", 4),
    ("order_source", "Điện thoại", 5),
]


def _migrate_v14_seed_order_sources(conn):
    """Seed order source config values into app_config."""
    for config_key, config_value, sort_order in SEED_ORDER_SOURCES:
        conn.execute(
            "INSERT OR IGNORE INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            (config_key, config_value, sort_order),
        )


def _migrate_v12_data(conn):
    """Migrate orders.items JSON → order_items rows; amount_paid > 0 → deposit transaction."""
    import json

    rows = conn.execute("SELECT * FROM orders").fetchall()
    for row in rows:
        order_id = row["id"]

        # Migrate items JSON -> order_items
        items_json = row["items"]
        if items_json:
            try:
                items = json.loads(items_json)
            except (json.JSONDecodeError, TypeError):
                items = []
            for position, item in enumerate(items):
                conn.execute(
                    """INSERT OR IGNORE INTO order_items
                       (order_id, product_id, product_name, quantity, unit_price, notes, position)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (
                        order_id,
                        item.get("product_id", ""),
                        item.get("product", ""),
                        item.get("qty", 1),
                        item.get("price", 0),
                        item.get("notes", ""),
                        position,
                    ),
                )

        # Migrate amount_paid > 0 → deposit transaction
        amount_paid = row["amount_paid"] or 0
        if amount_paid > 0:
            conn.execute(
                """INSERT INTO payment_transactions
                   (order_id, amount, type, method, note)
                   VALUES (?, ?, 'deposit', 'cash', 'Migrated from amount_paid')""",
                (order_id, amount_paid),
            )


SERVER_LOGS_AND_TRIGGERS_SCHEMA = """
CREATE TABLE IF NOT EXISTS server_logs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S.000', 'now', 'localtime')),
    level       TEXT NOT NULL DEFAULT 'INFO',
    method      TEXT DEFAULT '',
    path        TEXT DEFAULT '',
    status_code INTEGER DEFAULT 0,
    duration_ms REAL DEFAULT 0,
    client_ip   TEXT DEFAULT '',
    device_model TEXT DEFAULT '',
    app_version TEXT DEFAULT '',
    os_version  TEXT DEFAULT '',
    ref_type    TEXT DEFAULT '',
    ref_id      INTEGER DEFAULT NULL,
    message     TEXT DEFAULT '',
    detail      TEXT DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_server_logs_timestamp ON server_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_server_logs_level ON server_logs(level);
CREATE INDEX IF NOT EXISTS idx_server_logs_path ON server_logs(path);
CREATE INDEX IF NOT EXISTS idx_server_logs_ref ON server_logs(ref_type, ref_id);

CREATE TABLE IF NOT EXISTS log_triggers (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    condition   TEXT NOT NULL,
    action      TEXT NOT NULL,
    active      INTEGER DEFAULT 1,
    cooldown_seconds INTEGER DEFAULT 300,
    last_fired  TEXT DEFAULT NULL,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
"""

SEED_STAFF = [
    # (name, role)
    ("Ân", "staff"),
    ("Ngân", "staff"),
    ("Phượng", "staff"),
    ("Sinh", "owner"),
    ("Tân", "staff"),
]


def _migrate_v16_staff_and_created_by(conn):
    """Seed 5 staff members and add created_by column to orders."""
    for name, role in SEED_STAFF:
        conn.execute(
            "INSERT OR IGNORE INTO staff (name, role) VALUES (?, ?)",
            (name, role),
        )
    conn.execute(
        "ALTER TABLE orders ADD COLUMN created_by TEXT DEFAULT ''"
    )


def _migrate_v17_fix_staff_names(conn):
    """Fix staff names to use proper Vietnamese diacritics."""
    fixes = [
        ("An", "Ân"),
        ("Ngan", "Ngân"),
        ("Phuong", "Phượng"),
        ("Tan", "Tân"),
    ]
    for old_name, new_name in fixes:
        conn.execute(
            "UPDATE staff SET name = ? WHERE name = ?",
            (new_name, old_name),
        )


CHECKLIST_SCHEMA = """
CREATE TABLE IF NOT EXISTS checklist_templates (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    period      TEXT NOT NULL DEFAULT 'opening',
    sort_order  INTEGER NOT NULL DEFAULT 0,
    active      INTEGER DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_checklist_templates_period ON checklist_templates(period);

CREATE TABLE IF NOT EXISTS checklist_entries (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id     INTEGER NOT NULL REFERENCES checklist_templates(id),
    checklist_date  TEXT NOT NULL,
    completed       INTEGER NOT NULL DEFAULT 0,
    completed_by    TEXT DEFAULT '',
    completed_at    TEXT DEFAULT NULL,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_checklist_entries_unique ON checklist_entries(template_id, checklist_date);
CREATE INDEX IF NOT EXISTS idx_checklist_entries_date ON checklist_entries(checklist_date);
"""

SEED_CHECKLIST_OPENING = [
    ("Kiểm tra nhiệt độ tủ lạnh", "opening", 1),
    ("Bật lò nướng & kiểm tra hoạt động", "opening", 2),
    ("Kiểm tra nguyên liệu cần dùng trong ngày", "opening", 3),
    ("Vệ sinh bàn làm việc & dụng cụ", "opening", 4),
    ("Kiểm tra đơn hàng cần giao trong ngày", "opening", 5),
    ("Sắp xếp bánh ra tủ trưng bày", "opening", 6),
]

SEED_CHECKLIST_CLOSING = [
    ("Dọn dẹp & vệ sinh quầy bán hàng", "closing", 1),
    ("Rửa sạch dụng cụ làm bánh", "closing", 2),
    ("Kiểm tra & cất nguyên liệu thừa", "closing", 3),
    ("Tắt lò nướng & kiểm tra thiết bị điện", "closing", 4),
    ("Kiểm tra nhiệt độ tủ lạnh", "closing", 5),
    ("Đếm tiền & ghi sổ doanh thu", "closing", 6),
    ("Khóa cửa & kiểm tra an ninh", "closing", 7),
]


def _migrate_v18_seed_checklist(conn):
    """Seed default opening and closing checklist items."""
    for name, period, sort_order in SEED_CHECKLIST_OPENING + SEED_CHECKLIST_CLOSING:
        conn.execute(
            "INSERT OR IGNORE INTO checklist_templates (name, period, sort_order) VALUES (?, ?, ?)",
            (name, period, sort_order),
        )


ORDER_HISTORY_SCHEMA = """
CREATE TABLE IF NOT EXISTS order_history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id    INTEGER NOT NULL REFERENCES orders(id),
    action_type TEXT NOT NULL,
    field_name  TEXT DEFAULT '',
    old_value   TEXT DEFAULT '',
    new_value   TEXT DEFAULT '',
    changed_by  TEXT DEFAULT '',
    timestamp   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_order_history_order ON order_history(order_id);
CREATE INDEX IF NOT EXISTS idx_order_history_timestamp ON order_history(timestamp);
"""

SHIPPING_FEE_AND_EXTRAS_SCHEMA = """
ALTER TABLE orders ADD COLUMN shipping_fee REAL DEFAULT 0;
ALTER TABLE order_items ADD COLUMN is_extra INTEGER NOT NULL DEFAULT 0;
ALTER TABLE order_items ADD COLUMN is_gift INTEGER NOT NULL DEFAULT 0;
"""

SEED_SHIPPING_AND_EXTRAS = [
    ("shipping_fee_bus", "0", 0),
    ("shipping_fee_bus", "25000", 1),
    ("shipping_fee_door", "0", 0),
    ("shipping_fee_door", "20000", 1),
    ("shipping_fee_door", "30000", 2),
    ("shipping_fee_door", "40000", 3),
    ("shipping_fee_door", "50000", 4),
    ("order_extra", "Nến|5000", 1),
    ("order_extra", "Đĩa muỗng|10000", 2),
    ("order_extra", "Nón|5000", 3),
    ("order_extra", "Pháo|10000", 4),
]


def _migrate_v20_seed_shipping_and_extras(conn):
    """Seed shipping fee presets and extra item presets into app_config."""
    for config_key, config_value, sort_order in SEED_SHIPPING_AND_EXTRAS:
        conn.execute(
            "INSERT OR IGNORE INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            (config_key, config_value, sort_order),
        )


WORK_TICKET_PRINTED_AT_SCHEMA = """
ALTER TABLE orders ADD COLUMN work_ticket_printed_at TEXT DEFAULT NULL;
"""

PRINT_LOG_AND_PRINTED_BY_SCHEMA = """
CREATE TABLE IF NOT EXISTS print_log (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id     INTEGER NOT NULL REFERENCES orders(id),
    item_id      INTEGER,
    receipt_type TEXT NOT NULL,
    printed_by   TEXT NOT NULL DEFAULT '',
    printed_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_print_log_order ON print_log(order_id);
"""

RECONCILIATIONS_SCHEMA = """
CREATE TABLE IF NOT EXISTS reconciliation_sessions (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    reconciliation_date     TEXT NOT NULL,
    staff_name              TEXT NOT NULL,
    payment_method          TEXT DEFAULT '',
    waste_reason            TEXT DEFAULT '',
    linked_order_ref        TEXT DEFAULT NULL,
    linked_payment_ref      TEXT DEFAULT NULL,
    created_at              TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_reconciliation_sessions_date ON reconciliation_sessions(reconciliation_date);

CREATE TABLE IF NOT EXISTS reconciliation_lines (
    id                           INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id                   INTEGER NOT NULL REFERENCES reconciliation_sessions(id) ON DELETE CASCADE,
    product_id                   INTEGER NOT NULL REFERENCES products(id),
    expected_qty                 INTEGER NOT NULL,
    counted_qty                  INTEGER NOT NULL,
    sale_qty                     INTEGER NOT NULL DEFAULT 0,
    waste_qty                    INTEGER NOT NULL DEFAULT 0,
    waste_reason                 TEXT DEFAULT '',
    manual_unit_price            REAL DEFAULT NULL,
    linked_order_item_id         INTEGER DEFAULT NULL,
    linked_stock_movement_sale_id INTEGER DEFAULT NULL,
    linked_stock_movement_waste_id INTEGER DEFAULT NULL,
    created_at                   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_reconciliation_lines_session ON reconciliation_lines(session_id);
CREATE INDEX IF NOT EXISTS idx_reconciliation_lines_product ON reconciliation_lines(product_id);
"""

RECONCILIATION_SALE_ROWS_SCHEMA = """
CREATE TABLE IF NOT EXISTS reconciliation_sale_rows (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    line_id             INTEGER NOT NULL REFERENCES reconciliation_lines(id) ON DELETE CASCADE,
    quantity            INTEGER NOT NULL,
    unit_price          REAL NOT NULL,
    payment_method      TEXT NOT NULL,
    linked_order_ref    TEXT DEFAULT NULL,
    linked_payment_ref  TEXT DEFAULT NULL,
    created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_reconciliation_sale_rows_line ON reconciliation_sale_rows(line_id);
"""


def _migrate_v32_print_tracking(conn):
    """Add print tracking schema with idempotent orders column migration."""
    _guard_add_column(conn, "orders", "work_ticket_printed_by", "work_ticket_printed_by TEXT DEFAULT ''")


def _migrate_v35_reconciliation_line_waste_reason(conn):
    """Repair DBs that created reconciliation_lines before per-line waste reasons."""
    _guard_add_column(
        conn,
        "reconciliation_lines",
        "waste_reason",
        "waste_reason TEXT DEFAULT ''",
    )


STOCK_LOTS_AND_ITEMS_SCHEMA = """
CREATE TABLE IF NOT EXISTS stock_lots (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id      INTEGER NOT NULL REFERENCES products(id),
    price_chip_id   INTEGER REFERENCES product_price_chips(id),
    quantity        INTEGER NOT NULL DEFAULT 0,
    remaining_qty   INTEGER NOT NULL DEFAULT 0,
    restocked_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')),
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_stock_lots_product_chip ON stock_lots(product_id, price_chip_id);
CREATE INDEX IF NOT EXISTS idx_stock_lots_fifo ON stock_lots(product_id, price_chip_id, restocked_at ASC);

CREATE TABLE IF NOT EXISTS inventory_items (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    lot_id                      INTEGER NOT NULL REFERENCES stock_lots(id),
    uuid                        TEXT NOT NULL UNIQUE,
    status                      TEXT NOT NULL DEFAULT 'available',
    consumed_by_movement_id     INTEGER REFERENCES stock_movements(id),
    created_at                  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_inventory_items_lot ON inventory_items(lot_id);
CREATE INDEX IF NOT EXISTS idx_inventory_items_uuid ON inventory_items(uuid);
CREATE INDEX IF NOT EXISTS idx_inventory_items_lot_status ON inventory_items(lot_id, status, created_at);
"""


ORDER_INCIDENT_ORDER_ID_SCHEMA = """
ALTER TABLE events ADD COLUMN order_id INTEGER REFERENCES orders(id);
CREATE INDEX IF NOT EXISTS idx_events_order_id ON events(order_id);
"""

EVENT_PHOTOS_SCHEMA = """
CREATE TABLE IF NOT EXISTS event_photos (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id    INTEGER NOT NULL REFERENCES events(id),
    photo_id    INTEGER NOT NULL REFERENCES photos(id),
    tags        TEXT DEFAULT '',
    position    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_event_photos_event ON event_photos(event_id);
"""

PUBLIC_ORDER_CODE_SCHEMA = """
ALTER TABLE orders ADD COLUMN public_order_code TEXT DEFAULT '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_due_date_public_order_code_unique
ON orders(due_date, public_order_code)
WHERE public_order_code IS NOT NULL
  AND public_order_code != ''
  AND due_date IS NOT NULL
  AND due_date != '';
"""


def _migrate_v36_chip_aware_inventory(conn):
    """Migrate product_stock rows into stock_lots + inventory_items using lowest-priced option."""
    import uuid

    def _table_exists(table_name: str) -> bool:
        exists_row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
            (table_name,),
        ).fetchone()
        return exists_row is not None

    if _table_exists("stock_movements"):
        _guard_add_column(
            conn,
            "stock_movements",
            "lot_id",
            "lot_id INTEGER REFERENCES stock_lots(id)",
        )
        _guard_add_column(
            conn,
            "stock_movements",
            "price_chip_id",
            "price_chip_id INTEGER REFERENCES product_price_chips(id)",
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_stock_movements_lot ON stock_movements(lot_id)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_stock_movements_product_chip_created "
            "ON stock_movements(product_id, price_chip_id, created_at)"
        )

    if _table_exists("order_items"):
        _guard_add_column(
            conn,
            "order_items",
            "price_chip_id",
            "price_chip_id INTEGER REFERENCES product_price_chips(id)",
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_order_items_price_chip ON order_items(price_chip_id)"
        )

    if _table_exists("reconciliation_lines"):
        _guard_add_column(
            conn,
            "reconciliation_lines",
            "price_chip_id",
            "price_chip_id INTEGER REFERENCES product_price_chips(id)",
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_reconciliation_lines_price_chip ON reconciliation_lines(price_chip_id)"
        )

    has_product_stock = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='product_stock'"
    ).fetchone()
    if has_product_stock:
        rows = conn.execute(
            "SELECT product_id, quantity FROM product_stock ORDER BY product_id"
        ).fetchall()

        for row in rows:
            product_id = int(row["product_id"])
            quantity = int(row["quantity"] or 0)

            base_row = conn.execute(
                "SELECT base_price FROM products WHERE id = ?",
                (product_id,),
            ).fetchone()
            if base_row is None:
                continue

            best_chip_id = None
            best_price = float(base_row["base_price"] or 0)

            chip_rows = conn.execute(
                "SELECT id, price FROM product_price_chips WHERE product_id = ? ORDER BY id",
                (product_id,),
            ).fetchall()
            for chip in chip_rows:
                chip_price = float(chip["price"] or 0)
                if chip_price < best_price:
                    best_price = chip_price
                    best_chip_id = int(chip["id"])

            lot_cursor = conn.execute(
                """INSERT INTO stock_lots (product_id, price_chip_id, quantity, remaining_qty)
                   VALUES (?, ?, ?, ?)""",
                (product_id, best_chip_id, quantity, quantity),
            )
            lot_id = int(lot_cursor.lastrowid)

            for _ in range(quantity):
                conn.execute(
                    """INSERT INTO inventory_items (lot_id, uuid, status)
                       VALUES (?, ?, 'available')""",
                    (lot_id, str(uuid.uuid4())),
                )

        conn.execute("DROP TABLE product_stock")


def _migrate_v37_price_bucket_consolidation(conn):
    """Consolidate duplicate stock lots that share the same normalized price bucket."""
    required_tables = {"products", "stock_lots", "inventory_items"}
    existing_tables = {
        row["name"]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
    }
    if not required_tables.issubset(existing_tables):
        return

    product_rows = conn.execute("SELECT id, base_price FROM products").fetchall()
    for product_row in product_rows:
        product_id = int(product_row["id"])
        base_normalized = int(round(float(product_row["base_price"] or 0)))
        chip_rows = conn.execute(
            """SELECT id, price
               FROM product_price_chips
               WHERE product_id = ?
               ORDER BY position ASC, id ASC""",
            (product_id,),
        ).fetchall()
        chip_price_map = {
            int(chip_row["id"]): int(round(float(chip_row["price"] or 0))) for chip_row in chip_rows
        }

        lot_rows = conn.execute(
            """SELECT id, price_chip_id, quantity, remaining_qty, restocked_at
               FROM stock_lots
               WHERE product_id = ?
               ORDER BY restocked_at ASC, id ASC""",
            (product_id,),
        ).fetchall()
        if not lot_rows:
            continue

        bucket_map: dict[int, list] = {}
        for lot_row in lot_rows:
            chip_id = lot_row["price_chip_id"]
            normalized_price = base_normalized if chip_id is None else chip_price_map.get(int(chip_id), base_normalized)
            bucket_map.setdefault(normalized_price, []).append(lot_row)

        for bucket_lots in bucket_map.values():
            if len(bucket_lots) <= 1:
                continue

            canonical_lot = bucket_lots[0]
            canonical_lot_id = int(canonical_lot["id"])
            total_quantity = sum(int(lot["quantity"] or 0) for lot in bucket_lots)
            total_remaining = sum(int(lot["remaining_qty"] or 0) for lot in bucket_lots)

            for lot in bucket_lots[1:]:
                source_lot_id = int(lot["id"])
                conn.execute(
                    "UPDATE inventory_items SET lot_id = ? WHERE lot_id = ?",
                    (canonical_lot_id, source_lot_id),
                )
                conn.execute(
                    "UPDATE stock_movements SET lot_id = ? WHERE lot_id = ?",
                    (canonical_lot_id, source_lot_id),
                )
                conn.execute("DELETE FROM stock_lots WHERE id = ?", (source_lot_id,))

            conn.execute(
                "UPDATE stock_lots SET quantity = ?, remaining_qty = ?, price_chip_id = NULL WHERE id = ?",
                (total_quantity, total_remaining, canonical_lot_id),
            )


def _normalize_accessory_name(name: str) -> str:
    return " ".join(name.strip().lower().split())


def _migrate_v38_accessory_products(conn):
    """Create product-backed accessories from app_config.order_extra values."""
    table_rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()
    existing_tables = {row["name"] for row in table_rows}
    required_tables = {
        "categories",
        "products",
        "app_config",
        "product_attribute_values",
    }
    if not required_tables.issubset(existing_tables):
        return

    category_slug = "phu_kien"
    category_name = "Phụ kiện"
    category_prefix = "PKI"

    category_row = conn.execute(
        "SELECT id FROM categories WHERE slug = ?",
        (category_slug,),
    ).fetchone()
    if category_row is None:
        max_position = conn.execute(
            "SELECT COALESCE(MAX(position), -1) FROM categories WHERE active = 1"
        ).fetchone()[0]
        conn.execute(
            "INSERT INTO categories (slug, name, code_prefix, icon, position, active) VALUES (?, ?, ?, '', ?, 1)",
            (category_slug, category_name, category_prefix, int(max_position) + 1),
        )

    extras_rows = conn.execute(
        "SELECT config_value FROM app_config WHERE config_key = 'order_extra' ORDER BY sort_order, id"
    ).fetchall()
    if not extras_rows:
        return

    products = conn.execute(
        "SELECT id, name, base_price FROM products WHERE category = ?",
        (category_slug,),
    ).fetchall()
    existing_by_norm_name: dict[str, dict] = {
        _normalize_accessory_name(row["name"]): row for row in products if (row["name"] or "").strip()
    }

    next_code_idx_row = conn.execute(
        "SELECT COALESCE(MAX(CAST(SUBSTR(product_code, 5) AS INTEGER)), 0) AS max_idx "
        "FROM products WHERE product_code GLOB 'PKI-[0-9][0-9]'"
    ).fetchone()
    next_code_index = int(next_code_idx_row["max_idx"] or 0) + 1

    for extra_row in extras_rows:
        raw = (extra_row["config_value"] or "").strip()
        if not raw or "|" not in raw:
            continue

        name_part, price_part = raw.split("|", 1)
        accessory_name = name_part.strip()
        normalized_name = _normalize_accessory_name(accessory_name)
        if not normalized_name:
            continue

        try:
            base_price = float(price_part.strip())
        except (TypeError, ValueError):
            continue

        existing = existing_by_norm_name.get(normalized_name)
        if existing is not None:
            product_id = int(existing["id"])
            conn.execute(
                "UPDATE products SET active = 1, category = ? WHERE id = ?",
                (category_slug, product_id),
            )
            conn.execute(
                "UPDATE products SET base_price = ? WHERE id = ? AND ROUND(base_price) != ROUND(?)",
                (base_price, product_id, base_price),
            )
            conn.execute(
                "UPDATE products SET product_code = ? WHERE id = ? AND (product_code = '' OR product_code IS NULL)",
                (f"{category_prefix}-{next_code_index:02d}", product_id),
            )
            next_code_index += 1
        else:
            product_code = f"{category_prefix}-{next_code_index:02d}"
            next_code_index += 1
            cursor = conn.execute(
                """INSERT INTO products (name, category, base_price, cost, recipe_notes, active, product_code)
                   VALUES (?, ?, ?, 0, '', 1, ?)""",
                (accessory_name, category_slug, base_price, product_code),
            )
            product_id = int(cursor.lastrowid)
            existing_by_norm_name[normalized_name] = {
                "id": product_id,
                "name": accessory_name,
                "base_price": base_price,
            }

        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, 'trung_bay', 'true')
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (product_id,),
        )
        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, 'tang_kem', 'true')
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (product_id,),
        )

PRODUCT_ATTRIBUTES_SCHEMA = """
CREATE TABLE IF NOT EXISTS product_attributes (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    attribute_type      TEXT NOT NULL UNIQUE,
    label_vi            TEXT NOT NULL,
    value_type          TEXT NOT NULL DEFAULT 'text',
    applicable_categories TEXT NOT NULL DEFAULT '[]',
    default_value       TEXT DEFAULT '',
    sort_order          INTEGER DEFAULT 0,
    active              INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS product_attribute_values (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id          INTEGER NOT NULL REFERENCES products(id),
    attribute_type      TEXT NOT NULL REFERENCES product_attributes(attribute_type),
    value               TEXT NOT NULL DEFAULT '',
    UNIQUE(product_id, attribute_type)
);
"""

ORDER_ITEMS_ATTRIBUTES_SCHEMA = """
ALTER TABLE order_items ADD COLUMN attributes TEXT DEFAULT '{}';
"""

SEED_PRODUCT_ATTRIBUTES = [
    # (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
    ("cash_amount", "So tien rut", "number", '["banh_kem"]', "0", 1),
    ("cash_fee", "Phi rut tien", "number", '["banh_kem"]', "20000", 2),
]


def _migrate_v23_product_attributes(conn):
    """Seed cash_amount and cash_fee attribute types for banh_kem category."""
    for attr_type, label_vi, value_type, applicable_cats, default_val, sort_order in SEED_PRODUCT_ATTRIBUTES:
        conn.execute(
            """INSERT OR IGNORE INTO product_attributes
               (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (attr_type, label_vi, value_type, applicable_cats, default_val, sort_order),
        )

KNOWLEDGE_BASE_SCHEMA = """
CREATE TABLE IF NOT EXISTS knowledge_entries (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT NOT NULL,
    content     TEXT DEFAULT '',
    type        TEXT NOT NULL DEFAULT 'note',
    tags        TEXT DEFAULT '',
    logged_by   TEXT DEFAULT '',
    source      TEXT DEFAULT 'app',
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_knowledge_entries_type ON knowledge_entries(type);
CREATE INDEX IF NOT EXISTS idx_knowledge_entries_tags ON knowledge_entries(tags);
CREATE INDEX IF NOT EXISTS idx_knowledge_entries_updated ON knowledge_entries(updated_at);

CREATE TABLE IF NOT EXISTS knowledge_entry_photos (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id    INTEGER NOT NULL REFERENCES knowledge_entries(id) ON DELETE CASCADE,
    photo_id    INTEGER NOT NULL REFERENCES photos(id),
    caption     TEXT DEFAULT '',
    position    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_knowledge_photos_entry ON knowledge_entry_photos(entry_id);
"""


def _migrate_v24_rut_tien_toggle(conn):
    """Seed rut_tien attribute type and enable it for all existing banh_kem products."""
    conn.execute(
        """INSERT OR IGNORE INTO product_attributes
           (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
           VALUES ('rut_tien', 'Rút tiền', 'boolean', '[]', 'false', 0)""",
    )
    # Enable rut_tien for all existing banh_kem products
    conn.execute(
        """INSERT OR IGNORE INTO product_attribute_values (product_id, attribute_type, value)
           SELECT id, 'rut_tien', 'true' FROM products WHERE category = 'banh_kem'""",
    )


def _migrate_v25_tien_rut_rename(conn):
    """Rename rut_tien transaction type to tien_rut for consistency with Vietnamese 'Tiền rút'."""
    conn.execute(
        "UPDATE payment_transactions SET type = 'tien_rut' WHERE type = 'rut_tien'",
    )


CATALOG_PHOTO_TAGS_SCHEMA = """
CREATE TABLE IF NOT EXISTS catalog_photo_tags (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    photo_id    INTEGER NOT NULL REFERENCES product_catalog_photos(id),
    tag_key     TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_catalog_photo_tags_photo ON catalog_photo_tags(photo_id);
CREATE INDEX IF NOT EXISTS idx_catalog_photo_tags_tag ON catalog_photo_tags(tag_key);
CREATE UNIQUE INDEX IF NOT EXISTS idx_catalog_photo_tags_unique ON catalog_photo_tags(photo_id, tag_key);
"""

SEED_CATALOG_TAGS = [
    # Audience tags (6) — sort 1-6
    ("catalog_tag", "audience:nam:Nam", 1),
    ("catalog_tag", "audience:nu:Nữ", 2),
    ("catalog_tag", "audience:be-trai:Bé trai", 3),
    ("catalog_tag", "audience:be-gai:Bé gái", 4),
    ("catalog_tag", "audience:cha-me:Cha mẹ", 5),
    ("catalog_tag", "audience:ong-ba:Ông bà", 6),
    # Occasion tags (8) — sort 10-17
    ("catalog_tag", "occasion:sinh-nhat:Sinh nhật", 10),
    ("catalog_tag", "occasion:8-3:8/3", 11),
    ("catalog_tag", "occasion:ky-niem:Kỷ niệm", 12),
    ("catalog_tag", "occasion:dam-cuoi:Đám cưới", 13),
    ("catalog_tag", "occasion:tot-nghiep:Tốt nghiệp", 14),
    ("catalog_tag", "occasion:khai-truong:Khai trương", 15),
    ("catalog_tag", "occasion:noel:Noel", 16),
    ("catalog_tag", "occasion:tet:Tết", 17),
    # Style tags (6) — sort 20-25
    ("catalog_tag", "style:hoa:Hoa", 20),
    ("catalog_tag", "style:trai-cay:Trái cây", 21),
    ("catalog_tag", "style:socola:Socola", 22),
    ("catalog_tag", "style:fondant:Fondant", 23),
    ("catalog_tag", "style:kem-bo:Kem bơ", 24),
    ("catalog_tag", "style:minimalist:Minimalist", 25),
]


def _migrate_v27_seed_catalog_tags(conn):
    """Seed 20 catalog tag entries into app_config."""
    for config_key, config_value, sort_order in SEED_CATALOG_TAGS:
        conn.execute(
            "INSERT OR IGNORE INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            (config_key, config_value, sort_order),
        )


KNOWLEDGE_PIN_SCHEMA = """
ALTER TABLE knowledge_entries ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE knowledge_entries ADD COLUMN pinned_at TEXT;
CREATE INDEX idx_knowledge_pinned ON knowledge_entries(pinned);
"""


def _guard_add_column(conn, table: str, column: str, col_def: str):
    """Add a column only if it doesn't already exist (idempotent forward-only migration)."""
    existing = [r[1] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()]
    if column not in existing:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {col_def}")


def _migrate_v29_add_pin_support(conn):
    """Add pin columns to knowledge_entries (idempotent via PRAGMA guard)."""
    existing = [r[1] for r in conn.execute("PRAGMA table_info(knowledge_entries)").fetchall()]
    if "pinned" not in existing:
        conn.execute("ALTER TABLE knowledge_entries ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0")
    if "pinned_at" not in existing:
        conn.execute("ALTER TABLE knowledge_entries ADD COLUMN pinned_at TEXT")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_knowledge_pinned ON knowledge_entries(pinned)")


def _migrate_v28_cascade_and_reseed(conn):
    """Rebuild catalog_photo_tags with ON DELETE CASCADE and re-seed catalog_tag vocabulary."""
    # Rebuild junction table with ON DELETE CASCADE (SQLite recreate-and-copy)
    conn.executescript(
        """
        CREATE TABLE catalog_photo_tags_new (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            photo_id    INTEGER NOT NULL REFERENCES product_catalog_photos(id) ON DELETE CASCADE,
            tag_key     TEXT NOT NULL,
            created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
        );
        INSERT INTO catalog_photo_tags_new (id, photo_id, tag_key, created_at)
            SELECT id, photo_id, tag_key, created_at FROM catalog_photo_tags;
        DROP TABLE catalog_photo_tags;
        ALTER TABLE catalog_photo_tags_new RENAME TO catalog_photo_tags;
        CREATE INDEX idx_catalog_photo_tags_photo ON catalog_photo_tags(photo_id);
        CREATE INDEX idx_catalog_photo_tags_tag ON catalog_photo_tags(tag_key);
        CREATE UNIQUE INDEX idx_catalog_photo_tags_unique ON catalog_photo_tags(photo_id, tag_key);
        """
    )
    # Clear v27 seed (typos + wrong vocabulary) and re-seed approved F1 vocabulary
    conn.execute("DELETE FROM app_config WHERE config_key = 'catalog_tag'")
    for config_key, config_value, sort_order in SEED_CATALOG_TAGS:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            (config_key, config_value, sort_order),
        )
    # Drop any photo-tag rows referencing keys that no longer exist in vocabulary
    valid_keys = [v.split(":")[1] for _, v, _ in SEED_CATALOG_TAGS]
    placeholders = ",".join("?" * len(valid_keys))
    conn.execute(
        f"DELETE FROM catalog_photo_tags WHERE tag_key NOT IN ({placeholders})",
        valid_keys,
    )


PRODUCT_STOCK_SCHEMA = """
CREATE TABLE IF NOT EXISTS product_stock (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id      INTEGER NOT NULL UNIQUE REFERENCES products(id),
    quantity        INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_product_stock_product ON product_stock(product_id);

CREATE TABLE IF NOT EXISTS stock_movements (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id      INTEGER NOT NULL REFERENCES products(id),
    movement_type   TEXT NOT NULL,
    quantity        INTEGER NOT NULL,
    reason          TEXT DEFAULT '',
    reference_id    TEXT DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_created ON stock_movements(created_at);
"""


PRODUCT_PRICE_CHIPS_SCHEMA = """
CREATE TABLE IF NOT EXISTS product_price_chips (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id  INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    label       TEXT NOT NULL,
    price       REAL NOT NULL,
    position    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_product_price_chips_product ON product_price_chips(product_id);
"""


PRODUCT_ATTRIBUTE_OPTIONS_SCHEMA = """
CREATE TABLE IF NOT EXISTS product_attribute_options (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    attribute_id   INTEGER NOT NULL
                   REFERENCES product_attributes(id) ON DELETE CASCADE,
    value_vi       TEXT NOT NULL,
    sort_order     INTEGER NOT NULL DEFAULT 0,
    active         INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_attr_options_attr ON product_attribute_options(attribute_id);
"""


SEED_NHAN_BANH_OPTIONS = [
    # (value_vi, sort_order)
    ("Sầu riêng", 1),
    ("Sô-cô-la", 2),
    ("Việt quất", 3),
    ("Chanh dây", 4),
    ("Dâu", 5),
]


def _migrate_v31_enum_attributes(conn):
    """Seed nhan_banh enum attribute and its 5 options for banh_kem category."""
    conn.execute(
        """INSERT OR IGNORE INTO product_attributes
           (attribute_type, label_vi, value_type, applicable_categories,
            default_value, sort_order, active)
           VALUES ('nhan_banh', 'Nhân bánh', 'enum', '["banh_kem"]', '', 10, 1)""",
    )
    row = conn.execute(
        "SELECT id FROM product_attributes WHERE attribute_type = 'nhan_banh'"
    ).fetchone()
    if row is None:
        return
    attribute_id = row[0]

    for value_vi, sort_order in SEED_NHAN_BANH_OPTIONS:
        existing = conn.execute(
            "SELECT id FROM product_attribute_options "
            "WHERE attribute_id = ? AND value_vi = ?",
            (attribute_id, value_vi),
        ).fetchone()
        if existing is None:
            conn.execute(
                """INSERT INTO product_attribute_options
                   (attribute_id, value_vi, sort_order, active)
                   VALUES (?, ?, ?, 1)""",
                (attribute_id, value_vi, sort_order),
            )

    default_row = conn.execute(
        "SELECT id FROM product_attribute_options "
        "WHERE attribute_id = ? AND value_vi = 'Sầu riêng'",
        (attribute_id,),
    ).fetchone()
    if default_row is not None:
        conn.execute(
            "UPDATE product_attributes SET default_value = ? WHERE id = ?",
            (str(default_row[0]), attribute_id),
        )


def _migrate_v26_trung_bay_and_stock(conn):
    """Seed trung_bay and tang_kem attribute types; enable tang_kem for existing banh_kem products."""
    conn.execute(
        """INSERT OR IGNORE INTO product_attributes
           (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
           VALUES ('trung_bay', 'Trưng bày', 'boolean', '[]', 'false', 0)""",
    )
    conn.execute(
        """INSERT OR IGNORE INTO product_attributes
           (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
           VALUES ('tang_kem', 'Tặng kèm', 'boolean', '[]', 'false', 0)""",
    )
    # Auto-enable tang_kem for all existing banh_kem products (backwards compatibility)
    conn.execute(
        """INSERT OR IGNORE INTO product_attribute_values (product_id, attribute_type, value)
           SELECT id, 'tang_kem', 'true' FROM products WHERE category = 'banh_kem'""",
    )


def _migrate_v42_backfill_payment_source(conn):
    """Backfill payment_source: 'Shop tiền mặt' for all existing expense events."""
    import json

    rows = conn.execute(
        "SELECT id, data FROM events WHERE type = 'expense'"
    ).fetchall()

    for row in rows:
        try:
            data = json.loads(row["data"]) if row["data"] else {}
        except (json.JSONDecodeError, TypeError):
            data = {}

        if "payment_source" not in data:
            data["payment_source"] = "Shop tiền mặt"
            conn.execute(
                "UPDATE events SET data = ? WHERE id = ?",
                (json.dumps(data), row["id"]),
            )


EVENT_HISTORY_AND_SOFT_DELETE_SCHEMA = """
CREATE TABLE IF NOT EXISTS event_history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id    INTEGER NOT NULL REFERENCES events(id),
    action_type TEXT NOT NULL,
    actor       TEXT DEFAULT '',
    field_name  TEXT DEFAULT '',
    old_value   TEXT DEFAULT '',
    new_value   TEXT DEFAULT '',
    timestamp   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime') || '+07:00')
);

CREATE INDEX IF NOT EXISTS idx_event_history_event ON event_history(event_id);
CREATE INDEX IF NOT EXISTS idx_event_history_timestamp ON event_history(timestamp);
"""


def _migrate_v43_event_history_and_soft_delete(conn):
    """Create event_history table, add soft-delete columns to events,
    backfill expense staff_name values as audit entries."""
    import json

    conn.executescript(EVENT_HISTORY_AND_SOFT_DELETE_SCHEMA)

    _guard_add_column(conn, "events", "deleted_at", "deleted_at TEXT")
    _guard_add_column(conn, "events", "deleted_by", "deleted_by TEXT DEFAULT ''")
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_events_deleted_at ON events(deleted_at)"
    )

    rows = conn.execute(
        "SELECT id, data, logged_by, timestamp FROM events WHERE type = 'expense'"
    ).fetchall()

    for row in rows:
        try:
            data = json.loads(row["data"]) if row["data"] else {}
        except (json.JSONDecodeError, TypeError):
            data = {}

        event_timestamp = row["timestamp"] or ""
        logged_by = (row["logged_by"] or "").strip()

        if isinstance(data, dict) and "staff_name" in data:
            staff_name = data.pop("staff_name")
            if isinstance(staff_name, str) and staff_name.strip():
                staff_name = staff_name.strip()
                conn.execute(
                    """INSERT INTO event_history
                       (event_id, action_type, actor, field_name, old_value, new_value, timestamp)
                       VALUES (?, 'create', ?, 'staff_name', NULL, ?, ?)""",
                    (row["id"], staff_name, staff_name, event_timestamp),
                )

            if not logged_by:
                logged_by = staff_name.strip() if isinstance(staff_name, str) else ""
                if logged_by:
                    conn.execute(
                        "UPDATE events SET logged_by = ? WHERE id = ?",
                        (logged_by, row["id"]),
                    )

        conn.execute(
            "UPDATE events SET data = ? WHERE id = ?",
            (json.dumps(data), row["id"]),
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
    10: {
        "description": "Add amount_paid to orders table",
        "sql": "ALTER TABLE orders ADD COLUMN amount_paid REAL DEFAULT 0;",
    },
    11: {
        "description": "Order photos table for decoration references and chat screenshots",
        "sql": ORDER_PHOTOS_SCHEMA,
    },
    12: {
        "description": "order_items and payment_transactions tables with data migration",
        "sql": ORDER_ITEMS_AND_PAYMENT_TRANSACTIONS_SCHEMA,
        "callable": _migrate_v12_data,
    },
    13: {
        "description": "Per-item birthday/age fields and order_photos work_item_id FK",
        "sql": PER_ITEM_BIRTHDAY_AND_PHOTO_LINK_SCHEMA,
    },
    14: {
        "description": "app_config table for general config (order sources etc), source column on orders",
        "sql": APP_CONFIG_AND_ORDER_SOURCE_SCHEMA,
        "callable": _migrate_v14_seed_order_sources,
    },
    15: {
        "description": "Server logs and log triggers tables for API logging system",
        "sql": SERVER_LOGS_AND_TRIGGERS_SCHEMA,
    },
    16: {
        "description": "Seed staff table (5 members) and add created_by column to orders",
        "sql": "",
        "callable": _migrate_v16_staff_and_created_by,
    },
    17: {
        "description": "Fix staff names to use Vietnamese diacritics",
        "sql": "",
        "callable": _migrate_v17_fix_staff_names,
    },
    18: {
        "description": "Checklist templates and entries tables with seed data",
        "sql": CHECKLIST_SCHEMA,
        "callable": _migrate_v18_seed_checklist,
    },
    19: {
        "description": "Order history audit table for tracking all order changes",
        "sql": ORDER_HISTORY_SCHEMA,
    },
    20: {
        "description": "Add shipping_fee to orders, is_extra and is_gift to order_items, seed shipping presets and extras",
        "sql": SHIPPING_FEE_AND_EXTRAS_SCHEMA,
        "callable": _migrate_v20_seed_shipping_and_extras,
    },
    21: {
        "description": "Add work_ticket_printed_at column to orders for tracking work ticket print state",
        "sql": WORK_TICKET_PRINTED_AT_SCHEMA,
    },
    22: {
        "description": "Knowledge base: knowledge_entries and knowledge_entry_photos tables",
        "sql": KNOWLEDGE_BASE_SCHEMA,
    },
    23: {
        "description": "Product attribute system: product_attributes table, product_attribute_values table, order_items.attributes column, seed cash_amount and cash_fee for banh_kem",
        "sql": PRODUCT_ATTRIBUTES_SCHEMA + ORDER_ITEMS_ATTRIBUTES_SCHEMA,
        "callable": _migrate_v23_product_attributes,
    },
    24: {
        "description": "Add rut_tien per-product toggle: rut_tien attribute type, seed all existing banh_kem products with rut_tien=true",
        "sql": "",
        "callable": _migrate_v24_rut_tien_toggle,
    },
    25: {
        "description": "Rename rut_tien transaction type to tien_rut in payment_transactions for Vietnamese term consistency",
        "sql": "",
        "callable": _migrate_v25_tien_rut_rename,
    },
    26: {
        "description": "Add trung_bay and tang_kem product attributes; create product_stock and stock_movements tables for inventory management",
        "sql": PRODUCT_STOCK_SCHEMA,
        "callable": _migrate_v26_trung_bay_and_stock,
    },
    27: {
        "description": "Create catalog_photo_tags junction table and seed 20 catalog tag entries into app_config",
        "sql": CATALOG_PHOTO_TAGS_SCHEMA,
        "callable": _migrate_v27_seed_catalog_tags,
    },
    28: {
        "description": "Rebuild catalog_photo_tags with ON DELETE CASCADE; re-seed catalog_tag vocabulary with approved F1 keys (fixes v27 typos and wrong keys)",
        "sql": "",
        "callable": _migrate_v28_cascade_and_reseed,
    },
    29: {
        "description": "Add pin support to knowledge entries",
        "sql": "",
        "callable": _migrate_v29_add_pin_support,
    },
    30: {
        "description": "Add product price chips table for preset pricing",
        "sql": PRODUCT_PRICE_CHIPS_SCHEMA,
    },
    31: {
        "description": "Enum product attributes: product_attribute_options table; seed nhan_banh attribute with 5 fillings for banh_kem (Sầu riêng default)",
        "sql": PRODUCT_ATTRIBUTE_OPTIONS_SCHEMA,
        "callable": _migrate_v31_enum_attributes,
    },
    32: {
        "description": "Print tracking: print_log table and work_ticket_printed_by column",
        "sql": PRINT_LOG_AND_PRINTED_BY_SCHEMA,
        "callable": _migrate_v32_print_tracking,
    },
    33: {
        "description": "Reconciliation sessions and line history tables",
        "sql": RECONCILIATIONS_SCHEMA,
    },
    34: {
        "description": "Grouped reconciliation sale rows table",
        "sql": RECONCILIATION_SALE_ROWS_SCHEMA,
    },
    35: {
        "description": "Add per-line waste reason to reconciliation lines",
        "sql": "",
        "callable": _migrate_v35_reconciliation_line_waste_reason,
    },
    36: {
        "description": "Chip-aware inventory schema: stock_lots, inventory_items, option columns, and product_stock migration",
        "sql": STOCK_LOTS_AND_ITEMS_SCHEMA,
        "callable": _migrate_v36_chip_aware_inventory,
    },
    37: {
        "description": "Consolidate stock lots by normalized selling price buckets",
        "sql": "",
        "callable": _migrate_v37_price_bucket_consolidation,
    },
    38: {
        "description": "Migrate order_extra app config rows into product-backed phu_kien accessories",
        "sql": "",
        "callable": _migrate_v38_accessory_products,
    },
    39: {
        "description": "Add public order code column and per-due-date uniqueness index",
        "sql": PUBLIC_ORDER_CODE_SCHEMA,
    },
    40: {
        "description": "Add order_id nullable FK to events table for order incident linking",
        "sql": ORDER_INCIDENT_ORDER_ID_SCHEMA,
    },
    41: {
        "description": "Create event_photos junction table linking events to photo attachments",
        "sql": EVENT_PHOTOS_SCHEMA,
    },
    42: {
        "description": "Backfill payment_source for existing expense events",
        "sql": "",
        "callable": _migrate_v42_backfill_payment_source,
    },
    43: {
        "description": "Event history audit table, soft-delete columns on events, backfill expense staff_name to audit log",
        "sql": "",
        "callable": _migrate_v43_event_history_and_soft_delete,
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
