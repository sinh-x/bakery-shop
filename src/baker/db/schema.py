import os
from typing import Optional

from baker.utils.time import now_utc

INITIAL_SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
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
    delivery_phone  TEXT DEFAULT '',
    items           TEXT NOT NULL DEFAULT '[]',
    total_price     REAL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'new',
    due_date        TEXT,
    due_time        TEXT,
    delivery_type   TEXT DEFAULT 'pickup',
    delivery_address TEXT DEFAULT '',
    notes           TEXT DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    applied_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

CREATE TABLE IF NOT EXISTS payment_transactions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id        INTEGER NOT NULL REFERENCES orders(id),
    amount          REAL NOT NULL,
    type            TEXT NOT NULL DEFAULT 'deposit',
    method          TEXT NOT NULL DEFAULT 'cash',
    note            TEXT DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    timestamp   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S.000', 'now') || 'Z'),
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);
CREATE INDEX IF NOT EXISTS idx_checklist_templates_period ON checklist_templates(period);

CREATE TABLE IF NOT EXISTS checklist_entries (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id     INTEGER NOT NULL REFERENCES checklist_templates(id),
    checklist_date  TEXT NOT NULL,
    completed       INTEGER NOT NULL DEFAULT 0,
    completed_by    TEXT DEFAULT '',
    completed_at    TEXT DEFAULT NULL,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    timestamp   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    printed_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at              TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at                   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    restocked_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);
CREATE INDEX IF NOT EXISTS idx_stock_lots_product_chip ON stock_lots(product_id, price_chip_id);
CREATE INDEX IF NOT EXISTS idx_stock_lots_fifo ON stock_lots(product_id, price_chip_id, restocked_at ASC);

