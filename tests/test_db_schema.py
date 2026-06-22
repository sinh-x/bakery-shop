import json

from baker.db.connection import get_db
from baker.db.schema import MIGRATIONS, PRINT_LOG_AND_PRINTED_BY_SCHEMA, ensure_schema


def _migrate_to_version(conn, target_version: int) -> None:
    """Apply migrations incrementally up to target_version (inclusive)."""
    row = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
    ).fetchone()
    current_version = 0
    if row:
        current_row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
        current_version = current_row[0] if current_row and current_row[0] is not None else 0
    for version in sorted(MIGRATIONS.keys()):
        if version <= current_version or version > target_version:
            continue
        conn.executescript(MIGRATIONS[version]["sql"])

        seed = MIGRATIONS[version].get("seed")
        if seed:
            for name, category, base_price, cost, recipe_notes in seed:
                conn.execute(
                    "INSERT OR IGNORE INTO products "
                    "(name, category, base_price, cost, recipe_notes) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (name, category, base_price, cost, recipe_notes),
                )

        callable_fn = MIGRATIONS[version].get("callable")
        if callable_fn:
            callable_fn(conn)

        conn.execute(
            "INSERT INTO schema_version (version, description) VALUES (?, ?)",
            (version, MIGRATIONS[version]["description"]),
        )
    conn.commit()


def _schema_columns(conn, table: str) -> dict[str, tuple]:
    return {
        row["name"]: row
        for row in conn.execute(f"PRAGMA table_info({table})").fetchall()
    }


