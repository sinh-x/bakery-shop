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
        assert _migrated_version(conn) == 43
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
        assert _migrated_version(conn) == 43
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
        assert _migrated_version(conn) == 43

        ensure_schema(conn)
        assert _migrated_version(conn) == 43

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
