"""Module-level schema/seed/code constants extracted from the monolithic schema.py."""



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

_OLD_CATEGORY_TO_SLUG = {
    "bread": "banh_mi",
    "cake": "banh_kem",
    "pastry": "banh_ngot",
    "cookie": "cookie",
    "other": "khac",
}

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
    "cash_drawer",
}

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

EXPENSE_CATEGORIES_SCHEMA = """
CREATE TABLE IF NOT EXISTS expense_categories (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL,
    account_code TEXT NOT NULL,
    parent_id    INTEGER REFERENCES expense_categories(id),
    created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_expense_categories_parent ON expense_categories(parent_id);
CREATE INDEX IF NOT EXISTS idx_expense_categories_account_code ON expense_categories(account_code);
CREATE UNIQUE INDEX IF NOT EXISTS uq_expense_categories_name_parent
    ON expense_categories(name, COALESCE(parent_id, -1));
"""

CASH_DRAWER_SCHEMA = """
CREATE TABLE IF NOT EXISTS cash_drawer (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    opened_at       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    closed_at       TEXT,
    status          TEXT NOT NULL DEFAULT 'open',
    opening_balance INTEGER NOT NULL DEFAULT 0,
    cash_sales      INTEGER NOT NULL DEFAULT 0,
    owner_in        INTEGER NOT NULL DEFAULT 0,
    owner_out       INTEGER NOT NULL DEFAULT 0,
    cash_expenses   INTEGER NOT NULL DEFAULT 0,
    counted_amount  INTEGER,
    discrepancy     INTEGER
);

CREATE INDEX IF NOT EXISTS idx_cash_drawer_status ON cash_drawer(status);
CREATE INDEX IF NOT EXISTS idx_cash_drawer_opened_at ON cash_drawer(opened_at);
"""

SEED_EXPENSE_CATEGORIES = [
    # Parent categories
    ("Nguyên liệu", "5100", None),
    ("Bao bì", "5200", None),
    ("Vận chuyển", "5300", None),
    ("Điện/nước", "5400", None),
    ("Dụng cụ", "5500", None),
    ("Sửa chữa", "5600", None),
    ("Lương/phụ cấp", "5700", None),
    ("Khác", "5800", None),
    # Subcategories of Nguyên liệu
    ("Trứng", "5110", "Nguyên liệu"),
    ("Kem", "5120", "Nguyên liệu"),
    ("Bột", "5130", "Nguyên liệu"),
    ("Phụ gia khác", "5140", "Nguyên liệu"),
    ("Trái cây", "5150", "Nguyên liệu"),
    # Subcategories of Bao bì
    ("Hộp & đế", "5210", "Bao bì"),
    ("Phụ kiện", "5220", "Bao bì"),
    ("Bọc nilon", "5230", "Bao bì"),
]