def _assert_product_price_chips_schema(conn) -> None:
    columns = _schema_columns(conn, "product_price_chips")
    assert set(columns) >= {
        "id",
        "product_id",
        "label",
        "price",
        "position",
        "created_at",
    }
    for name in ["product_id", "label", "price", "position", "created_at"]:
        assert columns[name]["notnull"] == 1

    fk_rows = conn.execute("PRAGMA foreign_key_list(product_price_chips)").fetchall()
    assert len(fk_rows) == 1
    fk = fk_rows[0]
    assert fk["table"] == "products"
    assert fk["from"] == "product_id"
    assert fk["to"] == "id"
    assert fk["on_delete"] == "CASCADE"

    index_rows = conn.execute("PRAGMA index_list(product_price_chips)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_product_price_chips_product" in index_names
    index_info = conn.execute(
        "PRAGMA index_info(idx_product_price_chips_product)"
    ).fetchall()
    index_columns = [row["name"] for row in index_info]
    assert index_columns == ["product_id"]


def _migrated_version(conn) -> int:
    row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
    return int(row[0] or 0)


def test_schema_migration_v30_fresh_db():
    with get_db() as conn:
        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30
        _assert_product_price_chips_schema(conn)


def test_schema_migration_v29_to_v30():
    with get_db() as conn:
        _migrate_to_version(conn, 29)
        assert _migrated_version(conn) == 29

        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30
        _assert_product_price_chips_schema(conn)


def test_schema_migration_v30_idempotent():
    with get_db() as conn:
        _migrate_to_version(conn, 29)
        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30

        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30
        _assert_product_price_chips_schema(conn)


def _assert_product_attribute_options_schema(conn) -> None:
    columns = _schema_columns(conn, "product_attribute_options")
    assert set(columns) >= {
        "id",
        "attribute_id",
        "value_vi",
        "sort_order",
        "active",
    }
    for name in ["attribute_id", "value_vi", "sort_order", "active"]:
        assert columns[name]["notnull"] == 1

    fk_rows = conn.execute(
        "PRAGMA foreign_key_list(product_attribute_options)"
    ).fetchall()
    assert len(fk_rows) == 1
    fk = fk_rows[0]
    assert fk["table"] == "product_attributes"
    assert fk["from"] == "attribute_id"
    assert fk["to"] == "id"
    assert fk["on_delete"] == "CASCADE"

    index_rows = conn.execute(
        "PRAGMA index_list(product_attribute_options)"
    ).fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_attr_options_attr" in index_names


def _assert_print_tracking_schema(conn) -> None:
    orders = _schema_columns(conn, "orders")
    assert "work_ticket_printed_by" in orders

    print_log = _schema_columns(conn, "print_log")
    assert set(print_log) >= {
        "id",
        "order_id",
        "item_id",
        "receipt_type",
        "printed_by",
        "printed_at",
    }

    index_rows = conn.execute("PRAGMA index_list(print_log)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_print_log_order" in index_names


def _assert_reconciliation_sale_rows_schema(conn) -> None:
    line_columns = _schema_columns(conn, "reconciliation_lines")
    assert "waste_reason" in line_columns

    columns = _schema_columns(conn, "reconciliation_sale_rows")
    assert set(columns) >= {
        "id",
        "line_id",
        "quantity",
        "unit_price",
        "payment_method",
        "linked_order_ref",
        "linked_payment_ref",
        "created_at",
    }

    fk_rows = conn.execute("PRAGMA foreign_key_list(reconciliation_sale_rows)").fetchall()
    assert len(fk_rows) == 1
    fk = fk_rows[0]
    assert fk["table"] == "reconciliation_lines"
    assert fk["from"] == "line_id"
    assert fk["to"] == "id"
    assert fk["on_delete"] == "CASCADE"

    index_rows = conn.execute("PRAGMA index_list(reconciliation_sale_rows)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_reconciliation_sale_rows_line" in index_names


def _assert_nhan_banh_seed(conn) -> None:
    attr_row = conn.execute(
        "SELECT id, label_vi, value_type, applicable_categories, default_value, active "
        "FROM product_attributes WHERE attribute_type = 'nhan_banh'"
    ).fetchone()
    assert attr_row is not None
    assert attr_row["label_vi"] == "Nhân bánh"
    assert attr_row["value_type"] == "enum"
    assert attr_row["applicable_categories"] == '["banh_kem"]'
    assert attr_row["active"] == 1
    assert attr_row["default_value"] != ""

    options = conn.execute(
        "SELECT id, value_vi, sort_order, active "
        "FROM product_attribute_options WHERE attribute_id = ? "
        "ORDER BY sort_order",
        (attr_row["id"],),
    ).fetchall()
    assert len(options) == 5
    assert all(opt["active"] == 1 for opt in options)
    assert [opt["value_vi"] for opt in options] == [
        "Sầu riêng",
        "Sô-cô-la",
        "Việt quất",
        "Chanh dây",
        "Dâu",
    ]

    default_id = int(attr_row["default_value"])
    default_match = next(opt for opt in options if opt["id"] == default_id)
    assert default_match["value_vi"] == "Sầu riêng"


def _assert_chip_aware_inventory_schema(conn) -> None:
    stock_lot_columns = _schema_columns(conn, "stock_lots")
    assert set(stock_lot_columns) >= {
        "id",
        "product_id",
        "price_chip_id",
        "quantity",
        "remaining_qty",
        "restocked_at",
        "created_at",
    }

    item_columns = _schema_columns(conn, "inventory_items")
    assert set(item_columns) >= {
        "id",
        "lot_id",
        "uuid",
        "status",
        "consumed_by_movement_id",
        "created_at",
    }
    assert item_columns["uuid"]["notnull"] == 1

    stock_movement_columns = _schema_columns(conn, "stock_movements")
    assert "lot_id" in stock_movement_columns
    assert "price_chip_id" in stock_movement_columns

    order_item_columns = _schema_columns(conn, "order_items")
    assert "price_chip_id" in order_item_columns

    reconciliation_line_columns = _schema_columns(conn, "reconciliation_lines")
    assert "price_chip_id" in reconciliation_line_columns


def _assert_v40_v41_schema(conn) -> None:
    event_columns = _schema_columns(conn, "events")
    assert "order_id" in event_columns
    assert event_columns["order_id"]["notnull"] == 0

    event_fks = conn.execute("PRAGMA foreign_key_list(events)").fetchall()
    order_id_fks = [fk for fk in event_fks if fk["from"] == "order_id"]
    assert len(order_id_fks) == 1
    assert order_id_fks[0]["table"] == "orders"
    assert order_id_fks[0]["to"] == "id"

    index_rows = conn.execute("PRAGMA index_list(events)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_events_order_id" in index_names

    event_photos_columns = _schema_columns(conn, "event_photos")
    assert set(event_photos_columns) >= {
        "id",
        "event_id",
        "photo_id",
        "tags",
        "position",
        "created_at",
    }
    for name in ["event_id", "photo_id", "position"]:
        assert event_photos_columns[name]["notnull"] == 1

    event_photos_fks = conn.execute("PRAGMA foreign_key_list(event_photos)").fetchall()
    assert len(event_photos_fks) == 2
    fk_tables = {(fk["from"], fk["table"]) for fk in event_photos_fks}
    assert ("event_id", "events") in fk_tables
    assert ("photo_id", "photos") in fk_tables

    ep_index_rows = conn.execute("PRAGMA index_list(event_photos)").fetchall()
    ep_index_names = [row["name"] for row in ep_index_rows]
    assert "idx_event_photos_event" in ep_index_names


def _assert_event_history_schema(conn) -> None:
    columns = _schema_columns(conn, "event_history")
    assert set(columns) >= {
        "id",
        "event_id",
        "action_type",
        "actor",
        "field_name",
        "old_value",
        "new_value",
        "timestamp",
    }
    for name in ["event_id", "action_type", "timestamp"]:
        assert columns[name]["notnull"] == 1

    fk_rows = conn.execute("PRAGMA foreign_key_list(event_history)").fetchall()
    assert len(fk_rows) == 1
    fk = fk_rows[0]
    assert fk["table"] == "events"
    assert fk["from"] == "event_id"
    assert fk["to"] == "id"

    index_rows = conn.execute("PRAGMA index_list(event_history)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_event_history_event" in index_names
    assert "idx_event_history_timestamp" in index_names


def _assert_soft_delete_columns(conn) -> None:
    event_columns = _schema_columns(conn, "events")
    assert "deleted_at" in event_columns
    assert "deleted_by" in event_columns
    assert event_columns["deleted_at"]["notnull"] == 0
    assert event_columns["deleted_by"]["notnull"] == 0


def _seed_v35_stock(conn) -> tuple[int, int, int]:
    conn.execute(
        """INSERT INTO products (name, category, base_price, cost, recipe_notes)
           VALUES ('Migration Product A', 'banh_mi', 15000, 0, '')"""
    )
    product_a_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

    conn.execute(
        """INSERT INTO products (name, category, base_price, cost, recipe_notes)
           VALUES ('Migration Product B', 'banh_kem', 12000, 0, '')"""
    )
    product_b_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

    conn.execute(
        "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, 'Chip Low', 9000, 1)",
        (product_a_id,),
    )
    chip_a_low_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
    conn.execute(
        "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, 'Chip High', 18000, 2)",
        (product_a_id,),
    )

    conn.execute("INSERT INTO product_stock (product_id, quantity) VALUES (?, ?)", (product_a_id, 3))
    conn.execute("INSERT INTO product_stock (product_id, quantity) VALUES (?, ?)", (product_b_id, 2))

    return product_a_id, product_b_id, chip_a_low_id


def test_schema_migration_v31_fresh_db():
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 44
        _assert_product_attribute_options_schema(conn)
        _assert_nhan_banh_seed(conn)
        _assert_print_tracking_schema(conn)
        _assert_reconciliation_sale_rows_schema(conn)
        _assert_chip_aware_inventory_schema(conn)
        _assert_v40_v41_schema(conn)
        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)


def test_schema_migration_v30_to_v31():
    with get_db() as conn:
        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30

        ensure_schema(conn)
        assert _migrated_version(conn) == 44
        _assert_product_attribute_options_schema(conn)
        _assert_nhan_banh_seed(conn)
        _assert_print_tracking_schema(conn)
        _assert_reconciliation_sale_rows_schema(conn)
        _assert_chip_aware_inventory_schema(conn)
        _assert_v40_v41_schema(conn)
        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)


def test_schema_migration_v31_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 44

        ensure_schema(conn)
        assert _migrated_version(conn) == 44

        attr_count = conn.execute(
            "SELECT COUNT(*) FROM product_attributes WHERE attribute_type = 'nhan_banh'"
        ).fetchone()[0]
        assert attr_count == 1

        attr_id = conn.execute(
            "SELECT id FROM product_attributes WHERE attribute_type = 'nhan_banh'"
        ).fetchone()[0]
        opt_count = conn.execute(
            "SELECT COUNT(*) FROM product_attribute_options WHERE attribute_id = ?",
            (attr_id,),
        ).fetchone()[0]
        assert opt_count == 5
        _assert_print_tracking_schema(conn)
        _assert_reconciliation_sale_rows_schema(conn)
        _assert_chip_aware_inventory_schema(conn)
        _assert_v40_v41_schema(conn)


def test_schema_migration_v32_handles_preexisting_printed_by_column():
    with get_db() as conn:
        _migrate_to_version(conn, 31)
        conn.execute("ALTER TABLE orders ADD COLUMN work_ticket_printed_by TEXT DEFAULT ''")
        _migrate_to_version(conn, 32)

        assert _migrated_version(conn) == 32
        _assert_print_tracking_schema(conn)


def test_schema_migration_v32_sql_block_does_not_readd_orders_column():
    assert "ALTER TABLE orders ADD COLUMN work_ticket_printed_by" not in PRINT_LOG_AND_PRINTED_BY_SCHEMA


def test_schema_migration_v35_repairs_missing_reconciliation_line_waste_reason():
    with get_db() as conn:
        conn.execute(
            """CREATE TABLE schema_version (
                version INTEGER PRIMARY KEY,
                description TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
            )"""
        )
        conn.execute(
            """CREATE TABLE reconciliation_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL,
                product_id INTEGER NOT NULL,
                expected_qty INTEGER NOT NULL,
                counted_qty INTEGER NOT NULL,
                sale_qty INTEGER NOT NULL DEFAULT 0,
                waste_qty INTEGER NOT NULL DEFAULT 0,
                manual_unit_price REAL DEFAULT NULL,
                linked_order_item_id INTEGER DEFAULT NULL,
                linked_stock_movement_sale_id INTEGER DEFAULT NULL,
                linked_stock_movement_waste_id INTEGER DEFAULT NULL,
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
            )"""
        )
        conn.execute(
            "INSERT INTO schema_version (version, description) VALUES (34, 'Grouped reconciliation sale rows table')"
        )

        _migrate_to_version(conn, 35)

        assert _migrated_version(conn) == 35
        line_columns = _schema_columns(conn, "reconciliation_lines")
        assert "waste_reason" in line_columns


def test_schema_migration_v36_migrates_product_stock_to_lots_and_items():
    with get_db() as conn:
        _migrate_to_version(conn, 35)
        product_a_id, product_b_id, chip_a_low_id = _seed_v35_stock(conn)

        _migrate_to_version(conn, 36)

        assert _migrated_version(conn) == 36
        _assert_chip_aware_inventory_schema(conn)

        has_product_stock = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='product_stock'"
        ).fetchone()
        assert has_product_stock is None

        lots = conn.execute(
            "SELECT product_id, price_chip_id, quantity, remaining_qty FROM stock_lots ORDER BY product_id"
        ).fetchall()
        assert len(lots) == 2

        lot_a = next(row for row in lots if row["product_id"] == product_a_id)
        assert lot_a["price_chip_id"] == chip_a_low_id
        assert lot_a["quantity"] == 3
        assert lot_a["remaining_qty"] == 3

        lot_b = next(row for row in lots if row["product_id"] == product_b_id)
        assert lot_b["price_chip_id"] is None
        assert lot_b["quantity"] == 2
        assert lot_b["remaining_qty"] == 2

        item_count = conn.execute("SELECT COUNT(*) FROM inventory_items").fetchone()[0]
        assert item_count == 5

        distinct_uuid_count = conn.execute(
            "SELECT COUNT(DISTINCT uuid) FROM inventory_items"
        ).fetchone()[0]
        assert distinct_uuid_count == 5

        invalid_uuid_count = conn.execute(
            "SELECT COUNT(*) FROM inventory_items WHERE uuid NOT GLOB '????????-????-4???-[89abAB]???-????????????'"
        ).fetchone()[0]
        assert invalid_uuid_count == 0


def test_schema_migration_v37_merges_duplicate_price_buckets_without_data_loss():
    with get_db() as conn:
        _migrate_to_version(conn, 36)
        conn.execute(
            """INSERT INTO products (name, category, base_price, cost, recipe_notes)
               VALUES ('Bucket Merge Product', 'banh_mi', 13000, 0, '')"""
        )
        product_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
        conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, 'chip 130', 13000, 1)",
            (product_id,),
        )
        chip_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

        conn.execute(
            "INSERT INTO stock_lots (product_id, price_chip_id, quantity, remaining_qty) VALUES (?, NULL, 2, 2)",
            (product_id,),
        )
        base_lot_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
        conn.execute(
            "INSERT INTO stock_lots (product_id, price_chip_id, quantity, remaining_qty) VALUES (?, ?, 3, 3)",
            (product_id, chip_id),
        )
        chip_lot_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

        for lot_id in (base_lot_id, chip_lot_id):
            for idx in range(2 if lot_id == base_lot_id else 3):
                conn.execute(
                    "INSERT INTO inventory_items (lot_id, uuid, status) VALUES (?, ?, 'available')",
                    (lot_id, f"{lot_id}-uuid-{idx}"),
                )

        _migrate_to_version(conn, 37)
        assert _migrated_version(conn) == 37

        lots = conn.execute(
            "SELECT id, price_chip_id, quantity, remaining_qty FROM stock_lots WHERE product_id = ? ORDER BY id",
            (product_id,),
        ).fetchall()
        assert len(lots) == 1
        assert lots[0]["price_chip_id"] is None
        assert lots[0]["quantity"] == 5
        assert lots[0]["remaining_qty"] == 5

        inventory_count = conn.execute(
            "SELECT COUNT(*) FROM inventory_items WHERE lot_id = ?",
            (lots[0]["id"],),
        ).fetchone()[0]
        assert inventory_count == 5