CREATE TABLE IF NOT EXISTS inventory_items (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    lot_id                      INTEGER NOT NULL REFERENCES stock_lots(id),
    uuid                        TEXT NOT NULL UNIQUE,
    status                      TEXT NOT NULL DEFAULT 'available',
    consumed_by_movement_id     INTEGER REFERENCES stock_movements(id),
    created_at                  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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


ALLOWED_TABLES = {
    "orders",
    "reconciliation_lines",
    "stock_movements",
    "order_items",
    "events",
    "journal_entries",
    "payment_transactions",
}


def _guard_add_column(conn, table: str, column: str, col_def: str):
    """Add a column only if it doesn't already exist (idempotent forward-only migration)."""
    assert table in ALLOWED_TABLES, f"table {table!r} not in ALLOWED_TABLES"
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
            created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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
    timestamp   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
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


# ---------------------------------------------------------------------------
# Double-entry accounting schema (migration v44)
# ---------------------------------------------------------------------------

ACCOUNTING_SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    code        TEXT UNIQUE NOT NULL,
    name        TEXT NOT NULL,
    type        TEXT NOT NULL,
    parent_id   INTEGER REFERENCES accounts(id),
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_accounts_type ON accounts(type);
CREATE INDEX IF NOT EXISTS idx_accounts_parent ON accounts(parent_id);

CREATE TABLE IF NOT EXISTS journal_entries (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    description TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now', 'utc')),
    source_type TEXT NOT NULL,
    source_id   INTEGER,
    locked_at   TEXT,
    locked_by   TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_journal_entries_created ON journal_entries(created_at);
CREATE INDEX IF NOT EXISTS idx_journal_entries_source ON journal_entries(source_type, source_id);

CREATE TABLE IF NOT EXISTS journal_lines (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    journal_entry_id INTEGER NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
    account_id       INTEGER NOT NULL REFERENCES accounts(id),
    debit            REAL NOT NULL DEFAULT 0,
    credit           REAL NOT NULL DEFAULT 0,
    description      TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON journal_lines(journal_entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);
"""

# Chart of accounts seed: (code, name, type, parent_code)
# parent_code is None for top-level; otherwise resolved to parent account id.
SEED_CHART_OF_ACCOUNTS = [
    # Assets
    ("1000", "Tài sản", "asset", None),
    ("1100", "Tiền mặt (Cash on Hand)", "asset", "1000"),
    ("1200", "Tài khoản ngân hàng (Bank Account)", "asset", "1000"),
    ("1300", "Hàng tồn kho (Inventory)", "asset", "1000"),
    ("1500", "Phải thu khách hàng (Accounts Receivable)", "asset", "1000"),
    # Liabilities
    ("2000", "Nợ phải trả", "liability", None),
    ("2100", "Tiền khách đặt cọc (Customer Deposits)", "liability", "2000"),
    ("2200", "Tiền ship bus giữ hộ (Bus Shipping Held)", "liability", "2000"),
    ("2300", "Phải trả nhân viên (Staff Payables)", "liability", "2000"),
    ("2400", "Tiền rút tạm giữ (Tien Rut Held)", "liability", "2000"),
    ("2500", "Phải trả người bán (Accounts Payable)", "liability", "2000"),
    # Equity
    ("3000", "Vốn chủ sở hữu", "equity", None),
    ("3100", "Vốn chủ sở hữu (Owner's Equity)", "equity", "3000"),
    # Income
    ("4000", "Doanh thu", "income", None),
    ("4100", "Doanh thu bán hàng (Order Revenue)", "income", "4000"),
    # Expenses — 8 accounts matching the 8 expense categories used in the app
    ("5000", "Chi phí", "expense", None),
    ("5100", "Nguyên liệu (Ingredients)", "expense", "5000"),
    ("5200", "Bao bì (Packaging)", "expense", "5000"),
    ("5300", "Vận chuyển (Delivery/Shipping)", "expense", "5000"),
    ("5400", "Điện/nước (Utilities)", "expense", "5000"),
    ("5500", "Dụng cụ (Tools)", "expense", "5000"),
    ("5600", "Sửa chữa (Equipment Maintenance)", "expense", "5000"),
    ("5700", "Lương/phụ cấp (Staff Salary)", "expense", "5000"),
    ("5800", "Khác (Other Expenses)", "expense", "5000"),
    # COGS
    ("5900", "Giá vốn hàng bán (COGS)", "expense", "5000"),
]

# Map expense category (stored in events.data JSON) → expense account code.
# Keys must match VN labels in app/lib/features/expenses/expense_constants.dart.
EXPENSE_CATEGORY_TO_ACCOUNT_CODE = {
    "Nguyên liệu": "5100",
    "Bao bì": "5200",
    "Vận chuyển": "5300",
    "Điện/nước": "5400",
    "Dụng cụ": "5500",
    "Sửa chữa": "5600",
    "Lương/phụ cấp": "5700",
    "Khác": "5800",
}

# Categories that represent inventory purchases (raw materials, packaging).
# These debit Inventory (1300) instead of an expense account — the cost sits
# in inventory until goods are sold/wasted, at which point COGS (5900) is
# debited and Inventory is credited.
INVENTORY_PURCHASE_CATEGORIES = {"Nguyên liệu", "Bao bì"}

# Map expense payment_source (events.data JSON) → payment account code.
# "Nhân viên ứng trước" creates a sub-account per staff name (handled in backfill).
EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE = {
    "Shop tiền mặt": "1100",
    "TK Phượng VCB": "1200",
    "TK Ân VCB": "1200",
    "Nhân viên ứng trước": "2300",
}

# Map payment_transactions.method → asset account code.
PAYMENT_METHOD_TO_ASSET_CODE = {
    "cash": "1100",
    "card": "1100",
    "transfer": "1200",
}

# Expense debt payment method — records an expense as unpaid debt (FR1, DG-212).
# When ``events.data.payment_method`` equals this value, the expense's vendor
# field serves as the creditor identifier (FR2) and the journal entry debits
# the expense/inventory account and credits the Accounts Payable account 2500
# (FR3) instead of an asset account.
EXPENSE_DEBT_PAYMENT_METHOD = "Nợ"

# Accounts Payable account code — credited when a debt expense is created and
# debited when the debt is settled (Phase 2).
ACCOUNTS_PAYABLE_CODE = "2500"

# payment_transactions.type values that represent cash flowing back to the
# customer (negative deposit). These are recorded as debit Customer Deposits,
# credit Asset — the reverse of a normal deposit/payment.
#
# NOTE (DG-198 reversal): ``tien_rut`` is NOT an outflow. It is a deposit
# inflow — the customer gives cash to the shop for safekeeping — so it journals
# DR Asset / CR 2400 (Tien Rut Held) like a deposit, and at delivery 2400 is
# returned to the customer via a separate ``order`` journal entry. Only
# ``refund`` is an outflow (DR 2100 / CR Asset).
PAYMENT_OUTFLOW_TYPES = {"refund"}

# payment_transactions.type values that represent tien_rut deposit inflows
# (customer cash held by the shop). Journaled DR Asset / CR 2400 at payment
# time; 2400 is cleared via a separate return entry at delivery.
PAYMENT_TIEN_RUT_TYPES = {"tien_rut"}

# Account codes used by the backfill.
CUSTOMER_DEPOSITS_CODE = "2100"
ORDER_REVENUE_CODE = "4100"
COGS_CODE = "5900"
INVENTORY_CODE = "1300"
STAFF_PAYABLES_CODE = "2300"
ACCOUNTS_RECEIVABLE_CODE = "1500"
BUS_SHIPPING_HELD_CODE = "2200"
TIEN_RUT_HELD_CODE = "2400"

# Tolerance (VND) below which an existing order revenue entry's 2100 debit is
# considered already in sync with the current net deposits — no update needed.
# Single source of truth shared by journal_sync, the backfill, pipeline reports,
# and the repair command (review finding Mn-1).
REVENUE_UPDATE_TOLERANCE = 0.005


def _seed_chart_of_accounts(conn) -> None:
    """Seed the chart of accounts (idempotent via INSERT OR IGNORE)."""
    code_to_id: dict[str, int] = {}
    for code, name, acc_type, parent_code in SEED_CHART_OF_ACCOUNTS:
        parent_id = code_to_id.get(parent_code) if parent_code else None
        cursor = conn.execute(
            "INSERT OR IGNORE INTO accounts (code, name, type, parent_id) "
            "VALUES (?, ?, ?, ?)",
            (code, name, acc_type, parent_id),
        )
        if cursor.lastrowid:
            code_to_id[code] = int(cursor.lastrowid)
        else:
            row = conn.execute(
                "SELECT id FROM accounts WHERE code = ?", (code,)
            ).fetchone()
            code_to_id[code] = int(row[0])


def _ensure_staff_payable_sub_account(conn, staff_name: str) -> int:
    """Create (or return) a sub-account under Phải trả nhân viên for a staff member.

    Sub-account code is derived as 23XX where XX is a stable zero-padded index
    assigned by first-seen order. The code is unique within the chart of
    accounts and the parent is the 2300 parent account.
    """
    parent_row = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (STAFF_PAYABLES_CODE,)
    ).fetchone()
    if parent_row is None:
        raise RuntimeError(
            "Staff Payables parent account (2300) missing; seed COA first"
        )
    parent_id = int(parent_row[0])

    existing = conn.execute(
        "SELECT id FROM accounts WHERE parent_id = ? AND name = ?",
        (parent_id, staff_name),
    ).fetchone()
    if existing:
        return int(existing[0])

    count_row = conn.execute(
        "SELECT COUNT(*) FROM accounts WHERE parent_id = ?", (parent_id,)
    ).fetchone()
    next_idx = int(count_row[0]) + 1
    code = f"23{next_idx:02d}"
    cursor = conn.execute(
        "INSERT INTO accounts (code, name, type, parent_id) VALUES (?, ?, 'liability', ?)",
        (code, staff_name, parent_id),
    )
    return int(cursor.lastrowid)


def _account_id_by_code(conn, code: str) -> int:
    row = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (code,)
    ).fetchone()
    if row is None:
        raise RuntimeError(f"Account code {code!r} not found")
    return int(row[0])


def _insert_journal_entry(
    conn,
    *,
    description: str,
    source_type: str,
    source_id,
    lines: list[tuple[int, float, float, str]],
    transaction_date: str | None = None,
) -> int:
    """Create a journal entry with its lines.

    `lines` is a list of (account_id, debit, credit, line_description).
    Double-entry integrity is enforced: total debit must equal total credit.

    `transaction_date` is the business event date the entry relates to (used
    by reports, API filtering, and journal locks). When ``None``, defaults to
    the current local time.
    The audit-only ``created_at`` column is set explicitly via
    ``now_utc()`` — the same pattern used by Event.save(), Order.save(),
    PaymentTransaction.save(), etc.
    """
    total_debit = sum(d for _, d, _, _ in lines)
    total_credit = sum(c for _, _, c, _ in lines)
    if abs(total_debit - total_credit) > 0.005:
        raise RuntimeError(
            f"Double-entry violation: debit={total_debit} credit={total_credit} "
            f"for {source_type}:{source_id}"
        )

    if transaction_date is None:
        transaction_date = conn.execute(
            "SELECT strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'"
        ).fetchone()[0]

    # Transition guard: write transaction_date only when the column exists
    # (added by migration v50). Before v50 is applied, fall back to the legacy
    # INSERT that relies on the created_at DEFAULT. This keeps v44/v46/v47/v48/
    # v49 backfills (which run before v50 on fresh DBs) working unchanged.
    has_col = "transaction_date" in {
        r[1] for r in conn.execute("PRAGMA table_info(journal_entries)").fetchall()
    }
    now = now_utc()
    if has_col:
        cursor = conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, transaction_date, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (description, source_type, source_id, transaction_date, now),
        )
    else:
        cursor = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id, created_at) "
            "VALUES (?, ?, ?, ?)",
            (description, source_type, source_id, now),
        )
    entry_id = int(cursor.lastrowid)
    for account_id, debit, credit, line_desc in lines:
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, account_id, float(debit), float(credit), line_desc),
        )
    return entry_id


def _backfill_expense_journal_entries(conn) -> None:
    """Backfill journal entries for all non-deleted expense events."""
    import json

    rows = conn.execute(
        "SELECT id, summary, data, timestamp FROM events "
        "WHERE type = 'expense' "
        "  AND (deleted_at IS NULL OR deleted_at = '')"
    ).fetchall()

    for row in rows:
        event_id = int(row["id"])
        # Skip if a journal entry already exists for this source (idempotent).
        existing = conn.execute(
            "SELECT 1 FROM journal_entries "
            "WHERE source_type = 'expense' AND source_id = ?",
            (event_id,),
        ).fetchone()
        if existing:
            continue

        event_timestamp = row["timestamp"] or ""

        try:
            data = json.loads(row["data"]) if row["data"] else {}
        except (json.JSONDecodeError, TypeError):
            continue

        amount = data.get("amount_vnd")
        category = data.get("category")
        payment_source = data.get("payment_source")
        if not isinstance(amount, (int, float)) or amount <= 0:
            continue
        if not isinstance(category, str) or not category:
            continue
        if not isinstance(payment_source, str) or not payment_source:
            continue

        expense_code = EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(category)
        if not expense_code:
            continue

        if payment_source == "Nhân viên ứng trước":
            staff_name = (data.get("paid_by_name") or "").strip()
            if not staff_name:
                continue
            payment_account_id = _ensure_staff_payable_sub_account(conn, staff_name)
        else:
            account_code = EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE.get(payment_source)
            if not account_code:
                continue
            payment_account_id = _account_id_by_code(conn, account_code)

        if category in INVENTORY_PURCHASE_CATEGORIES:
            inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
            _insert_journal_entry(
                conn,
                description=f"Expense: {row['summary']}",
                source_type="expense",
                source_id=event_id,
                transaction_date=event_timestamp,
                lines=[
                    (inventory_account_id, float(amount), 0.0, "Nhập kho nguyên vật liệu"),
                    (payment_account_id, 0.0, float(amount), "Thanh toán"),
                ],
            )
        else:
            expense_account_id = _account_id_by_code(conn, expense_code)
            _insert_journal_entry(
                conn,
                description=f"Expense: {row['summary']}",
                source_type="expense",
                source_id=event_id,
                transaction_date=event_timestamp,
                lines=[
                    (expense_account_id, float(amount), 0.0, "Chi phí"),
                    (payment_account_id, 0.0, float(amount), "Thanh toán"),
                ],
            )


def _backfill_payment_transaction_journal_entries(conn) -> None:
    """Backfill journal entries for all payment_transactions."""
    rows = conn.execute(
        "SELECT id, order_id, amount, type, method, created_at "
        "FROM payment_transactions"
    ).fetchall()

    for row in rows:
        pt_id = int(row["id"])
        existing = conn.execute(
            "SELECT 1 FROM journal_entries "
            "WHERE source_type = 'payment_transaction' AND source_id = ?",
            (pt_id,),
        ).fetchone()
        if existing:
            continue

        amount = float(row["amount"] or 0)
        if amount <= 0:
            continue

        method = row["method"] or "cash"
        asset_code = PAYMENT_METHOD_TO_ASSET_CODE.get(method, "1100")
        asset_account_id = _account_id_by_code(conn, asset_code)
        deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
        tien_rut_account_id = _account_id_by_code(conn, TIEN_RUT_HELD_CODE)

        ptype = row["type"] or "deposit"
        transaction_date = row["created_at"] or ""
        if ptype in PAYMENT_OUTFLOW_TYPES:
            # Cash flows back to customer: debit Customer Deposits, credit Asset.
            _insert_journal_entry(
                conn,
                description=f"Payment: {ptype} {amount}",
                source_type="payment_transaction",
                source_id=pt_id,
                transaction_date=transaction_date,
                lines=[
                    (deposits_account_id, amount, 0.0, "Hoàn tiền khách"),
                    (asset_account_id, 0.0, amount, "Trả lại tiền"),
                ],
            )
        elif ptype in PAYMENT_TIEN_RUT_TYPES:
            # Tien rut deposit inflow (DG-198 reversal): customer gives cash to
            # the shop for safekeeping. DR Asset, CR 2400 (Tien Rut Held). 2400
            # is cleared at delivery via a separate return entry.
            _insert_journal_entry(
                conn,
                description=f"Payment: tien_rut {amount}",
                source_type="payment_transaction",
                source_id=pt_id,
                transaction_date=transaction_date,
                lines=[
                    (asset_account_id, amount, 0.0, "Tiền khách gửi giữ hộ"),
                    (tien_rut_account_id, 0.0, amount, "Tiền rút tạm giữ"),
                ],
            )
        else:
            # Customer pays in: debit Asset, credit Customer Deposits.
            _insert_journal_entry(
                conn,
                description=f"Payment: {ptype} {amount}",
                source_type="payment_transaction",
                source_id=pt_id,
                transaction_date=transaction_date,
                lines=[
                    (asset_account_id, amount, 0.0, "Tiền khách đặt/cọc"),
                    (deposits_account_id, 0.0, amount, "Tiền khách đặt cọc"),
                ],
            )


def _backfill_delivered_order_journal_entries(conn) -> None:
    """Backfill revenue conversion + COGS entries for delivered and completed orders.

    Revenue entries are reconciled against current net deposits
    (deposits − tien_rut refunds): stale entries are deleted and recreated so
    the 2100 debit matches the actual deposit balance being converted to
    revenue. Orders with net deposits <= 0 get no revenue entry. This keeps the
    backfill consistent with :func:`_sync_delivered_order_journal`.

    Delegates revenue reconciliation to
    :func:`_reconcile_order_revenue_entry` so that locked entries are reversed
    (never deleted) — the same path used by live sync (review findings M-1, Mn-2).
    """
    from baker.models.payment_transaction import PaymentTransaction
    from baker.services.journal_sync import _reconcile_order_revenue_entry

    orders = conn.execute(
        "SELECT id, order_ref, total_price, due_date, created_at "
        "FROM orders WHERE status IN ('delivered', 'completed')"
    ).fetchall()

    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    cogs_account_id = _account_id_by_code(conn, COGS_CODE)

    for orow in orders:
        order_id = int(orow["id"])
        order_ref = orow["order_ref"]
        # Phase 3: use now_utc() as the authoritative transaction timestamp
        # for backfilled delivered-order journal entries.
        transaction_date = now_utc()

        # Revenue reconciliation — shared with live sync (handles lock checks
        # and idempotent creation via _reconcile_order_revenue_entry).
        _reconcile_order_revenue_entry(
            conn,
            order_id,
            order_ref,
            total_price=float(orow["total_price"] or 0),
        )

        # COGS: for each order_item with product.cost > 0, debit COGS, credit Inventory.
        # Group into one COGS entry per order for performance and clarity.
        existing_cogs = conn.execute(
            "SELECT 1 FROM journal_entries "
            "WHERE source_type = 'order_cogs' AND source_id = ?",
            (order_id,),
        ).fetchone()
        if existing_cogs:
            continue

        items = conn.execute(
            "SELECT oi.product_name, oi.quantity, p.cost "
            "FROM order_items oi "
            "LEFT JOIN products p ON CAST(oi.product_id AS INTEGER) = p.id "
            "WHERE oi.order_id = ? AND oi.is_extra = 0 AND oi.is_gift = 0",
            (order_id,),
        ).fetchall()

        total_cogs = 0.0
        for irow in items:
            cost = float(irow["cost"] or 0)
            qty = int(irow["quantity"] or 0)
            if cost > 0 and qty > 0:
                total_cogs += cost * qty

        if total_cogs > 0:
            _insert_journal_entry(
                conn,
                description=f"Order COGS: {order_ref}",
                source_type="order_cogs",
                source_id=order_id,
                transaction_date=transaction_date,
                lines=[
                    (cogs_account_id, total_cogs, 0.0, "Giá vốn hàng bán"),
                    (inventory_account_id, 0.0, total_cogs, "Xuất kho"),
                ],
            )


def _migrate_v46_fix_old_expense_journal(conn):
    """One-time fix: backfill journal entry for old-format expense event #25.

    Event #25 uses pre-standardization data keys (``amount``, ``currency``
    instead of ``amount_vnd``, ``category``). Map the known fields manually:
    equipment repair → Sửa chữa (5600), Shop tiền mặt → 1100.
    """
    import json

    row = conn.execute(
        "SELECT id, summary, data, timestamp FROM events WHERE id = 25"
    ).fetchone()
    if row is None:
        return

    existing = conn.execute(
        "SELECT 1 FROM journal_entries "
        "WHERE source_type = 'expense' AND source_id = 25"
    ).fetchone()
    if existing:
        return

    try:
        data = json.loads(row["data"]) if row["data"] else {}
    except (json.JSONDecodeError, TypeError):
        return

    amount = data.get("amount")
    payment_source = data.get("payment_source")
    if not isinstance(amount, (int, float)) or amount <= 0:
        return
    if payment_source != "Shop tiền mặt":
        return

    expense_account_id = _account_id_by_code(conn, "5600")
    asset_account_id = _account_id_by_code(conn, "1100")
    _insert_journal_entry(
        conn,
        description=f"Expense: {row['summary']}",
        source_type="expense",
        source_id=25,
        transaction_date=row["timestamp"] or "",
        lines=[
            (expense_account_id, float(amount), 0.0, "Chi phí sửa chữa"),
            (asset_account_id, 0.0, float(amount), "Thanh toán tiền mặt"),
        ],
    )


def _migrate_v47_fix_stale_cogs_entries(conn):
    """One-time fix: delete and re-create order_cogs journal entries that were
    generated with the old cost resolver (which returned 0 for products with
    cost=0 and no cost_history). The current resolver uses baseline fallback
    (30% base_price, 100% for phụ kiện) so stale entries may be understated.

    Idempotent: re-creates via _sync_delivered_order_journal which skips
    existing entries, so we delete stale ones first.
    """
    _seed_chart_of_accounts(conn)
    from baker.services.cost_resolver import resolve_product_cost
    from baker.services.journal_sync import _sync_delivered_order_journal

    stale_ids = []
    rows = conn.execute(
        """
        SELECT je.id AS entry_id, je.source_id AS order_id
        FROM journal_entries je
        WHERE je.source_type = 'order_cogs'
        ORDER BY je.id
        """
    ).fetchall()

    for r in rows:
        entry_id = int(r["entry_id"])
        order_id = int(r["order_id"])

        actual = conn.execute(
            """
            SELECT SUM(jl.debit) FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND a.code = '5900'
            """,
            (entry_id,),
        ).fetchone()[0]
        actual = float(actual or 0)

        items = conn.execute(
            """
            SELECT oi.product_id, oi.quantity
            FROM order_items oi
            WHERE oi.order_id = ? AND oi.is_extra = 0 AND oi.is_gift = 0
            """,
            (order_id,),
        ).fetchall()

        expected = 0.0
        for i in items:
            pid_str = i["product_id"]
            if pid_str is None:
                continue
            try:
                pid = int(pid_str)
            except (TypeError, ValueError):
                continue
            cost = resolve_product_cost(conn, pid)
            qty = int(i["quantity"] or 0)
            expected += cost * qty

        if abs(actual - expected) > 0.01:
            stale_ids.append(entry_id)

    if stale_ids:
        placeholders = ",".join("?" * len(stale_ids))
        conn.execute(
            f"DELETE FROM journal_entries WHERE id IN ({placeholders})",
            stale_ids,
        )

    orders = conn.execute(
        """
        SELECT DISTINCT o.id, o.order_ref
        FROM orders o
        JOIN order_items oi ON oi.order_id = o.id
        WHERE o.status IN ('delivered', 'completed')
        """
    ).fetchall()

    for o in orders:
        _sync_delivered_order_journal(conn, int(o["id"]), o["order_ref"])


def _migrate_v44_double_entry_accounting(conn):
    """Create accounting schema, seed chart of accounts, and backfill journal
    entries for historical expenses, payment_transactions, and delivered orders."""
    conn.executescript(ACCOUNTING_SCHEMA)
    _seed_chart_of_accounts(conn)
    _backfill_expense_journal_entries(conn)
    _backfill_payment_transaction_journal_entries(conn)
    _backfill_delivered_order_journal_entries(conn)


def _migrate_v48_fix_inventory_purchase_entries(conn):
    """One-time fix: delete and re-create expense journal entries for
    Nguyên liệu and Bao bì categories. These were originally recorded as
    debit expense (5100/5200) but should debit Inventory (1300) — the cost
    sits in inventory until goods are sold/wasted (COGS).

    Idempotent: deletes stale entries then re-runs the expense backfill
    which now routes inventory purchases to Inventory (1300).
    """
    import json

    stale_ids = []
    rows = conn.execute(
        "SELECT id, data FROM events WHERE type = 'expense' AND deleted_at IS NULL"
    ).fetchall()

    for row in rows:
        try:
            data = json.loads(row["data"]) if row["data"] else {}
        except (json.JSONDecodeError, TypeError):
            continue
        category = data.get("category")
        if category not in INVENTORY_PURCHASE_CATEGORIES:
            continue

        je = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type = 'expense' AND source_id = ?",
            (row["id"],),
        ).fetchone()
        if je is None:
            continue

        entry_id = int(je["id"])
        lines = conn.execute(
            """
            SELECT a.code FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND jl.debit > 0
            """,
            (entry_id,),
        ).fetchall()
        debit_codes = {l["code"] for l in lines}
        if INVENTORY_CODE not in debit_codes:
            stale_ids.append(entry_id)

    if stale_ids:
        placeholders = ",".join("?" * len(stale_ids))
        conn.execute(
            f"DELETE FROM journal_entries WHERE id IN ({placeholders})",
            stale_ids,
        )

    _backfill_expense_journal_entries(conn)


def _migrate_v49_bus_shipping_backfill(conn):
    """One-time backfill: correct delivered bus orders for the shipping hold & release accounting.

    Prior to the bus shipping separation (FR5), delivered bus orders had:

    1. Stale revenue entries that *included* the shipping fee in the 2100→4100
       conversion (because ``shipping_fee`` was part of ``total_price`` and the
       old reconciler did not exclude it).
    2. No shipping hold entry — the shipping portion sat in 2100 instead of
       being moved to the dedicated 2200 holding account at payment time.
    3. No shipping release entry — nothing debited 2200 / credited 1100 at
       delivery to reflect paying the bus driver.

    This migration iterates every delivered/completed bus order with
    ``shipping_fee > 0`` and corrects all three:

    a. **Revenue fix** — delegates to
       :func:`_reconcile_order_revenue_entry`, which already excludes
       ``shipping_fee`` from the recognized revenue for bus orders (Phase 3).
       Stale entries are reconciled (locked → reversed, unlocked → deleted and
       recreated) so the 2100 debit matches ``net_deposits − shipping_fee``.
    b. **Hold entry** — when no ``order_shipping_hold`` journal entry exists for
       the order, creates one moving the shipping portion from Customer
       Deposits (2100) to Bus Shipping Held (2200): debit 2100, credit 2200.
       This mirrors what the payment-time split (Phase 2) would have produced.
    c. **Release entry** — delegates to
       :func:`_sync_bus_shipping_release_entry`, which creates the
       2200→1100 release entry (Phase 3, FR4) and is idempotent.

    Idempotency (NFR2):

    - Revenue reconciliation is idempotent (no-op when the 2100 debit already
      matches ``net_deposits − shipping_fee``).
    - The hold entry is skipped when an ``order_shipping_hold`` entry already
      exists for the order.
    - The release entry is idempotent by construction.

    Non-bus orders and bus orders with ``shipping_fee == 0`` are untouched
    (FR7 regression guard).
    """
    _seed_chart_of_accounts(conn)

    from baker.services.journal_sync import (
        _reconcile_order_revenue_entry,
        _sync_bus_shipping_release_entry,
    )

    orders = conn.execute(
        "SELECT id, order_ref, total_price, shipping_fee "
        "FROM orders "
        "WHERE status IN ('delivered', 'completed') "
        "  AND delivery_type = 'bus' "
        "  AND shipping_fee > 0"
    ).fetchall()

    deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
    bus_shipping_account_id = _account_id_by_code(conn, BUS_SHIPPING_HELD_CODE)

    for orow in orders:
        order_id = int(orow["id"])
        order_ref = orow["order_ref"]
        shipping_fee = float(orow["shipping_fee"] or 0)
        if shipping_fee <= 0:
            continue

        # (a) Fix the revenue entry: reconcile against net deposits minus the
        # bus shipping fee (Phase 3 logic lives inside the reconciler).
        _reconcile_order_revenue_entry(
            conn,
            order_id,
            order_ref,
            total_price=float(orow["total_price"] or 0),
        )

        # (b) Create the hold entry (2100 → 2200) if not already present.
        # Skip when shipping is already held in 2200 — either via an earlier
        # run of this backfill (order_shipping_hold entry exists) or via the
        # Phase 2 payment-time split (payment_transaction entries crediting
        # 2200). This keeps the backfill idempotent and avoids double-holding.
        existing_hold = conn.execute(
            "SELECT 1 FROM journal_entries "
            "WHERE source_type = 'order_shipping_hold' AND source_id = ?",
            (order_id,),
        ).fetchone()
        if not existing_hold:
            from baker.services.journal_sync import _held_shipping_for_order

            already_held = _held_shipping_for_order(conn, order_id)
            if already_held < shipping_fee - 0.005:
                _insert_journal_entry(
                    conn,
                    description=f"Bus shipping hold: {order_ref}",
                    source_type="order_shipping_hold",
                    source_id=order_id,
                    lines=[
                        (
                            deposits_account_id,
                            shipping_fee,
                            0.0,
                            "Rút ship bus khỏi cọc",
                        ),
                        (
                            bus_shipping_account_id,
                            0.0,
                            shipping_fee,
                            "Tiền ship bus giữ hộ",
                        ),
                    ],
                )

        # (c) Create the release entry (2200 → 1100). Idempotent by construction.
        _sync_bus_shipping_release_entry(conn, order_id, order_ref)


# ---------------------------------------------------------------------------
# Phase 4.1 (DG-192) — journal_entries.transaction_date column + re-backfill
# ---------------------------------------------------------------------------


def _migrate_v50_journal_transaction_date(conn):
    """Add the ``transaction_date`` column to ``journal_entries`` and create an
    index on it.

    The column records the business event date an entry relates to (distinct
    from the audit-only ``created_at`` INSERT timestamp). Existing rows get
    ``transaction_date = ''`` here; migration v51 backfills them from their
    source record dates. The default empty string keeps the column ``NOT NULL``
    while allowing a deferred backfill, and the index supports the report/API/
    lock queries that switch onto ``transaction_date`` in later phases.

    Idempotent: uses ``_guard_add_column`` so re-running on an already-migrated
    DB is a no-op, and ``CREATE INDEX IF NOT EXISTS`` guards the index.
    """
    _guard_add_column(
        conn,
        "journal_entries",
        "transaction_date",
        "transaction_date TEXT NOT NULL DEFAULT ''",
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_journal_entries_transaction_date "
        "ON journal_entries(transaction_date)"
    )


def _backfill_journal_transaction_date(conn) -> None:
    """Re-backfill ``transaction_date`` on existing ``journal_entries`` from
    their source record dates.

    Source-type → source-date mapping (FR10/FR11):

    - ``expense`` → ``events.timestamp`` (via ``source_id`` = event id)
    - ``payment_transaction`` → ``payment_transactions.created_at``
    - ``order`` → ``orders.due_date`` (fallback ``orders.created_at``)
    - ``order_cogs`` → ``orders.due_date`` (fallback ``orders.created_at``)
    - ``waste_cogs`` → ``stock_movements.created_at`` (via ``source_id``)
    - ``owner_capital``, ``owner_draw``, ``staff_reimburse`` → existing
      ``created_at`` (no source record exists; INSERT time is the business date)
    - ``reversal`` → existing ``created_at`` (reversals are corrected in
      Phase 3 via ``_reverse_journal_entry`` copying the original entry's date)
    - ``order_shipping_hold`` / ``order_shipping_release`` → ``orders.due_date``
      (fallback ``orders.created_at``); these originated at order delivery time

    Idempotent (AC10): entries whose ``transaction_date`` is already non-empty
    are skipped, so re-running on a backfilled DB is a no-op.
    """
    conn.execute(
        """
        UPDATE journal_entries
        SET transaction_date = (
            SELECT e.timestamp
            FROM events e
            WHERE e.id = journal_entries.source_id
        )
        WHERE source_type = 'expense'
          AND (transaction_date IS NULL OR transaction_date = '')
        """
    )
    conn.execute(
        """
        UPDATE journal_entries
        SET transaction_date = (
            SELECT pt.created_at
            FROM payment_transactions pt
            WHERE pt.id = journal_entries.source_id
        )
        WHERE source_type = 'payment_transaction'
          AND (transaction_date IS NULL OR transaction_date = '')
        """
    )
    now = now_utc()
    for source_type in ("order", "order_cogs", "order_shipping_hold",
                        "order_shipping_release"):
        conn.execute(
            """
            UPDATE journal_entries
            SET transaction_date = ?
            WHERE source_type = ?
              AND (transaction_date IS NULL OR transaction_date = '')
            """,
            (now, source_type,),
        )
    conn.execute(
        """
        UPDATE journal_entries
        SET transaction_date = (
            SELECT sm.created_at
            FROM stock_movements sm
            WHERE sm.id = journal_entries.source_id
        )
        WHERE source_type = 'waste_cogs'
          AND (transaction_date IS NULL OR transaction_date = '')
        """
    )
    # Manual / reversal source types have no source record — use the existing
    # created_at as the business date (FR6/FR12).
    conn.execute(
        """
        UPDATE journal_entries
        SET transaction_date = created_at
        WHERE source_type IN (
            'owner_capital', 'owner_draw', 'staff_reimburse', 'reversal'
        )
          AND (transaction_date IS NULL OR transaction_date = '')
        """
    )


def _migrate_v51_backfill_journal_transaction_date(conn):
    """Re-backfill existing journal entries with correct ``transaction_date``
    from their source record dates (FR10/AC10).

    Idempotent: only touches entries whose ``transaction_date`` is still empty.
    Runs after v50 (which added the column) so all existing rows are populated.
    """
    _backfill_journal_transaction_date(conn)


def _migrate_v52_reclassify_staff_advances_as_liabilities(conn):
    """Reclassify staff advance accounts (1400 asset) → staff payables (2300
    liability) for databases that already ran the v44 double-entry migration
    with the old 1400 seed (DG-194).

    On a v51-era database the chart of accounts seeded account 1400
    ("Nhân viên ứng trước", asset, parent 1000) plus per-staff sub-accounts
    14XX. The DG-194 seed now inserts 2300 ("Phải trả nhân viên", liability,
    parent 2000) via INSERT OR IGNORE, which leaves the old 1400 parent and
    its 14XX sub-accounts orphaned on existing databases.

    This migration:
      1. If 1400 exists and 2300 does not — UPDATE the 1400 row in place to
         code=2300, type='liability', parent=2000, name="Phải trả nhân viên
         (Staff Payables)".
      2. If both 1400 and 2300 exist (insert-before-migrate edge case) — move
         any 14XX sub-accounts under 2300, then delete the orphaned 1400
         parent.
      3. For each 14XX sub-account: reparent to the 2300 account, change type
         to 'liability', and renumber the code from 14XX → 23XX (zero-padded
         sequential index under 2300 to avoid colliding with seed-created
         23XX sub-accounts).
      4. If neither 1400 nor 2300 exists — no-op; seeding handles fresh DBs.

    Idempotent: re-running on an already-migrated DB finds no 1400 account and
    no 14XX sub-accounts, so every branch is a no-op.
    """
    parent_1400 = conn.execute(
        "SELECT id FROM accounts WHERE code = '1400'"
    ).fetchone()
    parent_2300 = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (STAFF_PAYABLES_CODE,)
    ).fetchone()

    if parent_1400 is None and parent_2300 is None:
        # Fresh install — seeding (INSERT OR IGNORE) handles COA. Nothing to do.
        return

    if parent_1400 is None:
        # Already migrated (no 1400, 2300 present). No-op.
        return

    old_parent_id = int(parent_1400[0])

    if parent_2300 is None:
        # Case 1: reclassify the 1400 row in place to become 2300.
        liabilities_root = conn.execute(
            "SELECT id FROM accounts WHERE code = '2000'"
        ).fetchone()
        parent_id = int(liabilities_root[0]) if liabilities_root else None
        conn.execute(
            "UPDATE accounts SET code = ?, name = ?, type = 'liability', "
            "parent_id = ? WHERE id = ?",
            (
                STAFF_PAYABLES_CODE,
                "Phải trả nhân viên (Staff Payables)",
                parent_id,
                old_parent_id,
            ),
        )
        new_parent_id = old_parent_id
    else:
        # Case 2: 2300 already present (insert-before-migrate). Keep 2300 as
        # the parent and remove the orphaned 1400 parent after reparenting.
        new_parent_id = int(parent_2300[0])

    # Reparent and renumber each 14XX sub-account. Codes are rewritten to
    # 23XX using a zero-padded sequential index starting after any existing
    # 23XX sub-accounts so we never collide with seed- or backfill-created
    # payables.
    existing_count_row = conn.execute(
        "SELECT COUNT(*) FROM accounts WHERE parent_id = ?", (new_parent_id,)
    ).fetchone()
    next_idx = int(existing_count_row[0]) if existing_count_row else 0

    subs = conn.execute(
        "SELECT id, name FROM accounts WHERE parent_id = ? ORDER BY id",
        (old_parent_id,),
    ).fetchall()
    for sub in subs:
        next_idx += 1
        new_code = f"23{next_idx:02d}"
        conn.execute(
            "UPDATE accounts SET code = ?, type = 'liability', parent_id = ? "
            "WHERE id = ?",
            (new_code, new_parent_id, int(sub["id"])),
        )

    if parent_2300 is not None:
        # Case 2 cleanup: the 1400 parent is now empty (all subs reparented).
        conn.execute("DELETE FROM accounts WHERE id = ?", (old_parent_id,))


def _migrate_v53_payment_transaction_invalidation(conn):
    """Add soft-delete (invalidation) columns to ``payment_transactions``.

    Mirrors the v43 events soft-delete pattern (``deleted_at``/``deleted_by``):
    invalidation is a soft-delete that preserves the row for audit while
    excluding it from payment totals, completion guards, and journal listings.

    Adds ``invalidated_at TEXT`` (NULL = valid) and ``invalidated_by TEXT
    DEFAULT ''`` plus an index on ``invalidated_at`` for fast filtering of
    valid (non-NULL) rows.

    Idempotent: re-running on an already-migrated DB is a no-op because
    ``_guard_add_column`` checks ``PRAGMA table_info`` before altering and
    ``CREATE INDEX IF NOT EXISTS`` skips existing indexes.
    """
    _guard_add_column(conn, "payment_transactions", "invalidated_at", "invalidated_at TEXT")
    _guard_add_column(
        conn, "payment_transactions", "invalidated_by", "invalidated_by TEXT DEFAULT ''"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_payment_transactions_invalidated_at "
        "ON payment_transactions(invalidated_at)"
    )


def _migrate_v54_add_account_2400(conn):
    """Ensure account 2400 (Tien Rut Held) exists in chart of accounts.

    DG-199 Phase 4.2. This calls the existing _seed_chart_of_accounts() which
    uses INSERT OR IGNORE for every account, so re-running v54 on an
    already-migrated DB is a no-op (idempotent by design).
    """
    _seed_chart_of_accounts(conn)


JOURNAL_SYNC_FAILURE_LOG_SCHEMA = """
CREATE TABLE IF NOT EXISTS journal_sync_failure_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    source_type     TEXT NOT NULL,
    source_id       INTEGER,
    error_message   TEXT NOT NULL,
    stack_trace     TEXT DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_failure_log_type_id ON journal_sync_failure_log(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_failure_log_created ON journal_sync_failure_log(created_at);
"""


def _migrate_v65_journal_sync_failure_log(conn):
    """Create journal_sync_failure_log table for per-source audit records (DG-226 Phase 1).

    Idempotent: uses CREATE TABLE IF NOT EXISTS and CREATE INDEX IF NOT EXISTS.
    """
    conn.executescript(JOURNAL_SYNC_FAILURE_LOG_SCHEMA)


NEGATIVE_BALANCE_SCHEMA = """
CREATE TABLE IF NOT EXISTS negative_balance (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id      INTEGER NOT NULL REFERENCES products(id),
    price_chip_id   INTEGER REFERENCES product_price_chips(id),
    qty             INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_negative_balance_product_chip
    ON negative_balance(product_id, price_chip_id);
"""


def _migrate_v62_negative_balance(conn):
    """Create negative_balance table for tracking oversold stock (DG-200 Phase 1).

    Idempotent: uses CREATE TABLE IF NOT EXISTS and CREATE INDEX IF NOT EXISTS,
    so re-running on an already-migrated DB is a no-op.
    """
    conn.executescript(NEGATIVE_BALANCE_SCHEMA)


COST_HISTORY_SCHEMA = """
CREATE TABLE IF NOT EXISTS cost_history (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id      INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    cost            REAL NOT NULL DEFAULT 0,
    effective_from  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_cost_history_product_effective
    ON cost_history(product_id, effective_from);
"""

# Category slug for accessories. Costs for these products default to 100% of
# base_price when no cost_history record exists; all other categories use 30%.
PHU_KIEN_CATEGORY = "phu_kien"


def _baseline_cost_for_product(
    category: str, base_price: float, *, price_override: Optional[float] = None
) -> float:
    """Baseline cost: 30% of the anchor price for non-phụ-kiện, 100% for phụ kiện.

    The anchor is ``price_override`` when provided (the actual selling price),
    otherwise ``base_price``. Phụ kiện always uses ``base_price`` regardless of
    ``price_override`` — the 100% rule is intentional and unchanged (Non-Goal:
    do not change how phụ kiện COGS works). The 30% non-phụ-kiện rule shifts to
    the selling price when available so COGS reflects the actual sale value
    rather than the catalog base price (DG-208 Phase 1, FR1).
    """
    if category == PHU_KIEN_CATEGORY:
        return float(base_price)
    anchor = float(price_override) if price_override is not None else float(base_price)
    return round(anchor * 0.30, 2)


def _backfill_order_items_cost_at_sale(conn) -> None:
    """Populate cost_at_sale on existing delivered order_items using the
    baseline rule (30% non-phụ-kiện / 100% phụ-kiện).

    The anchor is the actual selling price (``unit_price``) when available,
    falling back to ``base_price`` otherwise (DG-208 Phase 2, FR2/NFR2). For
    items whose product cannot be resolved (e.g. custom-product codes like
    ``BKS-DG-01`` that have no matching ``products`` row), the 30% non-phụ-kiện
    baseline is applied to ``unit_price`` — phụ kiện is a real product category
    that is always resolvable, so unresolvable items are never phụ kiện.

    Idempotent: only updates order_items whose cost_at_sale is 0. Cost_history
    is not consulted at backfill time because historical cost records do not
    exist before this migration; the baseline rule is the documented estimate.
    """
    rows = conn.execute(
        """
        SELECT oi.id AS item_id, oi.unit_price,
               p.category, p.base_price
        FROM order_items oi
        JOIN orders o ON o.id = oi.order_id
        LEFT JOIN products p ON CAST(oi.product_id AS INTEGER) = p.id
        WHERE o.status IN ('delivered', 'completed')
          AND oi.is_extra = 0
          AND oi.is_gift = 0
          AND (oi.cost_at_sale IS NULL OR oi.cost_at_sale = 0)
        """
    ).fetchall()
    for row in rows:
        category = row["category"] if row["category"] is not None else ""
        unit_price = float(row["unit_price"] or 0)
        base_price = float(row["base_price"] or 0)
        # Anchor on the actual selling price (unit_price) when available, else
        # base_price. Unresolvable products (no products row, e.g. custom
        # codes like BKS-DG-01) are never phụ kiện — phụ kiện is always a real
        # resolvable category — so they correctly fall through the 30% non-
        # phụ-kiện branch (DG-208 Phase 2, fixes Order #1091 missing COGS).
        anchor = unit_price if unit_price > 0 else base_price
        cost = _baseline_cost_for_product(category, base_price, price_override=anchor)
        if cost > 0:
            conn.execute(
                "UPDATE order_items SET cost_at_sale = ? WHERE id = ?",
                (cost, int(row["item_id"])),
            )


def _migrate_v45_cost_history_and_cost_at_sale(conn):
    """Create cost_history table, add cost_at_sale column to order_items, and
    backfill existing delivered order_items with baseline costs.

    Idempotent: re-running on an already-migrated DB produces no errors and no
    duplicate data. The cost_history table uses CREATE TABLE IF NOT EXISTS; the
    cost_at_sale column is added via _guard_add_column; the backfill UPDATE only
    touches rows whose cost_at_sale is still 0 (NULL treated as 0)."""
    conn.executescript(COST_HISTORY_SCHEMA)
    _guard_add_column(conn, "order_items", "cost_at_sale", "cost_at_sale REAL DEFAULT 0")
    _backfill_order_items_cost_at_sale(conn)


# ---------------------------------------------------------------------------
# UTC timestamp standardization (migration v55) — DG-202 Phase 2
# ---------------------------------------------------------------------------
#
# Migrates existing timestamp columns from bare/`+07:00` formats to UTC with
# `Z` suffix. Two patterns:
#   1. Bare timestamps (no suffix) — append `Z`. Production Docker runs UTC, so
#      existing bare values are already UTC and only need the suffix.
#   2. `+07:00`-suffixed timestamps — subtract 7 hours and append `Z`. This
#      affects `event_history.timestamp` and a small number of `events.timestamp`
#      rows written by an older code path.
#
# Excluded by design (see DG-202 §5 Out of Scope):
#   - `schema_version.applied_at` — historical migration records.
#   - `server_logs.timestamp` — 430K+ rows, low value to normalize.
#   - Date-only columns: `orders.due_date`, `orders.due_time`,
#     `checklist_entries.checklist_date`, `reconciliation_sessions.reconciliation_date`,
#     `journal_entries.transaction_date` (mixed date/timestamp; treated as date-only).
#
# Idempotent: bare rows already ending in `Z` are skipped; rows already ending in
# `Z` (post-conversion) are skipped by the `+07:00` matcher. Re-running on a
# fully-migrated DB is a no-op.

_TIMESTAMP_COLUMNS_V55 = [
    ("accounts", "created_at"),
    ("app_config", "created_at"),
    ("catalog_photo_tags", "created_at"),
    ("checklist_entries", "created_at"),
    ("checklist_entries", "completed_at"),
    ("checklist_templates", "created_at"),
    ("cost_history", "effective_from"),
    ("cost_history", "created_at"),
    ("event_history", "timestamp"),
    ("event_photos", "created_at"),
    ("events", "timestamp"),
    ("events", "deleted_at"),
    ("inventory", "updated_at"),
    ("inventory_items", "created_at"),
    ("journal_entries", "created_at"),
    ("journal_entries", "locked_at"),
    ("knowledge_entries", "created_at"),
    ("knowledge_entries", "updated_at"),
    ("knowledge_entry_photos", "created_at"),
    ("log_triggers", "created_at"),
    ("order_history", "timestamp"),
    ("order_items", "created_at"),
    ("order_photos", "created_at"),
    ("orders", "created_at"),
    ("orders", "updated_at"),
    ("orders", "work_ticket_printed_at"),
    ("payment_transactions", "created_at"),
    ("payment_transactions", "invalidated_at"),
    ("photos", "created_at"),
    ("print_log", "printed_at"),
    ("product_catalog_photos", "created_at"),
    ("product_price_chips", "created_at"),
    ("reconciliation_lines", "created_at"),
    ("reconciliation_sale_rows", "created_at"),
    ("reconciliation_sessions", "created_at"),
    ("staff", "created_at"),
    ("stock_lots", "restocked_at"),
    ("stock_lots", "created_at"),
    ("stock_movements", "created_at"),
]


def _migrate_v55_utc_timestamp_standardization(conn):
    """Append `Z` to bare timestamps and convert `+07:00`-suffixed timestamps
    to UTC `Z` across all in-scope timestamp columns (DG-202 Phase 2).

    Runs as a single transaction (the caller wraps migrations in commit/rollback).
    Idempotent: already-`Z`-suffixed rows are skipped on re-run.
    """
    for table, column in _TIMESTAMP_COLUMNS_V55:
        # 1) Bare timestamps: append 'Z'. Skip rows that already end in 'Z',
        #    have a '+offset' suffix, or are date-only (no 'T').
        conn.execute(
            f"""UPDATE "{table}" SET "{column}" = "{column}" || 'Z'
                WHERE "{column}" IS NOT NULL
                  AND "{column}" != ''
                  AND "{column}" NOT LIKE '%Z'
                  AND "{column}" NOT LIKE '%+%'
                  AND "{column}" LIKE '%T%'""",
        )
        # 2) +07:00-suffixed timestamps: subtract 7 hours and append 'Z'.
        #    Preserve fractional seconds when present (re-append the original
        #    fraction after the strftime, which truncates to whole seconds).
        #    The CASE keeps the whole-seconds path simple while retaining the
        #    fraction for rows that carry one.
        conn.execute(
            f"""UPDATE "{table}" SET "{column}" =
                    CASE
                        WHEN substr("{column}", 20, 1) = '.' THEN
                            strftime('%Y-%m-%dT%H:%M:%S', substr("{column}", 1, 19), '-7 hours')
                            || '.' || substr("{column}", 21, length("{column}") - 26) || 'Z'
                        ELSE
                            strftime('%Y-%m-%dT%H:%M:%SZ', substr("{column}", 1, 19), '-7 hours')
                    END
                WHERE "{column}" LIKE '%+07:00'""",
        )


CUSTOMERS_SCHEMA = """
CREATE TABLE IF NOT EXISTS customers (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    phone       TEXT DEFAULT '',
    search_name TEXT DEFAULT '',
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_customers_search_name ON customers(search_name);
"""


CUSTOMER_PHONES_SCHEMA = """
CREATE TABLE IF NOT EXISTS customer_phones (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id  INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    phone        TEXT NOT NULL,
    is_primary   INTEGER NOT NULL DEFAULT 0,
    created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_customer_phones_customer_id ON customer_phones(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_phones_phone ON customer_phones(phone);
"""


def _migrate_v56_customers_and_order_link(conn):
    """Create customers table, add customer_id FK to orders, auto-link existing
    orders to customers by phone match (DG-182 Phase 1).

    Phone is NOT unique — multiple customers may share a phone (NFR4). Auto-match
    links each existing order to the first customer (lowest id) sharing that
    phone. Orders with no phone or no matching customer remain customer_id=NULL.
    """
    # 1) Add customer_id column to orders (nullable FK)
    _guard_add_column(conn, "orders", "customer_id", "customer_id INTEGER REFERENCES customers(id)")

    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id)"
    )

    # 2) Auto-link existing orders to customers by phone match.
    #    For each distinct phone that matches at least one customer, link orders
    #    with that phone to the lowest-id customer sharing the phone. Only link
    #    non-empty phones to avoid matching all walk-in orders together.
    conn.execute(
        """
        UPDATE orders
        SET customer_id = (
            SELECT MIN(c.id) FROM customers c
            WHERE c.phone = orders.customer_phone
              AND c.phone != ''
              AND c.phone IS NOT NULL
        )
        WHERE customer_id IS NULL
          AND customer_phone != ''
          AND customer_phone IS NOT NULL
          AND EXISTS (
              SELECT 1 FROM customers c
              WHERE c.phone = orders.customer_phone
                AND c.phone != ''
                AND c.phone IS NOT NULL
          )
        """
    )


import unicodedata


def _strip_diacritics(text: str) -> str:
    """Remove Vietnamese diacritics for case-insensitive search.

    Converts 'Nguyễn Văn Đức' → 'nguyen van duc' so searching for
    'duc' or 'Đức' or 'đức' all match.
    """
    nfkd = unicodedata.normalize('NFKD', text)
    ascii_form = ''.join(ch for ch in nfkd if not unicodedata.combining(ch))
    return ascii_form.lower().replace('đ', 'd').replace('Đ', 'd')


def _normalize_phone(phone: str) -> str:
    """Normalize a phone number for grouping/deduplication.

    Strips whitespace, dots, and dashes. All phones are already in 84-prefix
    format (no leading "+"), so no prefix normalization is applied here. The
    normalized form is used only for grouping; the original phone is preserved
    in the customer record (FR2).

    >>> _normalize_phone("84 912 345 678")
    '84912345678'
    >>> _normalize_phone("84-912-345-678")
    '84912345678'
    >>> _normalize_phone("84.912.345.678")
    '84912345678'
    >>> _normalize_phone("84912345678")
    '84912345678'
    >>> _normalize_phone("")
    ''
    """
    if not phone:
        return ""
    return phone.replace(" ", "").replace(".", "").replace("-", "")


def _pick_most_common_name(names: list[str]) -> str:
    """Pick the most frequent customer name from a list of name variants.

    Comparison is case-insensitive and trims whitespace (FR3). On a tie, the
    name that sorts first alphabetically (case-insensitive) wins. The returned
    name preserves the original casing/whitespace of the first occurrence of
    the winning normalized form.

    >>> _pick_most_common_name(["Nguyen Van A"])
    'Nguyen Van A'
    >>> _pick_most_common_name(["Nguyen Van A", "Nguyen Van A", "Bob"])
    'Nguyen Van A'
    >>> _pick_most_common_name(["Nguyen Van A", "nguyen van a", "Bob"])
    'Nguyen Van A'
    >>> _pick_most_common_name(["  Nguyen Van A  ", "nguyen van a", "Bob"])
    'Nguyen Van A'
    >>> _pick_most_common_name(["Bob", "Alice"])  # tie -> Alice (alphabetical)
    'Alice'
    >>> _pick_most_common_name([])
    ''
    """
    if not names:
        return ""

    # Group original names by their normalized (lowercased, stripped) form,
    # preserving the first-seen original form within each group (stripped of
    # surrounding whitespace so the returned name is clean per FR3).
    groups: dict[str, list[str]] = {}
    counts: dict[str, int] = {}
    for name in names:
        key = (name or "").strip().lower()
        if key not in groups:
            groups[key] = []
        groups[key].append(name)
        counts[key] = counts.get(key, 0) + 1

    # Highest count wins; ties broken by alphabetical order of the key.
    best_key = min(counts, key=lambda k: (-counts[k], k))
    first = groups[best_key][0]
    return (first or "").strip()


def _migrate_v57_generate_customers_from_orders(conn):
    """Generate customer records from existing orders and link orders to them.

    DG-204 Phase 2. Scans all orders that have no customer_id yet, groups them
    by normalized phone (FR1/FR2), resolves a single customer name per group via
    the most-common-name rule (FR3), applies the earliest-order-wins rule for a
    phone shared by distinct name groups (FR4), inserts customer records via
    direct SQLite (FR5), links matching orders via customer_id (FR6), and also
    creates customers for phone-less orders using customer_name (FR8). The
    migration is idempotent (FR7): orders already linked and phones that already
    have a matching customer are skipped. A summary line is logged (FR9).

    Reusing `_normalize_phone()` and `_pick_most_common_name()` from Phase 1 and
    `Customer.save(conn)` for inserts, following the v56 migration-callable
    pattern (direct SQL, no API round-trips — NFR1/NFR3). The whole callable
    runs within the `ensure_schema` migration transaction (NFR2).
    """
    import logging

    from baker.models.customer import Customer

    logger = logging.getLogger("baker.db")

    # Existing customer phones (normalized) for idempotency — FR7/NFR4.
    existing_phones: dict[str, int] = {}
    for crow in conn.execute("SELECT id, phone FROM customers").fetchall():
        nphone = _normalize_phone(crow["phone"])
        if nphone and nphone not in existing_phones:
            existing_phones[nphone] = crow["id"]

    # Existing customers keyed by case-insensitive name (for phone-less links).
    existing_names: dict[str, int] = {}
    for crow in conn.execute("SELECT id, name FROM customers").fetchall():
        key = (crow["name"] or "").strip().lower()
        if key and key not in existing_names:
            existing_names[key] = crow["id"]

    customers_created = 0
    orders_linked = 0

    def _link_order(conn, oid: int, cust_id: int) -> None:
        nonlocal orders_linked
        cur = conn.execute(
            "UPDATE orders SET customer_id = ? WHERE id = ? AND customer_id IS NULL",
            (cust_id, oid),
        )
        if cur.rowcount > 0:
            orders_linked += 1

    # ── Phone-having orders (FR1–FR7) ─────────────────────────────────────
    # Scan orders with non-empty customer_phone where customer_id IS NULL,
    # ordered so the first row per phone is the earliest order.
    phone_rows = conn.execute(
        """
        SELECT id, customer_name, customer_phone, created_at
        FROM orders
        WHERE customer_id IS NULL
          AND customer_phone IS NOT NULL
          AND customer_phone != ''
        ORDER BY created_at ASC, id ASC
        """
    ).fetchall()

    # Group orders by normalized phone (FR1/FR2).
    phone_groups: dict[str, list[tuple[int, str]]] = {}
    for orow in phone_rows:
        nphone = _normalize_phone(orow["customer_phone"])
        if not nphone:
            continue
        phone_groups.setdefault(nphone, []).append(
            (orow["id"], orow["customer_name"] or "")
        )

    for nphone, orders in phone_groups.items():
        # Idempotency (FR7): phone already has a customer — link its orders.
        if nphone in existing_phones:
            cust_id = existing_phones[nphone]
            for oid, _name in orders:
                _link_order(conn, oid, cust_id)
            continue

        # Partition orders into distinct name groups (FR4). The group key uses
        # the same case-insensitive, trimmed rule as _pick_most_common_name so
        # name variants collapse into one group (FR3).
        name_to_orders: dict[str, list[tuple[int, str]]] = {}
        for oid, name in orders:
            gkey = (name or "").strip().lower()
            name_to_orders.setdefault(gkey, []).append((oid, name))

        # Resolve a representative name per group and capture each group's
        # earliest order. `orders` is already ASC by created_at/id, and we
        # appended in that order, so the first entry per group is earliest.
        group_info: list[tuple[str, list[tuple[int, str]], str]] = []
        for gkey, gorders in name_to_orders.items():
            resolved_name = _pick_most_common_name([o[1] for o in gorders])
            group_info.append((gkey, gorders, resolved_name))

        if not group_info:
            continue

        # FR4: earliest-order-wins. `orders` was ordered by created_at ASC,
        # id ASC, and `name_to_orders` preserved that insertion order, so the
        # first group seen has the earliest order and wins the phone. Iterate
        # in insertion order; idx 0 keeps the phone, later groups get "".
        for idx, (_gkey, gorders, resolved_name) in enumerate(group_info):
            phone_assigned = nphone if idx == 0 else ""
            cust = Customer(name=resolved_name or "Khách", phone=phone_assigned)
            cust_id = cust.save(conn)
            customers_created += 1
            # Track the new customer so a later phone group can reuse it.
            if phone_assigned:
                existing_phones[nphone] = cust_id
            # Also register the name so phone-less orders with the same name
            # reuse this customer instead of creating a duplicate.
            name_key = (resolved_name or "Khách").strip().lower()
            if name_key and name_key not in existing_names:
                existing_names[name_key] = cust_id
            for oid, _name in gorders:
                _link_order(conn, oid, cust_id)

    # ── Phone-less orders with a name (FR8) ───────────────────────────────
    nameless_rows = conn.execute(
        """
        SELECT id, customer_name
        FROM orders
        WHERE customer_id IS NULL
          AND (customer_phone IS NULL OR customer_phone = '')
          AND customer_name IS NOT NULL
          AND customer_name != ''
        """
    ).fetchall()

    # Group phone-less orders by case-insensitive name so a single customer is
    # created per distinct name, not per order.
    nameless_groups: dict[str, list[int]] = {}
    nameless_names: dict[str, list[str]] = {}
    for orow in nameless_rows:
        key = (orow["customer_name"] or "").strip().lower()
        if not key:
            continue
        nameless_groups.setdefault(key, []).append(orow["id"])
        nameless_names.setdefault(key, []).append(orow["customer_name"])

    for key, oids in nameless_groups.items():
        # Idempotency (FR7): name already has a customer — link its orders.
        if key in existing_names:
            cust_id = existing_names[key]
            for oid in oids:
                _link_order(conn, oid, cust_id)
            continue
        resolved = _pick_most_common_name(nameless_names[key])
        cust = Customer(name=resolved, phone="")
        cust_id = cust.save(conn)
        customers_created += 1
        existing_names[key] = cust_id
        for oid in oids:
            _link_order(conn, oid, cust_id)

    # FR9: summary log.
    logger.info("Đã tạo %d khách hàng, liên kết %d đơn hàng.", customers_created, orders_linked)


def _migrate_v59_deduplicate_customers(conn):
    """Merge duplicate customers that share the same case-insensitive name.

    DG-205 follow-up. v57 could create duplicate customers when phone-having
    and phone-less orders shared the same name but the name was not tracked in
    ``existing_names`` (fixed in v57 itself, but existing DBs may have dupes).
    This migration groups customers by case-insensitive trimmed name, keeps the
    one with the most orders (earliest id as tiebreak), reassigns all orders
    from duplicates to the winner, and deletes the duplicates. Idempotent:
    re-running when no duplicates exist is a no-op.
    """
    import logging

    logger = logging.getLogger("baker.db")

    # Group customers by case-insensitive trimmed name.
    rows = conn.execute(
        "SELECT id, name FROM customers ORDER BY id ASC"
    ).fetchall()
    name_groups: dict[str, list[int]] = {}
    for row in rows:
        key = (row["name"] or "").strip().lower()
        if not key:
            continue
        name_groups.setdefault(key, []).append(row["id"])

    merged = 0
    for key, ids in name_groups.items():
        if len(ids) <= 1:
            continue
        # Keep the customer with the most orders; earliest id breaks ties.
        best_id = ids[0]
        best_count = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (best_id,)
        ).fetchone()[0]
        for cid in ids[1:]:
            cnt = conn.execute(
                "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (cid,)
            ).fetchone()[0]
            if cnt > best_count:
                best_id = cid
                best_count = cnt
        # Reassign orders from duplicates to the winner.
        for cid in ids:
            if cid == best_id:
                continue
            conn.execute(
                "UPDATE orders SET customer_id = ? WHERE customer_id = ?",
                (best_id, cid),
            )
            conn.execute("DELETE FROM customer_phones WHERE customer_id = ?", (cid,))
            conn.execute("DELETE FROM customers WHERE id = ?", (cid,))
            merged += 1

    if merged:
        logger.info("Đã gộp %d khách hàng trùng tên.", merged)


def _migrate_v58_customer_phones(conn):
    """Create customer_phones table and migrate existing customers.phone into it.

    DG-205 Phase 1. Creates the normalized ``customer_phones`` table (FR1) and
    moves each existing non-empty ``customers.phone`` value into a row with
    ``is_primary=1`` (FR2). The ``customers.phone`` denormalized column is
    retained as a backward-compatible fallback (NFR4/AC2) — it is NOT modified.

    The migration is idempotent (NFR1): before inserting, it checks whether the
    customer already has any row in ``customer_phones`` and skips those that do.
    Re-running v58 therefore never duplicates phone rows (AC1).

    The DDL (table + indexes on ``customer_id`` and ``phone``) is applied via
    the ``CUSTOMER_PHONES_SCHEMA`` ``sql`` entry in ``MIGRATIONS``; this
    callable only performs the data backfill, following the v56/v57 pattern of
    separating schema (``sql``) from data (``callable``).
    """
    import logging

    logger = logging.getLogger("baker.db")

    # Idempotency (NFR1): collect customer_ids that already have phone rows.
    # This covers re-runs of v58 and DBs where phone rows were added by the API
    # before v58 finished — either way we never insert a duplicate.
    customers_with_phones = {
        row[0]
        for row in conn.execute("SELECT DISTINCT customer_id FROM customer_phones").fetchall()
    }

    migrated = 0
    # Move each existing non-empty customers.phone into customer_phones as the
    # primary phone (FR2). Empty/NULL phones are skipped (no point inserting a
    # blank primary phone row).
    for crow in conn.execute(
        "SELECT id, phone FROM customers WHERE phone IS NOT NULL AND phone != ''"
    ).fetchall():
        cust_id = crow["id"]
        phone = crow["phone"]
        if cust_id in customers_with_phones:
            continue
        # M-1: normalize the backfilled phone so customer_phones rows are
        # consistent with rows written by _sync_customer_phones (which now
        # applies _normalize_phone). Legacy customers.phone is left as-is.
        nphone = _normalize_phone(phone)
        if not nphone:
            continue
        conn.execute(
            "INSERT INTO customer_phones (customer_id, phone, is_primary) VALUES (?, ?, 1)",
            (cust_id, nphone),
        )
        customers_with_phones.add(cust_id)
        migrated += 1

    logger.info("Đã chuyển %d số điện thoại vào customer_phones.", migrated)


CUSTOMER_YEAR_SUMMARY_SCHEMA = """
CREATE TABLE IF NOT EXISTS customer_year_summary (
    customer_id  INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    year         INTEGER NOT NULL,
    order_count  INTEGER NOT NULL DEFAULT 0,
    total_volume REAL    NOT NULL DEFAULT 0,
    PRIMARY KEY (customer_id, year)
);

CREATE INDEX IF NOT EXISTS idx_customer_year_summary_customer
    ON customer_year_summary(customer_id);
"""


def _order_year(created_at: str) -> Optional[int]:
    """Extract the calendar year from an orders.created_at timestamp.

    created_at is stored as ISO-8601 UTC ('YYYY-MM-DDTHH:MM:SS...Z'). Returns
    ``None`` when the value is empty or malformed.
    """
    if not created_at:
        return None
    # The year is the first 4 chars of the ISO timestamp; validate it is numeric.
    year_str = created_at[:4]
    if len(year_str) != 4 or not year_str.isdigit():
        return None
    return int(year_str)


def _recompute_customer_year_summary(conn, customer_id, year) -> None:
    """Recompute one (customer_id, year) row from scratch.

    Counts orders and sums total_price for the given customer and year. The
    row is deleted then re-inserted so it always reflects the current state of
    ``orders``. Safe to call inside an existing order transaction (NFR2: a
    single UPSERT within the same transaction adds negligible latency).
    """
    if customer_id is None or year is None:
        return
    conn.execute(
        "DELETE FROM customer_year_summary WHERE customer_id = ? AND year = ?",
        (customer_id, year),
    )
    row = conn.execute(
        "SELECT COUNT(*) AS c, COALESCE(SUM(total_price), 0) AS v "
        "FROM orders WHERE customer_id = ? "
        "  AND CAST(strftime('%Y', created_at) AS INTEGER) = ?",
        (customer_id, int(year)),
    ).fetchone()
    order_count = int(row["c"] or 0)
    total_volume = float(row["v"] or 0)
    conn.execute(
        "INSERT INTO customer_year_summary (customer_id, year, order_count, total_volume) "
        "VALUES (?, ?, ?, ?)",
        (int(customer_id), int(year), order_count, total_volume),
    )


def _migrate_v60_customer_year_summary(conn):
    """Create ``customer_year_summary`` and backfill it from existing orders.

    DG-206 Phase 1 (FR6, NFR2). The table stores one row per
    (customer_id, year) with the order count and total volume. Idempotent:
    re-running on an already-backfilled DB is a no-op (CREATE TABLE IF NOT
    EXISTS plus a guarded backfill that only inserts when the row is absent).
    """
    # Backfill: one pass over orders grouped by (customer_id, year) where the
    # summary row does not yet exist. Guard with NOT EXISTS so a partial run
    # does not double-count.
    conn.execute(
        """
        INSERT INTO customer_year_summary (customer_id, year, order_count, total_volume)
        SELECT o.customer_id,
               CAST(strftime('%Y', o.created_at) AS INTEGER) AS year,
               COUNT(*)   AS order_count,
               COALESCE(SUM(o.total_price), 0) AS total_volume
        FROM orders o
        WHERE o.customer_id IS NOT NULL
          AND o.created_at IS NOT NULL
          AND o.created_at != ''
        GROUP BY o.customer_id, year
        ON CONFLICT(customer_id, year) DO NOTHING
        """
    )


def _migrate_v61_customer_search_name(conn):
    """Add ``search_name`` column and backfill for all existing customers.

    DG-206 follow-up: adds diacritic-insensitive search. For fresh DBs the
    column already exists via CUSTOMERS_SCHEMA; for existing DBs we add it
    with ALTER TABLE. Then backfills ``_strip_diacritics(name)`` for every
    customer row. Idempotent: re-running overwrites existing values with
    the same result.
    """
    cols = [r["name"] for r in conn.execute("PRAGMA table_info(customers)").fetchall()]
    if "search_name" not in cols:
        conn.execute("ALTER TABLE customers ADD COLUMN search_name TEXT DEFAULT ''")
    rows = conn.execute("SELECT id, name FROM customers").fetchall()
    for row in rows:
        conn.execute(
            "UPDATE customers SET search_name = ? WHERE id = ?",
            (_strip_diacritics(row["name"]), row["id"]),
        )


def _migrate_v63_repair_zero_cogs_and_missing_entries(conn):
    """Repair zero-cost order_items and missing order_cogs journal entries.

    DG-208 Phase 2. After Phase 1 changed the baseline anchor from base_price
    to unit_price, historical order_items with cost_at_sale=0 needed repair:
    - 117 delivered/completed order_items had cost_at_sale=0 (some because the
      product code like 'BKS-DG-01' has no products row, others because v45
      backfill ran before unit_price was used as the anchor).
    - 95 delivered/completed orders had no order_cogs journal entry (including
      Order #1091) — these items were never populated because the old resolver
      returned 0 and _sync_delivered_order_journal skipped journal insertion
      when total_cogs was 0.

    This migration:
      1. Re-runs _backfill_order_items_cost_at_sale() — now unit_price-anchored
         — to repair the 117 zero-cost order_items (FR2, NFR2).
      2. Re-runs _sync_delivered_order_journal() for every delivered/completed
         order to create the missing order_cogs entries (AC4 — Order #1091).

    Idempotent: the backfill only updates rows where cost_at_sale is still 0;
    _sync_delivered_order_journal skips orders that already have an order_cogs
    entry.
    """
    _seed_chart_of_accounts(conn)
    from baker.services.journal_sync import _sync_delivered_order_journal

    _backfill_order_items_cost_at_sale(conn)

    orders = conn.execute(
        """
        SELECT id, order_ref
        FROM orders
        WHERE status IN ('delivered', 'completed')
        ORDER BY id
        """
    ).fetchall()
    for o in orders:
        _sync_delivered_order_journal(conn, int(o["id"]), o["order_ref"])


def _migrate_v64_delivery_phone(conn):
    """Add delivery_phone column to orders table — DG-211 Phase 4.1."""
    cols = [row[1] for row in conn.execute("PRAGMA table_info(orders)").fetchall()]
    if "delivery_phone" not in cols:
        conn.execute("ALTER TABLE orders ADD COLUMN delivery_phone TEXT DEFAULT ''")


def _migrate_v66_repair_customer_links(conn):
    """Link all NULL customer_id orders to customers on startup — DG-227 Phase 2.

    Idempotent migration (v66 slot — v65 is taken by DG-226). Scans orders
    WHERE customer_id IS NULL, groups by phone/name, creates new customers
    for unmatched identities, and links orders. Three categories:
      (1) phone-having orders — resolve/match/create
      (2) name-only orders — match via search_name or create
      (3) walk-in (no phone, no name) — link to "Khách lẻ"

    Recomputes customer_year_summary for every affected customer after linking.
    Logs summary with counts per resolution method.
    """
    import logging
    from baker.models.customer import Customer

    logger = logging.getLogger("baker.db")

    total_null_before = conn.execute(
        "SELECT COUNT(*) FROM orders WHERE customer_id IS NULL"
    ).fetchone()[0]

    if total_null_before == 0:
        logger.info("Không có đơn hàng nào thiếu customer_id — bỏ qua.")
        return

    # -- Build lookup tables ------------------------------------------------
    # Existing customer phones (from customer_phones and legacy customers.phone).
    existing_phones: dict[str, int] = {}
    for crow in conn.execute(
        "SELECT customer_id, phone FROM customer_phones"
    ).fetchall():
        nphone = _normalize_phone(crow["phone"] or "")
        if nphone and nphone not in existing_phones:
            existing_phones[nphone] = crow["customer_id"]
    for crow in conn.execute(
        "SELECT id, phone FROM customers WHERE phone IS NOT NULL AND phone != ''"
    ).fetchall():
        nphone = _normalize_phone(crow["phone"] or "")
        if nphone and nphone not in existing_phones:
            existing_phones[nphone] = crow["id"]

    # Existing customers by search_name (for name-only matching).
    existing_names: dict[str, int] = {}
    for crow in conn.execute(
        "SELECT id, search_name FROM customers WHERE search_name IS NOT NULL AND search_name != ''"
    ).fetchall():
        key = crow["search_name"].strip().lower()
        if key and key not in existing_names:
            existing_names[key] = crow["id"]

    # Find "Khách lẻ" customer for walk-in orders (FR5).
    khach_le = conn.execute(
        "SELECT id FROM customers WHERE LOWER(name) = 'khách lẻ' ORDER BY id ASC LIMIT 1"
    ).fetchone()
    khach_le_id = khach_le["id"] if khach_le else None

    # -- Counters -----------------------------------------------------------
    phone_match = 0
    name_match = 0
    new_customer = 0
    walk_in = 0
    affected_customers: set[int] = set()

    def _link_and_track(oid: int, cust_id: int) -> None:
        conn.execute(
            "UPDATE orders SET customer_id = ? WHERE id = ? AND customer_id IS NULL",
            (cust_id, oid),
        )
        affected_customers.add(cust_id)

    # -- (1) Phone-having orders -------------------------------------------
    phone_rows = conn.execute(
        """
        SELECT id, customer_phone, customer_name
        FROM orders
        WHERE customer_id IS NULL
          AND customer_phone IS NOT NULL
          AND customer_phone != ''
        ORDER BY created_at ASC, id ASC
        """
    ).fetchall()

    # Group by normalized phone.
    phone_groups: dict[str, list[dict]] = {}
    for orow in phone_rows:
        nphone = _normalize_phone(orow["customer_phone"])
        if not nphone:
            continue
        phone_groups.setdefault(nphone, []).append({
            "id": orow["id"],
            "name": orow["customer_name"] or "",
        })

    for nphone, orders in phone_groups.items():
        if nphone in existing_phones:
            cust_id = existing_phones[nphone]
            for o in orders:
                _link_and_track(o["id"], cust_id)
                phone_match += 1
        else:
            # Create a new customer — use the most common name for the group.
            names = [o["name"] for o in orders if o["name"]]
            resolved_name = _pick_most_common_name(names) if names else "Khách"
            cust = Customer(name=resolved_name, phone=nphone)
            cust_id = cust.save(conn)
            existing_phones[nphone] = cust_id
            search_name = _strip_diacritics(resolved_name)
            if search_name and search_name not in existing_names:
                existing_names[search_name] = cust_id
            for o in orders:
                _link_and_track(o["id"], cust_id)
                new_customer += 1

    # -- (2) Name-only orders (no phone, has name) -------------------------
    name_rows = conn.execute(
        """
        SELECT id, customer_name
        FROM orders
        WHERE customer_id IS NULL
          AND (customer_phone IS NULL OR customer_phone = '')
          AND customer_name IS NOT NULL
          AND customer_name != ''
        ORDER BY created_at ASC, id ASC
        """
    ).fetchall()

    # Group by diacritic-stripped name.
    name_groups: dict[str, list[dict]] = {}
    for orow in name_rows:
        key = _strip_diacritics(orow["customer_name"] or "")
        if not key:
            continue
        name_groups.setdefault(key, []).append({
            "id": orow["id"],
            "name": orow["customer_name"],
        })

    for key, orders in name_groups.items():
        if key in existing_names:
            cust_id = existing_names[key]
            for o in orders:
                _link_and_track(o["id"], cust_id)
                name_match += 1
        else:
            resolved_name = _pick_most_common_name([o["name"] for o in orders])
            cust = Customer(name=resolved_name, phone="")
            cust_id = cust.save(conn)
            existing_names[key] = cust_id
            for o in orders:
                _link_and_track(o["id"], cust_id)
                new_customer += 1

    # -- (3) Walk-in orders (no phone, no name) — FR5 ---------------------
    if khach_le_id is not None:
        walk_in_rows = conn.execute(
            """
            SELECT id FROM orders
            WHERE customer_id IS NULL
              AND (customer_phone IS NULL OR customer_phone = '')
              AND (customer_name IS NULL OR customer_name = '')
            """
        ).fetchall()
        for row in walk_in_rows:
            _link_and_track(row["id"], khach_le_id)
            walk_in += 1

    # -- Recompute customer_year_summary for affected customers — FR6 ------
    for cust_id in affected_customers:
        year_rows = conn.execute(
            "SELECT DISTINCT CAST(strftime('%Y', created_at) AS INTEGER) AS yr "
            "FROM orders WHERE customer_id = ? AND created_at IS NOT NULL",
            (cust_id,),
        ).fetchall()
        for yr_row in year_rows:
            if yr_row["yr"]:
                _recompute_customer_year_summary(conn, cust_id, yr_row["yr"])

    # -- Log summary — FR3 --------------------------------------------------
    total_linked = phone_match + name_match + new_customer + walk_in
    total_null_after = conn.execute(
        "SELECT COUNT(*) FROM orders WHERE customer_id IS NULL"
    ).fetchone()[0]

    logger.info(
        "Đã sửa %d đơn hàng: %d khớp số điện thoại, %d khớp tên, "
        "%d tạo mới, %d khách lẻ. Còn lại NULL: %d.",
        total_linked, phone_match, name_match, new_customer, walk_in, total_null_after,
    )


USERS_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT UNIQUE NOT NULL,
    password_hash  TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'staff' CHECK(role IN ('admin', 'staff')),
    active        INTEGER NOT NULL DEFAULT 1,
    locked_until  TEXT DEFAULT NULL,
    created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_active ON users(active);
"""


# Map SEED_STAFF roles to system-user roles. "owner" → "admin" for full system
# access; all other roles → "staff" for daily operational access only.
_SEED_STAFF_ROLE_TO_USER_ROLE = {
    "owner": "admin",
}


def _migrate_v68_users_table(conn):
    """Create the ``users`` table and seed existing staff as users with random
    bcrypt-hashed passwords (DG-029 Phase 1, FR12/FR13).

    Each staff member in :data:`SEED_STAFF` is inserted as a user. Sinh (role
    "owner") becomes ``admin``; all others become ``staff``. A random password
    is generated for each user, bcrypt-hashed (cost factor 12), and the plain
    password is printed to stdout so the admin can distribute credentials.

    Idempotent: re-running on a DB where users already exist skips seeding
    (INSERT OR IGNORE on the unique ``username``); printed passwords are only
    emitted on the first run when a row is actually inserted.
    """
    import secrets as _secrets

    from passlib.context import CryptContext

    _pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=12)

    inserted: list[tuple[str, str, str]] = []  # (username, role, plain_password)

    for name, staff_role in SEED_STAFF:
        user_role = _SEED_STAFF_ROLE_TO_USER_ROLE.get(staff_role, "staff")
        # DG-029 follow-on: lowercase the system username (staff.name display
        # name is left unchanged — users.username is the login account name).
        # Python str.lower() is Unicode-aware and correct for Vietnamese
        # diacritics (Â→â, Ư→ư, Ầ→ầ, etc.).
        username = name.lower()
        existing = conn.execute(
            "SELECT id FROM users WHERE username = ?", (username,)
        ).fetchone()
        if existing:
            continue
        plain = _secrets.token_urlsafe(12)
        hashed = _pwd_ctx.hash(plain)
        conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES (?, ?, ?, 1)",
            (username, hashed, user_role),
        )
        inserted.append((username, user_role, plain))

    if inserted:
        import sys

        # MJ-2 (DG-029 phase 5.6-c1): gate plaintext password printing behind
        # BAKER_SEED_QUIET so CI logs don't capture plaintext credentials.
        # When unset/empty the admin-distribution UX is preserved.
        seed_quiet = os.environ.get("BAKER_SEED_QUIET", "").strip().lower() in (
            "1", "true", "yes", "on",
        )
        if seed_quiet:
            print(
                "DG-029 users migration: seeded initial user accounts "
                f"({len(inserted)} users) — passwords suppressed (BAKER_SEED_QUIET=1)",
                file=sys.stdout,
            )
        else:
            print("=" * 60, file=sys.stdout)
            print("DG-029 users migration: seeded initial user accounts", file=sys.stdout)
            print("Distribute these temporary passwords to each user:", file=sys.stdout)
            print("-" * 60, file=sys.stdout)
        for username, role, plain in inserted:
            print(f"  {username} ({role}): {plain}", file=sys.stdout)
        print("=" * 60, file=sys.stdout)


def _migrate_v71_users_role_check(conn):
    """Add a DB-level CHECK(role IN ('admin','staff')) to the ``users`` table.

    Mn-3 (DG-029 phase 5.6-c1): v68 created the users table without a
    DB-level CHECK on ``role``, so application bugs could persist invalid
    role values. Fresh DBs created on or after this migration get the
    constraint directly in ``USERS_SCHEMA``. Existing DBs where v68 has
    already run need a forward rebuild: SQLite has no ``ALTER TABLE ...
    ADD CONSTRAINT`` so we recreate the table with the CHECK, copy data,
    and recreate indexes. Idempotent: if the constraint is already
    present (fresh DB created post-fix, or this migration already ran),
    the rebuild is skipped.
    """
    # Detect whether the CHECK constraint is already in place. SQLite
    # exposes table-level CHECK constraints via the `sql` column of
    # sqlite_master. A fresh USERS_SCHEMA create includes the CHECK, so
    # re-running this migration on a fresh DB is a no-op.
    row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='users'"
    ).fetchone()
    if row is None:
        # users table does not exist yet — nothing to migrate. The
        # USERS_SCHEMA block in this same migration slot will create it
        # with the CHECK already in place.
        return
    create_sql = row["sql"] or ""
    if "CHECK(role IN" in create_sql.replace("\n", " "):
        return

    # Rebuild users with the CHECK constraint (table-rebuild pattern,
    # same approach used by _migrate_v28_cascade_and_reseed).
    conn.executescript(
        """
        CREATE TABLE users_new (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            username      TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            role          TEXT NOT NULL DEFAULT 'staff' CHECK(role IN ('admin', 'staff')),
            active        INTEGER NOT NULL DEFAULT 1,
            locked_until  TEXT DEFAULT NULL,
            created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
        );

        INSERT INTO users_new (id, username, password_hash, role, active, locked_until, created_at)
        SELECT id, username, password_hash, role, active, locked_until, created_at
        FROM users;

        DROP TABLE users;
        ALTER TABLE users_new RENAME TO users;

        CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
        CREATE INDEX IF NOT EXISTS idx_users_active ON users(active);
        """
    )


AUDIT_LOG_SCHEMA = """
CREATE TABLE IF NOT EXISTS audit_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    username    TEXT NOT NULL DEFAULT '',
    action      TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id   TEXT,
    old_value   TEXT,
    new_value   TEXT,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_log_username ON audit_log(username);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity_type ON audit_log(entity_type);
"""


# DG-029 Phase 4: sessions table for active session tracking (FR20/FR21).
#
# One row per active login session. Created on successful login (auth.py) and
# consulted by `baker session list` to show active sessions with IP/device
# metadata. The ``jti`` column links the session row to the JWT issued at
# login; force-logout adds that jti to the in-memory denylist checked by
# AuthMiddleware (FR21). ``revoked_at`` is set when a session is force-logged
# out so `session list` can omit revoked sessions.
SESSIONS_SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    jti             TEXT NOT NULL UNIQUE,
    username        TEXT NOT NULL,
    role            TEXT NOT NULL,
    client_ip       TEXT NOT NULL DEFAULT '',
    device_model    TEXT NOT NULL DEFAULT '',
    app_version     TEXT NOT NULL DEFAULT '',
    os_version      TEXT NOT NULL DEFAULT '',
    logged_in_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    last_activity   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    revoked_at      TEXT DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_username ON sessions(username);
CREATE INDEX IF NOT EXISTS idx_sessions_jti ON sessions(jti);
CREATE INDEX IF NOT EXISTS idx_sessions_revoked_at ON sessions(revoked_at);
"""


def _migrate_v72_lowercase_usernames(conn):
    """Lowercase all existing ``users.username`` values (DG-029 follow-on).

    SQLite ``lower()`` only lowercases ASCII by default, so a pure-SQL
    ``UPDATE`` would leave Vietnamese diacritics (Â, Ư, Ầ, ...) untouched.
    Instead this migration reads each row, lowercases the username in Python
    (str.lower() is Unicode-aware), and per-row UPDATEs the value.

    Defensive collision guard: if two rows would collapse to the same
    lowercased username (e.g. "An" and "an"), the conflicting pair is
    skipped + logged. There should be none for the seeded set, but existing
    DBs may have arbitrary history. We never raise — a migration must not
    crash the server.

    Idempotent: re-running on a DB where all usernames are already lowercase
    is a no-op (the UPDATE matches no rows).

    Scope: only ``users.username``. Does NOT touch ``audit_log``,
    ``sessions``, ``staff``, or any ``logged_by`` / ``completed_by``
    historical data (per DG-029 follow-on requirements).
    """
    import sys

    rows = conn.execute("SELECT id, username FROM users ORDER BY id").fetchall()
    if not rows:
        return

    # Pre-collect existing lowercase usernames (already-correct rows) so we
    # can detect collisions before any UPDATE.
    existing_lower = {row["username"] for row in rows if row["username"] == row["username"].lower()}

    skipped: list[tuple[str, str]] = []  # (original, would_be)
    for row in rows:
        original = row["username"]
        lowered = original.lower()
        if lowered == original:
            continue  # already lowercase
        if lowered in existing_lower:
            skipped.append((original, lowered))
            continue
        conn.execute(
            "UPDATE users SET username = ? WHERE id = ?",
            (lowered, row["id"]),
        )
        existing_lower.add(lowered)

    if skipped:
        print(
            "DG-029 v72 migration: skipped lowercase-colliding usernames "
            f"({len(skipped)} pairs): {skipped}",
            file=sys.stdout,
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
    44: {
        "description": "Double-entry accounting: accounts, journal_entries, journal_lines, chart of accounts seed, backfill historical entries",
        "sql": "",
        "callable": _migrate_v44_double_entry_accounting,
    },
    45: {
        "description": "Cost data foundation: cost_history table, order_items.cost_at_sale column, backfill delivered order_items with baseline costs",
        "sql": "",
         "callable": _migrate_v45_cost_history_and_cost_at_sale,
     },
     46: {
         "description": "One-time fix: backfill journal entry for old-format expense event #25 (pre-standardization data)",
         "sql": "",
         "callable": _migrate_v46_fix_old_expense_journal,
     },
     47: {
         "description": "One-time fix: delete and re-create stale order_cogs entries generated with old cost resolver (no baseline fallback)",
         "sql": "",
         "callable": _migrate_v47_fix_stale_cogs_entries,
     },
     48: {
         "description": "One-time fix: re-route Nguyên liệu and Bao bì expense journal entries to debit Inventory (1300) instead of expense accounts",
         "sql": "",
         "callable": _migrate_v48_fix_inventory_purchase_entries,
     },
     49: {
         "description": "Bus shipping accounting backfill: fix revenue entries, create hold+release entries for delivered bus orders",
         "sql": "",
         "callable": _migrate_v49_bus_shipping_backfill,
     },
     50: {
         "description": "Add transaction_date column + index to journal_entries (DG-192 Phase 4.1)",
         "sql": "",
         "callable": _migrate_v50_journal_transaction_date,
     },
    51: {
        "description": "Re-backfill journal_entries.transaction_date from source record dates (DG-192 Phase 4.1)",
        "sql": "",
        "callable": _migrate_v51_backfill_journal_transaction_date,
    },
    52: {
        "description": "Reclassify staff advance accounts (1400 asset) to staff payables (2300 liability) — DG-194 review remediation",
        "sql": "",
        "callable": _migrate_v52_reclassify_staff_advances_as_liabilities,
    },
     53: {
         "description": "Add invalidated_at/invalidated_by soft-delete columns to payment_transactions — DG-196 payment transaction invalidation",
         "sql": "",
         "callable": _migrate_v53_payment_transaction_invalidation,
     },
     54: {
         "description": "Ensure account 2400 (Tien Rut Held) exists in chart of accounts — DG-199 Phase 4.2",
         "sql": "",
         "callable": _migrate_v54_add_account_2400,
     },
     55: {
         "description": "UTC timestamp standardization — append Z to bare timestamps, convert +07:00 to UTC Z (DG-202 Phase 2)",
         "sql": "",
         "callable": _migrate_v55_utc_timestamp_standardization,
     },
    56: {
        "description": "Customer management foundation: customers table, customer_id FK on orders, auto-match existing orders by phone (DG-182 Phase 1)",
        "sql": CUSTOMERS_SCHEMA,
        "callable": _migrate_v56_customers_and_order_link,
    },
    57: {
        "description": "Generate customer records from existing orders and link orders to them — earliest-order-wins for shared phones, idempotent re-run (DG-204 Phase 2)",
        "sql": "",
        "callable": _migrate_v57_generate_customers_from_orders,
    },
    58: {
        "description": "Customer multi-phone: customer_phones table + migrate existing customers.phone as primary phone, idempotent re-run (DG-205 Phase 1)",
        "sql": CUSTOMER_PHONES_SCHEMA,
        "callable": _migrate_v58_customer_phones,
    },
    59: {
        "description": "Deduplicate customers with same case-insensitive name — merge orders, keep most-active, delete dupes (DG-205 follow-up)",
        "sql": "",
        "callable": _migrate_v59_deduplicate_customers,
    },
    60: {
        "description": "Customer yearly summary table (customer_year_summary) for order count + total volume per year, backfill from existing orders (DG-206 Phase 1)",
        "sql": CUSTOMER_YEAR_SUMMARY_SCHEMA,
        "callable": _migrate_v60_customer_year_summary,
    },
    61: {
        "description": "Add search_name column to customers for diacritic-insensitive search, backfill from existing names (DG-206 follow-up)",
        "sql": "",
        "callable": _migrate_v61_customer_search_name,
    },
    62: {
        "description": "Negative inventory: negative_balance table tracking oversold qty per (product_id, price_chip_id) (DG-200 Phase 1)",
        "sql": "",
        "callable": _migrate_v62_negative_balance,
    },
    63: {
        "description": "Repair zero-cost order_items (unit_price anchor) and missing order_cogs journal entries — DG-208 Phase 2",
        "sql": "",
        "callable": _migrate_v63_repair_zero_cogs_and_missing_entries,
    },
    64: {
        "description": "Add delivery_phone column to orders table — DG-211 Phase 4.1",
        "sql": "",
        "callable": _migrate_v64_delivery_phone,
    },
    65: {
        "description": "Create journal_sync_failure_log table for per-source audit records — DG-226 Phase 1",
        "sql": "",
        "callable": _migrate_v65_journal_sync_failure_log,
    },
    66: {
        "description": "Repair unlinked orders — link all NULL customer_id orders by phone/name/walk-in, idempotent re-run (DG-227 Phase 2)",
        "sql": "",
        "callable": _migrate_v66_repair_customer_links,
    },
    67: {
        "description": "Add acknowledged_at column to orders for order acknowledgment tracking — DG-221 Phase 1",
        "sql": "ALTER TABLE orders ADD COLUMN acknowledged_at TEXT DEFAULT NULL;",
    },
    68: {
        "description": "Auth RBAC: users table for JWT authentication + seed existing staff as users — DG-029 Phase 1",
        "sql": USERS_SCHEMA,
        "callable": _migrate_v68_users_table,
    },
    69: {
        "description": "Auth RBAC: audit_log table for recording admin write operations — DG-029 Phase 3",
        "sql": AUDIT_LOG_SCHEMA,
    },
    70: {
        "description": "Auth RBAC: sessions table for active session tracking — DG-029 Phase 4",
        "sql": SESSIONS_SCHEMA,
    },
    71: {
        "description": "Auth RBAC: DB-level CHECK(role IN ('admin','staff')) on users table — DG-029 phase 5.6-c1 (Mn-3)",
        # No-op SQL block; the callable does the conditional rebuild. On
        # fresh DBs USERS_SCHEMA (with the CHECK) is applied by v68's
        # `CREATE TABLE IF NOT EXISTS`, which is a no-op if the table
        # already exists, so this migration's callable is the authority.
        "sql": "",
        "callable": _migrate_v71_users_role_check,
    },
    72: {
        "description": "Auth RBAC: lowercase existing users.username values — DG-029 follow-on",
        "sql": "",
        "callable": _migrate_v72_lowercase_usernames,
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