SEED_CHART_OF_ACCOUNTS = [
    # Assets
    ("1000", "Tài sản", "asset", None),
    ("1100", "Tiền mặt (Cash on Hand)", "asset", "1000"),
    ("1200", "Tài khoản ngân hàng (Bank Account)", "asset", "1000"),
    # DG-244 Phase 4: distinct bank sub-accounts under 1200 for payment
    # transaction routing. The expense flow still maps both VCB labels to
    # 1200 via EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE — these sub-accounts
    # are used only by the payment_transaction journal routing
    # (TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE) so per-account balances are
    # visible without disturbing expense journal behavior.
    ("1210", "TK Phượng VCB (Bank — Phượng)", "asset", "1200"),
    ("1220", "TK Ân VCB (Bank — Ân)", "asset", "1200"),
    ("1290", "TK ngân hàng chưa phân bổ (Un-allocated Bank)", "asset", "1200"),
    ("1300", "Hàng tồn kho (Inventory)", "asset", "1000"),
    ("1500", "Phải thu khách hàng (Accounts Receivable)", "asset", "1000"),
    # DG-300 Phase 1: Fixed Assets account for investing-activity cash flows.
    # Sub-account of 1000 (Tài sản) so it sits within the asset hierarchy
    # alongside cash, inventory, and receivables.
    ("1600", "Tài sản cố định (Fixed Assets)", "asset", "1000"),
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
    # DG-302 Phase 1: Ingredient subcategory accounts (sub-accounts of 5100).
    # Each subcategory debits its own account so journal entries can be sliced
    # by raw-material type. The parent account 5100 is still used for expense
    # events that have no subcategory (backward compatibility, FR6).
    ("5110", "Trứng (Eggs)", "expense", "5100"),
    ("5120", "Kem (Cream)", "expense", "5100"),
    ("5130", "Bột (Flour)", "expense", "5100"),
    ("5140", "Phụ gia khác (Other Additives)", "expense", "5100"),
    ("5150", "Trái cây (Fruits)", "expense", "5100"),
    # DG-302 Phase 1: Packaging subcategory accounts (sub-accounts of 5200).
    ("5210", "Hộp & đế (Boxes & Bases)", "expense", "5200"),
    ("5220", "Phụ kiện (Accessories)", "expense", "5200"),
    ("5230", "Bọc nilon (Plastic Wrap)", "expense", "5200"),
    # COGS
    ("5900", "Giá vốn hàng bán (COGS)", "expense", "5000"),
    # DG-297 Phase 1: Promotional Expense account for gifted extras (is_gift=1).
    # Used as the debit account in the order_gift_cogs journal entry. Sub-account
    # of 5000 (Chi phí), sibling of the COGS account 5900. Inserted via
    # INSERT OR IGNORE so re-seeding on existing DBs is idempotent.
    ("5910", "Chi phí khuyến mãi (Promotional Expense)", "expense", "5000"),
]

EXPENSE_CATEGORY_TO_ACCOUNT_CODE = {
    # Parent categories
    "Nguyên liệu": "5100",
    "Bao bì": "5200",
    "Vận chuyển": "5300",
    "Điện/nước": "5400",
    "Dụng cụ": "5500",
    "Sửa chữa": "5600",
    "Lương/phụ cấp": "5700",
    "Khác": "5800",
    # DG-302 subcategories — Nguyên liệu (5110–5140)
    "Trứng": "5110",
    "Kem": "5120",
    "Bột": "5130",
    "Phụ gia khác": "5140",
    "Trái cây": "5150",
    # DG-302 subcategories — Bao bì (5210–5230)
    "Hộp & đế": "5210",
    "Phụ kiện": "5220",
    "Bọc nilon": "5230",
}

INVENTORY_PURCHASE_CATEGORIES = {
    "Nguyên liệu",
    "Bao bì",
    # Subcategories of Nguyên liệu
    "Trứng",
    "Kem",
    "Bột",
    "Phụ gia khác",
    "Trái cây",
    # Subcategories of Bao bì
    "Hộp & đế",
    "Phụ kiện",
    "Bọc nilon",
}

EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE = {
    "Shop tiền mặt": "1100",
    "TK Phượng VCB": "1210",
    "TK Ân VCB": "1220",
    "Nhân viên ứng trước": "2300",
}

PAYMENT_METHOD_TO_ASSET_CODE = {
    "cash": "1100",
    "card": "1100",
    "transfer": "1200",
}

TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE = {
    "TK Phượng VCB": "1210",
    "TK Ân VCB": "1220",
}

UNALLOCATED_BANK_CODE = "1290"

EXPENSE_DEBT_PAYMENT_METHOD = "Nợ"

ACCOUNTS_PAYABLE_CODE = "2500"

PAYMENT_OUTFLOW_TYPES = {"refund"}

PAYMENT_TIEN_RUT_TYPES = {"tien_rut"}

CUSTOMER_DEPOSITS_CODE = "2100"

ORDER_REVENUE_CODE = "4100"

COGS_CODE = "5900"

PROMO_EXPENSE_CODE = "5910"

INVENTORY_CODE = "1300"

STAFF_PAYABLES_CODE = "2300"

ACCOUNTS_RECEIVABLE_CODE = "1500"

BUS_SHIPPING_HELD_CODE = "2200"

TIEN_RUT_HELD_CODE = "2400"

REVENUE_UPDATE_TOLERANCE = 0.005

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