def test_schema_migration_v38_creates_phu_kien_from_order_extra():
    with get_db() as conn:
        _migrate_to_version(conn, 37)
        conn.execute("DELETE FROM app_config WHERE config_key = 'order_extra'")
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES ('order_extra', 'Hộp|20000', 1)"
        )
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES ('order_extra', 'Nến|5000', 2)"
        )

        _migrate_to_version(conn, 38)

        category = conn.execute(
            "SELECT slug, name, active FROM categories WHERE slug = 'phu_kien'"
        ).fetchone()
        assert category is not None
        assert category["name"] == "Phụ kiện"
        assert category["active"] == 1

        products = conn.execute(
            "SELECT id, name, category, base_price, active FROM products WHERE category = 'phu_kien' ORDER BY name"
        ).fetchall()
        assert len(products) == 2
        assert [row["name"] for row in products] == ["Hộp", "Nến"]
        assert [int(row["base_price"]) for row in products] == [20000, 5000]
        assert all(row["active"] == 1 for row in products)

        for product in products:
            attrs = conn.execute(
                "SELECT attribute_type, value FROM product_attribute_values WHERE product_id = ?",
                (product["id"],),
            ).fetchall()
            attr_map = {row["attribute_type"]: row["value"] for row in attrs}
            assert attr_map["trung_bay"] == "true"
            assert attr_map["tang_kem"] == "true"


def test_schema_migration_v38_is_idempotent_for_normalized_accessory_names():
    with get_db() as conn:
        _migrate_to_version(conn, 37)
        conn.execute("DELETE FROM app_config WHERE config_key = 'order_extra'")
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES ('order_extra', 'Hộp|20000', 1)"
        )
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES ('order_extra', '  hộp  |20000', 2)"
        )

        _migrate_to_version(conn, 38)
        MIGRATIONS[38]["callable"](conn)

        rows = conn.execute(
            "SELECT LOWER(TRIM(name)) AS normalized_name, COUNT(*) AS c "
            "FROM products WHERE category = 'phu_kien' GROUP BY LOWER(TRIM(name))"
        ).fetchall()
        assert len(rows) == 1
        assert rows[0]["normalized_name"] == "hộp"
        assert rows[0]["c"] == 1


def test_schema_migration_v43_creates_event_history_table_and_soft_delete_columns():
    with get_db() as conn:
        _migrate_to_version(conn, 42)
        assert _migrated_version(conn) == 42

        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)


def test_schema_migration_v43_idempotent():
    with get_db() as conn:
        _migrate_to_version(conn, 42)
        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)


def test_schema_migration_v43_backfills_staff_name_audit_entries():
    with get_db() as conn:
        _migrate_to_version(conn, 42)

        conn.execute(
            """INSERT INTO events (type, summary, data, logged_by, timestamp)
               VALUES ('expense', 'Test expense', ?, '', '2026-06-21T10:00:00+07:00')""",
            (json.dumps({"amount_vnd": 50000, "category": "NL", "payment_method": "TM",
                         "payment_source": "Shop tiền mặt", "vendor": "NCC A", "note": "",
                         "staff_name": "Ân", "paid_by_name": ""}),),
        )

        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        audit_rows = conn.execute(
            "SELECT * FROM event_history WHERE action_type = 'create' AND field_name = 'staff_name'"
        ).fetchall()
        assert len(audit_rows) == 1
        assert audit_rows[0]["actor"] == "Ân"
        assert audit_rows[0]["new_value"] == "Ân"
        assert audit_rows[0]["old_value"] is None

        event_row = conn.execute("SELECT logged_by, data FROM events WHERE type = 'expense'").fetchone()
        assert event_row is not None
        assert event_row["logged_by"] == "Ân"

        data = json.loads(event_row["data"])
        assert "staff_name" not in data