PHU_KIEN_CATEGORY = "phu_kien"

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

USERS_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT UNIQUE NOT NULL,
    password_hash  TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'staff' CHECK(role IN ('admin', 'staff')),
    active        INTEGER NOT NULL DEFAULT 1,
    locked_until  TEXT DEFAULT NULL,
    staff_id      INTEGER REFERENCES staff(id) ON DELETE SET NULL,
    force_password_change INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_staff_id ON users(staff_id) WHERE staff_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_active ON users(active);
"""

_SEED_STAFF_ROLE_TO_USER_ROLE = {
    "owner": "admin",
}

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
    revoked_at      TEXT DEFAULT NULL,
    staff_id        INTEGER DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_username ON sessions(username);
CREATE INDEX IF NOT EXISTS idx_sessions_jti ON sessions(jti);
CREATE INDEX IF NOT EXISTS idx_sessions_revoked_at ON sessions(revoked_at);
"""

BLANKS_SCHEMA = """
CREATE TABLE IF NOT EXISTS blanks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    category    TEXT NOT NULL DEFAULT '',
    unit        TEXT NOT NULL DEFAULT '',
    notes       TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z'),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_blanks_category ON blanks(category);

CREATE TABLE IF NOT EXISTS product_blank_bom (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id      INTEGER,
    price_chip_id   INTEGER,
    blank_id        INTEGER NOT NULL REFERENCES blanks(id) ON DELETE CASCADE,
    quantity        REAL NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_product_blank_bom_blank ON product_blank_bom(blank_id);
CREATE INDEX IF NOT EXISTS idx_product_blank_bom_product ON product_blank_bom(product_id);
CREATE INDEX IF NOT EXISTS idx_product_blank_bom_price_chip ON product_blank_bom(price_chip_id);

CREATE TABLE IF NOT EXISTS blank_stock (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    blank_id        INTEGER NOT NULL REFERENCES blanks(id) ON DELETE CASCADE,
    quantity        REAL NOT NULL DEFAULT 0,
    produced_date   TEXT NOT NULL,
    expiry_date     TEXT,
    type            TEXT NOT NULL DEFAULT 'production',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_blank_stock_blank ON blank_stock(blank_id);

CREATE TABLE IF NOT EXISTS blank_stock_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    blank_id        INTEGER NOT NULL REFERENCES blanks(id) ON DELETE CASCADE,
    quantity_change REAL NOT NULL,
    type            TEXT NOT NULL,
    produced_date   TEXT,
    expiry_date     TEXT,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_blank_stock_log_blank ON blank_stock_log(blank_id);
"""

ORDER_ITEM_BLANKS_SCHEMA = """
CREATE TABLE IF NOT EXISTS order_item_blanks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    order_item_id   INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
    blank_id        INTEGER NOT NULL REFERENCES blanks(id) ON DELETE CASCADE,
    quantity        REAL NOT NULL DEFAULT 1,
    notes           TEXT NOT NULL DEFAULT '',
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_order_item_blanks_item ON order_item_blanks(order_item_id);
CREATE INDEX IF NOT EXISTS idx_order_item_blanks_blank ON order_item_blanks(blank_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_order_item_blanks_item_blank_unique
    ON order_item_blanks(order_item_id, blank_id);
"""