def test_schema_migration_v43_preserves_existing_logged_by():
    with get_db() as conn:
        _migrate_to_version(conn, 42)

        conn.execute(
            """INSERT INTO events (type, summary, data, logged_by, timestamp)
               VALUES ('expense', 'Test expense', ?, 'Sinh', '2026-06-21T10:00:00+07:00')""",
            (json.dumps({"amount_vnd": 50000, "category": "NL", "payment_method": "TM",
                         "payment_source": "Shop tiền mặt", "vendor": "NCC A", "note": "",
                         "staff_name": "Ân", "paid_by_name": ""}),),
        )

        _migrate_to_version(conn, 43)

        event_row = conn.execute("SELECT logged_by, data FROM events WHERE type = 'expense'").fetchone()
        assert event_row["logged_by"] == "Sinh"

        data = json.loads(event_row["data"])
        assert "staff_name" not in data


def test_schema_migration_v43_skips_non_expense_events():
    with get_db() as conn:
        _migrate_to_version(conn, 42)

        conn.execute(
            """INSERT INTO events (type, summary, data, logged_by, timestamp)
               VALUES ('note', 'Test note', ?, 'Sinh', '2026-06-21T10:00:00+07:00')""",
            (json.dumps({"staff_name": "Ân"}),),
        )

        _migrate_to_version(conn, 43)

        audit_count = conn.execute(
            "SELECT COUNT(*) FROM event_history WHERE action_type = 'create' AND field_name = 'staff_name'"
        ).fetchone()[0]
        assert audit_count == 0

        event_row = conn.execute("SELECT data FROM events WHERE type = 'note'").fetchone()
        data = json.loads(event_row["data"])
        assert "staff_name" in data


def test_schema_migration_v43_no_expense_events_is_noop():
    with get_db() as conn:
        _migrate_to_version(conn, 42)

        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)

        audit_count = conn.execute("SELECT COUNT(*) FROM event_history").fetchone()[0]
        assert audit_count == 0


# ---------------------------------------------------------------------------
# Migration v44 — Double-entry accounting
# ---------------------------------------------------------------------------


def _assert_accounts_table(conn) -> None:
    columns = _schema_columns(conn, "accounts")
    assert set(columns) >= {
        "id",
        "code",
        "name",
        "type",
        "parent_id",
        "is_active",
        "created_at",
    }
    assert columns["code"]["notnull"] == 1
    assert columns["name"]["notnull"] == 1
    assert columns["type"]["notnull"] == 1
    # code must be unique
    index_rows = conn.execute("PRAGMA index_list(accounts)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "sqlite_autoindex_accounts_1" in index_names or any(
        "unique" in str(row).lower() for row in index_rows
    )
    # parent_id self-reference
    fk_rows = conn.execute("PRAGMA foreign_key_list(accounts)").fetchall()
    parent_fks = [fk for fk in fk_rows if fk["from"] == "parent_id"]
    assert len(parent_fks) == 1
    assert parent_fks[0]["table"] == "accounts"


def _assert_journal_entries_table(conn) -> None:
    columns = _schema_columns(conn, "journal_entries")
    assert set(columns) >= {
        "id",
        "description",
        "created_at",
        "source_type",
        "source_id",
        "locked_at",
        "locked_by",
    }
    assert columns["description"]["notnull"] == 1
    assert columns["source_type"]["notnull"] == 1
    # source_id is nullable
    assert columns["source_id"]["notnull"] == 0
    assert columns["locked_at"]["notnull"] == 0

    index_rows = conn.execute("PRAGMA index_list(journal_entries)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_journal_entries_created" in index_names
    assert "idx_journal_entries_source" in index_names


def _assert_journal_lines_table(conn) -> None:
    columns = _schema_columns(conn, "journal_lines")
    assert set(columns) >= {
        "id",
        "journal_entry_id",
        "account_id",
        "debit",
        "credit",
        "description",
    }
    for name in ("journal_entry_id", "account_id", "debit", "credit"):
        assert columns[name]["notnull"] == 1

    fk_rows = conn.execute("PRAGMA foreign_key_list(journal_lines)").fetchall()
    fk_tables = {(fk["from"], fk["table"], fk["on_delete"]) for fk in fk_rows}
    assert ("journal_entry_id", "journal_entries", "CASCADE") in fk_tables
    assert ("account_id", "accounts", "NO ACTION") in fk_tables

    index_rows = conn.execute("PRAGMA index_list(journal_lines)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_journal_lines_entry" in index_names
    assert "idx_journal_lines_account" in index_names


# Expected chart of accounts seeded by v44.
_EXPECTED_COA = {
    "1000": ("Tài sản", "asset", None),
    "1100": ("Tiền mặt (Cash on Hand)", "asset", "1000"),
    "1200": ("Tài khoản ngân hàng (Bank Account)", "asset", "1000"),
    "1300": ("Hàng tồn kho (Inventory)", "asset", "1000"),
    "1400": ("Nhân viên ứng trước (Staff Advances)", "asset", "1000"),
    "2000": ("Nợ phải trả", "liability", None),
    "2100": ("Tiền khách đặt cọc (Customer Deposits)", "liability", "2000"),
    "3000": ("Vốn chủ sở hữu", "equity", None),
    "3100": ("Vốn chủ sở hữu (Owner's Equity)", "equity", "3000"),
    "4000": ("Doanh thu", "income", None),
    "4100": ("Doanh thu bán hàng (Order Revenue)", "income", "4000"),
    "5000": ("Chi phí", "expense", None),
    "5100": ("Nguyên liệu (Ingredients)", "expense", "5000"),
    "5200": ("Bao bì (Packaging)", "expense", "5000"),
    "5300": ("Vận chuyển (Delivery/Shipping)", "expense", "5000"),
    "5400": ("Điện/nước (Utilities)", "expense", "5000"),
    "5500": ("Dụng cụ (Tools)", "expense", "5000"),
    "5600": ("Sửa chữa (Equipment Maintenance)", "expense", "5000"),
    "5700": ("Lương/phụ cấp (Staff Salary)", "expense", "5000"),
    "5800": ("Khác (Other Expenses)", "expense", "5000"),
    "5900": ("Giá vốn hàng bán (COGS)", "expense", "5000"),
}


def _assert_seed_coa(conn) -> None:
    rows = conn.execute("SELECT * FROM accounts ORDER BY code").fetchall()
    by_code = {row["code"]: row for row in rows}
    for code, (name, acc_type, parent_code) in _EXPECTED_COA.items():
        assert code in by_code, f"Missing account code {code}"
        row = by_code[code]
        assert row["name"] == name, f"{code}: name {row['name']!r} != {name!r}"
        assert row["type"] == acc_type, f"{code}: type {row['type']!r} != {acc_type!r}"
        if parent_code:
            assert parent_code in by_code, f"Parent {parent_code} missing"
            assert row["parent_id"] == by_code[parent_code]["id"]
        else:
            assert row["parent_id"] is None
        assert row["is_active"] == 1
    # At least the required minimum accounts per AC8
    assert len(rows) >= 21


def _seed_expense_event(
    conn,
    *,
    amount_vnd=50000,
    category="Nguyên liệu",
    payment_source="Shop tiền mặt",
    paid_by_name="",
    summary="Test expense",
):
    data = json.dumps(
        {
            "amount_vnd": amount_vnd,
            "category": category,
            "payment_method": "TM",
            "payment_source": payment_source,
            "vendor": "NCC A",
            "note": "",
            "paid_by_name": paid_by_name,
        }
    )
    cursor = conn.execute(
        "INSERT INTO events (type, summary, data, logged_by, timestamp) "
        "VALUES ('expense', ?, ?, '', '2026-06-22T10:00:00+07:00')",
        (summary, data),
    )
    return int(cursor.lastrowid)


def _seed_payment_transaction(
    conn, order_id, amount=200000, type_="deposit", method="cash"
):
    cursor = conn.execute(
        "INSERT INTO payment_transactions (order_id, amount, type, method, note) "
        "VALUES (?, ?, ?, ?, '')",
        (order_id, amount, type_, method),
    )
    return int(cursor.lastrowid)


def _seed_order_with_items(conn, *, product_cost=5000, qty=2, status="delivered"):
    # Order
    cursor = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, items, total_price, status) "
        "VALUES ('ORD-TEST-001', 'Khách test', '[]', 100000, ?)",
        (status,),
    )
    order_id = int(cursor.lastrowid)
    # Product
    cursor = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
        "VALUES ('Bánh test', 'banh_mi', 10000, ?, '')",
        (product_cost,),
    )
    product_id = int(cursor.lastrowid)
    # Order item with product_id as string (matches app convention)
    conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, position) "
        "VALUES (?, ?, 'Bánh test', ?, 50000, 0)",
        (order_id, str(product_id), qty),
    )
    return order_id, product_id