__all__ = [
    'INITIAL_SCHEMA',
    'STAFF_AND_PEOPLE_SCHEMA',
    'PHOTO_PATH_AND_SEED',
    'SEED_PRODUCTS',
    'PRODUCT_CODE_AND_CATEGORIES_SCHEMA',
    'SEED_CATEGORIES',
    '_OLD_CATEGORY_TO_SLUG',
    'SEED_CAKE_VARIANTS',
    'SEED_SU_KEM_SETS',
    'PRODUCT_CATALOG_PHOTOS_SCHEMA',
    'PHOTOS_TABLE_AND_PHOTO_IDS_SCHEMA',
    'ORDER_PHOTOS_SCHEMA',
    'ORDER_ITEMS_AND_PAYMENT_TRANSACTIONS_SCHEMA',
    'PER_ITEM_BIRTHDAY_AND_PHOTO_LINK_SCHEMA',
    'APP_CONFIG_AND_ORDER_SOURCE_SCHEMA',
    'SEED_ORDER_SOURCES',
    'SERVER_LOGS_AND_TRIGGERS_SCHEMA',
    'SEED_STAFF',
    'CHECKLIST_SCHEMA',
    'SEED_CHECKLIST_OPENING',
    'SEED_CHECKLIST_CLOSING',
    'ORDER_HISTORY_SCHEMA',
    'SHIPPING_FEE_AND_EXTRAS_SCHEMA',
    'SEED_SHIPPING_AND_EXTRAS',
    'WORK_TICKET_PRINTED_AT_SCHEMA',
    'PRINT_LOG_AND_PRINTED_BY_SCHEMA',
    'RECONCILIATIONS_SCHEMA',
    'RECONCILIATION_SALE_ROWS_SCHEMA',
    'STOCK_LOTS_AND_ITEMS_SCHEMA',
    'ORDER_INCIDENT_ORDER_ID_SCHEMA',
    'EVENT_PHOTOS_SCHEMA',
    'PUBLIC_ORDER_CODE_SCHEMA',
    'PRODUCT_ATTRIBUTES_SCHEMA',
    'ORDER_ITEMS_ATTRIBUTES_SCHEMA',
    'SEED_PRODUCT_ATTRIBUTES',
    'KNOWLEDGE_BASE_SCHEMA',
    'CATALOG_PHOTO_TAGS_SCHEMA',
    'SEED_CATALOG_TAGS',
    'KNOWLEDGE_PIN_SCHEMA',
    'ALLOWED_TABLES',
    'PRODUCT_STOCK_SCHEMA',
    'PRODUCT_PRICE_CHIPS_SCHEMA',
    'PRODUCT_ATTRIBUTE_OPTIONS_SCHEMA',
    'SEED_NHAN_BANH_OPTIONS',
    'EVENT_HISTORY_AND_SOFT_DELETE_SCHEMA',
    'ACCOUNTING_SCHEMA',
    'EXPENSE_CATEGORIES_SCHEMA',
    'SEED_EXPENSE_CATEGORIES',
    'CASH_DRAWER_SCHEMA',
    'SEED_CHART_OF_ACCOUNTS',
    'EXPENSE_CATEGORY_TO_ACCOUNT_CODE',
    'INVENTORY_PURCHASE_CATEGORIES',
    'EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE',
    'PAYMENT_METHOD_TO_ASSET_CODE',
    'TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE',
    'UNALLOCATED_BANK_CODE',
    'EXPENSE_DEBT_PAYMENT_METHOD',
    'ACCOUNTS_PAYABLE_CODE',
    'PAYMENT_OUTFLOW_TYPES',
    'PAYMENT_TIEN_RUT_TYPES',
    'CUSTOMER_DEPOSITS_CODE',
    'ORDER_REVENUE_CODE',
    'COGS_CODE',
    'PROMO_EXPENSE_CODE',
    'INVENTORY_CODE',
    'STAFF_PAYABLES_CODE',
    'ACCOUNTS_RECEIVABLE_CODE',
    'BUS_SHIPPING_HELD_CODE',
    'TIEN_RUT_HELD_CODE',
    'REVENUE_UPDATE_TOLERANCE',
    'JOURNAL_SYNC_FAILURE_LOG_SCHEMA',
    'NEGATIVE_BALANCE_SCHEMA',
    'COST_HISTORY_SCHEMA',
    'PHU_KIEN_CATEGORY',
    '_TIMESTAMP_COLUMNS_V55',
    'CUSTOMERS_SCHEMA',
    'CUSTOMER_PHONES_SCHEMA',
    'CUSTOMER_YEAR_SUMMARY_SCHEMA',
    'USERS_SCHEMA',
    '_SEED_STAFF_ROLE_TO_USER_ROLE',
    'AUDIT_LOG_SCHEMA',
    'SESSIONS_SCHEMA',
    'BLANKS_SCHEMA',
    'ORDER_ITEM_BLANKS_SCHEMA',
]