def _assert_double_entry_integrity(conn) -> None:
    """Every journal entry has total debit == total credit."""
    rows = conn.execute(
        """
        SELECT je.id, SUM(jl.debit) AS total_debit, SUM(jl.credit) AS total_credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        GROUP BY je.id
        """
    ).fetchall()
    assert len(rows) > 0, "No journal entries to verify"
    for row in rows:
        delta = abs(float(row["total_debit"]) - float(row["total_credit"]))
        assert delta < 0.005, (
            f"Entry {row['id']}: debit {row['total_debit']} != credit {row['total_credit']}"
        )


def test_v44_accounts_table():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        _migrate_to_version(conn, 44)
        assert _migrated_version(conn) == 44
        _assert_accounts_table(conn)


def test_v44_journal_entries_table():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _assert_journal_entries_table(conn)


def test_v44_journal_lines_table():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _assert_journal_lines_table(conn)


def test_v44_seed_coa():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _assert_seed_coa(conn)


def test_v44_seed_coa_idempotent():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        account_count = conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
        # Re-run callable (simulates re-migration safety)
        from baker.db.schema import _migrate_v44_double_entry_accounting

        _migrate_v44_double_entry_accounting(conn)
        account_count_after = conn.execute(
            "SELECT COUNT(*) FROM accounts"
        ).fetchone()[0]
        assert account_count == account_count_after


def test_v44_backfill_expenses():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        event_id = _seed_expense_event(
            conn,
            amount_vnd=50000,
            category="Nguyên liệu",
            payment_source="Shop tiền mặt",
            summary="Expense cash",
        )
        event_id_bank = _seed_expense_event(
            conn,
            amount_vnd=30000,
            category="Điện/nước",
            payment_source="TK Phượng VCB",
            summary="Expense bank",
        )

        _migrate_to_version(conn, 44)
        assert _migrated_version(conn) == 44

        # Two expense journal entries
        entries = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type = 'expense' ORDER BY id"
        ).fetchall()
        assert len(entries) == 2

        # Cash expense: debit 5100 (Nguyên liệu), credit 1100 (Cash)
        cash_entry = next(e for e in entries if e["source_id"] == event_id)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id = ? ORDER BY id",
            (cash_entry["id"],),
        ).fetchall()
        assert len(lines) == 2
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        assert float(debit_line["debit"]) == 50000
        assert float(credit_line["credit"]) == 50000
        # account codes
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "5100"
        assert credit_acc == "1100"

        # Bank expense: credit 1200 (Bank Account)
        bank_entry = next(e for e in entries if e["source_id"] == event_id_bank)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id = ?",
            (bank_entry["id"],),
        ).fetchall()
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert credit_acc == "1200"

        _assert_double_entry_integrity(conn)


def test_v44_backfill_expense_staff_advance_creates_sub_account():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        # Seed staff
        conn.execute("INSERT OR IGNORE INTO staff (name, role) VALUES ('Ân', 'staff')")
        event_id = _seed_expense_event(
            conn,
            amount_vnd=40000,
            category="Lương/phụ cấp",
            payment_source="Nhân viên ứng trước",
            paid_by_name="Ân",
            summary="Staff advance Ân",
        )

        _migrate_to_version(conn, 44)

        # Sub-account created under 1400
        parent = conn.execute(
            "SELECT id FROM accounts WHERE code = '1400'"
        ).fetchone()
        subs = conn.execute(
            "SELECT * FROM accounts WHERE parent_id = ? ORDER BY id",
            (parent["id"],),
        ).fetchall()
        assert len(subs) == 1
        assert subs[0]["name"] == "Ân"

        # Journal entry credit goes to the staff sub-account
        entry = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type='expense' AND source_id=?",
            (event_id,),
        ).fetchone()
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id = ?", (entry["id"],)
        ).fetchall()
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        assert credit_line["account_id"] == subs[0]["id"]
        _assert_double_entry_integrity(conn)


def test_v44_backfill_payments():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        # Need an order for FK
        cursor = conn.execute(
            "INSERT INTO orders (order_ref, customer_name, items, total_price, status) "
            "VALUES ('ORD-P-001', 'Khách p', '[]', 200000, 'new')"
        )
        order_id = int(cursor.lastrowid)

        pt_cash = _seed_payment_transaction(
            conn, order_id, amount=200000, type_="deposit", method="cash"
        )
        pt_transfer = _seed_payment_transaction(
            conn, order_id, amount=50000, type_="payment", method="transfer"
        )
        pt_refund = _seed_payment_transaction(
            conn, order_id, amount=10000, type_="refund", method="cash"
        )

        _migrate_to_version(conn, 44)

        entries = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type='payment_transaction' "
            "ORDER BY id"
        ).fetchall()
        assert len(entries) == 3

        # deposit cash: debit 1100, credit 2100
        dep_entry = next(e for e in entries if e["source_id"] == pt_cash)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (dep_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "1100"
        assert credit_acc == "2100"
        assert float(debit_line["debit"]) == 200000

        # transfer payment: debit 1200
        tr_entry = next(e for e in entries if e["source_id"] == pt_transfer)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (tr_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "1200"

        # refund: debit 2100, credit 1100 (reversed)
        rf_entry = next(e for e in entries if e["source_id"] == pt_refund)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (rf_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "2100"
        assert credit_acc == "1100"

        _assert_double_entry_integrity(conn)


def test_v44_backfill_delivered_orders():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        order_id, product_id = _seed_order_with_items(
            conn, product_cost=5000, qty=2, status="delivered"
        )
        # payment to create revenue conversion
        _seed_payment_transaction(
            conn, order_id, amount=120000, type_="full_payment", method="cash"
        )

        _migrate_to_version(conn, 44)

        # Revenue conversion entry
        rev_entry = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type='order' AND source_id=?",
            (order_id,),
        ).fetchone()
        assert rev_entry is not None
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (rev_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "2100"  # Customer Deposits
        assert credit_acc == "4100"  # Order Revenue
        assert float(debit_line["debit"]) == 120000

        # COGS entry: cost 5000 * qty 2 = 10000; debit 5900, credit 1300
        cogs_entry = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type='order_cogs' AND source_id=?",
            (order_id,),
        ).fetchone()
        assert cogs_entry is not None
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (cogs_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "5900"
        assert credit_acc == "1300"
        assert float(debit_line["debit"]) == 10000

        _assert_double_entry_integrity(conn)


def test_v44_backfill_delivered_order_zero_cost_skips_cogs():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        order_id, _ = _seed_order_with_items(
            conn, product_cost=0, qty=3, status="delivered"
        )
        _seed_payment_transaction(conn, order_id, amount=50000)

        _migrate_to_version(conn, 44)

        cogs_count = conn.execute(
            "SELECT COUNT(*) FROM journal_entries "
            "WHERE source_type='order_cogs' AND source_id=?",
            (order_id,),
        ).fetchone()[0]
        assert cogs_count == 0


def test_v44_double_entry_integrity():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        # Seed a mix of data
        _seed_expense_event(conn, amount_vnd=50000, category="Bao bì")
        _seed_expense_event(
            conn,
            amount_vnd=40000,
            category="Vận chuyển",
            payment_source="TK Ân VCB",
        )
        order_id, _ = _seed_order_with_items(
            conn, product_cost=3000, qty=2, status="delivered"
        )
        _seed_payment_transaction(conn, order_id, amount=80000, method="transfer")
        _seed_payment_transaction(
            conn, order_id, amount=20000, type_="tien_rut", method="cash"
        )

        _migrate_to_version(conn, 44)
        _assert_double_entry_integrity(conn)


def test_v44_fresh_db_seeds_coa_and_no_backfill():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        assert _migrated_version(conn) == 44
        _assert_seed_coa(conn)
        # No historical data → no journal entries
        entry_count = conn.execute(
            "SELECT COUNT(*) FROM journal_entries"
        ).fetchone()[0]
        assert entry_count == 0
